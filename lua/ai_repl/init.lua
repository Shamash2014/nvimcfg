local M = {}

-- AI REPL - Chat Buffer Only Architecture
-- =======================================
-- This module manages AI agent sessions through .chat buffers only.
-- The traditional REPL interface has been removed in favor of the more
-- powerful chat buffer system (Flemma-style UI with @You:, @Djinni: markers).
--
-- Key changes:
-- - M.new_session() creates a process and opens a chat buffer
-- - M.show() redirects to M.open_chat_buffer()
-- - setup_buffer_keymaps() is minimal (chat buffers have their own setup)
-- - Process buffers are hidden/internal only
-- =======================================

local Process = require("ai_repl.process")
local registry = require("ai_repl.registry")
local render = require("ai_repl.render")
local providers = require("ai_repl.providers")
local ralph_helper = require("ai_repl.ralph_helper")
local tool_utils = require("ai_repl.tool_utils")
local questionnaire = require("ai_repl.questionnaire")
local syntax = require("ai_repl.syntax")
local chat_buffer = require("ai_repl.chat_buffer")

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
  max_sessions_per_project = 20,
  chat = {
    split_width = 0.8,
    split_direction = "right",  -- "right", "left", "above", "below"
  },
  mcp_servers = {},
  annotations = {
    enabled = false,
    session_dir = vim.fn.stdpath("data") .. "/annotations",
    capture_mode = "snippet",
    auto_open_panel = true,
    keys = {
      start_session = "<leader>as",
      stop_session = "<leader>aq",
      annotate = "<leader>aa",
      toggle_window = "<leader>aw",
      send_to_ai = "<leader>af",
    },
  }
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
  project_root = nil,
}

-- Get the REPL window (deprecated - returns nil since we use chat buffers only)
local function get_tab_win()
  -- No REPL window anymore - all interaction is through chat buffers
  return nil
end

local function setup_window_options(win)
  -- Deprecated - no-op since we use chat buffers
end

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

-- Node mode icons mapping (matching Factory's mode system)
local NODE_MODE_ICONS = {
  plan = "📋",
  spec = "📝",
  auto = "🤖",
  code = "💻",
  chat = "💬",
  execute = "▶️",
}

local function get_mode_display(mode_id)
  if not mode_id then return "📋 plan" end
  
  -- Check if we have mode metadata from ACP
  local proc = registry.active()
  local mode_icon = NODE_MODE_ICONS[mode_id] or "•"
  local mode_name = mode_id
  
  -- Try to get friendly name from available modes
  if proc and proc.state.modes and #proc.state.modes > 0 then
    for _, m in ipairs(proc.state.modes) do
      if m.id == mode_id or m.modeId == mode_id then
        mode_name = m.displayName or m.name or mode_id
        if m.icon then
          mode_icon = m.icon
        end
        break
      end
    end
  end
  
  return mode_icon .. " " .. mode_name
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
  local mode_display = get_mode_display(mode)
  local queue_count = proc and #proc.data.prompt_queue or 0
  local queue_str = queue_count > 0 and (" Q:" .. queue_count) or ""
  local busy_str = proc and proc.state.busy and " ●" or ""
  local bg_count = count_background_busy()
  local bg_str = bg_count > 0 and (" [" .. bg_count .. " bg]") or ""
  local skill_str = proc and proc.data.active_skill and (" 🎯 " .. proc.data.active_skill) or ""
  vim.wo[win].statusline = " " .. provider_name .. " | " .. agent_name .. " [" .. mode_display .. "]" .. busy_str .. queue_str .. bg_str .. skill_str
end

local session_state = require("ai_repl.session_state")

local function handle_session_update(proc, params)
  local result = session_state.apply_update(proc, params.update)
  if not result then return end

  local buf = proc.data.buf
  local u = result.update

  if config.debug and result.type ~= "agent_message_chunk" then
    render.append_content(buf, { "[debug] " .. (result.type or "unknown") })
  end

  if result.type == "compact_boundary" then
    render.stop_animation()
    render.append_content(buf, { "", "[~] Context compacted" .. (result.compact_info or ""), "" })

  elseif result.type == "agent_message_chunk" then
    render.start_animation(buf, "generating")
    if result.text then
      if result.text:match("%[compact%]") or result.text:match("Conversation compacted") then
        render.stop_animation()
        render.append_content(buf, { "", "[~] Context compacted", "" })
        return
      end

      -- Check if this is a response to a slash command
      if proc.data.pending_slash_command then
        -- First message chunk for slash command response - add @System: marker
        if not proc.data.slash_command_response_started then
          proc.data.slash_command_response_started = true
          render.append_content(buf, { "", "@System:" })
        end
      end

      render.update_streaming(buf, result.text, proc.ui)
    end

  elseif result.type == "current_mode_update" then
    -- Show mode change notification
    local mode_display = get_mode_display(proc.state.mode)
    render.append_content(buf, { "", "[↻] Mode: " .. mode_display, "" })
    update_statusline()

  elseif result.type == "tool_call" then
    if result.is_plan_tool then
      render.render_plan(buf, result.plan_entries)
      return
    elseif result.is_exit_plan then
      local mode_display = get_mode_display(proc.state.mode or "execute")
      render.append_content(buf, { "", "[▶] " .. mode_display .. " mode: Starting execution...", "" })
      return
    elseif result.is_ask_user then
      render.stop_animation()
      if #result.questions > 0 then
        questionnaire.start(proc, result.questions, function(response)
          M.send_prompt(response)
        end)
      end
    else
      render.start_animation(buf, "executing")
      render.render_tool(buf, result.tool)
    end

  elseif result.type == "tool_call_update" then
    if result.tool_finished then
      render.stop_animation()

      if result.diff then
        render.render_diff(buf, result.diff.path, result.diff.old, result.diff.new)
      end

      if result.tool.title ~= "AskUser" and result.tool.title ~= "AskUserQuestion" then
        render.render_tool(buf, result.tool)
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
            render.append_content(buf, { "[image] " .. tmp })
          end
        end
      end

      if result.is_exit_plan_complete then
        render.append_content(buf, { "[>] Starting execution..." })
        vim.defer_fn(function()
          M.send_prompt("proceed with the plan", { silent = true })
        end, 200)
      end
    end

  elseif result.type == "plan" then
    render.render_plan(buf, result.plan_entries)

  elseif result.type == "stop" then
    render.stop_animation()

    if result.response_text ~= "" and not result.had_plan then
      local md_plan = render.parse_markdown_plan(result.response_text)
      if #md_plan >= 3 then
        proc.ui.current_plan = md_plan
        render.render_plan(buf, md_plan)
      end
    end

    render.finish_streaming(buf, proc.ui)

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
    render.append_content(buf, { "", (reason_msgs[result.stop_reason] or "---") .. mode_str .. queue_info, "" })

    -- Clear slash command state if this was a response to a slash command
    if proc.data.pending_slash_command then
      proc.data.pending_slash_command = nil
      proc.data.slash_command_response_started = nil
    end

    -- Add @You: marker after agent completes
    local chat_buffer = require("ai_repl.chat_buffer")
    if not chat_buffer.is_chat_buffer(buf) then
      -- For non-chat buffers, append @You: directly
      render.append_content(buf, { "", "@You:", "", "" })
    else
      -- For chat buffers, ensure @You: marker exists
      local chat_buffer_events = require("ai_repl.chat_buffer_events")
      chat_buffer_events.ensure_you_marker(buf)
    end

    if result.ralph_continuing then
      return
    end

    update_statusline()

    vim.defer_fn(function()
      proc:process_queued_prompts()
      update_statusline()
    end, 200)

  elseif result.type == "modes" then
    -- Show available modes when they're first received
    if proc.state.modes and #proc.state.modes > 0 then
      local mode_list = {}
      for _, m in ipairs(proc.state.modes) do
        local name = m.displayName or m.name or m.id or m.modeId
        local icon = m.icon or NODE_MODE_ICONS[m.id or m.modeId] or "•"
        table.insert(mode_list, icon .. " " .. name)
      end
      if #mode_list > 0 then
        render.append_content(buf, { "", "[ℹ] Available modes: " .. table.concat(mode_list, ", "), "" })
      end
    end
    update_statusline()

  elseif result.type == "agent_thought_chunk" then
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

local function read_provider_mcp_servers(provider_id)
  if provider_id == "claude" then
    local path = vim.fn.expand("~/.claude.json")
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    local ok, json = pcall(vim.json.decode, content)
    if not ok or type(json.mcpServers) ~= "table" then return nil end
    local servers = setmetatable({}, { __is_list = true })
    for name, cfg in pairs(json.mcpServers) do
      table.insert(servers, {
        name = name,
        command = cfg.command,
        args = cfg.args or setmetatable({}, { __is_list = true }),
        env = cfg.env or {},
      })
    end
    return #servers > 0 and servers or nil
  end
  return nil
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

  local EMPTY_ARRAY_LOCAL = setmetatable({}, { __is_list = true })
  local mcp_servers = (#config.mcp_servers > 0)
    and config.mcp_servers
    or read_provider_mcp_servers(provider_id)
    or EMPTY_ARRAY_LOCAL

  local proc = Process.new(session_id, {
    cmd = provider.cmd,
    args = args,
    env = vim.tbl_extend("force", provider.env or {}, opts.env or {}),
    cwd = opts.cwd or get_current_project_root(),
    debug = config.debug,
    load_session_id = opts.load_session_id,
    provider = provider_id,
    profile_id = opts.profile_id,
    mcp_servers = mcp_servers,
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
        render.append_content(buf, {
          "",
          "==================================================================",
          "[ACP SESSION READY]",
          "==================================================================",
          "Working Directory: " .. self.data.cwd,
          "Session ID: " .. self.session_id,
          "Provider: " .. (self.data.provider or "unknown"),
          "==================================================================",
          "",
        })
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
        render.append_content(buf, {
          "",
          "==================================================================",
          "[ACP SESSION LOADED]",
          "==================================================================",
          "Working Directory: " .. self.data.cwd,
          "Session ID: " .. self.session_id,
          "Provider: " .. (self.data.provider or "unknown"),
          "==================================================================",
          "",
        })
        local messages = registry.load_messages(self.session_id)
        if messages and #messages > 0 then
          render.render_history(buf, messages)
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

  -- Hide this internal buffer from the user's buffer list
  vim.bo[buf].buflisted = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false

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
  -- Minimal setup for internal process buffer (hidden, not used for interaction)
  -- Chat buffers have their own keymap setup in chat_buffer.lua

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

  local buf = proc.data.buf
  local chat_buffer = require("ai_repl.chat_buffer")

  if not chat_buffer.is_chat_buffer(buf) then
    -- For non-chat buffers, append cancelled and @You:
    render.append_content(buf, { "Cancelled", "", "@You:", "", "" })
  else
    -- For chat buffers, append cancelled and ensure @You: marker exists
    local chat_buffer_events = require("ai_repl.chat_buffer_events")
    chat_buffer_events.append_to_chat_buffer(buf, { "Cancelled" })
    chat_buffer_events.ensure_you_marker(buf)
  end
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
      "  /kill - Kill current session (terminate process)",
      "  /restart - Restart session (kill and create fresh)",
      "  /mode [mode] - Show mode picker or switch to specific mode",
      "  /config - Show session config options picker",
      "  /chat [file] - Open/create .chat buffer (creates session if needed)",
      "  /start - Start AI session for current .chat buffer",
      "  /chat-new - Start chat in current buffer (if .chat file) or create new one (session starts on C-])",
      "  /restart-chat - Restart conversation in current .chat buffer",
      "  /summarize - Summarize current conversation",
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
      "Chat Buffer Annotations:",
      "  In .chat buffer, select code and press <leader>aa to add annotation",
      "  Annotations sync to annotation system automatically on send",
      "  /add-ann - Add selection as annotation (visual mode in .chat)",
      "  /sync-ann - Sync annotations from .chat buffer to system",
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
      "  💾 .chat - Flemma-style buffer-as-state UI (use /chat)",
      "",
      "Chat Buffer Annotations:",
      "  In .chat buffer, select code and press <leader>aa to add annotation",
      "  Annotations sync to annotation system automatically on send",
      "  /sync-ann - Sync annotations from .chat buffer to system",
      "  /add-ann - Add selection as annotation (visual mode)",
      ""
    })
  elseif command == "new" then
    M.new_session(config.default_provider)
  elseif command == "sessions" then
    M.open_session_picker()
  elseif command == "mode" then
    if args[1] then
      M.switch_to_mode(args[1])
    else
      M.show_mode_picker()
    end
  elseif command == "config" or command == "options" then
    M.show_config_options_picker()
  elseif command == "chat" or command == "mode-chat" then
    M.open_chat_buffer(args[1])
  elseif command == "chat-new" then
    M.open_chat_buffer_new()
  elseif command == "start" then
    local current_buf = vim.api.nvim_get_current_buf()
    if chat_buffer.is_chat_buffer(current_buf) then
      vim.notify("[.chat] Starting session...", vim.log.levels.INFO)

      local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
      local chat_parser = require("ai_repl.chat_parser")
      local parsed = chat_parser.parse_buffer(lines, current_buf)
      local old_messages = parsed.messages or {}

      M.new_session(config.default_provider)

      local chat_buffer_events = require("ai_repl.chat_buffer_events")
      local function attach_and_sync()
        local proc = registry.active()
        if not proc then return end

        chat_buffer_events.setup_event_forwarding(current_buf, proc)
        chat_buffer.attach_session(current_buf, proc.session_id)

        if #old_messages > 0 then
          proc.data.messages = {}
          for _, msg in ipairs(old_messages) do
            if msg.role == "user" or msg.role == "djinni" then
              registry.append_message(proc.session_id, msg.role, msg.content, msg.tool_calls)
            end
          end
          vim.notify("[.chat] Session started with " .. #old_messages .. " messages synced. Press C-] to send.", vim.log.levels.INFO)
        else
          vim.notify("[.chat] Session started! Press C-] to send.", vim.log.levels.INFO)
        end
      end

      local attempts = 0
      local timer = vim.uv.new_timer()
      timer:start(100, 200, vim.schedule_wrap(function()
        attempts = attempts + 1
        local proc = registry.active()
        if (proc and proc:is_ready()) or attempts > 50 then
          timer:stop()
          timer:close()
          attach_and_sync()
        end
      end))
    else
      if buf then
        render.append_content(buf, { "[!] Not a .chat buffer" })
      else
        vim.notify("[!] Not a .chat buffer", vim.log.levels.ERROR)
      end
    end
  elseif command == "restart-chat" then
    -- Restart conversation in current chat buffer
    local current_buf = vim.api.nvim_get_current_buf()
    if chat_buffer.is_chat_buffer(current_buf) then
      chat_buffer.restart_conversation(current_buf)
    else
      render.append_content(buf, { "[!] Not a .chat buffer" })
    end
  elseif command == "summarize" or command == "summary" then
    -- Summarize current chat buffer
    local current_buf = vim.api.nvim_get_current_buf()
    if chat_buffer.is_chat_buffer(current_buf) then
      local ok = chat_buffer.summarize_conversation(current_buf)
      if not ok then
        render.append_content(buf, { "[!] Failed to summarize conversation" })
      end
    else
      render.append_content(buf, { "[!] Not a .chat buffer" })
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
  elseif command == "export-chat" then
    local proc = registry.active()
    if not proc then
      render.append_content(buf, { "", "[!] No active session" })
      return
    end

    local output_path = args[1]
    local path, err = registry.export_chat(proc.session_id, output_path)
    if err then
      render.append_content(buf, { "", "[!] Export failed: " .. err })
    else
      render.append_content(buf, { "", "[+] Chat exported to: " .. path })
    end
  elseif command == "import-chat" then
    local path = args[1]
    if not path then
      render.append_content(buf, { "", "[!] Usage: /import-chat <path>" })
      return
    end

    local data, err = registry.import_chat(path)
    if err then
      render.append_content(buf, { "", "[!] Import failed: " .. err })
      return
    end

    local imported_count = 0

    if data.messages and #data.messages > 0 then
      for _, msg in ipairs(data.messages) do
        registry.append_message(proc.session_id, msg.role, msg.content, msg.tool_calls)
        imported_count = imported_count + 1
      end
    end

    local annotation_imported = false
    if data.annotations and #data.annotations > 0 then
      -- Try to restore annotations
      local annotation_session = require("ai_repl.annotations.session")
      if not annotation_session.is_active() then
        annotation_session.start(require("ai_repl.annotations.config").config)
      end

      local bufnr = annotation_session.get_bufnr()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local writer = require("ai_repl.annotations.writer")
        local session_state = annotation_session.get_state()

        for _, ann in ipairs(data.annotations) do
          writer.append(session_state, "snippet", ann, ann.note or "")
        end

        annotation_imported = true
      end
    end

    if annotation_imported then
      render.append_content(buf, {
        "",
        "[+] Imported " .. imported_count .. " messages from " .. path,
        "[+] Restored " .. #data.annotations .. " annotations to annotation session",
      })
    else
      render.append_content(buf, { "", "[+] Imported " .. imported_count .. " messages from " .. path })
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
  elseif command == "kill" then
    M.kill_session()
  elseif command == "restart" then
    M.restart_session()
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
          -- Mark that we're expecting a response to a slash command
          proc.data.pending_slash_command = {
            name = sc.name,
            args = args
          }

          -- Provide feedback that command is being executed
          local cmd_display = sc.name:gsub("^/", "")
          if buf then
            render.append_content(buf, { "", "[⚡] " .. cmd_display .. (args[1] and (" " .. table.concat(args, " ")) or "") })
          else
            vim.notify("Executing: " .. cmd_display, vim.log.levels.INFO)
          end

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
  if not proc then
    vim.notify("No active session", vim.log.levels.INFO)
    return
  end

  if not proc.state.modes or #proc.state.modes == 0 then
    if proc.state.config_options and #proc.state.config_options > 0 then
      for _, opt in ipairs(proc.state.config_options) do
        if opt.configId and opt.configId:match("mode") then
          M._show_config_option_values(proc, opt)
          return
        end
      end
    end
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

function M._show_config_option_values(proc, option)
  local options = option.options or {}
  if #options == 0 then
    vim.notify("No values for: " .. (option.label or option.configId), vim.log.levels.INFO)
    return
  end

  local labels = {}
  for _, val in ipairs(options) do
    local current = val.value == option.value and "[*] " or "[ ] "
    local name = val.name or val.value
    local desc = val.description and (" - " .. val.description) or ""
    table.insert(labels, current .. name .. desc)
  end

  vim.ui.select(labels, {
    prompt = (option.label or option.configId) .. ":",
  }, function(choice, idx)
    if not choice or not idx then return end
    local selected = options[idx]
    if selected then
      proc:set_config_option(option.configId, selected.value, function(result, err)
        if err then
          vim.notify("Failed to set config: " .. vim.inspect(err), vim.log.levels.ERROR)
        else
          vim.notify((option.label or option.configId) .. " set to: " .. (selected.name or selected.value), vim.log.levels.INFO)
        end
      end)
    end
  end)
end

function M.show_config_options_picker()
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.ERROR)
    return
  end

  local config_options = proc.state.config_options
  if not config_options or #config_options == 0 then
    vim.notify("No config options available", vim.log.levels.INFO)
    return
  end

  local labels = {}
  for _, opt in ipairs(config_options) do
    local label = opt.label or opt.configId
    local current = opt.value and (" = " .. tostring(opt.value)) or ""
    table.insert(labels, label .. current)
  end

  vim.ui.select(labels, {
    prompt = "Config Options:",
  }, function(choice, idx)
    if not choice or not idx then return end
    local selected_option = config_options[idx]
    if selected_option then
      M._show_config_option_values(proc, selected_option)
    end
  end)
end

function M.open()
  -- Redirect to chat buffer
  M.open_chat_buffer()
end

function M.close()
  -- Close current chat buffer if any
  local buf = vim.api.nvim_get_current_buf()
  if chat_buffer.is_chat_buffer(buf) then
    vim.cmd("close")
  end
end

function M.kill_session()
  -- Kill the current session/process
  local proc = registry.active()
  if not proc then
    vim.notify("No active session to kill", vim.log.levels.WARN)
    return
  end

  local session_id = proc.session_id
  local session_name = proc.data.name or "Session"

  -- Kill the process
  proc:kill()

  -- Remove from registry
  registry.unregister(session_id)

  vim.notify("Killed session: " .. session_name, vim.log.levels.INFO)
end

function M.restart_session()
  -- Kill current session and create a fresh one
  local proc = registry.active()
  local cwd

  if proc then
    -- Save current working directory
    cwd = proc.data.cwd

    -- Get current chat buffer if any
    local current_buf = vim.api.nvim_get_current_buf()
    local is_chat = chat_buffer.is_chat_buffer(current_buf)

    -- Kill the current session
    proc:kill()
    registry.unregister(proc.session_id)

    vim.notify("Restarting session...", vim.log.levels.INFO)

    -- If in a chat buffer, restart the conversation
    if is_chat then
      vim.defer_fn(function()
        chat_buffer.restart_conversation(current_buf)
      end, 100)
      return
    end
  else
    cwd = get_current_project_root()
  end

  -- Create new session
  vim.defer_fn(function()
    M.new_session({ cwd = cwd })
  end, 100)
end

function M.hide()
  -- No-op for chat buffers (they're regular buffers)
  -- Kept for backward compatibility
end

function M.show()
  -- Redirect to chat buffer
  M.open_chat_buffer()
end

function M.toggle()
  -- Toggle chat buffer: open if none exists, or switch to existing one
  local current_buf = vim.api.nvim_get_current_buf()
  local current_name = vim.api.nvim_buf_get_name(current_buf)

  -- If already in a chat buffer, close it
  if chat_buffer.is_chat_buffer(current_buf) then
    vim.cmd("close")
    return
  end

  -- Otherwise, open or switch to a chat buffer
  M.open_chat_buffer()
end

-- Open or create .chat buffer
-- Open or create .chat buffer
function M.open_chat_buffer(file_path)
  -- Ensure we have an active ACP session first
  local proc = registry.active()
  if not proc or not proc:is_alive() then
    M.new_session(config.default_provider)
    proc = registry.active()

    if not proc then
      vim.notify("[.chat] Failed to create ACP session", vim.log.levels.ERROR)
      return
    end

    -- Wait for session to be ready (with timeout)
    local timeout = 50
    local waited = 0
    while not proc:is_ready() and waited < timeout do
      vim.cmd("sleep 10m")
      waited = waited + 1
    end

    if not proc:is_ready() then
      vim.notify("[.chat] ACP session not ready", vim.log.levels.ERROR)
      return
    end
  end

  local chat_parser = require("ai_repl.chat_parser")

  file_path = file_path or vim.fn.expand("%:p")

  -- If current buffer is .chat, use it
  local buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(buf)

  if not buf_name:match("%.chat$") then
    -- Generate unique ID for chat file
    local timestamp = os.time()
    local random = math.floor(math.random() * 10000)
    local chat_id = string.format("%s-%d-%04d.chat",
      proc.data.name or "chat",
      timestamp,
      random
    )

    -- Create new .chat buffer
    local template = chat_parser.generate_template({
      session_id = proc.session_id or "chat_" .. os.time(),
      provider = proc.data.provider or config.default_provider,
    })

    buf = vim.api.nvim_create_buf(true, false)
    local new_path = vim.fn.getcwd() .. "/" .. chat_id
    vim.api.nvim_buf_set_name(buf, new_path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(template, "\n"))
  end

  -- Initialize chat buffer
  local ok, err = chat_buffer.init_buffer(buf)
  if not ok then
    vim.notify("[.chat] Failed to initialize: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  -- Open in configured split direction (default: right vertical)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    local split_direction = config.chat.split_direction or "right"
    local split_cmd

    if split_direction == "right" then
      split_cmd = "vsplit"
    elseif split_direction == "left" then
      vim.cmd("noautocmd wincmd h")
      split_cmd = "vsplit"
    elseif split_direction == "above" then
      split_cmd = "split"
    elseif split_direction == "below" then
      split_cmd = "split"
    else
      split_cmd = "vsplit"
    end

    vim.cmd(split_cmd)
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)

    -- Set window width/height
    local split_width = config.chat.split_width or 0.4
    if split_direction == "right" or split_direction == "left" then
      local current_width = vim.api.nvim_win_get_width(0)
      local new_width = math.floor(current_width * split_width)
      vim.api.nvim_win_set_width(win, new_width)
    elseif split_direction == "above" or split_direction == "below" then
      local current_height = vim.api.nvim_win_get_height(0)
      local new_height = math.floor(current_height * split_height)
      vim.api.nvim_win_set_height(win, new_height)
    end

    -- Enable wrapping and prevent text overflow
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].breakindent = true
    vim.wo[win].breakindentopt = "shift:2,sbr"
  else
    -- Just switch to existing window
    vim.api.nvim_set_current_win(win)

    -- Ensure wrapping is enabled on existing window
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].breakindent = true
    vim.wo[win].breakindentopt = "shift:2,sbr"
  end

  -- Switch to buffer
  vim.api.nvim_set_current_buf(buf)

  vim.notify("[.chat] Buffer ready - press C-] to send", vim.log.levels.INFO)
end

--- Open a new .chat buffer for the current file without requiring a running process
--- This allows you to start drafting a conversation before starting the AI
function M.open_chat_buffer_new()
  local chat_parser = require("ai_repl.chat_parser")
  local chat_buffer = require("ai_repl.chat_buffer")

  -- Check if current buffer is already a .chat file
  local buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(buf)

  if buf_name:match("%.chat$") then
    -- Current buffer is already a .chat file, just initialize it
    vim.notify("[.chat] Initializing existing chat buffer...", vim.log.levels.INFO)

    -- Initialize chat buffer (will create session when needed)
    local ok, err = chat_buffer.init_buffer(buf)
    if not ok then
      vim.notify("[.chat] Failed to initialize: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    vim.notify("[.chat] Buffer ready - press C-] to send (session will start automatically)", vim.log.levels.INFO)
    return
  end

  -- Not a .chat file, create new one
  local current_file = vim.fn.expand("%:t")
  local file_basename = vim.fn.fnamemodify(current_file, ":r")

  -- Generate chat file name based on current file
  local timestamp = os.time()
  local random = math.floor(math.random() * 10000)
  local chat_id = string.format("%s-%d-%04d.chat", file_basename or "chat", timestamp, random)

  -- Create new .chat buffer without session
  local template = chat_parser.generate_template()

  buf = vim.api.nvim_create_buf(true, false)
  local new_path = vim.fn.getcwd() .. "/" .. chat_id

  vim.api.nvim_buf_set_name(buf, new_path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(template, "\n"))

  -- Initialize chat buffer (will handle session creation when needed)
  local ok, err = chat_buffer.init_buffer(buf)
  if not ok then
    vim.notify("[.chat] Failed to initialize: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  -- Open in configured split direction
  local split_direction = config.chat.split_direction or "right"
  local split_cmd

  if split_direction == "right" then
    split_cmd = "vsplit"
  elseif split_direction == "left" then
    vim.cmd("noautocmd wincmd h")
    split_cmd = "vsplit"
  elseif split_direction == "above" then
    split_cmd = "split"
  elseif split_direction == "below" then
    split_cmd = "split"
  else
    split_cmd = "vsplit"
  end

  vim.cmd(split_cmd)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Set window size
  local split_width = config.chat.split_width or 0.4
  if split_direction == "right" or split_direction == "left" then
    local current_width = vim.api.nvim_win_get_width(0)
    local new_width = math.floor(current_width * split_width)
    vim.api.nvim_win_set_width(win, new_width)
  elseif split_direction == "above" or split_direction == "below" then
    local current_height = vim.api.nvim_win_get_height(0)
    local new_height = math.floor(current_height * split_height)
    vim.api.nvim_win_set_height(win, new_height)
  end

  -- Enable wrapping
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].breakindentopt = "shift:2,sbr"

  -- Switch to buffer
  vim.api.nvim_set_current_buf(buf)

  vim.notify("[.chat] New buffer ready - start typing, session will be created when you press C-]", vim.log.levels.INFO)
end

-- Add annotation to current .chat buffer
function M.add_annotation_to_chat()
  local buf = vim.api.nvim_get_current_buf()

  if not chat_buffer.is_chat_buffer(buf) then
    vim.notify("Not a .chat buffer", vim.log.levels.WARN)
    return
  end

  if vim.fn.mode() ~= "v" and vim.fn.mode() ~= "V" then
    vim.notify("Visual selection required", vim.log.levels.WARN)
    return
  end

  chat_buffer.add_annotation_from_selection(buf)
end

-- Sync annotations from .chat buffer to annotation system
function M.sync_chat_annotations()
  local buf = vim.api.nvim_get_current_buf()

  if not chat_buffer.is_chat_buffer(buf) then
    vim.notify("Not a .chat buffer", vim.log.levels.WARN)
    return
  end

  local ok, msg = chat_buffer.sync_annotations_from_buffer(buf)
  if ok then
    vim.notify(msg, vim.log.levels.INFO)
  else
    vim.notify("Sync failed: " .. tostring(msg), vim.log.levels.ERROR)
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

  -- Create actual ACP process
  local session_id = "session_" .. os.time()
  proc = create_process(session_id, {
    provider = provider_id,
    extra_args = extra_args,
    profile_id = profile_id,
  })

  -- Create a minimal hidden buffer for the process (used for internal output only)
  local buf = create_buffer(proc, nil)

  -- Show initialization message
  render.append_content(buf, {
    "",
    "==================================================================",
    "[INITIALIZING ACP SESSION...]",
    "==================================================================",
    "Working Directory: " .. proc.data.cwd,
    "Provider: " .. provider_id,
    "Waiting for connection...",
    "==================================================================",
    "",
  })

  registry.set(session_id, proc)
  registry.set_active(session_id)

  proc:start()

  M.open_chat_buffer()
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
    update_statusline()
    render.append_content(existing.data.buf, { "[+] Switched to session: " .. session_id:sub(1, 8) .. "...", "" })
    M.open_chat_buffer()
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

  setup_buffer_keymaps(buf)
  render.append_content(buf, { "Loading session " .. session_id:sub(1, 8) .. "..." })

  proc:start()

  -- Open chat buffer instead of showing REPL buffer
  M.open_chat_buffer()
end

function M.open_session_picker()
  local chat_dir = vim.fn.stdpath("data") .. "/ai_repl_chats"
  local items = {}

  -- List .chat files
  if vim.fn.isdirectory(chat_dir) == 1 then
    local chat_files = vim.fn.glob(chat_dir .. "/*.chat", true, true)
    
    -- Sort by modification time (newest first)
    table.sort(chat_files, function(a, b)
      local stat_a = vim.loop.fs_stat(a)
      local stat_b = vim.loop.fs_stat(b)
      return (stat_a and stat_b) and stat_a.mtime.sec > stat_b.mtime.sec or false
    end)

    for _, file_path in ipairs(chat_files) do
      local filename = vim.fn.fnamemodify(file_path, ":t")
      local session_id = vim.fn.fnamemodify(filename, ":r")
      
      -- Try to get session info from the file
      local stat = vim.loop.fs_stat(file_path)
      local mtime = stat and os.date("%Y-%m-%d %H:%M", stat.mtime.sec) or "Unknown"
      
      table.insert(items, {
        label = string.format("%s (%s)", session_id:sub(1, 8), mtime),
        action = "import_chat",
        file_path = file_path,
        session_id = session_id
      })
    end
  end

  -- Add "New Session" option
  table.insert(items, 1, { label = "+ New Session", action = "new" })

  if #items == 1 then
    vim.notify("No .chat files found. Creating new session.", vim.log.levels.INFO)
    M.new_session()
    return
  end

  vim.ui.select(extract_labels(items), { prompt = "Select .chat file:" }, function(choice, idx)
    if not choice or not idx then return end
    local item = items[idx]
    if item.action == "new" then
      M.new_session()
    elseif item.action == "import_chat" then
      M.import_chat_from_picker(item.file_path, item.session_id)
    end
  end)
end

function M.import_chat_from_picker(file_path, session_id)
  -- Import the .chat file
  local data, err = registry.import_chat(file_path)
  if err then
    vim.notify("Failed to import .chat file: " .. err, vim.log.levels.ERROR)
    return
  end

  -- Create a new session with the imported data
  local temp_id = "import_" .. os.time() .. "_" .. math.random(1000, 9999)
  local proc = create_process(temp_id, {
    cwd = get_current_project_root(),
  })
  
  local buf = create_buffer(proc, "Imported: " .. session_id:sub(1, 8))
  
  registry.set(temp_id, proc)
  registry.set_active(temp_id)
  
  -- Load messages into the session
  if data.messages and #data.messages > 0 then
    for _, msg in ipairs(data.messages) do
      registry.append_message(temp_id, msg.role, msg.content, msg.tool_calls)
    end
    -- Render the imported messages
    render.render_history(buf, data.messages)
  end
  
  -- Handle annotations if present
  if data.annotations and #data.annotations > 0 then
    local annotation_session = require("ai_repl.annotations.session")
    if not annotation_session.is_active() then
      local annotations_config = require("ai_repl.annotations.config")
      annotation_session.start(annotations_config.config)
    end
    
    local ann_bufnr = annotation_session.get_bufnr()
    if ann_bufnr and vim.api.nvim_buf_is_valid(ann_bufnr) then
      local writer = require("ai_repl.annotations.writer")
      local session_state = annotation_session.get_state()
      
      for _, ann in ipairs(data.annotations) do
        writer.append(session_state, "location", ann, ann.note or "")
      end
    end
  end
  
  -- Show the buffer
  local win = get_tab_win()
  if not win or not vim.api.nvim_win_is_valid(win) then
    M.show()
    win = get_tab_win()
  end
  
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_buf(win, buf)
  end
  
  setup_buffer_keymaps(buf)
  proc:start()
  
  render.append_content(buf, { 
    "", 
    "[+] Imported .chat file: " .. vim.fn.fnamemodify(file_path, ":t"),
    "[+] Session ready",
    "" 
  })
  
  update_statusline()
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
  -- Add selection to active chat buffer or create new one
  local buf = vim.api.nvim_get_current_buf()
  local start_pos = vim.api.nvim_buf_get_mark(buf, "<")
  local end_pos = vim.api.nvim_buf_get_mark(buf, ">")

  if not start_pos or not end_pos then
    vim.notify("No visual selection", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[1] - 1, end_pos[1], false)
  local text = table.concat(lines, "\n")

  local file_path = vim.api.nvim_buf_get_name(buf)
  local rel_path = vim.fn.fnamemodify(file_path, ":~:.")

  -- Check if current buffer is a chat buffer
  if chat_buffer.is_chat_buffer(buf) then
    -- Append to current chat buffer
    local chat_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local insert_pos = #chat_lines

    -- Find last @You: or @Djinni: to insert after
    for i = #chat_lines, 1, -1 do
      if chat_lines[i]:match("^@You:") or chat_lines[i]:match("^@Djinni:") then
        insert_pos = i + 1
        break
      end
    end

    -- Insert blank line, file reference, and content
    vim.api.nvim_buf_set_lines(buf, insert_pos, insert_pos, false, {
      "",
      string.format("@%s:%d-%d", rel_path, start_pos[1], end_pos[1]),
      "",
      text,
      "",
    })

    vim.notify("[.chat] Added selection to buffer", vim.log.levels.INFO)
  else
    -- Check for active chat buffer
    local chat_buf = chat_buffer.get_active_chat_buffer()
    if chat_buf and vim.api.nvim_buf_is_valid(chat_buf) then
      -- Switch to chat buffer and add selection
      vim.api.nvim_set_current_buf(chat_buf)
      M.add_selection_to_prompt()
    else
      -- Create new chat buffer with selection
      M.open_chat_buffer()
      vim.schedule(function()
        M.add_selection_to_prompt()
      end)
    end
  end
end

function M.send_selection()
  -- Send selection to chat buffer
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

  -- Check if current buffer is a chat buffer
  local buf = vim.api.nvim_get_current_buf()
  if chat_buffer.is_chat_buffer(buf) then
    -- Add selection to current chat buffer and send
    M.add_selection_to_prompt()
    vim.schedule(function()
      -- Trigger send (C-] keybinding)
      vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-]>", true, false, true), "n")
    end)
  else
    -- Open chat buffer and send selection
    M.open_chat_buffer()
    vim.schedule(function()
      M.send_selection()
    end)
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

    -- Open or switch to chat buffer
    local buf = vim.api.nvim_get_current_buf()
    if not chat_buffer.is_chat_buffer(buf) then
      M.open_chat_buffer()
      vim.schedule(function()
        execute_action(action)
      end)
      return
    end

    -- Append to chat buffer
    local chat_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local insert_pos = #chat_lines

    -- Find last @You: to insert after
    for i = #chat_lines, 1, -1 do
      if chat_lines[i]:match("^@You:") then
        insert_pos = i + 1
        break
      end
    end

    -- Insert prompt and trigger send
    vim.api.nvim_buf_set_lines(buf, insert_pos, insert_pos, false, {
      "",
      prompt,
      "",
    })

    vim.schedule(function()
      vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-]>", true, false, true), "n")
    end)
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

  -- Auto-initialize .chat buffers
  vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = "*.chat",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if chat_buffer.is_chat_buffer(buf) then
        chat_buffer.init_buffer(buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufNewFile", {
    pattern = "*.chat",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      local chat_parser = require("ai_repl.chat_parser")
      local template = chat_parser.generate_template({
        session_id = "chat_" .. os.time(),
        provider = config.default_provider,
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(template, "\n"))
    end,
  })

  -- Initialize existing .chat buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if chat_buffer.is_chat_buffer(buf) then
      chat_buffer.init_buffer(buf)
    end
  end

  for cmd_name, fn in pairs({
    AIRepl = M.toggle,
    AIReplOpen = M.open,
    AIReplClose = M.close,
    AIReplNew = M.new_session,
    AIReplSessions = M.open_session_picker,
    AIReplPicker = M.pick_process,
    AIReplChat = M.open_chat_buffer,
    AIReplAddAnnotation = M.add_annotation_to_chat,
    AIReplSyncAnnotations = M.sync_chat_annotations,
  }) do
    vim.api.nvim_create_user_command(cmd_name, fn, {})
  end

  vim.api.nvim_set_hl(0, "AIReplPrompt", { fg = "#7aa2f7", bold = true })
  syntax.setup()

  -- Setup .chat syntax highlighting
  require("ai_repl.chat_syntax").setup()

  if config.annotations and config.annotations.enabled then
    require("ai_repl.annotations").setup(config.annotations)
  end
end

return M
