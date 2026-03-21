local M = {}
local chat_parser = require("ai_repl.chat_parser")
local tool_utils = require("ai_repl.tool_utils")
local chat_state = require("ai_repl.chat_state")
local session_state = require("ai_repl.session_state")
local chat_decorations = require("ai_repl.chat_decorations")
local render_mod = require("ai_repl.render")
local cost_mod = require("ai_repl.cost")
local chat_buffer_mod -- lazy to avoid circular require
local function get_chat_buffer()
  if not chat_buffer_mod then chat_buffer_mod = require("ai_repl.chat_buffer") end
  return chat_buffer_mod
end
local buffer_state = {}
local model_info_dirty = {}

local function mark_model_info_dirty(buf, proc)
  if model_info_dirty[buf] then return end
  model_info_dirty[buf] = true
  vim.schedule(function()
    model_info_dirty[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(chat_decorations.show_model_info, buf, proc)
    end
  end)
end

local TOOL_NAMES = {
  Read = "Read", Edit = "Edit", Write = "Write", Bash = "Run",
  Glob = "Find Files", Grep = "Search", Task = "Agent",
  WebFetch = "Fetch", WebSearch = "Web Search", TodoWrite = "Plan",
  NotebookEdit = "Notebook", LSP = "LSP", KillShell = "Kill Process",
  Skill = "Skill",
}

local MODE_ICONS = {
  plan = "📋", spec = "📝", auto = "🤖", code = "💻",
  chat = "💬", execute = "▶️",
}

local NS_PLAN_BLOCK = vim.api.nvim_create_namespace("chat_plan_block")

local function get_state(buf)
  if not buffer_state[buf] then
    buffer_state[buf] = {
      session_id = nil,
      process = nil,
      last_role = nil,
      streaming = false,
      streaming_text = "",
      streaming_insert_line = nil,
      render_scheduled = false,
      tool_approvals = {},
      tool_line_map = {},
      modified = false,
      original_handlers = nil,
      reconnect_count = 0,
      streaming_split_offset = 0,
      thinking_scan_pos = 0,
      plan_block_extmark = nil,
      plan_block_line_count = 0,
    }
  end
  return buffer_state[buf]
end

local function render_plan_in_chat(buf, entries)
  if not entries or #entries == 0 then return end

  local state = get_state(buf)

  local prev = state.proc and state.proc.ui and state.proc.ui._prev_plan
  local diff_summary = nil
  if prev and #prev > 0 then
    local added, changed, removed = 0, 0, 0
    local prev_map = {}
    for _, item in ipairs(prev) do
      prev_map[item.content or item.text or ""] = item.status or "pending"
    end
    for _, item in ipairs(entries) do
      local key = item.content or item.text or ""
      if not prev_map[key] then added = added + 1
      elseif prev_map[key] ~= (item.status or "pending") then changed = changed + 1 end
      prev_map[key] = nil
    end
    removed = vim.tbl_count(prev_map)
    if added + changed + removed > 0 then
      local parts = {}
      if changed > 0 then table.insert(parts, changed .. " changed") end
      if added > 0 then table.insert(parts, added .. " added") end
      if removed > 0 then table.insert(parts, removed .. " removed") end
      diff_summary = "[~] Plan updated: " .. table.concat(parts, ", ")
    end
  end

  if state.proc and state.proc.ui then
    state.proc.ui._prev_plan = entries
  end

  local plan_lines = render_mod.format_plan_lines(entries)
  local new_block = {}
  if diff_summary then
    table.insert(new_block, diff_summary)
  end
  for _, l in ipairs(plan_lines) do
    table.insert(new_block, l)
  end

  if state.plan_block_extmark then
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, NS_PLAN_BLOCK, state.plan_block_extmark, {})
    if pos and #pos > 0 then
      local start_row = pos[1]
      local end_row = start_row + state.plan_block_line_count
      vim.api.nvim_buf_set_lines(buf, start_row, end_row, false, new_block)
      state.plan_block_line_count = #new_block
      vim.api.nvim_buf_set_extmark(buf, NS_PLAN_BLOCK, start_row, 0, {
        id = state.plan_block_extmark,
      })
      return
    end
  end

  M.append_to_chat_buffer(buf, new_block)
  local new_line_count = vim.api.nvim_buf_line_count(buf)
  local block_start = new_line_count - #new_block
  state.plan_block_extmark = vim.api.nvim_buf_set_extmark(buf, NS_PLAN_BLOCK, block_start, 0, {})
  state.plan_block_line_count = #new_block

  if not state.plan_discuss then
    state.plan_discuss = true
    M.append_to_chat_buffer(buf, { "[📋] Plan discussion mode ON" })
  end
end

local function find_or_create_insert_line(buf, state)
  if state.streaming_insert_line then return end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local scan_from = math.max(0, line_count - 20)
  local lines = vim.api.nvim_buf_get_lines(buf, scan_from, line_count, false)

  local djinni_line = -1
  for i = #lines, 1, -1 do
    if lines[i]:match("^@Djinni:") then
      djinni_line = scan_from + i
      break
    end
  end

  if djinni_line == -1 then
    vim.api.nvim_buf_set_lines(buf, line_count, -1, false, { "", "@Djinni:" })
    state.streaming_insert_line = line_count + 2
    state.plan_block_extmark = nil
    state.plan_block_line_count = 0
  else
    local has_content_after = false
    local lines_after_djinni = djinni_line - scan_from
    for j = lines_after_djinni + 1, #lines do
      if lines[j] ~= "" then
        has_content_after = true
        break
      end
    end
    if has_content_after then
      vim.api.nvim_buf_set_lines(buf, line_count, -1, false, { "", "@Djinni:" })
      state.streaming_insert_line = line_count + 2
      state.plan_block_extmark = nil
      state.plan_block_line_count = 0
    else
      state.streaming_insert_line = djinni_line
    end
  end
end

local function render_streaming_lines(buf, state)
  if state.streaming_text == "" then return end

  vim.bo[buf].modifiable = true
  find_or_create_insert_line(buf, state)

  local response_lines = vim.split(state.streaming_text, "\n", { trimempty = false })
  local rendered = state.rendered_line_count or 0

  if rendered == 0 then
    vim.api.nvim_buf_set_lines(buf, state.streaming_insert_line, -1, false, response_lines)
  elseif #response_lines > rendered then
    local last_idx = state.streaming_insert_line + rendered - 1
    vim.api.nvim_buf_set_lines(buf, last_idx, last_idx + 1, false,
      { response_lines[rendered] })
    if #response_lines > rendered then
      vim.api.nvim_buf_set_lines(buf, last_idx + 1, last_idx + 1, false,
        vim.list_slice(response_lines, rendered + 1))
    end
  else
    local last_idx = state.streaming_insert_line + #response_lines - 1
    vim.api.nvim_buf_set_lines(buf, last_idx, last_idx + 1, false,
      { response_lines[#response_lines] })
  end

  state.rendered_line_count = #response_lines
  return response_lines
end

local function flush_streaming_text(buf, state)
  render_streaming_lines(buf, state)
end

M.get_state = get_state

function M.setup_event_forwarding(buf, proc)
  if not proc or not proc:is_alive() then
    return false
  end

  local state = get_state(buf)

  if proc.ui.chat_buf and proc.ui.chat_buf ~= buf and vim.api.nvim_buf_is_valid(proc.ui.chat_buf) then
    vim.notify("[.chat] Process already attached to another buffer, skipping", vim.log.levels.WARN)
    return false
  end

  if not state.original_handlers then
    state.original_handlers = {
      on_method = proc._on_method,
      on_status = proc._on_status,
      on_debug = proc._on_debug,
      on_exit = proc._on_process_exit,
      on_ready = proc._on_ready,
    }
  end

  -- Store the buffer reference for later use
  state.proc = proc
  state.buf = buf

  local consecutive_errors = 0

  proc:set_handlers({
    on_method = function(self, method, params, msg_id)
      local buf_valid = vim.api.nvim_buf_is_valid(buf)

      if method == "session/request_permission" then
        if buf_valid then
          pcall(M.handle_permission_in_chat, buf, self, msg_id, params)
        else
          -- Buffer closed, use original handler
          if state.original_handlers and state.original_handlers.on_method then
            pcall(state.original_handlers.on_method, self, method, params, msg_id)
          end
        end
        return
      end

      if method == "session/update" then
        if buf_valid then
          local ok, err = pcall(M.handle_session_update_in_chat, buf, params.update, self)
          if not ok then
            consecutive_errors = consecutive_errors + 1
            vim.notify("[.chat] Error processing update: " .. tostring(err), vim.log.levels.ERROR)
            if consecutive_errors >= 3 then
              self.state.busy = false
              self.ui.active_tools = {}
              self.ui.streaming_response = ""
              self.ui.streaming_start_line = nil
              pcall(chat_decorations.stop_spinner, buf)
              M.ensure_you_marker(buf)
              consecutive_errors = 0
            end
            local apply_ok, result = pcall(session_state.apply_update, self, params.update)
            if apply_ok and result and result.should_process_queue then
              vim.defer_fn(function()
                self:process_queued_prompts()
              end, 200)
            end
            local is_stop = params.update and params.update.sessionUpdate == "stop"
            if is_stop then
              self.state.busy = false
              vim.defer_fn(function()
                self:process_queued_prompts()
                if not self.state.busy and vim.api.nvim_buf_is_valid(buf) then
                  M.ensure_you_marker(buf)
                end
              end, 200)
            end
          else
            consecutive_errors = 0
          end
        else
          -- Buffer closed but we still need to process updates
          local apply_ok, result = pcall(session_state.apply_update, self, params.update)
          if apply_ok and result and result.should_process_queue then
            vim.defer_fn(function()
              self:process_queued_prompts()
            end, 200)
          end
          if not apply_ok or not result then
            local is_stop = params.update and params.update.sessionUpdate == "stop"
            if is_stop then
              self.state.busy = false
              self.ui.active_tools = {}
              self.ui.pending_tool_calls = {}
              self.ui.streaming_response = ""
              vim.defer_fn(function()
                self:process_queued_prompts()
              end, 200)
            end
          end
        end
        return
      end

      -- For all other methods, use original handler
      if state.original_handlers and state.original_handlers.on_method then
        pcall(state.original_handlers.on_method, self, method, params, msg_id)
      end
    end,
    on_status = function(self, status, data)
      -- Always call original handler first
      if state.original_handlers and state.original_handlers.on_status then
        pcall(state.original_handlers.on_status, self, status, data)
      end

      -- Only update chat buffer if it's valid
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(M.handle_status_in_chat, buf, status, data, self)
      end
    end,
    on_debug = state.original_handlers.on_debug,
    on_exit = function(self, code, was_alive)
      if state.original_handlers.on_exit then
        pcall(state.original_handlers.on_exit, self, code, was_alive)
      end

      local should_reconnect = was_alive and code ~= 0
      if not should_reconnect then
        state.reconnect_count = 0
        return
      end

      if not vim.api.nvim_buf_is_valid(buf) then return end

      local max_reconnect = 5
      state.reconnect_count = (state.reconnect_count or 0) + 1

      if state.reconnect_count > max_reconnect then
        M.append_to_chat_buffer(buf, {
          "",
          "[!] Process crashed " .. max_reconnect .. " times. Auto-reconnect disabled.",
          "    Use /restart-chat to manually reconnect.",
          "",
        })
        state.reconnect_count = 0
        return
      end

      state.was_busy_on_crash = self.state and self.state.busy

      local attempt = state.reconnect_count
      M.append_to_chat_buffer(buf, {
        "[~] Process exited unexpectedly (code " .. code .. "). Reconnecting " .. attempt .. "/" .. max_reconnect .. "...",
      })

      local delay = attempt * 1000
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        pcall(get_chat_buffer().reconnect_session, buf)
      end, delay)
    end,
    on_ready = state.original_handlers.on_ready,
  })

  return true
end

function M.is_forwarding_setup(buf, proc)
  local state = get_state(buf)
  return state.original_handlers ~= nil and state.proc == proc
end

function M.handle_session_update_in_chat(buf, update, proc)
  -- Check if buffer is still valid, if not, just process the update internally
  if not vim.api.nvim_buf_is_valid(buf) then
    pcall(session_state.apply_update, proc, update)
    return
  end

  local is_stop_update = update and update.sessionUpdate == "stop"

  local apply_ok, result = pcall(session_state.apply_update, proc, update)
  if not apply_ok then
    proc.state.busy = false
    proc.ui.active_tools = {}
    proc.ui.pending_tool_calls = {}
    proc.ui.streaming_response = ""
    proc.ui.streaming_start_line = nil
    pcall(chat_decorations.stop_spinner, buf)
    if is_stop_update then
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        proc:process_queued_prompts()
        if not proc.state.busy then
          M.ensure_you_marker(buf)
        end
      end, 200)
    end
    return
  end
  if not result then
    if is_stop_update then
      proc.state.busy = false
      proc.ui.active_tools = {}
      proc.ui.pending_tool_calls = {}
      proc.ui.streaming_response = ""
      proc.ui.streaming_start_line = nil
      pcall(chat_decorations.stop_spinner, buf)
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        proc:process_queued_prompts()
        if not proc.state.busy then
          M.ensure_you_marker(buf)
        end
      end, 200)
    end
    return
  end

  local state = get_state(buf)
  if result.type == "compact_boundary" then
    if result.post_tokens then
      proc.ui.context_tokens = result.post_tokens
    elseif result.pre_tokens then
      proc.ui.context_tokens = result.pre_tokens
    end
    M.append_to_chat_buffer(buf, { "", "[~] Context compacted" .. (result.compact_info or ""), "" })

  elseif result.type == "agent_message_chunk" then
    if state.tool_block_start then
      local tool_start = state.tool_block_start
      state.tool_block_start = nil
      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        pcall(vim.api.nvim_win_call, win, function()
          pcall(vim.cmd, tool_start .. "foldclose")
        end)
      end
    end
    if not state.streaming then
      state.streaming = true
      chat_state.set_activity_phase(buf, "generating")
      pcall(chat_decorations.start_spinner, buf, "generating")
    end
    M.stream_to_chat_buffer(buf, result.text)

  elseif result.type == "tool_call" then
    if not state.tool_block_start then
      state.tool_block_start = vim.api.nvim_buf_line_count(buf)
    end
    if result.is_enter_plan then
      state.plan_discuss = true
      M.append_to_chat_buffer(buf, { "", "[📝] Entering plan mode" })
      pcall(chat_decorations.show_plan_discuss_indicator, buf)
      mark_model_info_dirty(buf, proc)
      return
    end
    if result.is_plan_tool then
      render_plan_in_chat(buf, result.plan_entries)
      return
    elseif result.is_exit_plan then
      local mode_icon = MODE_ICONS[proc.state.mode or "execute"] or "▶️"
      M.append_to_chat_buffer(buf, { "", "[▶] " .. mode_icon .. " Starting execution..." })
      return
    end

    local u = result.update
    local raw_title = u.title or u.kind or "tool"
    chat_state.set_activity_phase(buf, "executing", { tool_name = raw_title, increment_tool = true })
    pcall(chat_decorations.stop_spinner, buf)
    local friendly = TOOL_NAMES[raw_title] or raw_title
    if not TOOL_NAMES[raw_title] and raw_title:match("^mcp__") then
      local provider = raw_title:match("^mcp__([^_]+)__") or "mcp"
      friendly = "MCP [" .. provider .. "]"
    end
    local input = u.rawInput or {}
    if type(input) == "string" then
      local ok, parsed = pcall(vim.json.decode, input)
      input = ok and parsed or {}
    end
    local desc = tool_utils.get_tool_description(raw_title, input, u.locations or {}, { include_path = true })
    local label = friendly
    if desc ~= "" then label = label .. ": " .. desc end
    M.append_to_chat_buffer(buf, { "[*] " .. label })
    local tool_id = u.toolCallId or u.id
    if tool_id then
      state.tool_line_map[tool_id] = vim.api.nvim_buf_line_count(buf) - 1
    end

    local preview = tool_utils.format_tool_preview(raw_title, input)
    if #preview > 0 then
      local tool_line = vim.api.nvim_buf_line_count(buf) - 2
      local mark_id = chat_decorations.show_tool_preview(buf, tool_line, preview)
      if mark_id and tool_id then
        state.tool_preview_marks = state.tool_preview_marks or {}
        state.tool_preview_marks[tool_id] = mark_id
      end
    end

  elseif result.type == "tool_call_update" then
    if result.tool_finished then
      pcall(chat_decorations.stop_spinner, buf)
      chat_state.set_activity_phase(buf, "thinking")
      pcall(chat_decorations.start_spinner, buf, "thinking")

      local tool_id = (result.tool and result.tool.id) or (result.update and result.update.toolCallId)
      local tool_line = tool_id and state.tool_line_map[tool_id]
      local is_success = result.update.status ~= "failed"

      if tool_id then
        local mark_id = state.tool_preview_marks and state.tool_preview_marks[tool_id]
        if mark_id then
          pcall(chat_decorations.clear_tool_preview, buf, mark_id)
          state.tool_preview_marks[tool_id] = nil
        end
      end

      local tool_title = result.tool and result.tool.title or ""
      if tool_title == "Edit" or tool_title == "Write" or tool_title == "Bash" then
        pcall(vim.cmd.checktime)
      end

      if tool_line and vim.api.nvim_buf_is_valid(buf) then
        local line_idx = tool_line - 1
        local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, line_idx, line_idx + 1, false)
        if ok and lines and lines[1] then
          local marker = is_success and "[+]" or "[!]"
          local updated = lines[1]:gsub("%[%*%]", marker, 1)
          if updated ~= lines[1] then
            vim.bo[buf].modifiable = true
            pcall(vim.api.nvim_buf_set_lines, buf, line_idx, line_idx + 1, false, { updated })
          end
        end
      end

      if not (result.is_edit_tool and result.diff) then
        local summary = tool_utils.get_tool_result_summary(result.tool)
        if summary and summary ~= "" then
          M.append_to_chat_buffer(buf, { "  \xe2\x8e\xbf  " .. summary })
        end
        local raw_title = result.tool and result.tool.title or ""
        if raw_title == "Bash" or raw_title == "Task" or raw_title == "Agent" or not is_success then
          local output_lines = tool_utils.format_tool_output_lines(result.tool)
          if #output_lines > 0 then
            M.append_to_chat_buffer(buf, output_lines)
          end
        end
      end

      if tool_id then
        state.tool_line_map[tool_id] = nil
      end

      if result.is_edit_tool and result.diff then
        render_mod.render_diff(buf, result.diff.path, result.diff.old, result.diff.new)
        M.append_to_chat_buffer(buf, {
          "[~] " .. vim.fn.fnamemodify(result.diff.path, ":~:."),
        })
      end

      if result.images and #result.images > 0 then
        for _, img in ipairs(result.images) do
          local ext = (img.mimeType or ""):match("/(%w+)") or "png"
          local tmp = vim.fn.tempname() .. "." .. ext
          local raw = vim.base64.decode(img.data)
          local f = io.open(tmp, "wb")
          if f then
            f:write(raw)
            f:close()
            M.append_to_chat_buffer(buf, { "[image] " .. tmp })
          end
        end
      end

      if result.is_exit_plan_complete then
        state.plan_discuss = false
        pcall(chat_decorations.clear_plan_discuss_indicator, buf)
        M.append_to_chat_buffer(buf, { "[▶] Starting execution..." })
        mark_model_info_dirty(buf, proc)
        proc:send_prompt("proceed with the plan", { silent = true })
      end
    end

  elseif result.type == "plan" then
    render_plan_in_chat(buf, result.plan_entries)

  elseif result.type == "current_mode_update" then
    local mode_id = result.update.modeId or result.update.currentModeId
    local icon = MODE_ICONS[mode_id] or "↻"
    M.append_to_chat_buffer(buf, { "[" .. icon .. "] Mode: " .. (mode_id or "unknown") })
    vim.notify("[" .. icon .. "] Mode: " .. (mode_id or "unknown"), vim.log.levels.INFO)
    mark_model_info_dirty(buf, proc)

  elseif result.type == "modes" then
    mark_model_info_dirty(buf, proc)

  elseif result.type == "stop" then
    if state.tool_block_start then
      local tool_start = state.tool_block_start
      state.tool_block_start = nil
      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        pcall(vim.api.nvim_win_call, win, function()
          pcall(vim.cmd, tool_start .. "foldclose")
        end)
      end
    end
    state.streaming = false
    state.tool_line_map = {}
    chat_state.set_activity_phase(buf, nil)
    pcall(flush_streaming_text, buf, state)
    state.streaming_text = ""
    state.streaming_insert_line = nil
    state.rendered_line_count = 0
    state.streaming_split_offset = 0
    state.thinking_scan_pos = 0
    proc.ui.streaming_response = ""
    proc.ui.streaming_start_line = nil
    vim.bo[buf].modifiable = true

    pcall(function()
      if result.response_text ~= "" and not result.had_plan then
        local md_plan = render_mod.parse_markdown_plan(result.response_text)
        if #md_plan >= 3 then
          proc.ui.current_plan = md_plan
          render_plan_in_chat(buf, md_plan)
        end
      end
    end)

    if not result.ralph_continuing then
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        M.ensure_you_marker(buf)

        local stop_state = get_state(buf)
        if stop_state.plan_discuss then
          pcall(chat_decorations.show_plan_discuss_indicator, buf)
        end

        pcall(get_chat_buffer().autosave_buffer, buf)
      end, 100)
    end
    local plan = proc.ui.current_plan
    if plan and #plan > 0 then
      local done = 0
      for _, item in ipairs(plan) do
        if item.status == "completed" then done = done + 1 end
      end
      if done > 0 then
        M.append_to_chat_buffer(buf, { "[📋] Plan: " .. done .. "/" .. #plan .. " completed" })
      end
    end

    pcall(chat_decorations.stop_spinner, buf)
    pcall(chat_decorations.schedule_redecorate, buf)

    if result.usage then
      local usage = result.usage
      local input_tokens = usage.inputTokens or usage.input_tokens or 0
      local output_tokens = usage.outputTokens or usage.output_tokens or 0
      local model_id = proc.data and proc.data.profile_id or proc.data and proc.data.provider
      local cost = cost_mod.calculate(model_id, input_tokens, output_tokens)
      if cost then
        proc.ui.session_cost = (proc.ui.session_cost or 0) + cost
      end
      pcall(chat_decorations.show_tokens, buf, usage, proc.ui.session_cost)
      mark_model_info_dirty(buf, proc)

      if input_tokens > 100000 then
        M.append_to_chat_buffer(buf, { "[!] Context getting large -- consider /compact" })
      end
    end

    if result.should_process_queue then
      vim.defer_fn(function()
        proc:process_queued_prompts()
      end, 200)
    end

  elseif result.type == "agent_thought_chunk" then
    local bstate = chat_state.get_buffer_state(buf)
    if bstate.activity_phase ~= "thinking" then
      chat_state.set_activity_phase(buf, "thinking")
    end
    pcall(chat_decorations.start_spinner, buf, "thinking")
  end
end

function M.append_new_user_marker(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  M.ensure_you_marker(buf)
end

function M.stop_streaming(buf)
  local state = get_state(buf)
  if not state.streaming then return end

  state.streaming = false

  flush_streaming_text(buf, state)

  state.streaming_text = ""
  state.streaming_insert_line = nil
  state.rendered_line_count = 0
  state.streaming_split_offset = 0
  state.thinking_scan_pos = 0

  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modifiable = true
  end

  pcall(chat_decorations.stop_spinner, buf)
end

function M.ensure_you_marker(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  vim.bo[buf].modifiable = true

  local line_count = vim.api.nvim_buf_line_count(buf)
  local scan_from = math.max(0, line_count - 30)
  local lines = vim.api.nvim_buf_get_lines(buf, scan_from, line_count, false)

  local last_marker_line = 0

  for i = #lines, 1, -1 do
    local role = chat_parser.parse_role_marker(lines[i])
    if role then
      last_marker_line = scan_from + i
      break
    end
  end

  local ends_with_you = last_marker_line > 0 and lines[last_marker_line - scan_from] and lines[last_marker_line - scan_from]:match("^@You:")

  if not ends_with_you then
    vim.api.nvim_buf_set_lines(buf, line_count, -1, false, {
      "",
      "@You:",
      "",
      "",
    })
    line_count = vim.api.nvim_buf_line_count(buf)
  end

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    local target = ends_with_you and (last_marker_line + 1) or (line_count - 1)
    target = math.min(target, vim.api.nvim_buf_line_count(buf))
    pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
    pcall(vim.api.nvim_win_call, win, function()
      vim.cmd("normal! zb")
    end)
  end

  vim.bo[buf].modifiable = true
end

function M.handle_permission_in_chat(buf, proc, msg_id, params)
  if proc.ui and proc.ui.permission_active then
    proc.ui.permission_queue = proc.ui.permission_queue or {}
    table.insert(proc.ui.permission_queue, { msg_id = msg_id, params = params })
    return
  end

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end

    pcall(chat_decorations.stop_spinner, buf)

    local tool = params.toolCall or {}
    local tool_id = tool.toolCallId or tool.id or "unknown"
    local stored_tool = (proc.ui and proc.ui.active_tools and tool_id ~= "unknown")
      and proc.ui.active_tools[tool_id] or {}

    local raw_input = tool.rawInput or tool.input or params.rawInput or params.input
      or stored_tool.rawInput or stored_tool.input
    if type(raw_input) == "string" then
      local ok, parsed = pcall(vim.json.decode, raw_input)
      raw_input = ok and parsed or {}
    end
    local input = raw_input or {}

    local tool_kind = tool.kind or stored_tool.kind or ""
    local title_str = tool.title or stored_tool.title or ""
    local raw_title = title_str:match("^`?(%w+)") or tool_kind or "tool"
    local friendly_name = TOOL_NAMES[raw_title] or raw_title
    local locations = tool.locations or stored_tool.locations or {}

    local desc = tool_utils.get_tool_description(raw_title, input, locations, { include_path = true, include_line = true })

    local agent_options = params.options or {}
    local perm_opts = tool_utils.parse_permission_options(agent_options)

    local config_ok, ai_config = pcall(function()
      return require("ai_repl.init").get_config and require("ai_repl.init").get_config() or {}
    end)
    local provider_id = proc.data and proc.data.provider or "claude"
    local providers_cfg = (config_ok and ai_config.providers) or {}
    local provider_config = providers_cfg[provider_id] or {}
    local mode = provider_config.permission_mode
      or (config_ok and ai_config.permission_mode)
      or "default"

    if mode == "bypassPermissions" or mode == "dontAsk" then
      local bypass_id = perm_opts.always or perm_opts.allow
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "selected", optionId = bypass_id } }
      }
      if not bypass_id then
        response.result = { outcome = { outcome = "cancelled" } }
      end
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
      if proc.ui then
        proc.ui.permission_active = false
        if proc.ui.permission_queue and #proc.ui.permission_queue > 0 then
          local next_req = table.remove(proc.ui.permission_queue, 1)
          proc.ui.permission_active = true
          M.handle_permission_in_chat(buf, proc, next_req.msg_id, next_req.params)
        end
      end
      return
    end

    -- Show prompt in .chat buffer
    local display = friendly_name
    if desc ~= "" then
      display = display .. ": " .. desc
    end

    vim.bo[buf].modifiable = true

    local prompt_line, bindings = tool_utils.build_permission_prompt(perm_opts.entries)

    M.append_to_chat_buffer(buf, {
      "",
      "[?] " .. display,
      prompt_line,
    })

    local perm_preview = tool_utils.format_tool_preview(raw_title, input)
    if #perm_preview > 0 then
      local perm_preview_line = vim.api.nvim_buf_line_count(buf) - 3
      chat_decorations.show_tool_preview(buf, perm_preview_line, perm_preview)
    end

    vim.bo[buf].modifiable = true

    if proc.ui then proc.ui.permission_active = true end
    chat_state.set_activity_phase(buf, "permission")

    vim.notify("[ai_repl] Permission required: " .. display, vim.log.levels.WARN)

    local perm_line = vim.api.nvim_buf_line_count(buf) - 1
    pcall(chat_decorations.start_permission_blink, buf, perm_line)

    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      pcall(vim.api.nvim_win_set_cursor, win, { math.max(1, perm_line), 0 })
    end

    local function send_selected(option_id)
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "selected", optionId = option_id } }
      }
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
    end

    local function send_cancelled()
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "cancelled" } }
      }
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
    end

    local perm_notify_timer = vim.uv.new_timer()
    if perm_notify_timer then
      get_state(buf).perm_notify_timer = perm_notify_timer
      perm_notify_timer:start(30000, 30000, vim.schedule_wrap(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          if perm_notify_timer then
            perm_notify_timer:stop()
            if not perm_notify_timer:is_closing() then perm_notify_timer:close() end
          end
          get_state(buf).perm_notify_timer = nil
          return
        end
        vim.notify("[ai_repl] Still waiting: " .. display, vim.log.levels.WARN)
        local w = vim.fn.bufwinid(buf)
        if w ~= -1 then
          local cursor = vim.api.nvim_win_get_cursor(w)
          if math.abs(cursor[1] - perm_line) > 5 then
            pcall(vim.api.nvim_win_set_cursor, w, { math.max(1, perm_line), 0 })
          end
        end
      end))
    end

    local answered = false
    local function cleanup_keymaps()
      for _, b in ipairs(bindings) do
        pcall(vim.keymap.del, "n", b.key, { buffer = buf })
      end
      pcall(chat_decorations.stop_permission_blink, buf)
      if perm_notify_timer then
        perm_notify_timer:stop()
        if not perm_notify_timer:is_closing() then perm_notify_timer:close() end
      end
      perm_notify_timer = nil
      get_state(buf).perm_notify_timer = nil
    end

    local function handle_choice(binding)
      if answered then return end
      answered = true
      cleanup_keymaps()

      if binding.role == "cancel" or not binding.id then
        M.append_to_chat_buffer(buf, { "[x] Cancelled", "", "@You:", "", "" })
        send_cancelled()
      elseif binding.role == "deny" then
        M.append_to_chat_buffer(buf, { "[x] " .. binding.label })
        send_selected(binding.id)
      else
        M.append_to_chat_buffer(buf, { "[+] " .. binding.label })
        send_selected(binding.id)
      end

      pcall(chat_decorations.start_spinner, buf, "executing")

      if proc.ui then
        local queue = proc.ui.permission_queue or {}
        if #queue > 0 then
          local next_req = table.remove(queue, 1)
          M.handle_permission_in_chat(buf, proc, next_req.msg_id, next_req.params)
        else
          proc.ui.permission_active = false
        end
      end
    end

    local opts = { buffer = buf, nowait = true }
    for _, b in ipairs(bindings) do
      local binding = b
      vim.keymap.set("n", binding.key, function() handle_choice(binding) end, opts)
    end
  end)
end

function M.handle_status_in_chat(buf, status, data, proc)
  local label
  if status == "session_created" then
    local provider_id = proc.data.provider or "unknown"
    local providers = require("ai_repl.providers")
    local provider_cfg = providers.get(provider_id) or {}
    local provider_name = provider_cfg.name or provider_id
    label = "[ACP SESSION READY] " .. provider_name
  elseif status == "session_loaded" then
    local provider_id = proc.data.provider or "unknown"
    local providers = require("ai_repl.providers")
    local provider_cfg = providers.get(provider_id) or {}
    local provider_name = provider_cfg.name or provider_id
    label = "[ACP SESSION LOADED] " .. provider_name
  end
  if not label then return end

  local cwd = proc.data.cwd or vim.fn.getcwd()
  local banner = {
    "",
    label,
    "  /restart - Restart session",
    "  /restart-chat - Restart conversation in current .chat buffer",
    "  /discuss - Enter plan discussion mode",
    "  /approve - Approve plan and exit discussion mode",
    "  /kill - Force kill session",
    "  /force-cancel - Cancel + kill (for stuck agents)",
    "  pwd: " .. cwd,
  }

  local mcp_servers = proc.config and proc.config.mcp_servers or {}
  if #mcp_servers > 0 then
    local names = {}
    for _, s in ipairs(mcp_servers) do
      table.insert(names, s.name or s.command or "unknown")
    end
    table.insert(banner, "  mcp: " .. table.concat(names, ", "))
  end

  table.insert(banner, "")

  if not vim.api.nvim_buf_is_valid(buf) then return end

  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local insert_before = nil
  for i = #lines, 1, -1 do
    if chat_parser.parse_role_marker(lines[i]) == "user" then
      insert_before = i - 1
      break
    end
  end

  if insert_before then
    vim.api.nvim_buf_set_lines(buf, insert_before, insert_before, false, banner)
  else
    local line_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, line_count, -1, false, banner)
  end

  -- Keep buffer modifiable for voice input
  vim.bo[buf].modifiable = true

  chat_decorations.show_model_info(buf, proc)
end

function M.stream_to_chat_buffer(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local state = get_state(buf)
  state.streaming_text = state.streaming_text .. text

  if not state.render_scheduled then
    state.render_scheduled = true
    vim.schedule(function()
      state.render_scheduled = false
      if not vim.api.nvim_buf_is_valid(buf) then
        state.streaming_text = ""
        state.streaming = false
        state.rendered_line_count = 0
        if state.proc then
          state.proc.state.busy = false
          state.proc.ui.streaming_response = ""
          state.proc.ui.active_tools = {}
        end
        return
      end

      if not state.streaming then return end

      local response_lines = render_streaming_lines(buf, state)
      if not response_lines then return end
      vim.bo[buf].modifiable = true

      local folds_to_close = {}
      for i = math.max(1, state.thinking_scan_pos), #response_lines do
        local line = response_lines[i]
        if line:match("^<thinking>") then
          state.thinking_start_line = state.streaming_insert_line + i - 1
        elseif line:match("^</thinking>") and state.thinking_start_line then
          table.insert(folds_to_close, state.thinking_start_line)
          state.thinking_start_line = nil
        end
      end
      state.thinking_scan_pos = #response_lines

      if #folds_to_close > 0 then
        local w = vim.fn.bufwinid(buf)
        if w ~= -1 then
          pcall(vim.api.nvim_win_call, w, function()
            for _, start in ipairs(folds_to_close) do
              pcall(vim.cmd, start .. "foldclose")
            end
          end)
        end
      end

      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        local new_count = vim.api.nvim_buf_line_count(buf)
        pcall(vim.api.nvim_win_set_cursor, win, { new_count, 0 })
      end
    end)
  end
end

function M.append_to_chat_buffer(buf, new_lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  vim.bo[buf].modifiable = true

  local line_count = vim.api.nvim_buf_line_count(buf)

  local to_append = {}
  if type(new_lines) == "string" then
    to_append[1] = new_lines
  elseif type(new_lines) == "table" then
    for i, line in ipairs(new_lines) do
      to_append[i] = line
    end
  end
  to_append[#to_append + 1] = ""

  vim.api.nvim_buf_set_lines(buf, line_count, -1, false, to_append)

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    pcall(vim.api.nvim_win_set_cursor, win, { line_count + #to_append, 0 })
  end
end

function M.cleanup_buffer(buf)
  local state = buffer_state[buf]
  if state then
    if state.perm_notify_timer then
      state.perm_notify_timer:stop()
      if not state.perm_notify_timer:is_closing() then state.perm_notify_timer:close() end
      state.perm_notify_timer = nil
    end
    buffer_state[buf] = nil
  end
end

return M
