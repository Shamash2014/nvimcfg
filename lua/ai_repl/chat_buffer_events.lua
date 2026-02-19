local M = {}
local chat_parser = require("ai_repl.chat_parser")
local tool_utils = require("ai_repl.tool_utils")
local buffer_state = {}

local TOOL_NAMES = {
  Read = "Read", Edit = "Edit", Write = "Write", Bash = "Run",
  Glob = "Find Files", Grep = "Search", Task = "Agent",
  WebFetch = "Fetch", WebSearch = "Web Search", TodoWrite = "Plan",
  NotebookEdit = "Notebook", LSP = "LSP", KillShell = "Kill Process",
}

local MODE_ICONS = {
  plan = "📋", spec = "📝", auto = "🤖", code = "💻",
  chat = "💬", execute = "▶️",
}

local function render_plan_in_chat(buf, entries)
  if not entries or #entries == 0 then return end
  local lines = { "", "━━━ 📋 Plan ━━━" }
  for i, item in ipairs(entries) do
    local icon = tool_utils.STATUS_ICONS[item.status] or "○"
    local pri = item.priority == "high" and "! " or ""
    local text = item.content or item.text or item.activeForm or item.description or tostring(item)
    table.insert(lines, string.format(" %s %d. %s%s", icon, i, pri, text))
  end
  table.insert(lines, "━━━━━━━━━━━━")
  table.insert(lines, "")
  M.append_to_chat_buffer(buf, lines)
end

local function get_state(buf)
  if not buffer_state[buf] then
    buffer_state[buf] = {
      session_id = nil,
      process = nil,
      last_role = nil,
      streaming = false,
      streaming_text = "",
      streaming_insert_line = nil,
      tool_approvals = {},
      modified = false,
      original_handlers = nil,
    }
  end
  return buffer_state[buf]
end

local function find_or_create_insert_line(buf, state)
  if state.streaming_insert_line then return end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, line_count, false)

  local djinni_line = -1
  for i = #lines, 1, -1 do
    if lines[i]:match("^@Djinni:") then
      djinni_line = i
      break
    end
  end

  if djinni_line == -1 then
    vim.api.nvim_buf_set_lines(buf, line_count, -1, false, { "", "@Djinni:" })
    state.streaming_insert_line = line_count + 2
  else
    state.streaming_insert_line = djinni_line
  end
end

local function flush_streaming_text(buf, state)
  if state.streaming_text == "" then return end

  vim.bo[buf].modifiable = true
  find_or_create_insert_line(buf, state)

  local response_lines = vim.split(state.streaming_text, "\n", { trimempty = false })
  vim.api.nvim_buf_set_lines(buf, state.streaming_insert_line, -1, false, response_lines)
end

function M.setup_event_forwarding(buf, proc)
  if not proc or not proc:is_alive() then
    return false
  end

  local state = get_state(buf)

  if not state.original_handlers then
    state.original_handlers = {
      on_method = proc._on_method,
      on_status = proc._on_status,
    }
  end

  -- Store the buffer reference for later use
  state.proc = proc
  state.buf = buf

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
          pcall(M.handle_session_update_in_chat, buf, params.update, self)
        else
          -- Buffer closed but we still need to process updates
          -- Just update internal state, don't try to write to buffer
          local session_state = require("ai_repl.session_state")
          session_state.apply_update(self, params.update)
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
  })

  return true
end

function M.handle_session_update_in_chat(buf, update, proc)
  -- Check if buffer is still valid, if not, just process the update internally
  if not vim.api.nvim_buf_is_valid(buf) then
    local session_state = require("ai_repl.session_state")
    session_state.apply_update(proc, update)
    return
  end

  local session_state = require("ai_repl.session_state")
  local result = session_state.apply_update(proc, update)
  if not result then return end

  local state = get_state(buf)
  local decorations_ok, decorations = pcall(require, "ai_repl.chat_decorations")

  if result.type == "compact_boundary" then
    M.append_to_chat_buffer(buf, { "", "[~] Context compacted" .. (result.compact_info or ""), "" })

  elseif result.type == "agent_message_chunk" then
    if not state.streaming then
      state.streaming = true
      -- Don't set modifiable = false - keep it true for voice input
      -- The streaming will update at the @Djinni: marker line
      if decorations_ok then pcall(decorations.start_spinner, buf, "generating") end
    end
    M.stream_to_chat_buffer(buf, result.text)

  elseif result.type == "tool_call" then
    if result.is_plan_tool then
      render_plan_in_chat(buf, result.plan_entries)
      return
    elseif result.is_exit_plan then
      local mode_icon = MODE_ICONS[proc.state.mode or "execute"] or "▶️"
      M.append_to_chat_buffer(buf, { "", "[▶] " .. mode_icon .. " Starting execution..." })
      return
    elseif result.is_ask_user then
      if decorations_ok then pcall(decorations.stop_spinner, buf) end
      if result.questions and #result.questions > 0 then
        local q_ok, questionnaire = pcall(require, "ai_repl.questionnaire")
        if q_ok then
          questionnaire.start(proc, result.questions, function(response)
            proc:send_prompt(response)
          end)
        end
      end
      return
    end

    if decorations_ok then pcall(decorations.start_spinner, buf, "executing") end
    local u = result.update
    local raw_title = u.title or u.kind or "tool"
    local friendly = TOOL_NAMES[raw_title] or raw_title
    local input = u.rawInput or {}
    if type(input) == "string" then
      local ok, parsed = pcall(vim.json.decode, input)
      input = ok and parsed or {}
    end
    local desc = tool_utils.get_tool_description(raw_title, input, u.locations or {}, { include_path = true })
    local label = friendly
    if desc ~= "" then label = label .. ": " .. desc end
    M.append_to_chat_buffer(buf, { "[*] " .. label })

  elseif result.type == "tool_call_update" then
    if result.tool_finished then
      if result.update.status == "failed" then
        local tool_name = result.tool.title or result.tool.kind or "tool"
        M.append_to_chat_buffer(buf, { "[!] " .. tool_name .. " failed" })
      elseif result.is_edit_tool and result.diff then
        local render = require("ai_repl.render")
        render.render_diff(buf, result.diff.path, result.diff.old, result.diff.new)
        M.append_to_chat_buffer(buf, {
          "[~] " .. vim.fn.fnamemodify(result.diff.path, ":~:."),
        })
      end

      if result.is_exit_plan_complete then
        M.append_to_chat_buffer(buf, { "[>] Starting execution..." })
        vim.defer_fn(function()
          proc:send_prompt("proceed with the plan", { silent = true })
        end, 200)
      end
    end

  elseif result.type == "plan" then
    render_plan_in_chat(buf, result.plan_entries)

  elseif result.type == "current_mode_update" then
    local mode_id = result.update.modeId or result.update.currentModeId
    local icon = MODE_ICONS[mode_id] or "↻"
    M.append_to_chat_buffer(buf, { "[" .. icon .. "] Mode: " .. (mode_id or "unknown") })

  elseif result.type == "modes" then
    -- Silently track available modes (no UI output needed)

  elseif result.type == "stop" then
    state.streaming = false
    flush_streaming_text(buf, state)
    state.streaming_text = ""
    state.streaming_insert_line = nil
    proc.ui.streaming_response = ""
    proc.ui.streaming_start_line = nil
    vim.bo[buf].modifiable = true

    if result.response_text ~= "" and not result.had_plan then
      local render = require("ai_repl.render")
      local md_plan = render.parse_markdown_plan(result.response_text)
      if #md_plan >= 3 then
        proc.ui.current_plan = md_plan
        render_plan_in_chat(buf, md_plan)
      end
    end

    M.append_new_user_marker(buf)
    if decorations_ok then
      pcall(decorations.stop_spinner, buf)
      pcall(decorations.redecorate, buf)
      pcall(decorations.show_tokens, buf, result.usage)
    end

    if result.should_process_queue then
      vim.defer_fn(function()
        proc:process_queued_prompts()
      end, 200)
    end

  elseif result.type == "agent_thought_chunk" then
    if decorations_ok then pcall(decorations.start_spinner, buf, "thinking") end
  end
end

function M.append_new_user_marker(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  M.ensure_you_marker(buf)
end

function M.stop_streaming(buf)
  local state = get_state(buf)
  if not state.streaming then return end
  
  -- Reset streaming state
  state.streaming = false
  
  -- Flush any pending text
  flush_streaming_text(buf, state)
  
  -- Clear all streaming state
  state.streaming_text = ""
  state.streaming_insert_line = nil
  
  -- Ensure buffer is modifiable
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modifiable = true
  end
  
  -- Stop any active spinner
  local decorations_ok, decorations = pcall(require, "ai_repl.chat_decorations")
  if decorations_ok then
    pcall(decorations.stop_spinner, buf)
  end
end

function M.ensure_you_marker(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for i = #lines, 1, -1 do
    local role = chat_parser.parse_role_marker(lines[i])
    if role then
      if role == "user" then
        -- Already have @You: marker, keep buffer modifiable for input
        vim.bo[buf].modifiable = true
        return
      end
      break
    end
  end

  local line_count = #lines
  vim.api.nvim_buf_set_lines(buf, line_count, -1, false, {
    "",
    "@You:",
    "",
    "",
  })

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_set_cursor(win, { line_count + 2, 0 })
  end

  -- Keep buffer modifiable to allow voice input after @You:
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

    local decorations_ok, decorations = pcall(require, "ai_repl.chat_decorations")
    if decorations_ok then pcall(decorations.stop_spinner, buf) end

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

    -- Extract option IDs from agent-provided options
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

    -- Check bypass mode
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
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "selected", optionId = first_allow_id or "allow_always" } }
      }
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

    local was_modifiable = vim.bo[buf].modifiable
    vim.bo[buf].modifiable = true

    M.append_to_chat_buffer(buf, {
      "",
      "[?] " .. display,
      "  [y] Allow  [a] Always  [n] Deny  [c] Cancel",
    })

    -- Don't set modifiable back to false - keep it true for voice input
    -- The permission keymaps will handle preventing editing elsewhere
    vim.bo[buf].modifiable = true

    if proc.ui then proc.ui.permission_active = true end

    -- Response helpers
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
        M.append_to_chat_buffer(buf, { "[+] Allowed" })
        send_selected(first_allow_id or "allow_once")
      elseif choice == "a" then
        M.append_to_chat_buffer(buf, { "[+] Always allowed" })
        send_selected(allow_always_id or "allow_always")
      elseif choice == "n" then
        M.append_to_chat_buffer(buf, { "[x] Denied" })
        send_selected(first_deny_id or "reject_once")
      else
        M.append_to_chat_buffer(buf, { "[x] Cancelled", "", "@You:", "", "" })
        send_cancelled()
      end

      if decorations_ok then pcall(decorations.start_spinner, buf, "executing") end

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
    vim.keymap.set("n", "y", function() handle_choice("y") end, opts)
    vim.keymap.set("n", "a", function() handle_choice("a") end, opts)
    vim.keymap.set("n", "n", function() handle_choice("n") end, opts)
    vim.keymap.set("n", "c", function() handle_choice("c") end, opts)
  end)
end

function M.handle_status_in_chat(buf, status, data, proc)
  local label
  if status == "session_created" then
    label = "[ACP SESSION READY]"
  elseif status == "session_loaded" then
    label = "[ACP SESSION LOADED]"
  end
  if not label then return end

  local banner = {
    "",
    "==================================================================",
    label,
    "==================================================================",
    "Working Directory: " .. proc.data.cwd,
    "Session ID: " .. proc.session_id,
    "Provider: " .. (proc.data.provider or "unknown"),
    "==================================================================",
    "",
  }

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
end

function M.stream_to_chat_buffer(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local state = get_state(buf)
  state.streaming_text = state.streaming_text .. text

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      -- Buffer was closed, just clear the streaming state
      state.streaming_text = ""
      state.streaming = false
      return
    end

    if not state.streaming then return end

    local was_modifiable = vim.bo[buf].modifiable
    vim.bo[buf].modifiable = true

    find_or_create_insert_line(buf, state)

    local response_lines = vim.split(state.streaming_text, "\n", { trimempty = false })
    vim.api.nvim_buf_set_lines(buf, state.streaming_insert_line, -1, false, response_lines)

    -- Keep buffer modifiable during streaming for voice input
    vim.bo[buf].modifiable = true

    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      local new_count = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_win_set_cursor(win, { new_count, 0 })
      vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zb")
      end)
    end
  end)
end

function M.append_to_chat_buffer(buf, new_lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    -- Buffer is closed, silently skip
    return
  end

  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true

  local line_count = vim.api.nvim_buf_line_count(buf)

  local to_append = {}
  if type(new_lines) == "string" then
    table.insert(to_append, new_lines)
  elseif type(new_lines) == "table" then
    for _, line in ipairs(new_lines) do
      table.insert(to_append, line)
    end
  end
  table.insert(to_append, "")

  vim.api.nvim_buf_set_lines(buf, line_count, -1, false, to_append)

  -- Keep buffer modifiable for voice input
  vim.bo[buf].modifiable = true

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    local new_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(win, { new_count, 0 })
  end
end

return M
