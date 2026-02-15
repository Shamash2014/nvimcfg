local M = {}

local registry = require("ai_repl.registry")
local ralph_helper = require("ai_repl.ralph_helper")

function M.apply_update(proc, update)
  if not update then return nil end
  local u = update
  local update_type = u.sessionUpdate

  if u.type == "system" and u.subtype == "compact_boundary" then
    local tokens = u.compactMetadata and u.compactMetadata.preTokens
    local trigger = u.compactMetadata and u.compactMetadata.trigger or "auto"
    local info = tokens and string.format(" (%s, %dk tokens)", trigger, math.floor(tokens / 1000)) or ""
    return {
      type = "compact_boundary",
      update = u,
      compact_info = info,
    }
  end

  if update_type == "agent_message_chunk" then
    ralph_helper.record_activity()
    local content = u.content
    if content and content.text then
      proc.ui.streaming_response = (proc.ui.streaming_response or "") .. content.text
      return {
        type = "agent_message_chunk",
        update = u,
        text = content.text,
      }
    end
    return nil

  elseif update_type == "current_mode_update" then
    proc.state.mode = u.modeId or u.currentModeId
    return {
      type = "current_mode_update",
      update = u,
    }

  elseif update_type == "tool_call" then
    local tool = {
      id = u.toolCallId,
      title = u.title,
      kind = u.kind,
      status = u.status or "pending",
      locations = u.locations,
      rawInput = u.rawInput,
      content = u.content,
    }
    proc.ui.active_tools[u.toolCallId] = tool
    table.insert(proc.ui.pending_tool_calls, {
      id = u.toolCallId, title = u.title, kind = u.kind, input = u.rawInput,
    })

    local is_plan_tool = u.title == "TodoWrite" and u.rawInput and u.rawInput.todos
    if is_plan_tool then
      proc.ui.current_plan = u.rawInput.todos
    end

    local is_exit_plan = u.title == "ExitPlanMode"

    local is_ask_user = u.title == "AskUser" or u.title == "AskUserQuestion"
      or (u.rawInput and u.rawInput.questions)
    local questions = is_ask_user and u.rawInput and u.rawInput.questions or {}

    return {
      type = "tool_call",
      update = u,
      tool = tool,
      is_plan_tool = is_plan_tool,
      plan_entries = is_plan_tool and u.rawInput.todos or nil,
      is_exit_plan = is_exit_plan,
      is_ask_user = is_ask_user,
      questions = questions,
    }

  elseif update_type == "tool_call_update" then
    local tool = proc.ui.active_tools[u.toolCallId] or {}
    tool.status = u.status or tool.status
    tool.title = u.title or tool.title
    tool.kind = u.kind or tool.kind
    tool.locations = u.locations or tool.locations
    tool.rawOutput = u.rawOutput or tool.rawOutput
    tool.rawInput = tool.rawInput or u.rawInput

    if u.content and type(u.content) == "table" then
      for _, block in ipairs(u.content) do
        if block.type == "diff" then
          tool.diff = {
            path = block.path,
            oldText = block.oldText,
            newText = block.newText,
          }
          break
        end
      end
      tool.content = u.content
    end

    proc.ui.active_tools[u.toolCallId] = tool

    local tool_finished = u.status == "completed" or u.status == "failed"
    local is_edit_tool = tool.kind == "edit" or tool.kind == "write"
      or tool.title == "Edit" or tool.title == "Write"

    local diff = nil
    if tool_finished and u.status == "completed" and is_edit_tool then
      local file_path, old_text, new_text

      -- Try to get diff from tool.diff first
      if tool.diff then
        file_path = tool.diff.path
        old_text = tool.diff.oldText
        new_text = tool.diff.newText
      end

      -- Fall back to rawInput if diff fields are missing
      if not file_path and tool.locations and #tool.locations > 0 then
        local loc = tool.locations[1]
        file_path = loc.path or loc.uri
        if file_path then
          file_path = file_path:gsub("^file://", "")
        end
      end

      if not file_path and tool.rawInput then
        file_path = tool.rawInput.file_path or tool.rawInput.path
      end

      if not old_text and tool.rawInput then
        old_text = tool.rawInput.old_string or tool.rawInput.oldString
      end

      if not new_text and tool.rawInput then
        new_text = tool.rawInput.new_string or tool.rawInput.newString or tool.rawInput.content
      end

      -- Create diff if we have a file path and at least one of old/new text
      if file_path and (old_text or new_text) then
        diff = {
          path = file_path,
          old = old_text or "",
          new = new_text or ""
        }
      end

      -- Debug logging if diff was not created
      if not diff then
        vim.notify(string.format("[DEBUG] Edit tool diff not created: path=%s, old=%s, new=%s",
          tostring(file_path),
          tostring(old_text):sub(1, 50),
          tostring(new_text):sub(1, 50)), vim.log.levels.DEBUG)
      end
    end

    if tool_finished then
      proc.ui.active_tools[u.toolCallId] = nil
    end

    local is_exit_plan_complete = tool.title == "ExitPlanMode" and u.status == "completed"

    return {
      type = "tool_call_update",
      update = u,
      tool = tool,
      tool_finished = tool_finished,
      is_edit_tool = is_edit_tool,
      diff = diff,
      is_exit_plan_complete = is_exit_plan_complete,
    }

  elseif update_type == "plan" then
    proc.ui.current_plan = u.entries or u.plan or {}
    if type(proc.ui.current_plan) == "table" and proc.ui.current_plan.entries then
      proc.ui.current_plan = proc.ui.current_plan.entries
    end
    return {
      type = "plan",
      update = u,
      plan_entries = proc.ui.current_plan,
    }

  elseif update_type == "available_commands_update" then
    proc.data.slash_commands = u.availableCommands or {}
    return {
      type = "available_commands_update",
      update = u,
    }

  elseif update_type == "stop" then
    proc.state.busy = false

    local had_plan = #proc.ui.current_plan > 0
    local response_text = proc.ui.streaming_response or ""

    if response_text ~= "" then
      local tool_calls_to_save = nil
      if #proc.ui.pending_tool_calls > 0 then
        tool_calls_to_save = vim.deepcopy(proc.ui.pending_tool_calls)
      end
      registry.append_message(proc.session_id, "djinni", response_text, tool_calls_to_save)
    end

    local ralph_continuing = false
    if ralph_helper.is_loop_enabled() then
      local loop_continuing = ralph_helper.on_agent_stop(proc, response_text)
      if loop_continuing then
        ralph_continuing = true
      end
    end

    if not ralph_continuing then
      ralph_continuing = ralph_helper.check_and_continue(proc, response_text)
    end

    local should_process_queue = not ralph_continuing

    local stop_reason = u.stopReason or "end_turn"
    local usage = u.usage

    proc.ui.current_plan = {}
    proc.ui.active_tools = {}
    proc.ui.pending_tool_calls = {}

    return {
      type = "stop",
      update = u,
      stop_reason = stop_reason,
      usage = usage,
      response_text = response_text,
      had_plan = had_plan,
      ralph_continuing = ralph_continuing,
      should_process_queue = should_process_queue,
    }

  elseif update_type == "modes" then
    proc.state.modes = u.modes or {}
    proc.state.mode = u.currentModeId
    return {
      type = "modes",
      update = u,
    }

  elseif update_type == "agent_thought_chunk" then
    return {
      type = "agent_thought_chunk",
      update = u,
    }
  end

  return nil
end

return M
