local M = {}

local Process = require("ai_repl.process")
local registry = require("ai_repl.registry")
local render = require("ai_repl.render")
local providers = require("ai_repl.providers")
local ralph_helper = require("ai_repl.ralph_helper")
local tool_utils = require("ai_repl.tool_utils")
local questionnaire = require("ai_repl.questionnaire")
local syntax = require("ai_repl.syntax")

local config = setmetatable({
  window = {
    width = 0.45,
    border = "rounded",
    title = "AI REPL"
  },
  default_provider = "claude",
  history_size = 1000,
  permission_mode = "default",
  show_tool_calls = true,
  debug = false,
  reconnect = true,
  max_reconnect_attempts = 3,
  sessions_file = vim.fn.stdpath("data") .. "/ai_repl_sessions.json",
  max_sessions_per_project = 20
}, {
  __index = function(_, key)
    if key == "providers" then
      local p = {}
      for _, provider in ipairs(providers.list()) do
        p[provider.id] = provider
      end
      return p
    end
  end
})

local ui = {
  wins = {},  -- per-tab windows: { [tabpage] = win }
  active = false,
  source_buf = nil,
  project_root = nil,
}

local function extract_labels(items)
  return vim.tbl_map(function(item) return item.label end, items)
end

local function format_session_label(is_current, is_running, name_or_id, provider)
  local status
  if is_current then
    status = "[*]"
  elseif is_running then
    status = "[~]"
  else
    status = "[ ]"
  end
  local provider_badge = provider and (" [" .. provider .. "]") or ""
  return status .. " " .. name_or_id .. provider_badge
end

local function truncate(text, limit)
  if #text > limit then return text:sub(1, limit - 3) .. "..." end
  return text
end

local function get_tab_win()
  local tab = vim.api.nvim_get_current_tabpage()
  local win = ui.wins[tab]
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
  ui.wins[tab] = nil
  return nil
end

local function set_tab_win(win)
  local tab = vim.api.nvim_get_current_tabpage()
  ui.wins[tab] = win
end

local function clear_tab_win()
  local tab = vim.api.nvim_get_current_tabpage()
  ui.wins[tab] = nil
end

local function get_project_root(buf)
  local file = buf and vim.api.nvim_buf_get_name(buf) or vim.api.nvim_buf_get_name(0)
  local dir = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]
  if vim.v.shell_error == 0 and git_root and git_root ~= "" then
    return git_root
  end
  return dir
end

local function get_current_project_root()
  if ui.project_root then
    return ui.project_root
  end
  return get_project_root(ui.source_buf)
end

local function get_session_name(cwd)
  cwd = cwd or get_current_project_root()
  local dir_name = vim.fn.fnamemodify(cwd, ":t")
  local branch = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " branch --show-current 2>/dev/null")[1]
  if vim.v.shell_error == 0 and branch and branch ~= "" then
    return dir_name .. "/" .. branch
  end
  return dir_name
end

local function simplify_agent_name(name)
  if not name then return "Agent" end
  local simplified = name:gsub("^@[^/]+/", "")
  local friendly_names = {
    ["claude-code-acp"] = "Claude Code",
  }
  return friendly_names[simplified] or simplified
end

local function count_background_busy()
  local count = 0
  local active_id = registry.active_session_id()
  for sid, p in pairs(registry.all()) do
    if sid ~= active_id and p.state.busy then
      count = count + 1
    end
  end
  return count
end

local function update_statusline()
  local proc = registry.active()
  local win = get_tab_win()
  if not win then return end
  local provider_id = proc and proc.data.provider or config.default_provider
  local provider = config.providers[provider_id]
  local provider_name = provider and provider.name or provider_id
  local profile_id = proc and proc.data.profile_id
  if profile_id then
    provider_name = provider_name .. ":" .. profile_id
  end
  local agent_name = simplify_agent_name(proc and proc.state.agent_info and proc.state.agent_info.name)
  local mode = proc and proc.state.mode or "plan"
  local queue_count = proc and #proc.data.prompt_queue or 0
  local queue_str = queue_count > 0 and (" Q:" .. queue_count) or ""
  local busy_str = proc and proc.state.busy and " ●" or ""
  local bg_count = count_background_busy()
  local bg_str = bg_count > 0 and (" [" .. bg_count .. " bg]") or ""
  local skill_str = proc and proc.data.active_skill and (" 🎯 " .. proc.data.active_skill) or ""
  vim.wo[win].statusline = " " .. provider_name .. " | " .. agent_name .. " [" .. mode .. "]" .. busy_str .. queue_str .. bg_str .. skill_str
end

local function setup_window_options(win)
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
end

local function handle_session_update(proc, params)
  local u = params.update
  if not u then return end

  local buf = proc.data.buf
  local update_type = u.sessionUpdate

  if u.type == "system" and u.subtype == "compact_boundary" then
    render.stop_animation()
    local tokens = u.compactMetadata and u.compactMetadata.preTokens
    local trigger = u.compactMetadata and u.compactMetadata.trigger or "auto"
    local info = tokens and string.format(" (%s, %dk tokens)", trigger, math.floor(tokens / 1000)) or ""
    render.append_content(buf, { "", "[~] Context compacted" .. info, "" })
    return
  end

  if config.debug and update_type ~= "agent_message_chunk" then
    render.append_content(buf, { "[debug] " .. (update_type or "unknown") })
  end

  if update_type == "agent_message_chunk" then
    render.start_animation(buf, "generating")
    ralph_helper.record_activity()
    local content = u.content
    if content and content.text then
      if content.text:match("%[compact%]") or content.text:match("Conversation compacted") then
        render.stop_animation()
        render.append_content(buf, { "", "[~] Context compacted", "" })
        return
      end
      render.update_streaming(buf, content.text, proc.ui)
    end

  elseif update_type == "current_mode_update" then
    proc.state.mode = u.modeId or u.currentModeId
    update_statusline()

  elseif update_type == "tool_call" then
    local tool = {
      id = u.toolCallId,
      title = u.title,
      kind = u.kind,
      status = u.status or "pending",
      locations = u.locations,
      rawInput = u.rawInput,
      content = u.content
    }
    proc.ui.active_tools[u.toolCallId] = tool
    table.insert(proc.ui.pending_tool_calls, {
      id = u.toolCallId, title = u.title, kind = u.kind, input = u.rawInput
    })

    if u.title == "TodoWrite" and u.rawInput and u.rawInput.todos then
      proc.ui.current_plan = u.rawInput.todos
      render.render_plan(buf, proc.ui.current_plan)
      return
    elseif u.title == "ExitPlanMode" then
      render.append_content(buf, { "[>] Exiting plan mode..." })
      return
    elseif u.title == "AskUser" or u.title == "AskUserQuestion" or (u.rawInput and u.rawInput.questions) then
      render.stop_animation()
      local questions = u.rawInput and u.rawInput.questions or {}
      if #questions > 0 then
        questionnaire.start(proc, questions, function(response)
          M.send_prompt(response)
        end)
      end
    else
      render.start_animation(buf, "executing")
      render.render_tool(buf, tool)
    end

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

    if u.status == "completed" or u.status == "failed" then
      render.stop_animation()

      local is_edit_tool = tool.kind == "edit" or tool.kind == "write"
        or tool.title == "Edit" or tool.title == "Write"

      if u.status == "completed" and is_edit_tool then
        local file_path, old_text, new_text

        if tool.diff then
          file_path = tool.diff.path
          old_text = tool.diff.oldText
          new_text = tool.diff.newText
        end

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

        if file_path and (old_text or new_text) then
          render.render_diff(buf, file_path, old_text or "", new_text or "")
        end
      end

      if tool.title ~= "AskUser" and tool.title ~= "AskUserQuestion" then
        render.render_tool(buf, tool)
      end

      if tool.title == "ExitPlanMode" and u.status == "completed" then
        render.append_content(buf, { "[>] Starting execution..." })
        vim.defer_fn(function()
          M.send_prompt("proceed with the plan", { silent = true })
        end, 200)
      end

      proc.ui.active_tools[u.toolCallId] = nil
    end

  elseif update_type == "plan" then
    proc.ui.current_plan = u.entries or u.plan or {}
    if type(proc.ui.current_plan) == "table" and proc.ui.current_plan.entries then
      proc.ui.current_plan = proc.ui.current_plan.entries
    end
    render.render_plan(buf, proc.ui.current_plan)

  elseif update_type == "available_commands_update" then
    proc.data.slash_commands = u.availableCommands or {}

  elseif update_type == "stop" then
    render.stop_animation()
    proc.state.busy = false

    if proc.ui.streaming_response and proc.ui.streaming_response ~= "" then
      local tool_calls_to_save = nil
      if #proc.ui.pending_tool_calls > 0 then
        tool_calls_to_save = vim.deepcopy(proc.ui.pending_tool_calls)
      end
      registry.append_message(proc.session_id, "assistant", proc.ui.streaming_response, tool_calls_to_save)

      if #proc.ui.current_plan == 0 then
        local md_plan = render.parse_markdown_plan(proc.ui.streaming_response)
        if #md_plan >= 3 then
          proc.ui.current_plan = md_plan
          render.render_plan(buf, md_plan)
        end
      end
    end

    proc.ui.current_plan = {}
    proc.ui.active_tools = {}
    proc.ui.pending_tool_calls = {}
    render.finish_streaming(buf, proc.ui)

    local reason = u.stopReason or "end_turn"
    local reason_msgs = {
      end_turn = "---",
      max_tokens = "[!] Stopped: token limit",
      max_turn_requests = "[!] Stopped: turn limit",
      refusal = "[!] Agent refused",
      cancelled = "[x] Cancelled"
    }
    local mode_str = proc.state.mode and (" [" .. proc.state.mode .. "]") or ""
    local queue_count = #proc.data.prompt_queue
    local queue_info = queue_count > 0 and (" [" .. queue_count .. " queued]") or ""
    render.append_content(buf, { "", (reason_msgs[reason] or "---") .. mode_str .. queue_info, "" })

    -- Ralph Loop: Simple re-injection loop (takes priority)
    local response_text = proc.ui.streaming_response or ""
    if ralph_helper.is_loop_enabled() then
      local loop_continuing = ralph_helper.on_agent_stop(proc, response_text)
      if loop_continuing then
        return -- Ralph Loop is re-injecting prompt
      end
    end

    -- Ralph Wiggum mode: Check if we should continue looping
    local ralph_continuing = ralph_helper.check_and_continue(proc, response_text)
    if ralph_continuing then
      return -- Don't process queued prompts, Ralph is handling it
    end

    update_statusline()

    vim.defer_fn(function()
      proc:process_queued_prompts()
      update_statusline()
    end, 200)

  elseif update_type == "modes" then
    proc.state.modes = u.modes or {}
    proc.state.mode = u.currentModeId
    update_statusline()

  elseif update_type == "agent_thought_chunk" then
    render.start_animation(buf, "thinking")
  end
end

local TOOL_NAMES = {
  Read = "Read",
  Edit = "Edit",
  Write = "Write",
  Bash = "Run",
  Glob = "Find Files",
  Grep = "Search",
  Task = "Agent",
  WebFetch = "Fetch",
  WebSearch = "Web Search",
  TodoWrite = "Plan",
  NotebookEdit = "Notebook",
  LSP = "LSP",
  KillShell = "Kill Process",
}

local function get_tool_description(title, input, locations)
  return tool_utils.get_tool_description(title, input, locations, { include_path = true, include_line = true })
end

local function show_permission_prompt(proc, msg_id, params)
  local buf = proc.data.buf

  vim.schedule(function()
    local tool = params.toolCall or {}
    local tool_id = tool.toolCallId or tool.id

    if config.debug then
      render.append_content(buf, { "[debug] permission params: " .. vim.inspect(params):sub(1, 500) })
    end

    local stored_tool = tool_id and proc.ui.active_tools[tool_id] or {}

    local raw_input = tool.rawInput
      or tool.input
      or params.rawInput
      or params.input
      or stored_tool.rawInput
      or stored_tool.input
    if type(raw_input) == "string" then
      local ok, parsed = pcall(vim.json.decode, raw_input)
      raw_input = ok and parsed or {}
    end
    local input = raw_input or {}
    if vim.tbl_isempty(input) and tool.parameters then
      input = tool.parameters
    end

    local tool_kind = tool.kind or stored_tool.kind or ""
    local title_str = tool.title or stored_tool.title or ""
    local raw_title = title_str:match("^`?(%w+)") or tool_kind or "tool"
    local friendly_name = TOOL_NAMES[raw_title] or raw_title
    local locations = tool.locations or stored_tool.locations or {}

    if config.debug then
      render.append_content(buf, { "[debug] raw_title=" .. raw_title .. " kind=" .. tool_kind })
      render.append_content(buf, { "[debug] input: " .. vim.inspect(input):sub(1, 800) })
    end

    local desc = get_tool_description(raw_title, input, locations)

    local agent_options = params.options or {}
    local first_allow_id, first_deny_id, allow_always_id
    for _, opt in ipairs(agent_options) do
      local oid = opt.optionId or opt.id
      local okind = opt.kind or ""
      if oid then
        if oid:match("allow_always") or oid:match("allowAlways") then
          allow_always_id = allow_always_id or oid
        elseif okind:match("allow") or oid:match("allow") or oid:match("yes") or oid:match("approve") then
          first_allow_id = first_allow_id or oid
        end
        if okind:match("deny") or oid:match("deny") or oid:match("no") or oid:match("reject") then
          first_deny_id = first_deny_id or oid
        end
      end
    end

    local provider_id = proc.data.provider or config.default_provider
    local provider_config = config.providers[provider_id] or {}
    local mode = provider_config.permission_mode or config.permission_mode

    if mode == "bypassPermissions" or mode == "dontAsk" then
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "selected", optionId = first_allow_id or "allow_always" } }
      }
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
      proc.ui.permission_active = false
      local queue = proc.ui.permission_queue
      if #queue > 0 then
        local next_req = table.remove(queue, 1)
        proc.ui.permission_active = true
        show_permission_prompt(proc, next_req.msg_id, next_req.params)
      end
      return
    end

    local file_path = input.file_path or input.filePath or input.path
    local old_str = input.old_string or input.oldString or input.oldText
    local new_str = input.new_string or input.newString or input.newText

    local tool_content = tool.content or stored_tool.content
    if tool_content and type(tool_content) == "table" then
      for _, block in ipairs(tool_content) do
        if block.type == "diff" then
          file_path = file_path or block.path
          old_str = old_str or block.oldText
          new_str = new_str or block.newText
          break
        end
      end
    end

    if not file_path and locations and #locations > 0 then
      local loc = locations[1]
      file_path = loc.path or loc.uri
      if file_path then
        file_path = file_path:gsub("^file://", "")
      end
    end

    local is_edit = raw_title == "Edit" or raw_title == "Write" or tool_kind == "edit"
    if is_edit and old_str and new_str then
      render.render_diff(buf, file_path or "file", old_str, new_str)
    elseif is_edit and input.content and file_path then
      local old_content = ""
      if vim.fn.filereadable(file_path) == 1 then
        old_content = table.concat(vim.fn.readfile(file_path), "\n")
      end
      render.render_diff(buf, file_path, old_content, input.content)
    elseif raw_title == "Bash" and input.command then
      render.append_content(buf, { "$ " .. input.command })
    end

    local display = friendly_name
    if desc ~= "" then
      display = display .. ": " .. desc
    end
    render.append_content(buf, { "", "[?] " .. display })

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

    render.append_content(buf, { "  [y] Allow  [a] Always  [n] Deny  [c] Cancel" })

    local answered = false
    local function cleanup_keymaps()
      for _, key in ipairs({ "y", "a", "n", "c" }) do
        pcall(vim.keymap.del, "n", key, { buffer = buf })
      end
    end

    local function handle_choice(choice)
      if answered then return end
      answered = true
      cleanup_keymaps()

      if choice == "y" then
        render.append_content(buf, { "[+] Allowed" })
        send_selected(first_allow_id or "allow_once")
      elseif choice == "a" then
        render.append_content(buf, { "[+] Always allowed" })
        send_selected(allow_always_id or "allow_always")
      elseif choice == "n" then
        render.append_content(buf, { "[x] Denied" })
        send_selected(first_deny_id or "reject_once")
      else
        render.append_content(buf, { "[x] Cancelled" })
        send_cancelled()
      end

      local queue = proc.ui.permission_queue
      if #queue > 0 then
        local next_req = table.remove(queue, 1)
        show_permission_prompt(proc, next_req.msg_id, next_req.params)
      else
        proc.ui.permission_active = false
      end
    end

    local opts = { buffer = buf, nowait = true }
    vim.keymap.set("n", "y", function() handle_choice("y") end, opts)
    vim.keymap.set("n", "a", function() handle_choice("a") end, opts)
    vim.keymap.set("n", "n", function() handle_choice("n") end, opts)
    vim.keymap.set("n", "c", function() handle_choice("c") end, opts)
  end)
end

local function handle_permission_request(proc, msg_id, params)
  render.stop_animation()

  if proc.ui.permission_active then
    table.insert(proc.ui.permission_queue, { msg_id = msg_id, params = params })
    return
  end

  proc.ui.permission_active = true
  show_permission_prompt(proc, msg_id, params)
end

local function handle_method(proc, method, params, msg_id)
  local buf = proc.data.buf
  local is_active = proc.session_id == registry.active_session_id()

  if method == "session/update" then
    handle_session_update(proc, params)

    if not is_active then
      local u = params.update
      if u and u.sessionUpdate == "stop" then
        update_statusline()
        local agent_name = proc:get_agent_name()
        vim.notify("Background: " .. agent_name .. " completed", vim.log.levels.INFO)
      end
    end

  elseif method == "session/request_permission" then
    if is_active then
      handle_permission_request(proc, msg_id, params)
    else
      -- Get provider-specific background permission policy
      local provider_id = proc.data.provider or config.default_provider
      local provider_config = config.providers[provider_id] or {}
      local background_mode = provider_config.background_permissions or "allow_once"
      
      -- Extract agent-provided options to find appropriate response
      local agent_options = params.options or {}
      local tool_call = params.toolCall or {}
      
      -- Find option IDs based on agent's provided options
      local first_allow_id, allow_always_id, default_option_id
      for _, opt in ipairs(agent_options) do
        local oid = opt.optionId or opt.id
        local okind = opt.kind or ""
        
        -- Check for agent's marked default
        if opt.default or opt.isDefault then
          default_option_id = default_option_id or oid
        end
        
        -- Find allow_always option
        if oid and (oid:match("allow_always") or oid:match("allowAlways")) then
          allow_always_id = allow_always_id or oid
        end
        
        -- Find first allow option
        if oid and okind:match("allow") and not first_allow_id then
          first_allow_id = oid
        end
      end
      
      -- Determine which option to select based on provider's background policy
      local selected_option_id
      if background_mode == "respect_agent" and default_option_id then
        -- Use agent's suggested default
        selected_option_id = default_option_id
      elseif background_mode == "allow_once" then
        -- Use first allow option (not always)
        selected_option_id = first_allow_id or "allow_once"
      else
        -- Default to allow_always (backward compatible)
        selected_option_id = allow_always_id or first_allow_id or "allow_always"
      end
      
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "selected", optionId = selected_option_id } }
      }
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
      render.append_content(buf, { 
        "[+] Auto-approved (background " .. background_mode .. "): " .. (tool_call.title or "tool") 
      })
    end

  elseif method == "session/system" or method == "session/notification" then
    if params.type == "system" and params.subtype == "compact_boundary" then
      render.stop_animation()
      local tokens = params.compactMetadata and params.compactMetadata.preTokens
      local trigger = params.compactMetadata and params.compactMetadata.trigger or "auto"
      local info = tokens and string.format(" (%s, %dk tokens)", trigger, math.floor(tokens / 1000)) or ""
      render.append_content(buf, { "", "[~] Context compacted" .. info, "" })
    elseif config.debug then
      render.append_content(buf, { "[debug] system: " .. vim.inspect(params):sub(1, 200) })
    end

  elseif method:match("^terminal/") then
    local response = {
      jsonrpc = "2.0",
      id = msg_id,
      result = {}
    }
    if method == "terminal/create" then
      local term_id = "term_" .. os.time() .. "_" .. math.random(1000, 9999)
      proc.data.terminals[term_id] = { id = term_id, buf = nil }
      response.result = { terminalId = term_id }
    end
    vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")

  elseif msg_id then
    local url = params and (params.url or params.uri)
    local prompt_text = params and (params.prompt or params.message)

    render.append_content(buf, {
      "[*] Agent request: " .. method .. " " .. vim.inspect(params):sub(1, 200)
    })

    if url then
      vim.ui.open(url)
      render.append_content(buf, { "[*] Opened: " .. url })
    end

    if prompt_text then
      render.append_content(buf, { "[?] Agent asks: " .. prompt_text })
      vim.ui.input({ prompt = prompt_text .. " " }, function(input)
        local result = {}
        if input and input ~= "" then
          result = { line = input, value = input, input = input }
          render.append_content(buf, { "[+] Sent response" })
        end
        if proc.job_id then
          vim.fn.chansend(proc.job_id, vim.json.encode({
            jsonrpc = "2.0",
            id = msg_id,
            result = result,
          }) .. "\n")
        end
      end)
    else
      vim.fn.chansend(proc.job_id, vim.json.encode({
        jsonrpc = "2.0",
        id = msg_id,
        result = {},
      }) .. "\n")
    end
  end
end

local function get_provider(provider_id)
  provider_id = provider_id or config.default_provider
  return provider_id, config.providers[provider_id]
end

local function create_process(session_id, opts)
  opts = opts or {}

  local provider_id, provider = get_provider(opts.provider)
  if not provider then
    provider_id = config.default_provider
    provider = config.providers[provider_id]
  end

  local args = vim.deepcopy(provider.args or {})
  if opts.extra_args then
    for _, arg in ipairs(opts.extra_args) do
      table.insert(args, arg)
    end
  end

  local proc = Process.new(session_id, {
    cmd = provider.cmd,
    args = args,
    env = vim.tbl_extend("force", provider.env or {}, opts.env or {}),
    cwd = opts.cwd or get_current_project_root(),
    debug = config.debug,
    load_session_id = opts.load_session_id,
    provider = provider_id,
    profile_id = opts.profile_id,
  })
  proc._created_at = os.time()
  proc.data.profile_id = opts.profile_id

  proc:set_handlers({
    on_method = function(self, method, params, msg_id)
      handle_method(self, method, params, msg_id)
    end,
    on_debug = function(self, line)
      if self.data.buf then
        render.append_content(self.data.buf, { "[debug] " .. line })
      end
    end,
    on_exit = function(self, code, was_alive)
      render.stop_animation()
      if code ~= 0 and self.data.buf and was_alive then
        render.append_content(self.data.buf, { "Process exited with code: " .. code })
        if config.reconnect and ui.active and self.state.reconnect_count < config.max_reconnect_attempts then
          self.state.reconnect_count = self.state.reconnect_count + 1
          render.append_content(self.data.buf, { "Reconnecting... (" .. self.state.reconnect_count .. "/" .. config.max_reconnect_attempts .. ")" })
          vim.defer_fn(function()
            if ui.active and self.session_id == registry.active_session_id() then
              self:restart()
            end
          end, 1000)
        end
      else
        self.state.reconnect_count = 0
      end
    end,
    on_ready = function(self)
      update_statusline()
    end,
    on_status = function(self, status, data)
      local buf = self.data.buf
      if not buf then return end

      if status == "initialized" then
        local caps = {}
        if self.state.agent_capabilities.loadSession then table.insert(caps, "sessions") end
        if self.state.agent_capabilities.modes then table.insert(caps, "modes") end
        if self.state.agent_capabilities.plans then table.insert(caps, "plans") end
        local agent_name = self:get_agent_name()
        local caps_str = #caps > 0 and " [" .. table.concat(caps, ", ") .. "]" or ""

        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_set_name, buf, agent_name)
        end
        render.append_content(buf, { "Connected: " .. agent_name .. caps_str })

      elseif status == "session_created" then
        local session_name = get_session_name(self.data.cwd)
        self.data.name = session_name
        local buf_name = "AI: " .. session_name
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_set_name, buf, buf_name)
        end
        render.append_content(buf, { "Project: " .. self.data.cwd, "[+] Session ready", "" })
        update_statusline()

      elseif status == "session_loaded" then
        if not self.data.name or self.data.name == "New Session" then
          local session_name = get_session_name(self.data.cwd)
          self.data.name = session_name
          local buf_name = "AI: " .. session_name
          if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_set_name, buf, buf_name)
          end
        end
        local messages = registry.load_messages(self.session_id)
        if messages and #messages > 0 then
          render.render_history(buf, messages)
        else
          render.append_content(buf, { "[+] Session loaded: " .. self.session_id:sub(1, 8) .. "...", "" })
        end
        update_statusline()

      elseif status == "session_load_failed" then
        render.append_content(buf, { "[!] Session load failed, creating new..." })

      elseif status == "auth_methods_available" then

      elseif status == "session_error_detail" then
        local detail = type(data) == "table" and vim.inspect(data):sub(1, 300) or tostring(data)
        render.append_content(buf, { "[!] session/new error: " .. detail })

      elseif status == "authenticating" then
      elseif status == "authenticated" then
      elseif status == "auth_failed" then
      elseif status == "auth_timeout" then

      elseif status == "init_failed" or status == "session_failed" then
        local err_msg = type(data) == "table" and (data.message or vim.json.encode(data)) or tostring(data)
        render.append_content(buf, { "[!] Error: " .. err_msg })

      elseif status == "resetting_session" then
        update_statusline()

      elseif status == "session_reset" then
        update_statusline()

      elseif status == "session_reset_failed" then
        render.append_content(buf, { "[!] Session reset failed" })
      end
    end,
  })

  proc._on_session_id_changed = function(self, old_id, new_id)
    local was_active = registry.active_session_id() == old_id
    registry.unregister(old_id)
    registry.set(new_id, self)
    if was_active then
      registry.set_active(new_id)
    end
  end

  return proc
end

local function create_buffer(proc, name)
  local buf = vim.api.nvim_create_buf(true, false)
  local session_name = name or get_session_name(proc.data.cwd)
  local buf_name = "AI: " .. session_name
  pcall(vim.api.nvim_buf_set_name, buf, buf_name)

  render.init_buffer(buf)
  proc.data.buf = buf
  proc.data.name = session_name

  return buf
end

local IMAGE_EXTENSIONS = {
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  webp = "image/webp",
  svg = "image/svg+xml",
}

local function get_mime_type(file_path)
  local ext = file_path:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    if IMAGE_EXTENSIONS[ext] then
      return IMAGE_EXTENSIONS[ext], true
    end
  end
  return "text/plain", false
end

local function read_file_content(file_path, is_image)
  if is_image then
    local f = io.open(file_path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local ok, encoded = pcall(function()
      return vim.base64.encode(data)
    end)
    if ok then return encoded end
    return nil
  else
    local lines = vim.fn.readfile(file_path)
    return table.concat(lines, "\n")
  end
end

local function parse_file_references(text)
  local prompt = {}
  local files = {}
  local remaining_text = text

  for file_ref in text:gmatch("@([^%s]+)") do
    local abs_path = vim.fn.fnamemodify(file_ref, ":p")
    if vim.fn.filereadable(abs_path) == 1 then
      table.insert(files, abs_path)
      remaining_text = remaining_text:gsub("@" .. vim.pesc(file_ref), "", 1)
    end
  end

  for _, file_path in ipairs(files) do
    local mime_type, is_image = get_mime_type(file_path)
    local content = read_file_content(file_path, is_image)

    if content then
      local resource = {
        uri = "file://" .. file_path,
        name = vim.fn.fnamemodify(file_path, ":t"),
        mimeType = mime_type,
      }
      if is_image then
        resource.blob = content
      else
        resource.text = content
      end
      table.insert(prompt, { type = "resource", resource = resource })
    end
  end

  remaining_text = remaining_text:gsub("^%s*(.-)%s*$", "%1")
  if remaining_text ~= "" then
    table.insert(prompt, { type = "text", text = remaining_text })
  end

  return prompt, #files > 0
end

local function setup_buffer_keymaps(buf)
  local function submit()
    local raw_text = render.get_prompt_input(buf)
    local text = raw_text:gsub("^%s*(.-)%s*$", "%1")

    if questionnaire.is_awaiting_input() then
      render.clear_prompt_input(buf)
      questionnaire.handle_text_input(text)
      return
    end

    if text == "" then
      vim.notify("AI REPL: Empty prompt", vim.log.levels.DEBUG)
      return
    end
    render.clear_prompt_input(buf)

    if text:sub(1, 1) == "/" then
      M.handle_command(text:sub(2))
    else
      local proc = registry.active()
      local prompt, has_files = parse_file_references(text)

      if proc and #proc.data.context_files > 0 then
        for _, file_path in ipairs(proc.data.context_files) do
          local mime_type, is_image = get_mime_type(file_path)
          local file_content = read_file_content(file_path, is_image)
          if file_content then
            local resource = {
              uri = "file://" .. file_path,
              name = vim.fn.fnamemodify(file_path, ":t"),
              mimeType = mime_type,
            }
            if is_image then
              resource.blob = file_content
            else
              resource.text = file_content
            end
            table.insert(prompt, 1, { type = "resource", resource = resource })
          end
        end
        proc.data.context_files = {}
      end

      if has_files or #prompt > 1 then
        M.send_prompt(prompt)
      else
        M.send_prompt(text)
      end
    end
  end

  render.setup_cursor_lock(buf)

  local opts = { buffer = buf, silent = true }
  vim.keymap.set("i", "<CR>", submit, opts)
  vim.keymap.set("n", "<CR>", submit, opts)
  vim.keymap.set("n", "q", M.hide, opts)
  vim.keymap.set("n", "<Esc>", M.hide, opts)
  vim.keymap.set("n", "<C-c>", M.cancel, opts)
  vim.keymap.set("i", "<C-c>", M.cancel, opts)
  vim.keymap.set({ "n", "i" }, "<S-Tab>", function() M.show_mode_picker() end, opts)
  vim.keymap.set("n", "<C-q>", M.show_queue, opts)
  vim.keymap.set("n", "<C-e>", M.edit_queued, opts)
  vim.keymap.set("n", "i", function()
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then render.goto_prompt(buf, win) end
  end, opts)
  vim.keymap.set("n", "a", function()
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then render.goto_prompt(buf, win) end
  end, opts)
  vim.keymap.set("n", "G", function()
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then render.goto_prompt(buf, win) end
  end, opts)

  vim.keymap.set("i", "@", function()
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      local root = get_current_project_root()
      local target_buf = buf
      local target_win = vim.api.nvim_get_current_win()
      snacks.picker.files({
        layout = { preset = "vscode" },
        cwd = root,
        confirm = function(picker, item)
          picker:close()
          if item then
            local file_path = item.file or item[1]
            if file_path then
              local rel_path = vim.fn.fnamemodify(file_path, ":.")
              vim.schedule(function()
                if vim.api.nvim_buf_is_valid(target_buf) and vim.api.nvim_win_is_valid(target_win) then
                  vim.api.nvim_set_current_win(target_win)
                  vim.api.nvim_win_set_buf(target_win, target_buf)
                  vim.cmd("startinsert")
                  vim.api.nvim_put({ "@" .. rel_path .. " " }, "c", false, true)
                end
              end)
            end
          end
        end,
        on_close = function()
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(target_buf) and vim.api.nvim_win_is_valid(target_win) then
              vim.api.nvim_set_current_win(target_win)
              vim.cmd("startinsert")
            end
          end)
        end,
      })
    else
      vim.api.nvim_put({ "@" }, "c", false, true)
    end
  end, opts)

  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      local p, sid = registry.get_by_buffer(buf)
      if p and sid and sid ~= registry.active_session_id() then
        registry.set_active(sid)
        update_statusline()
      end
    end
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    callback = function()
      render.cleanup_buffer(buf)
    end
  })
end

local function create_ui()
  local width = config.window.width < 1 and math.floor(vim.o.columns * config.window.width) or config.window.width

  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  set_tab_win(win)
  vim.api.nvim_win_set_width(win, width)
  setup_window_options(win)

  local provider_id = ui.pending_provider or config.default_provider
  local profile_id = ui.pending_profile
  local extra_args = ui.pending_extra_args
  ui.pending_provider = nil
  ui.pending_profile = nil
  ui.pending_extra_args = nil

  local temp_id = "temp_" .. os.time() .. "_" .. math.random(1000, 9999)
  local proc = create_process(temp_id, {
    cwd = ui.project_root,
    provider = provider_id,
    profile_id = profile_id,
    extra_args = extra_args,
  })
  local buf = create_buffer(proc, "New Session")

  registry.set(temp_id, proc)
  registry.set_active(temp_id)

  vim.api.nvim_win_set_buf(win, buf)
  setup_buffer_keymaps(buf)

  local provider = config.providers[provider_id]
  local provider_display = provider and provider.name or provider_id
  if profile_id then
    provider_display = provider_display .. ":" .. profile_id
  end
  render.append_content(buf, { "AI REPL (" .. provider_display .. ") | /help for commands", "" })

  proc:start()

  render.goto_prompt(buf, win)
end

function M.send_prompt(content, opts)
  opts = opts or {}
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  if not proc:is_alive() then
    render.append_content(proc.data.buf, { "Error: Agent not running" })
    return
  end

  if not proc:is_ready() then
    render.append_content(proc.data.buf, { "Error: Session not ready yet, please wait..." })
    return
  end

  local prompt
  local user_message_text = ""

  if type(content) == "string" then
    prompt = { { type = "text", text = content } }
    user_message_text = content
  elseif type(content) == "table" then
    prompt = content
    local preview = ""
    for _, block in ipairs(content) do
      if block.type == "text" then
        preview = preview .. block.text
      elseif block.type == "resource" then
        preview = preview .. "[" .. (block.resource.uri or "resource") .. "] "
      elseif block.type == "resource_link" then
        preview = preview .. "[@" .. (block.resourceLink and block.resourceLink.name or "file") .. "] "
      end
    end
    user_message_text = preview
  else
    return
  end

  local is_queued = proc.state.busy

  -- Initialize Ralph Wiggum mode if enabled
  local modes_module = require("ai_repl.modes")
  if modes_module.is_ralph_wiggum_mode() and not is_queued and not opts.silent then
    local ralph = require("ai_repl.modes.ralph_wiggum")
    if ralph.get_iteration_count() == 0 and ralph.is_planning_phase() then
      ralph.set_original_prompt(user_message_text)
      local planning_prompt = ralph.get_planning_prompt(user_message_text)
      render.append_content(proc.data.buf, {
        "",
        "┌─ Ralph Wiggum Mode ─────────────────────────",
        "│ Phase 1: PLANNING (research & docs)",
        "│ Phase 2: EXECUTION (implementation)",
        "└─────────────────────────────────────────────",
        "",
      })
      prompt = planning_prompt
      user_message_text = planning_prompt:sub(1, 100)
    end
  end

  if not opts.silent then
    if is_queued then
      local queue_pos = #proc.data.prompt_queue + 1
      render.append_content(proc.data.buf, { "", "> " .. user_message_text:sub(1, 100) .. " [queued #" .. queue_pos .. "]" })
    else
      render.append_content(proc.data.buf, { "", "> " .. user_message_text:sub(1, 100) })
    end
  end

  if not opts.silent and user_message_text ~= "" then
    registry.append_message(proc.session_id, "user", user_message_text)
  end

  proc:send_prompt(prompt)
  update_statusline()
end

function M.set_mode(mode_id)
  local proc = registry.active()
  if not proc or not proc:is_ready() then return end
  proc:set_mode(mode_id)
  update_statusline()
  render.append_content(proc.data.buf, { "Mode set to: " .. mode_id })
end

function M.cancel()
  local proc = registry.active()
  if not proc then return end
  proc:cancel()
  render.stop_animation()
  render.append_content(proc.data.buf, { "Cancelled" })
end

function M.show_queue()
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  local queue = proc:get_queue()
  if #queue == 0 then
    render.append_content(proc.data.buf, { "[i] Queue is empty" })
    return
  end

  local lines = { "", "━━━ Queue ━━━" }
  for i, item in ipairs(queue) do
    local text = item.text or (type(item.prompt) == "string" and item.prompt or "")
    if #text > 60 then text = text:sub(1, 57) .. "..." end
    table.insert(lines, string.format(" %d. %s", i, text))
  end
  table.insert(lines, "━━━━━━━━━━━━")
  table.insert(lines, "")
  render.append_content(proc.data.buf, lines)
end

function M.edit_queued(index)
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  local queue = proc:get_queue()
  if #queue == 0 then
    vim.notify("Queue is empty", vim.log.levels.INFO)
    return
  end

  local function do_edit(idx)
    local item = proc:get_queued_item(idx)
    if not item then
      vim.notify("Invalid queue index: " .. idx, vim.log.levels.ERROR)
      return
    end

    local current_text = item.text or (type(item.prompt) == "string" and item.prompt or "")
    vim.ui.input({ prompt = "Edit queued #" .. idx .. ": ", default = current_text }, function(new_text)
      if new_text and new_text ~= "" then
        proc:update_queued_item(idx, new_text)
        render.append_content(proc.data.buf, { "[+] Updated queued #" .. idx })
        update_statusline()
      end
    end)
  end

  if index then
    do_edit(index)
  elseif #queue == 1 then
    do_edit(1)
  else
    local items = {}
    for i, item in ipairs(queue) do
      local text = truncate(item.text or (type(item.prompt) == "string" and item.prompt or ""), 50)
      table.insert(items, string.format("#%d: %s", i, text))
    end

    vim.ui.select(items, { prompt = "Select message to edit:" }, function(choice, idx)
      if choice and idx then
        do_edit(idx)
      end
    end)
  end
end

function M.remove_queued(index)
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  local queue = proc:get_queue()
  if #queue == 0 then
    vim.notify("Queue is empty", vim.log.levels.INFO)
    return
  end

  local function do_remove(idx)
    local removed = proc:remove_queued_item(idx)
    if removed then
      render.append_content(proc.data.buf, { "[x] Removed queued #" .. idx })
      update_statusline()
    else
      vim.notify("Invalid queue index: " .. idx, vim.log.levels.ERROR)
    end
  end

  if index then
    do_remove(index)
  elseif #queue == 1 then
    do_remove(1)
  else
    local items = {}
    for i, item in ipairs(queue) do
      local text = truncate(item.text or (type(item.prompt) == "string" and item.prompt or ""), 50)
      table.insert(items, string.format("#%d: %s", i, text))
    end

    vim.ui.select(items, { prompt = "Select message to remove:" }, function(choice, idx)
      if choice and idx then
        do_remove(idx)
      end
    end)
  end
end

function M.clear_queue()
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  local count = #proc:get_queue()
  if count == 0 then
    vim.notify("Queue is empty", vim.log.levels.INFO)
    return
  end

  proc:clear_queue()
  render.append_content(proc.data.buf, { "[x] Cleared " .. count .. " queued messages" })
  update_statusline()
end

local function get_settings_path()
  local proc = registry.active()
  local cwd = proc and proc.data.cwd or vim.fn.getcwd()
  return cwd .. "/.claude/settings.local.json"
end

local function read_settings()
  local path = get_settings_path()
  if vim.fn.filereadable(path) ~= 1 then return nil end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  return ok and data or nil
end

local function write_settings(data)
  local path = get_settings_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(data) }, path)
end

function M.show_permissions()
  local proc = registry.active()
  if not proc then return end

  local data = read_settings()
  local allow = data and data.permissions and data.permissions.allow or {}

  if #allow == 0 then
    render.append_content(proc.data.buf, { "[i] No allow rules" })
    return
  end

  local lines = { "", "━━━ Allowed ━━━" }
  for i, rule in ipairs(allow) do
    table.insert(lines, string.format("  %d. %s", i, rule))
  end
  table.insert(lines, "━━━━━━━━━━━━━━━")
  render.append_content(proc.data.buf, lines)
end

function M.revoke_permission()
  local proc = registry.active()
  if not proc then return end

  local data = read_settings()
  local allow = data and data.permissions and data.permissions.allow or {}

  if #allow == 0 then
    vim.notify("No permissions to revoke", vim.log.levels.INFO)
    return
  end

  vim.ui.select(allow, { prompt = "Revoke:" }, function(choice, idx)
    if not choice then return end
    table.remove(data.permissions.allow, idx)
    write_settings(data)
    render.append_content(proc.data.buf, { "[x] Revoked: " .. choice })
  end)
end

function M.handle_command(cmd)
  local proc = registry.active()
  local buf = proc and proc.data.buf

  local parts = vim.split(cmd, "%s+", { trimempty = true })
  local command = parts[1] or ""
  local args = { unpack(parts, 2) }

  if command == "help" or command == "h" then
    render.append_content(buf, {
      "", "Commands:",
      "  /help - Show this help",
      "  /ext - All extensions (skills + commands + local)",
      "  /ext <category> - Filter by category (skills/agent/session)",
      "  /cmd - Agent slash commands only",
      "  /skill - Make a skill available to agent",
      "  /skill off - Remove skill symlink",
      "  /skill info <name> - Show skill information",
      "  /skill verify - Verify all skills for current provider",
      "  /new - New session",
      "  /sessions - List sessions",
      "  /mode [mode] - Show/switch mode (chat/spec)",
      "  /spec export - Export spec to markdown",
      "  /cwd [path] - Show/change working directory",
      "  /queue - Show queued messages",
      "  /edit [n] - Edit queued message",
      "  /remove [n] - Remove queued message",
      "  /clearq - Clear all queued messages",
      "  /perms - Show allow rules",
      "  /revoke - Revoke allow rule",
      "  /clear - Clear buffer",
      "  /cancel - Cancel current",
      "  /quit - Close REPL",
      "",
      "Ralph Wiggum (SDLC mode):",
      "  /ralph pause   - Pause looping",
      "  /ralph resume  - Resume looping",
      "  /ralph stop    - Stop and show summary",
      "  /ralph status  - Show current status",
      "  /ralph history - Show iteration history",
      "  /ralph max N   - Set max iterations",
      "",
      "Ralph Loop (simple re-injection):",
      "  /ralph-loop <prompt> - Start loop that re-injects same prompt",
      "  /ralph-loop-status   - Show loop status",
      "  /cancel-ralph        - Cancel the loop",
      "  Options: --max-iterations N --completion-promise STRING --timeout N",
      "",
      "Extensions System:",
      "  /ext - Unified picker for skills, agent commands, and local commands",
      "  Categories: skills, agent, session, messages, security, control, system",
      "  Use /ext <category> to filter (e.g., /ext skills)",
      "",
      "Skills:",
      "  Skills are agent-side features that agents load automatically",
      "  when relevant. /skill symlinks to provider-specific paths where",
      "  agents discover them. Use /skill verify to check accessibility.",
      "",
      "Modes:",
      "  💬 Chat - Free-form conversation (default)",
      "  📋 Spec - Spec-driven development (Requirements→Design→Tasks→Implementation)",
      "  🔄 Ralph Wiggum - Persistent looping until task completion (works with ALL providers)",
      ""
    })
  elseif command == "new" then
    M.new_session()
  elseif command == "sessions" then
    M.open_session_picker()
  elseif command == "mode" then
    if args[1] then
      M.switch_to_mode(args[1])
    else
      M.show_mode_status()
    end
  elseif command == "cwd" then
    if args[1] then
      local new_cwd = vim.fn.expand(args[1])
      if vim.fn.isdirectory(new_cwd) == 1 then
        new_cwd = vim.fn.fnamemodify(new_cwd, ":p"):gsub("/$", "")
        if proc then
          proc.data.cwd = new_cwd
          ui.project_root = new_cwd
          render.append_content(buf, { "Working directory: " .. new_cwd })
        end
      else
        render.append_content(buf, { "[!] Not a directory: " .. new_cwd })
      end
    else
      local cwd = proc and proc.data.cwd or ui.project_root or vim.fn.getcwd()
      render.append_content(buf, { "Working directory: " .. cwd })
    end
  elseif command == "clear" then
    if buf then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      render.init_buffer(buf)
    end
  elseif command == "cancel" then
    M.cancel()
  elseif command == "queue" or command == "q" then
    M.show_queue()
  elseif command == "edit" or command == "e" then
    local idx = args[1] and tonumber(args[1])
    M.edit_queued(idx)
  elseif command == "remove" or command == "rm" then
    local idx = args[1] and tonumber(args[1])
    M.remove_queued(idx)
  elseif command == "clearq" or command == "cq" then
    M.clear_queue()
  elseif command == "perms" or command == "permissions" then
    M.show_permissions()
  elseif command == "revoke" then
    M.revoke_permission()
  elseif command == "quit" or command == "close" then
    M.close()
  elseif command == "debug" then
    config.debug = not config.debug
    if proc then
      proc.config.debug = config.debug
    end
    render.append_content(buf, { "Debug: " .. tostring(config.debug) })
  elseif command == "skill" or command == "skills" then
    if args[1] == "off" or args[1] == "clear" then
      M.deactivate_skill()
    elseif args[1] == "info" and args[2] then
      M.show_skill_info(args[2])
    elseif args[1] == "verify" then
      M.verify_all_skills()
    else
      M.show_skill_picker()
    end
  elseif command == "ext" or command == "extensions" then
    M.show_extensions_picker(args[1])
  elseif command == "cm" or command == "commands" or command == "cmd" then
    M.show_agent_commands_only()
  elseif command == "ralph" then
    local ralph = require("ai_repl.modes.ralph_wiggum")
    local modes = require("ai_repl.modes")
    local subcommand = args[1]

    if subcommand == "pause" then
      if ralph.pause() then
        render.append_content(buf, { "", "[⏸️ Ralph Wiggum paused. Use /ralph resume to continue]" })
      else
        render.append_content(buf, { "", "[!] Ralph Wiggum not active" })
      end
    elseif subcommand == "resume" then
      if ralph.resume() then
        render.append_content(buf, { "", "[▶️ Ralph Wiggum resumed]" })
        if proc then
          local continuation = ralph.get_continuation_prompt()
          vim.defer_fn(function()
            proc:send_prompt(continuation, { silent = true })
          end, 500)
        end
      else
        render.append_content(buf, { "", "[!] Ralph Wiggum not paused or not active" })
      end
    elseif subcommand == "stop" or subcommand == "cancel" then
      if ralph.is_enabled() then
        local summary = ralph.get_summary()
        ralph.disable()
        modes.switch_mode("chat")
        render.append_content(buf, { "", "[⏹️ Ralph Wiggum stopped]" })
        if summary then
          render.append_content(buf, {
            "┌─ Final Summary ─────────────────────────────",
            string.format("│ Completed iterations: %d", summary.iterations),
            "└─────────────────────────────────────────────",
          })
        end
      else
        render.append_content(buf, { "", "[!] Ralph Wiggum not active" })
      end
    elseif subcommand == "status" then
      local status = ralph.get_status()
      if status.enabled then
        local phase_display = status.phase == "planning" and "📋 PLANNING" or "⚡ EXECUTION"
        render.append_content(buf, {
          "",
          "┌─ Ralph Wiggum Status ───────────────────────",
          string.format("│ State: %s", status.paused and "PAUSED" or "RUNNING"),
          string.format("│ Phase: %s", phase_display),
          string.format("│ Iteration: %d%s", status.iteration, status.phase == "execution" and ("/" .. status.max_iterations .. " (" .. status.progress_pct .. "%)") or ""),
          string.format("│ Has plan: %s", status.has_plan and "Yes" or "No"),
          string.format("│ Stuck count: %d", status.stuck_count),
          string.format("│ Current delay: %dms", status.backoff_delay),
          "└─────────────────────────────────────────────",
        })
      else
        render.append_content(buf, { "", "[i] Ralph Wiggum not active" })
      end
    elseif subcommand == "history" then
      local history = ralph.get_history()
      if #history == 0 then
        render.append_content(buf, { "", "[i] No iteration history" })
      else
        local lines = { "", "┌─ Iteration History ─────────────────────────" }
        for _, entry in ipairs(history) do
          table.insert(lines, string.format("│ #%d: %d chars%s",
            entry.iteration,
            entry.response_length or 0,
            entry.stuck_count > 0 and " (stuck:" .. entry.stuck_count .. ")" or ""
          ))
        end
        table.insert(lines, "└─────────────────────────────────────────────")
        render.append_content(buf, lines)
      end
    elseif subcommand == "max" and args[2] then
      local new_max = tonumber(args[2])
      if new_max and new_max > 0 then
        ralph.enable({ max_iterations = new_max })
        render.append_content(buf, { "", "[i] Max iterations set to " .. new_max })
      else
        render.append_content(buf, { "", "[!] Invalid number" })
      end
    else
      render.append_content(buf, {
        "", "Ralph Wiggum Commands:",
        "  /ralph pause   - Pause looping",
        "  /ralph resume  - Resume looping",
        "  /ralph stop    - Stop and show summary",
        "  /ralph status  - Show current status",
        "  /ralph history - Show iteration history",
        "  /ralph max N   - Set max iterations",
        "",
        "To enable Ralph mode: /mode ralph_wiggum",
      })
    end
  elseif command == "ralph-loop" then
    if not proc then
      render.append_content(buf, { "", "[!] No active session" })
      return
    end

    local prompt_parts = {}
    local max_iterations = 150
    local completion_promise = nil
    local response_timeout_ms = 60000
    local circuit_breaker_threshold = 5

    local i = 1
    while i <= #args do
      local arg = args[i]
      if arg == "--max-iterations" and args[i + 1] then
        max_iterations = tonumber(args[i + 1]) or 150
        i = i + 2
      elseif arg == "--completion-promise" and args[i + 1] then
        completion_promise = args[i + 1]
        i = i + 2
      elseif arg == "--timeout" and args[i + 1] then
        response_timeout_ms = (tonumber(args[i + 1]) or 60) * 1000
        i = i + 2
      elseif arg == "--circuit-breaker" and args[i + 1] then
        circuit_breaker_threshold = tonumber(args[i + 1]) or 5
        i = i + 2
      else
        table.insert(prompt_parts, arg)
        i = i + 1
      end
    end

    local prompt = table.concat(prompt_parts, " ")
    if prompt == "" then
      render.append_content(buf, {
        "", "Usage: /ralph-loop <prompt> [options]",
        "",
        "Options:",
        "  --max-iterations N       Max loop iterations (default: 150)",
        "  --completion-promise STR  Exit when output contains this string",
        "  --timeout N              Response timeout in seconds (default: 60)",
        "  --circuit-breaker N      Exit after N consecutive completion signals (default: 5)",
        "",
        "Example:",
        "  /ralph-loop Build a REST API. Output <promise>DONE</promise> when complete. --completion-promise DONE --max-iterations 50",
      })
      return
    end

    ralph_helper.start_loop(proc, prompt, {
      max_iterations = max_iterations,
      completion_promise = completion_promise,
      response_timeout_ms = response_timeout_ms,
      circuit_breaker_threshold = circuit_breaker_threshold,
    })

  elseif command == "cancel-ralph" then
    if not proc then
      render.append_content(buf, { "", "[!] No active session" })
      return
    end

    if ralph_helper.is_loop_enabled() then
      ralph_helper.cancel_loop(proc)
    else
      render.append_content(buf, { "", "[!] Ralph Loop not active" })
    end

  elseif command == "ralph-loop-status" then
    local status = ralph_helper.get_loop_status()
    if status.enabled then
      render.append_content(buf, {
        "",
        "┌─ Ralph Loop Status ─────────────────────────",
        string.format("│ State: RUNNING"),
        string.format("│ Phase: %s", status.phase_display),
        string.format("│ Execution iteration: %d/%d", status.current_iteration, status.max_iterations),
        string.format("│ Completion promise: %s", status.completion_promise or "(none)"),
        string.format("│ Consecutive completion signals: %d", status.consecutive_completion_signals),
        "│",
        "│ Use /cancel-ralph to stop",
        "└─────────────────────────────────────────────",
      })
    else
      render.append_content(buf, { "", "[i] Ralph Loop not active" })
    end
  else
    if proc and proc.data.slash_commands then
      for _, sc in ipairs(proc.data.slash_commands) do
        if sc.name == command or sc.name == "/" .. command then
          proc:notify("session/slash_command", {
            sessionId = proc.session_id,
            commandName = sc.name,
            args = args
          })
          return
        end
      end
    end
    render.append_content(buf, { "[!] Unknown command: " .. command })
  end
end

function M.show_skill_picker()
  local skills_module = require("ai_repl.skills")
  local skills = skills_module.list_skills()

  if #skills == 0 then
    vim.notify("No skills found in ~/.claude/skills", vim.log.levels.WARN)
    return
  end

  local lines = {}
  for i, skill in ipairs(skills) do
    local desc = truncate(skill.description, 100)
    table.insert(lines, string.format("%d. %s - %s", i, skill.name, desc))
  end

  vim.ui.select(lines, {
    prompt = "Select a skill to activate:",
  }, function(choice, idx)
    if choice and idx then
      M.activate_skill(skills[idx].name)
    end
  end)
end

function M.activate_skill(skill_name)
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.ERROR)
    return
  end

  local skills_module = require("ai_repl.skills")
  local provider_id = proc.data.provider or config.default_provider

  local success, status = skills_module.ensure_skill_available_for_provider(skill_name, provider_id)

  if not success then
    vim.notify("Failed to activate skill: " .. status, vim.log.levels.ERROR)
    return
  end

  local is_accessible, path = skills_module.verify_skill_accessible(skill_name, provider_id)

  local buf = proc.data.buf
  if buf then
    local status_msg = ""
    if status == "linked" then
      status_msg = " (symlinked)"
    elseif status == "copied" then
      status_msg = " (copied)"
    elseif status == "already_available" or status == "already_linked" then
      status_msg = " (already available)"
    end

    local provider_msg = ""
    if is_accessible then
      provider_msg = "\n[Accessible to " .. provider_id .. " at " .. path .. "]"
    end

    render.append_content(buf, {
      "",
      "[Skill made available: " .. skill_name .. status_msg .. "]" .. provider_msg,
      "[Agent will load when relevant]",
      ""
    })
  end

  proc.data.active_skill = skill_name

  vim.notify("Skill available to " .. provider_id .. ": " .. skill_name, vim.log.levels.INFO)
end

function M.deactivate_skill()
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.ERROR)
    return
  end

  if not proc.data.active_skill then
    vim.notify("No skill is currently active", vim.log.levels.INFO)
    return
  end

  local skill_name = proc.data.active_skill
  local skills_module = require("ai_repl.skills")
  local success, status = skills_module.remove_skill_link(skill_name)

  proc.data.active_skill = nil

  local buf = proc.data.buf
  if buf then
    local msg = "[Skill tracking stopped: " .. skill_name .. "]"
    if success then
      msg = "[Skill removed: " .. skill_name .. " (symlink removed)]"
    end

    render.append_content(buf, {
      "",
      msg,
      ""
    })
  end

  if success then
    vim.notify("Skill removed: " .. skill_name, vim.log.levels.INFO)
  else
    vim.notify("Skill tracking stopped (manual cleanup may be needed)", vim.log.levels.WARN)
  end
end

function M.show_skill_info(skill_name)
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.ERROR)
    return
  end

  local skills_module = require("ai_repl.skills")
  local skill = skills_module.get_skill(skill_name)

  if not skill then
    vim.notify("Skill not found: " .. skill_name, vim.log.levels.ERROR)
    return
  end

  local provider_id = proc.data.provider or config.default_provider
  local is_accessible, path = skills_module.verify_skill_accessible(skill_name, provider_id)

  local buf = proc.data.buf
  if buf then
    local lines = {
      "",
      "Skill: " .. skill.name,
      "Description: " .. skill.description,
      "Version: " .. skill.version,
      "Source: " .. skill.path,
      "",
      "Provider: " .. provider_id,
      "Accessible: " .. (is_accessible and "Yes" or "No"),
    }

    if is_accessible then
      table.insert(lines, "Available at: " .. path)
    end

    table.insert(lines, "")
    table.insert(lines, "References: " .. #skill.references)
    table.insert(lines, "Scripts: " .. #skill.scripts)
    table.insert(lines, "")

    render.append_content(buf, lines)
  end
end

function M.verify_all_skills()
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.ERROR)
    return
  end

  local skills_module = require("ai_repl.skills")
  local all_skills = skills_module.list_skills()
  local provider_id = proc.data.provider or config.default_provider

  if #all_skills == 0 then
    vim.notify("No skills found", vim.log.levels.WARN)
    return
  end

  local buf = proc.data.buf
  if buf then
    local lines = {
      "",
      "Skill Accessibility for Provider: " .. provider_id,
      "",
    }

    for _, skill in ipairs(all_skills) do
      local is_accessible, path = skills_module.verify_skill_accessible(skill.name, provider_id)
      local status = is_accessible and "✓" or "✗"
      local location = is_accessible and (" (" .. path .. ")") or ""
      table.insert(lines, "  " .. status .. " " .. skill.name .. location)
    end

    table.insert(lines, "")
    render.append_content(buf, lines)
  end

  vim.notify("Verified " .. #all_skills .. " skills for " .. provider_id, vim.log.levels.INFO)
end

function M.show_extensions_picker(category_filter)
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.ERROR)
    return
  end

  local extensions_module = require("ai_repl.extensions")
  local all_extensions = extensions_module.create_unified_picker(proc)

  if category_filter then
    all_extensions = extensions_module.filter_by_category(all_extensions, category_filter)
  end

  if #all_extensions == 0 then
    vim.notify("No extensions available", vim.log.levels.WARN)
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    local items = {}
    for _, ext in ipairs(all_extensions) do
      table.insert(items, {
        text = extensions_module.format_extension_for_display(ext),
        extension = ext,
      })
    end

    snacks.picker.pick({
      source = "select",
      items = items,
      prompt = category_filter and ("Extensions [" .. category_filter .. "]") or "All Extensions",
      format = function(item) return { { item.text } } end,
      confirm = function(picker, item)
        picker:close()
        if item and item.extension then
          vim.schedule(function()
            M.execute_extension(item.extension)
          end)
        end
      end,
    })
  else
    local buf = proc.data.buf
    if buf then
      local lines = { "", "Available Extensions:" }

      local by_category = {}
      for _, ext in ipairs(all_extensions) do
        by_category[ext.category] = by_category[ext.category] or {}
        table.insert(by_category[ext.category], ext)
      end

      local categories = { "skills", "agent", "session", "messages", "security", "control", "system" }
      for _, cat in ipairs(categories) do
        if by_category[cat] then
          table.insert(lines, "")
          table.insert(lines, "[" .. cat:upper() .. "]")
          for _, ext in ipairs(by_category[cat]) do
            table.insert(lines, "  " .. extensions_module.format_extension_for_display(ext))
          end
        end
      end

      table.insert(lines, "")
      render.append_content(buf, lines)
    end
  end
end

function M.show_agent_commands_only()
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.ERROR)
    return
  end

  if not proc.data.slash_commands or #proc.data.slash_commands == 0 then
    local buf = proc.data.buf
    if buf then
      render.append_content(buf, { "", "[!] No agent commands available", "" })
    end
    vim.notify("No agent commands available", vim.log.levels.WARN)
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    local items = {}
    for _, sc in ipairs(proc.data.slash_commands) do
      table.insert(items, {
        text = "⚡ " .. sc.name .. (sc.description and (" - " .. sc.description) or ""),
        command = sc,
      })
    end

    snacks.picker.pick({
      source = "select",
      items = items,
      prompt = "Agent Slash Commands",
      format = function(item) return { { item.text } } end,
      confirm = function(picker, item)
        picker:close()
        if item and item.command then
          vim.schedule(function()
            local cmd_text = "/" .. item.command.name
            render.append_content(proc.data.buf, { "", "> " .. cmd_text, "" })
            proc:send_prompt(cmd_text)
          end)
        end
      end,
    })
  else
    local buf = proc.data.buf
    if buf then
      local lines = { "", "Agent Commands:" }
      for _, sc in ipairs(proc.data.slash_commands) do
        table.insert(lines, "  ⚡ " .. sc.name .. (sc.description and (" - " .. sc.description) or ""))
      end
      table.insert(lines, "")
      render.append_content(buf, lines)
    end
  end
end

function M.execute_extension(extension)
  if extension.type == "skill" then
    M.activate_skill(extension.name)
  elseif extension.type == "command" then
    local proc = registry.active()
    if proc and proc.data.buf then
      local cmd_text = "/" .. extension.name
      render.append_content(proc.data.buf, { "", "> " .. cmd_text, "" })
      proc:send_prompt(cmd_text)
    end
  elseif extension.type == "local" then
    M.handle_command(extension.name)
  end
end

function M.show_mode_status()
  local proc = registry.active()
  if not proc then return end

  local modes_module = require("ai_repl.modes")
  local current_mode = modes_module.get_current_mode()
  local mode_info = modes_module.get_mode_info(current_mode)

  local lines = { "", "Mode: " .. mode_info.icon .. " " .. mode_info.name }

  for _, mode in ipairs(modes_module.list_modes()) do
    local marker = mode.id == current_mode and "[*]" or "[ ]"
    table.insert(lines, marker .. " " .. mode.icon .. " " .. mode.name)
  end

  render.append_content(proc.data.buf, lines)
end

function M.switch_to_mode(mode_id)
  local proc = registry.active()
  if not proc then return end

  local modes_module = require("ai_repl.modes")
  local success, result = modes_module.switch_mode(mode_id)

  if not success then
    render.append_content(proc.data.buf, { result })
    return
  end

  if result == "already_in_mode" then
    return
  end

  local info = result.info
  render.append_content(proc.data.buf, { "", info.icon .. " " .. info.name .. " mode" })
end

function M.show_mode_picker()
  local proc = registry.active()
  if not proc or not proc.state.modes or #proc.state.modes == 0 then
    vim.notify("No modes available", vim.log.levels.INFO)
    return
  end

  local labels = {}
  for _, m in ipairs(proc.state.modes) do
    local prefix = m.id == proc.state.mode and "[*] " or "[ ] "
    table.insert(labels, prefix .. m.name)
  end

  vim.ui.select(labels, { prompt = "Select mode:" }, function(choice, idx)
    if not choice or not idx then return end
    local mode = proc.state.modes[idx]
    if mode then
      M.set_mode(mode.id)
    end
  end)
end

function M.open()
  local win = get_tab_win()
  if win then
    M.show()
    return
  end
  ui.active = true
  ui.source_buf = vim.api.nvim_get_current_buf()
  ui.project_root = get_project_root(ui.source_buf)
  create_ui()
end

function M.close()
  local win = get_tab_win()
  if win then
    vim.api.nvim_win_close(win, true)
  end
  clear_tab_win()
  ui.active = false
end

function M.hide()
  local win = get_tab_win()
  if win then
    vim.api.nvim_win_hide(win)
  end
end

function M.show()
  local proc = registry.active()
  if not proc or not proc.data.buf then
    M.open()
    return
  end

  local win = get_tab_win()
  if not win then
    local width = config.window.width < 1 and math.floor(vim.o.columns * config.window.width) or config.window.width
    vim.cmd("botright vsplit")
    win = vim.api.nvim_get_current_win()
    set_tab_win(win)
    vim.api.nvim_win_set_width(win, width)
    setup_window_options(win)
  end

  vim.api.nvim_win_set_buf(win, proc.data.buf)
  update_statusline()
  vim.api.nvim_set_current_win(win)
end

function M.toggle()
  local win = get_tab_win()
  if win then
    M.hide()
  else
    local proc = registry.active()
    if proc and proc.data.buf and vim.api.nvim_buf_is_valid(proc.data.buf) then
      M.show()
    else
      M.open()
    end
  end
end

function M.pick_provider(callback)
  local items = {}
  for id, p in pairs(config.providers) do
    table.insert(items, { id = id, name = p.name or id })
  end
  table.sort(items, function(a, b) return a.name < b.name end)

  vim.ui.select(items, {
    prompt = "Select AI Provider:",
    format_item = function(item) return item.name end,
  }, function(choice)
    if choice and callback then
      callback(choice.id)
    end
  end)
end

function M.new_session(provider_id, profile_id)
  if not provider_id then
    M.pick_provider(function(id)
      M.new_session(id)
    end)
    return
  end

  local cur_buf = vim.api.nvim_get_current_buf()
  local proc = registry.active()
  if not (proc and proc.data.buf and cur_buf == proc.data.buf) then
    ui.source_buf = cur_buf
  end
  ui.project_root = get_project_root(ui.source_buf or cur_buf)

  local extra_args = nil
  if providers.supports_profiles(provider_id) then
    local codex_profiles = require("ai_repl.codex_profiles")
    local effective_profile = profile_id or codex_profiles.get_last_profile()
    if effective_profile then
      extra_args = codex_profiles.build_args(effective_profile)
      profile_id = effective_profile
    end
  end

  local win = get_tab_win()
  if not win then
    ui.active = true
    ui.pending_provider = provider_id
    ui.pending_profile = profile_id
    ui.pending_extra_args = extra_args
    create_ui()
    return
  end

  local width = config.window.width < 1 and math.floor(vim.o.columns * config.window.width) or config.window.width
  vim.api.nvim_win_set_width(win, width)
  setup_window_options(win)

  local temp_id = "temp_" .. os.time() .. "_" .. math.random(1000, 9999)
  local new_proc = create_process(temp_id, {
    cwd = ui.project_root,
    provider = provider_id,
    profile_id = profile_id,
    extra_args = extra_args,
  })
  local buf = create_buffer(new_proc, "New Session")

  registry.set(temp_id, new_proc)
  registry.set_active(temp_id)

  vim.api.nvim_win_set_buf(win, buf)
  setup_buffer_keymaps(buf)

  local provider = config.providers[provider_id]
  local provider_display = provider and provider.name or provider_id
  if profile_id then
    provider_display = provider_display .. ":" .. profile_id
  end
  render.append_content(buf, { "Creating new session with " .. provider_display .. "..." })

  new_proc:start()

  render.goto_prompt(buf, win)
end

function M.pick_codex_profile(callback)
  local codex_profiles = require("ai_repl.codex_profiles")
  local profiles = codex_profiles.list_profiles()

  if #profiles == 0 then
    vim.notify("No profiles found in ~/.codex/config.toml", vim.log.levels.WARN)
    if callback then callback(nil) end
    return
  end

  local items = {
    { id = nil, label = "default (no profile override)" }
  }
  for _, p in ipairs(profiles) do
    table.insert(items, {
      id = p.id,
      label = codex_profiles.format_profile_label(p)
    })
  end

  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label)
  end

  vim.ui.select(labels, {
    prompt = "Select Codex Profile:",
  }, function(choice, idx)
    if not choice then
      if callback then callback(nil) end
      return
    end
    local selected = items[idx]
    codex_profiles.set_last_profile(selected.id)
    if callback then callback(selected.id) end
  end)
end

function M.pick_codex_profile_and_start()
  M.pick_codex_profile(function(profile_id)
    M.new_session("codex", profile_id)
  end)
end

function M.load_session(session_id, opts)
  opts = opts or {}

  local existing = registry.get(session_id)
  if existing and existing:is_ready() then
    registry.set_active(session_id)
    local win = get_tab_win()
    if win then
      vim.api.nvim_win_set_buf(win, existing.data.buf)
    end
    update_statusline()
    render.append_content(existing.data.buf, { "[+] Switched to session: " .. session_id:sub(1, 8) .. "...", "" })
    return
  end

  local sessions = registry.load_from_disk()
  local session_info = sessions[session_id]

  local proc = create_process(session_id, {
    cwd = session_info and session_info.cwd or get_current_project_root(),
    env = session_info and session_info.env or {},
    provider = session_info and session_info.provider or config.default_provider,
    load_session_id = session_id,
  })

  local buf = create_buffer(proc, session_info and session_info.name or nil)

  registry.set(session_id, proc)
  registry.set_active(session_id)

  local win = get_tab_win()
  if win then
    vim.api.nvim_win_set_buf(win, buf)
    setup_window_options(win)
  end

  setup_buffer_keymaps(buf)
  render.append_content(buf, { "Loading session " .. session_id:sub(1, 8) .. "..." })

  proc:start()

  if not win then
    win = vim.fn.bufwinid(buf)
  end
  if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
    render.goto_prompt(buf, win)
  end
end

function M.open_session_picker()
  local root = get_current_project_root()
  local disk_sessions = registry.get_sessions_for_project(root)
  local items = {}

  table.insert(items, { label = "+ New Session", action = "new" })

  for _, s in ipairs(disk_sessions) do
    table.insert(items, {
      label = format_session_label(s.is_active, s.has_process, s.name or s.session_id:sub(1, 8), s.provider),
      action = s.is_active and "current" or "load",
      id = s.session_id
    })
  end

  vim.ui.select(extract_labels(items), { prompt = "Select session:" }, function(choice, idx)
    if not choice or not idx then return end
    local item = items[idx]
    if item.action == "new" then
      M.new_session()
    elseif item.action == "load" then
      M.load_session(item.id)
    end
  end)
end

function M.pick_process()
  local running = registry.list_running()
  if #running == 0 then
    vim.notify("No active processes", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, r in ipairs(running) do
    local is_current = r.session_id == registry.active_session_id()
    local name = r.process.data.name or r.session_id:sub(1, 8)
    table.insert(items, {
      label = format_session_label(is_current, true, name, r.process.data.provider),
      session_id = r.session_id,
      is_current = is_current
    })
  end

  vim.ui.select(extract_labels(items), { prompt = "Select process:" }, function(choice, idx)
    if not choice or not idx then return end
    local item = items[idx]
    if not item.is_current then
      M.load_session(item.session_id)
    end
  end)
end

function M.switch_to_buffer()
  local all = registry.all()
  local items = {}

  for sid, proc in pairs(all) do
    if proc.data.buf and vim.api.nvim_buf_is_valid(proc.data.buf) then
      local is_current = sid == registry.active_session_id()
      local has_process = proc:is_alive()
      local name = proc.data.name or sid:sub(1, 8)

      table.insert(items, {
        label = format_session_label(is_current, has_process, name, proc.data.provider),
        session_id = sid,
        buf = proc.data.buf,
        is_current = is_current
      })
    end
  end

  if #items == 0 then
    M.open()
    return
  end

  table.sort(items, function(a, b)
    if a.is_current then return true end
    if b.is_current then return false end
    return a.label < b.label
  end)

  vim.ui.select(extract_labels(items), { prompt = "Switch to buffer:" }, function(choice, idx)
    if not choice or not idx then return end
    local item = items[idx]
    local win = get_tab_win()
    if item.is_current then
      if win then
        vim.api.nvim_set_current_win(win)
      end
    else
      registry.set_active(item.session_id)
      if win then
        vim.api.nvim_win_set_buf(win, item.buf)
      end
      update_statusline()
    end
  end)
end

function M.kill_current_session()
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.WARN)
    return
  end

  local session_id = proc.session_id
  local buf = proc.data.buf

  registry.save_messages(session_id, proc.data.messages)
  registry.delete_session(session_id)

  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  local remaining = registry.list_running()
  if #remaining > 0 then
    M.load_session(remaining[1].session_id)
  else
    M.close()
  end

  vim.notify("Session killed", vim.log.levels.INFO)
end

function M.add_file_as_link(file, message)
  local proc = registry.active()
  if not proc then return end

  local abs_path = vim.fn.fnamemodify(file, ":p")
  local mime_type, is_image = get_mime_type(abs_path)
  local content = read_file_content(abs_path, is_image)

  if not content then return end

  local resource = {
    uri = "file://" .. abs_path,
    name = vim.fn.fnamemodify(file, ":t"),
    mimeType = mime_type,
  }
  if is_image then
    resource.blob = content
  else
    resource.text = content
  end

  local prompt = { { type = "resource", resource = resource } }

  if message then
    table.insert(prompt, { type = "text", text = message })
  end

  M.send_prompt(prompt)
end

function M.add_selection_to_prompt()
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    vim.cmd('normal! "vy')
  end

  local text = vim.fn.getreg("v")
  if not text or text == "" then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getline(start_pos[2], end_pos[2])
    if #lines == 0 then return end

    if #lines == 1 then
      lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
    else
      lines[1] = lines[1]:sub(start_pos[3])
      lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    end
    text = table.concat(lines, "\n")
  end

  if not text or text == "" then return end

  local function add_to_prompt()
    local proc = registry.active()
    if not proc or not proc.data.buf then return end

    local current = render.get_prompt_input(proc.data.buf)
    local separator = current ~= "" and "\n" or ""
    render.set_prompt_input(proc.data.buf, current .. separator .. "```\n" .. text .. "\n```\n")

    local win = get_tab_win()
    if not win then
      win = vim.fn.bufwinid(proc.data.buf)
    end
    if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      render.goto_prompt(proc.data.buf, win)
    end
  end

  if not ui.active then
    M.open()
    vim.defer_fn(add_to_prompt, 500)
  else
    add_to_prompt()
  end
end

function M.send_selection()
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    vim.cmd('normal! "vy')
  end

  local text = vim.fn.getreg("v")
  if not text or text == "" then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getline(start_pos[2], end_pos[2])
    if #lines == 0 then return end

    if #lines == 1 then
      lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
    else
      lines[1] = lines[1]:sub(start_pos[3])
      lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    end
    text = table.concat(lines, "\n")
  end

  if not text or text == "" then return end

  if not ui.active then
    M.open()
    vim.defer_fn(function()
      M.send_prompt("```\n" .. text .. "\n```")
    end, 500)
  else
    M.send_prompt("```\n" .. text .. "\n```")
  end
end

local QUICK_ACTIONS = {
  { label = "Explain this code", prompt = "Explain this code concisely:\n```\n%s\n```" },
  { label = "Check for issues", prompt = "Check this code for bugs, issues, or improvements:\n```\n%s\n```" },
  { label = "Add types", prompt = "Add type annotations to this code:\n```\n%s\n```" },
  { label = "Refactor", prompt = "Refactor this code to be cleaner and more maintainable:\n```\n%s\n```" },
  { label = "Write tests", prompt = "Write tests for this code:\n```\n%s\n```" },
  { label = "Add documentation", prompt = "Add documentation/comments to this code:\n```\n%s\n```" },
  { label = "Simplify", prompt = "Simplify this code while maintaining functionality:\n```\n%s\n```" },
  { label = "Optimize", prompt = "Optimize this code for performance:\n```\n%s\n```" },
}

local function get_visual_selection()
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    vim.cmd('normal! "vy')
  end

  local text = vim.fn.getreg("v")
  if text and text ~= "" then
    return text
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.fn.getline(start_pos[2], end_pos[2])
  if #lines == 0 then return nil end

  if #lines == 1 then
    lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
  else
    lines[1] = lines[1]:sub(start_pos[3])
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
  end
  return table.concat(lines, "\n")
end

function M.quick_action(action_index)
  local text = get_visual_selection()
  if not text or text == "" then
    vim.notify("No selection", vim.log.levels.WARN)
    return
  end

  local function execute_action(action)
    local prompt = string.format(action.prompt, text)
    if not ui.active then
      M.open()
      vim.defer_fn(function()
        M.send_prompt(prompt)
      end, 500)
    else
      M.send_prompt(prompt)
    end
  end

  if action_index and QUICK_ACTIONS[action_index] then
    execute_action(QUICK_ACTIONS[action_index])
    return
  end

  vim.ui.select(extract_labels(QUICK_ACTIONS), { prompt = "Quick Action:" }, function(choice, idx)
    if not choice or not idx then return end
    execute_action(QUICK_ACTIONS[idx])
  end)
end

function M.explain_selection()
  M.quick_action(1)
end

function M.check_selection()
  M.quick_action(2)
end

function M.get_slash_commands()
  local proc = registry.active()
  return proc and proc.data.slash_commands or {}
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  registry.setup({
    sessions_file = config.sessions_file,
    save_interval = 30000,
    max_sessions_per_project = config.max_sessions_per_project,
  })

  registry.start_autosave()

  for cmd_name, fn in pairs({
    AIRepl = M.toggle,
    AIReplOpen = M.open,
    AIReplClose = M.close,
    AIReplNew = M.new_session,
    AIReplSessions = M.open_session_picker,
    AIReplPicker = M.pick_process,
  }) do
    vim.api.nvim_create_user_command(cmd_name, fn, {})
  end

  vim.api.nvim_set_hl(0, "AIReplPrompt", { fg = "#7aa2f7", bold = true })
  syntax.setup()
end

return M
