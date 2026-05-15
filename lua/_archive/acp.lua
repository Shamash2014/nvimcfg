local M = {}

local state_by_buf = {}
local did_setup = false
local ensure_transcript_buffer
local resolve_executable
local apply_transcript_folds
local recollapse_transcript

local function acp_dir()
  return vim.fn.stdpath("data") .. "/acp"
end

local function transcript_path(id)
  return acp_dir() .. "/" .. id .. ".md"
end

local function provider_presets()
  return vim.g.nvim3_acp_providers or {
    claude = "claude-code-acp",
    codex = "codex-acp",
    opencode = "opencode acp",
  }
end

local function provider_items()
  local items = {}
  for name, command in pairs(provider_presets()) do
    local parts = vim.split(command, " ", { trimempty = true })
    local resolved = parts[1] and resolve_executable(parts[1]) or nil
    table.insert(items, {
      name = name,
      command = command,
      executable = parts[1] or "",
      resolved = resolved,
      installed = resolved ~= nil,
    })
  end

  table.sort(items, function(a, b)
    if a.installed ~= b.installed then
      return a.installed and not b.installed
    end
    return a.name < b.name
  end)

  return items
end

local function installed_provider_items()
  local items = {}
  for _, item in ipairs(provider_items()) do
    if item.installed then
      table.insert(items, item)
    end
  end
  return items
end

local function trim(text)
  return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

resolve_executable = function(bin)
  if not bin or bin == "" then
    return nil
  end

  local direct = vim.fn.exepath(bin)
  if direct ~= "" then
    return direct
  end

  local mise = vim.fn.exepath("mise")
  if mise == "" then
    return nil
  end

  local result = vim.system({ mise, "which", bin }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local path = trim(result.stdout)
  if path == "" then
    return nil
  end

  return path
end

local function default_provider()
  if vim.g.nvim3_acp_default_provider and vim.g.nvim3_acp_default_provider ~= "" then
    return vim.g.nvim3_acp_default_provider
  end

  local presets = provider_presets()
  for _, name in ipairs({ "claude", "codex", "opencode" }) do
    local command = presets[name]
    if command then
      local parts = vim.split(command, " ", { trimempty = true })
      if parts[1] and resolve_executable(parts[1]) then
        return name
      end
    end
  end

  return "claude"
end

local function default_agent()
  local presets = provider_presets()
  return presets[default_provider()] or "claude-code --acp"
end

local function parse_agent_command(agent)
  return vim.split(agent or default_agent(), " ", { trimempty = true })
end

local function resolve_agent_command(agent)
  local cmd = parse_agent_command(agent)
  if not cmd[1] then
    return nil
  end

  local resolved = resolve_executable(cmd[1])
  if not resolved then
    return nil
  end

  cmd[1] = resolved
  return cmd
end

local function is_transcript_path(path)
  return type(path) == "string" and path:match(vim.pesc(acp_dir()) .. "/.+%.md$")
end

local function notify(message, level)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and type(snacks.notify) == "function" then
    local notified = pcall(snacks.notify, message, { title = "ACP", level = level })
    if notified then
      return
    end
  end

  vim.notify(message, level or vim.log.levels.INFO, { title = "ACP" })
end

local function ensure_dir()
  vim.fn.mkdir(acp_dir(), "p")
end

local function parse_header(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local meta = {
    session_id = "",
    cwd = vim.fn.getcwd(),
    provider = default_provider(),
    agent = default_agent(),
    model = "",
    mode = "",
  }

  if lines[1] ~= "---" then
    return meta
  end

  for i = 2, #lines do
    local line = lines[i]
    if line == "---" then
      break
    end

    local key, value = line:match("^([%w_]+):%s*(.*)$")
    if key then
      meta[key] = value
    end
  end

  return meta
end

local function normalize_meta(meta)
  meta.session_id = meta.session_id or ""
  meta.cwd = meta.cwd ~= "" and meta.cwd or vim.fn.getcwd()
  meta.provider = meta.provider ~= "" and meta.provider or default_provider()
  meta.model = meta.model or ""
  meta.mode = meta.mode or ""
  if meta.agent == "" or meta.agent == nil then
    local presets = provider_presets()
    meta.agent = presets[meta.provider] or default_agent()
  end
  return meta
end

local function header_lines(meta)
  meta = normalize_meta(meta)
  return {
    "---",
    (meta.session_id and meta.session_id ~= "") and ("session_id: " .. meta.session_id) or "session_id:",
    "cwd: " .. (meta.cwd or vim.fn.getcwd()),
    "provider: " .. meta.provider,
    "agent: " .. (meta.agent or default_agent()),
    (meta.model ~= "") and ("model: " .. meta.model) or "model:",
    (meta.mode ~= "") and ("mode: " .. meta.mode) or "mode:",
    "---",
    "",
  }
end

local function header_end(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if lines[1] ~= "---" then
    return 0
  end

  for i = 2, #lines do
    if lines[i] == "---" then
      if lines[i + 1] == "" then
        return i + 1
      end
      return i
    end
  end

  return 0
end

local function write_buffer(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent write")
  end)
end

local function write_header(bufnr, meta)
  meta = normalize_meta(meta)
  local stop = header_end(bufnr)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, stop > 0 and stop or 0, false, header_lines(meta))
  write_buffer(bufnr)
end

local function ensure_header(bufnr)
  local meta = normalize_meta(parse_header(bufnr))
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 8, false)
  if lines[1] ~= "---" then
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, header_lines(meta))
    write_buffer(bufnr)
  else
    write_header(bufnr, meta)
  end
  return meta
end

local function with_meta(bufnr, mutator)
  local meta = ensure_header(bufnr)
  mutator(meta)
  write_header(bufnr, meta)
  return meta
end

local function input_value(prompt, initial)
  return vim.fn.input(prompt, initial or "")
end

local function pick(items, opts, on_choice)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.picker and snacks.picker.select then
    snacks.picker.select(items, opts or {}, on_choice)
    return
  end

  vim.ui.select(items, opts or {}, on_choice)
end

local function flatten_lines(lines)
  local out = {}
  for _, line in ipairs(lines or {}) do
    local s = type(line) == "string" and line or tostring(line)
    if s:find("\n", 1, true) then
      for _, part in ipairs(vim.split(s, "\n", { plain = true })) do
        table.insert(out, part)
      end
    else
      table.insert(out, s)
    end
  end
  return out
end

local function append_lines(bufnr, lines)
  lines = flatten_lines(lines)
  local last = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1]
  if last == "" and lines[1] == "" then
    lines = vim.list_slice(lines, 2, #lines)
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
  write_buffer(bufnr)
end

local function current_state(bufnr)
  state_by_buf[bufnr] = state_by_buf[bufnr] or {
    next_id = 1,
    pending = {},
    queued_prompts = {},
    session_id = nil,
    ready = false,
    pending_permission = nil,
    config_options = nil,
    modes = nil,
    compose_buf = nil,
    streaming_role = nil,
    tool_calls = {},
  }

  return state_by_buf[bufnr]
end

local tool_call_ns = vim.api.nvim_create_namespace("nvim3_acp_tool_calls")

local function record_tool_call(bufnr, update, block_start)
  if not update.toolCallId then
    return
  end
  local state = current_state(bufnr)
  state.tool_calls = state.tool_calls or {}

  local block = vim.api.nvim_buf_get_lines(bufnr, block_start, -1, false)
  for i, line in ipairs(block) do
    if line:match("^status:") then
      local idx = block_start + i - 1
      local mark = vim.api.nvim_buf_set_extmark(bufnr, tool_call_ns, idx, 0, {})
      state.tool_calls[update.toolCallId] = { status_mark = mark }
      return
    end
  end
end

local function patch_tool_status(bufnr, update)
  if not update.toolCallId then
    return false
  end
  local state = current_state(bufnr)
  if not state.tool_calls then
    return false
  end
  local entry = state.tool_calls[update.toolCallId]
  if not entry or not entry.status_mark then
    return false
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, tool_call_ns, entry.status_mark, {})
  if not pos[1] then
    return false
  end

  if update.status and update.status ~= "" then
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, pos[1], pos[1] + 1, false, { "status: " .. update.status })
    write_buffer(bufnr)
  end
  return true
end

local function tool_output_header(update)
  if update.toolCallId then
    return "### tool output (" .. update.toolCallId .. ")"
  end
  return "### tool output"
end

local function reset_streaming(bufnr)
  current_state(bufnr).streaming_role = nil
end

local function append_chunk(bufnr, role, text)
  if not text or text == "" then
    return
  end

  local state = current_state(bufnr)
  local parts = vim.split(text, "\n", { plain = true })

  if state.streaming_role ~= role then
    state.streaming_role = role
    local header = { "", "## " .. role, "" }
    vim.list_extend(header, parts)
    append_lines(bufnr, header)
    return
  end

  vim.bo[bufnr].modifiable = true
  local last_idx = vim.api.nvim_buf_line_count(bufnr) - 1
  local last = vim.api.nvim_buf_get_lines(bufnr, last_idx, last_idx + 1, false)[1] or ""
  vim.api.nvim_buf_set_lines(bufnr, last_idx, last_idx + 1, false, { last .. parts[1] })
  if #parts > 1 then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, vim.list_slice(parts, 2))
  end
  write_buffer(bufnr)
end

local function current_buffer()
  return vim.api.nvim_get_current_buf()
end

local function send_payload(bufnr, payload)
  local state = current_state(bufnr)
  vim.fn.chansend(state.job, vim.json.encode(payload) .. "\n")
end

local function send_response(bufnr, id, result)
  send_payload(bufnr, {
    jsonrpc = "2.0",
    id = id,
    result = result,
  })
end

local function send_request(bufnr, method, params, callback)
  local state = current_state(bufnr)
  local id = state.next_id
  state.next_id = state.next_id + 1
  if callback then
    state.pending[id] = callback
  end
  send_payload(bufnr, {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params,
  })
end

local function send_notify(bufnr, method, params)
  send_payload(bufnr, {
    jsonrpc = "2.0",
    method = method,
    params = params,
  })
end

local function find_option(options, query)
  if not query or query == "" then
    for _, option in ipairs(options or {}) do
      if option.kind == "allow_once" or option.kind == "allow_always" then
        return option
      end
    end
    return options and options[1] or nil
  end

  for _, option in ipairs(options or {}) do
    if option.optionId == query or option.kind == query or option.name == query then
      return option
    end
  end
end

local function text_lines(text)
  return vim.split(text or "", "\n", { plain = true })
end

local function append_if_present(lines, label, value)
  if value and value ~= "" then
    vim.list_extend(lines, vim.split(label .. ": " .. tostring(value), "\n", { plain = true }))
  end
end

local function option_value(option)
  return (option and option.currentValue) or ""
end

local function find_config_option(state, matcher)
  for _, option in ipairs(state.config_options or {}) do
    if matcher(option) then
      return option
    end
  end
end

local function find_model_option(state)
  return find_config_option(state, function(option)
    return option.category == "model" or option.id == "model"
  end)
end

local function find_mode_option(state)
  return find_config_option(state, function(option)
    return option.category == "mode" or option.id == "mode"
  end)
end

local function find_config_value(option, query)
  if not option or type(option.options) ~= "table" then
    return nil
  end

  for _, item in ipairs(option.options) do
    if item.value == query or item.name == query then
      return item.value
    end
  end
end

local function mode_choices(state)
  return (state.modes and state.modes.availableModes) or {}
end

local function find_mode_value(state, query)
  for _, item in ipairs(mode_choices(state)) do
    if item.id == query or item.name == query then
      return item.id
    end
  end
end

local function next_mode_id(state)
  local modes = mode_choices(state)
  if #modes == 0 then
    return nil
  end

  local current = state.modes and state.modes.currentModeId or nil
  if not current then
    return modes[1].id
  end

  for i, item in ipairs(modes) do
    if item.id == current then
      local next_item = modes[i + 1] or modes[1]
      return next_item.id
    end
  end

  return modes[1].id
end

local function sync_config_options(bufnr, config_options)
  if not config_options then
    return
  end

  local state = current_state(bufnr)
  state.config_options = config_options

  with_meta(bufnr, function(meta)
    for _, option in ipairs(config_options) do
      if option.category == "model" or option.id == "model" then
        meta.model = option.currentValue or ""
      elseif option.category == "mode" or option.id == "mode" then
        meta.mode = option.currentValue or ""
      end
    end
  end)
end

local function sync_modes(bufnr, modes)
  if not modes then
    return
  end

  local state = current_state(bufnr)
  state.modes = modes
  if modes.currentModeId then
    with_meta(bufnr, function(meta)
      meta.mode = modes.currentModeId
    end)
  end
end

local function sync_session_state(bufnr, result)
  if not result then
    return
  end

  sync_config_options(bufnr, result.configOptions)
  sync_modes(bufnr, result.modes)
end

local function permission_lines(params)
  local tool = params.toolCall or {}
  local title = tool.title or tool.kind or "permission request"
  local options = {}
  local lines = {
    "",
    "## permission",
    "",
    "tool: " .. title,
    "call: " .. (tool.toolCallId or ""),
  }

  for _, option in ipairs(params.options or {}) do
    table.insert(options, option.optionId)
  end

  if tool.rawInput and tool.rawInput.path then
    table.insert(lines, "path: " .. tool.rawInput.path)
  end
  if tool.rawInput and tool.rawInput.diff then
    table.insert(lines, "diff:")
    vim.list_extend(lines, text_lines(tool.rawInput.diff))
  end
  table.insert(lines, "options: " .. table.concat(options, ", "))

  return lines
end

local function tool_lines(kind, tool)
  local lines = {
    "",
    "### " .. kind,
    "",
  }

  append_if_present(lines, "title", tool.title or tool.kind)
  append_if_present(lines, "call", tool.toolCallId)
  append_if_present(lines, "status", tool.status)

  if tool.rawInput and tool.rawInput.path then
    vim.list_extend(lines, text_lines("path: " .. tostring(tool.rawInput.path)))
  end
  if tool.rawInput and tool.rawInput.command then
    local command = tool.rawInput.command
    if type(command) == "table" then
      command = table.concat(command, " ")
    end
    vim.list_extend(lines, text_lines("command: " .. tostring(command)))
  end
  if tool.rawInput and tool.rawInput.diff then
    table.insert(lines, "diff:")
    vim.list_extend(lines, text_lines(tool.rawInput.diff))
  end

  local flat = {}
  for _, line in ipairs(lines) do
    if type(line) == "string" and line:find("\n", 1, true) then
      vim.list_extend(flat, vim.split(line, "\n", { plain = true }))
    else
      table.insert(flat, line)
    end
  end
  return flat
end

local function persist_session_id(bufnr, session_id)
  local meta = ensure_header(bufnr)
  meta.session_id = session_id or ""
  write_header(bufnr, meta)
end

local function close_job(bufnr, clear_session)
  local state = current_state(bufnr)
  if state.job then
    pcall(vim.fn.jobstop, state.job)
  end

  state.job = nil
  state.ready = false
  state.pending = {}
  state.pending_permission = nil
  state.capabilities = nil
  state.config_options = nil
  state.modes = nil
  if clear_session then
    state.session_id = nil
  end
  vim.b[bufnr].acp_job = nil
end

local function set_config_option(bufnr, option, value, callback)
  local state = current_state(bufnr)
  if not state.session_id then
    if callback then
      callback(false)
    end
    return
  end

  send_request(bufnr, "session/set_config_option", {
    sessionId = state.session_id,
    configId = option.id,
    value = value,
  }, function(result)
    sync_config_options(bufnr, result and result.configOptions or nil)
    if callback then
      callback(true, result)
    end
  end)
end

local function set_mode_legacy(bufnr, mode_id, callback)
  local state = current_state(bufnr)
  if not state.session_id then
    if callback then
      callback(false)
    end
    return
  end

  send_request(bufnr, "session/set_mode", {
    sessionId = state.session_id,
    modeId = mode_id,
  }, function(result)
    sync_modes(bufnr, result and result.modes or {
      currentModeId = mode_id,
      availableModes = mode_choices(state),
    })
    if callback then
      callback(true, result)
    end
  end)
end

local function apply_header_preferences(bufnr)
  local meta = ensure_header(bufnr)
  local state = current_state(bufnr)

  local model_option = find_model_option(state)
  if meta.model ~= "" and model_option and option_value(model_option) ~= meta.model then
    local value = find_config_value(model_option, meta.model)
    if value then
      set_config_option(bufnr, model_option, value)
    end
  end

  local mode_option = find_mode_option(state)
  if meta.mode ~= "" and mode_option and option_value(mode_option) ~= meta.mode then
    local value = find_config_value(mode_option, meta.mode)
    if value then
      set_config_option(bufnr, mode_option, value)
      return
    end
  end

  if meta.mode ~= "" and state.modes and state.modes.currentModeId ~= meta.mode then
    local mode_id = find_mode_value(state, meta.mode)
    if mode_id then
      set_mode_legacy(bufnr, mode_id)
    end
  end
end

local function drain_prompts(bufnr)
  local state = current_state(bufnr)
  if not state.ready or not state.session_id then
    return
  end

  while #state.queued_prompts > 0 do
    local prompt = table.remove(state.queued_prompts, 1)
    send_request(bufnr, "session/prompt", {
      sessionId = state.session_id,
      prompt = {
        {
          type = "text",
          text = prompt,
        },
      },
    })
  end
end

local function session_ready(bufnr, session_id, result)
  local state = current_state(bufnr)
  state.session_id = session_id
  state.ready = true
  sync_session_state(bufnr, result)
  persist_session_id(bufnr, session_id)
  apply_header_preferences(bufnr)
  drain_prompts(bufnr)
end

local function attach_session(bufnr)
  local meta = ensure_header(bufnr)
  local state = current_state(bufnr)
  local requested_session_id = meta.session_id ~= "" and meta.session_id or nil

  local function create_new()
    send_request(bufnr, "session/new", {
      cwd = meta.cwd,
      mcpServers = {},
    }, function(result)
      session_ready(bufnr, result and (result.sessionId or result.session_id) or "", result)
    end)
  end

  if requested_session_id and state.capabilities and state.capabilities.sessionCapabilities and state.capabilities.sessionCapabilities.resume then
    send_request(bufnr, "session/resume", {
      sessionId = requested_session_id,
      cwd = meta.cwd,
      mcpServers = {},
    }, function(result)
      session_ready(bufnr, requested_session_id, result)
    end)
    return
  end

  if requested_session_id and state.capabilities and state.capabilities.loadSession then
    send_request(bufnr, "session/load", {
      sessionId = requested_session_id,
      cwd = meta.cwd,
      mcpServers = {},
    }, function(result)
      session_ready(bufnr, requested_session_id, result)
    end)
    return
  end

  create_new()
end

local function handle_permission_request(bufnr, message)
  local state = current_state(bufnr)
  local params = message.params or {}
  local title = (((params.toolCall or {}).title) or ((params.toolCall or {}).kind) or "permission request")

  state.pending_permission = {
    request_id = message.id,
    options = params.options or {},
    session_id = params.sessionId,
    tool_call = params.toolCall or {},
  }

  reset_streaming(bufnr)
  append_lines(bufnr, permission_lines(params))
  notify("ACP permission requested: " .. title, vim.log.levels.WARN)
end

local function handle_update(bufnr, update)
  if not update then
    return
  end

  if update.sessionUpdate == "agent_message_chunk" then
    append_chunk(bufnr, "assistant", (((update.content or {}).text) or ""))
  elseif update.sessionUpdate == "user_message_chunk" then
    append_chunk(bufnr, "user", (((update.content or {}).text) or ""))
  elseif update.sessionUpdate == "tool_call" then
    reset_streaming(bufnr)
    local block_start = vim.api.nvim_buf_line_count(bufnr)
    local last = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1]
    local block_lines = tool_lines("tool", update)
    if last == "" and block_lines[1] == "" then
      block_lines = vim.list_slice(block_lines, 2, #block_lines)
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, block_lines)
    write_buffer(bufnr)
    record_tool_call(bufnr, update, block_start)
  elseif update.sessionUpdate == "tool_call_update" then
    reset_streaming(bufnr)
    local text = {}
    for _, item in ipairs(update.content or {}) do
      if item.type == "content" and item.content and item.content.text then
        table.insert(text, item.content.text)
      end
    end

    local handled = patch_tool_status(bufnr, update)
    if handled then
      if #text > 0 then
        local out = { "", tool_output_header(update), "" }
        vim.list_extend(out, text_lines(table.concat(text, "\n")))
        append_lines(bufnr, out)
      end
    else
      local lines = tool_lines("tool update", update)
      if #text > 0 then
        vim.list_extend(lines, text_lines(table.concat(text, "\n")))
      end
      append_lines(bufnr, lines)
    end
  elseif update.sessionUpdate == "current_mode_update" then
    sync_modes(bufnr, {
      currentModeId = update.modeId,
      availableModes = mode_choices(current_state(bufnr)),
    })
  elseif update.sessionUpdate == "config_option_update" then
    sync_config_options(bufnr, update.configOptions)
  end
end

local function on_stdout(bufnr, _job, data)
  for _, line in ipairs(data or {}) do
    if line ~= "" then
      local ok, message = pcall(vim.json.decode, line)
      if ok and message then
        local state = current_state(bufnr)
        if message.id and state.pending[message.id] then
          local callback = state.pending[message.id]
          state.pending[message.id] = nil
          callback(message.result, message.error)
        elseif message.method == "session/update" then
          handle_update(bufnr, (message.params or {}).update)
        elseif message.method == "session/request_permission" then
          handle_permission_request(bufnr, message)
        end
      end
    end
  end
end

local function start(bufnr)
  local state = current_state(bufnr)
  if state.job then
    return
  end

  local meta = ensure_header(bufnr)
  local cmd = resolve_agent_command(meta.agent)

  if not cmd then
    local fallback_provider = default_provider()
    local fallback_agent = provider_presets()[fallback_provider]

    if meta.session_id == "" and fallback_agent and fallback_agent ~= meta.agent then
      meta = with_meta(bufnr, function(updated)
        updated.provider = fallback_provider
        updated.agent = fallback_agent
      end)
      cmd = resolve_agent_command(meta.agent)
      if cmd then
        notify("ACP agent fallback: " .. fallback_provider, vim.log.levels.WARN)
      end
    end
  end

  if not cmd then
    local bad = parse_agent_command(meta.agent)
    notify("ACP agent is not executable: " .. ((bad and bad[1]) or meta.agent) .. " (use :AcpProvider or :AcpAgent)", vim.log.levels.ERROR)
    return
  end
  local job = vim.fn.jobstart(cmd, {
    on_stdout = function(job_id, data)
      on_stdout(bufnr, job_id, data)
    end,
  })

  if job <= 0 then
    notify("Failed to start ACP agent: " .. table.concat(cmd, " "), vim.log.levels.ERROR)
    return
  end

  state.job = job
  vim.b[bufnr].acp_job = job

  send_request(bufnr, "initialize", {
    protocolVersion = 1,
    clientCapabilities = {},
    clientInfo = {
      name = "nvim.3",
      title = "nvim.3",
      version = "0.1.0",
    },
  }, function(result)
    state.capabilities = result and result.agentCapabilities or {}
    attach_session(bufnr)
  end)
end

ensure_transcript_buffer = function(id)
  local bufnr = current_buffer()
  if id and id ~= "" then
    M.open(id)
    return current_buffer()
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name:match(vim.pesc(acp_dir()) .. "/.+%.md$") then
    ensure_header(bufnr)
    return bufnr
  end

  local new_id = os.date("%Y%m%d-%H%M%S")
  M.open(new_id)
  return current_buffer()
end

function M.open(id)
  ensure_dir()
  local target = transcript_path(id ~= "" and id or os.date("%Y%m%d-%H%M%S"))
  vim.cmd("edit " .. vim.fn.fnameescape(target))
  ensure_header(current_buffer())
end

function M.list_sessions()
  ensure_dir()
  local dir = acp_dir()
  local entries = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return entries
  end

  while true do
    local name, t = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if (t == "file" or t == nil) and name:match("%.md$") then
      local id = name:gsub("%.md$", "")
      local path = dir .. "/" .. name
      local stat = vim.uv.fs_stat(path)
      local meta =
        { session_id = "", provider = "", model = "", agent = "", mode = "", cwd = "" }
      local ok, lines = pcall(vim.fn.readfile, path, "", 24)
      if ok and lines and lines[1] == "---" then
        for i = 2, #lines do
          if lines[i] == "---" then
            break
          end
          local key, value = lines[i]:match("^([%w_]+):%s*(.*)$")
          if key then
            meta[key] = value
          end
        end
      end
      table.insert(entries, {
        id = id,
        path = path,
        mtime = stat and stat.mtime.sec or 0,
        size = stat and stat.size or 0,
        meta = meta,
      })
    end
  end

  local open_paths = {}
  for bufnr in pairs(state_by_buf) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      open_paths[vim.api.nvim_buf_get_name(bufnr)] = true
    end
  end
  for _, e in ipairs(entries) do
    e.open = open_paths[e.path] or false
  end

  table.sort(entries, function(a, b)
    return a.mtime > b.mtime
  end)
  return entries
end

local function session_label(e)
  local active = (e.meta.session_id and e.meta.session_id ~= "") and "●" or "○"
  local open_mark = e.open and "*" or " "
  local age = os.date("%m-%d %H:%M", e.mtime)
  local provider = e.meta.provider ~= "" and e.meta.provider or "?"
  local model = e.meta.model ~= "" and e.meta.model or "-"
  return string.format(
    "%s%s %s  %-10s %-22s  %s",
    open_mark,
    active,
    age,
    provider,
    model,
    e.id
  )
end

function M.sessions()
  local list = M.list_sessions()
  if #list == 0 then
    notify("no ACP sessions yet", vim.log.levels.INFO)
    return
  end
  vim.ui.select(list, {
    prompt = "ACP sessions",
    format_item = session_label,
  }, function(choice)
    if not choice then
      return
    end
    M.open(choice.id)
  end)
end

function M.sessions_qf()
  local list = M.list_sessions()
  if #list == 0 then
    notify("no ACP sessions yet", vim.log.levels.INFO)
    return
  end
  local items = {}
  for _, e in ipairs(list) do
    table.insert(items, {
      filename = e.path,
      lnum = 1,
      col = 1,
      text = session_label(e),
      user_data = {
        kind = "acp_session",
        id = e.id,
        meta = e.meta,
        mtime = e.mtime,
        open = e.open,
      },
    })
  end
  vim.fn.setqflist({}, " ", {
    title = string.format("ACP sessions (%d)", #items),
    items = items,
  })
  vim.cmd("botright copen")
end

local function choose_provider(bufnr)
  local items = installed_provider_items()

  if #items == 0 then
    notify("No ACP providers are installed", vim.log.levels.ERROR)
    return
  end

  pick(items, {
    prompt = "ACP provider",
    format_item = function(item)
      return string.format("%s  (%s)", item.name, item.command)
    end,
  }, function(item)
    if not item then
      return
    end
    M.set_provider(item.name, bufnr)
  end)
end

local function health_lines()
  local lines = {
    "ACP health",
    "",
    "default provider: " .. default_provider(),
    "default agent: " .. default_agent(),
    "",
    "providers:",
  }

  for _, item in ipairs(provider_items()) do
    local status = item.installed and "installed" or "missing"
    local resolved = item.resolved and (" -> " .. item.resolved) or ""
    table.insert(lines, string.format("- %s: %s (%s)%s", item.name, item.command, status, resolved))
  end

  return lines
end

function M.health()
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].swapfile = false
  vim.bo[scratch].filetype = "markdown"
  vim.api.nvim_buf_set_name(scratch, "acp://health")
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, health_lines())
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, scratch)
end

local function choose_model(bufnr, option)
  pick(option.options or {}, {
    prompt = "ACP model",
    format_item = function(item)
      return item.name or item.value
    end,
  }, function(item)
    if not item then
      return
    end
    M.set_model(item.value, bufnr)
  end)
end

local function choose_mode(bufnr, option, state)
  if option and option.options and #option.options > 0 then
    pick(option.options, {
      prompt = "ACP mode",
      format_item = function(item)
        return item.name or item.value
      end,
    }, function(item)
      if not item then
        return
      end
      M.set_mode(item.value, bufnr)
    end)
    return
  end

  pick(mode_choices(state), {
    prompt = "ACP mode",
    format_item = function(item)
      return item.name or item.id
    end,
  }, function(item)
    if not item then
      return
    end
    M.set_mode(item.id, bufnr)
  end)
end

function M.set_provider(provider_name, bufnr)
  bufnr = bufnr or ensure_transcript_buffer()

  if not provider_name or provider_name == "" then
    choose_provider(bufnr)
    return
  end

  local presets = provider_presets()
  local agent = presets[provider_name]
  if not agent then
    notify("Unknown ACP provider: " .. provider_name, vim.log.levels.ERROR)
    return
  end

  with_meta(bufnr, function(meta)
    meta.provider = provider_name
    meta.agent = agent
    meta.session_id = ""
  end)
  close_job(bufnr, true)
  notify("ACP provider set to " .. provider_name, vim.log.levels.INFO)
end

function M.set_agent(agent_command, bufnr)
  bufnr = bufnr or ensure_transcript_buffer()
  local meta = ensure_header(bufnr)

  if not agent_command or agent_command == "" then
    agent_command = input_value("ACP agent> ", meta.agent)
  end
  if agent_command == "" then
    return
  end

  with_meta(bufnr, function(updated)
    updated.agent = agent_command
    updated.session_id = ""
  end)
  close_job(bufnr, true)
  notify("ACP agent command updated", vim.log.levels.INFO)
end

function M.set_model(model, bufnr)
  bufnr = bufnr or ensure_transcript_buffer()
  local meta = ensure_header(bufnr)
  local state = current_state(bufnr)
  local option = find_model_option(state)

  if (not model or model == "") and option and option.options and #option.options > 0 then
    choose_model(bufnr, option)
    return
  end

  if not model or model == "" then
    model = input_value("ACP model> ", meta.model)
  end
  if model == "" then
    return
  end

  with_meta(bufnr, function(updated)
    updated.model = model
  end)

  if not state.ready or not state.session_id then
    notify("ACP model saved for next session start", vim.log.levels.INFO)
    return
  end

  if not option then
    notify("ACP agent did not advertise a model selector; saved for next compatible session", vim.log.levels.WARN)
    return
  end

  local value = find_config_value(option, model)
  if not value then
    notify("Unknown ACP model: " .. model, vim.log.levels.ERROR)
    return
  end

  set_config_option(bufnr, option, value, function()
    notify("ACP model set to " .. value, vim.log.levels.INFO)
  end)
end

function M.set_mode(mode, bufnr)
  bufnr = bufnr or ensure_transcript_buffer()
  local meta = ensure_header(bufnr)
  local state = current_state(bufnr)
  local option = find_mode_option(state)

  if (not mode or mode == "") and ((option and option.options and #option.options > 0) or #mode_choices(state) > 0) then
    choose_mode(bufnr, option, state)
    return
  end

  if not mode or mode == "" then
    mode = input_value("ACP mode> ", meta.mode)
  end
  if mode == "" then
    return
  end

  with_meta(bufnr, function(updated)
    updated.mode = mode
  end)

  if not state.ready or not state.session_id then
    notify("ACP mode saved for next session start", vim.log.levels.INFO)
    return
  end

  if option then
    local value = find_config_value(option, mode)
    if not value then
      notify("Unknown ACP mode: " .. mode, vim.log.levels.ERROR)
      return
    end

    set_config_option(bufnr, option, value, function()
      notify("ACP mode set to " .. value, vim.log.levels.INFO)
    end)
    return
  end

  local mode_id = find_mode_value(state, mode)
  if not mode_id then
    notify("ACP agent did not advertise compatible modes; saved for next compatible session", vim.log.levels.WARN)
    return
  end

  set_mode_legacy(bufnr, mode_id, function()
    notify("ACP mode set to " .. mode_id, vim.log.levels.INFO)
  end)
end

function M.cycle_mode(bufnr)
  bufnr = bufnr or ensure_transcript_buffer()
  local state = current_state(bufnr)
  local next_mode = next_mode_id(state)

  if not next_mode then
    notify("ACP agent has no advertised modes", vim.log.levels.WARN)
    return
  end

  M.set_mode(next_mode, bufnr)
end

function M.open_compose()
  local source_buf = current_buffer()

  if is_transcript_path(vim.api.nvim_buf_get_name(source_buf)) then
    local state = current_state(source_buf)
    vim.bo[source_buf].modifiable = true

    local last = vim.api.nvim_buf_get_lines(source_buf, -2, -1, false)[1]
    if last ~= "" then
      vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "" })
    end
    state.compose_start = vim.api.nvim_buf_line_count(source_buf) - 1

    local send_inline = function()
      require("acp").send_compose(source_buf)
    end
    vim.keymap.set("n", "<C-CR>", send_inline, { buffer = source_buf, silent = true, desc = "Send ACP compose" })
    vim.keymap.set("i", "<C-CR>", function()
      vim.cmd("stopinsert")
      send_inline()
    end, { buffer = source_buf, silent = true, desc = "Send ACP compose" })

    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(source_buf), 0 })
    vim.cmd("startinsert!")
    return
  end

  vim.cmd("botright split")
  local compose_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, compose_buf)
  vim.bo[compose_buf].buftype = "nofile"
  vim.bo[compose_buf].bufhidden = "wipe"
  vim.bo[compose_buf].swapfile = false
  vim.bo[compose_buf].filetype = "markdown"
  vim.bo[compose_buf].modifiable = true
  vim.api.nvim_buf_set_name(compose_buf, "acp://compose")
  vim.api.nvim_buf_set_lines(compose_buf, 0, -1, false, {})

  vim.b[compose_buf].acp_compose_target = nil
  local send = function()
    require("acp").send_compose(compose_buf)
  end
  vim.keymap.set("n", "<CR>", send, { buffer = compose_buf, silent = true, desc = "Send ACP compose buffer" })
  vim.keymap.set("i", "<C-CR>", function()
    vim.cmd("stopinsert")
    send()
  end, { buffer = compose_buf, silent = true, desc = "Send ACP compose buffer" })
  vim.keymap.set("n", "q", "<cmd>bd!<cr>", { buffer = compose_buf, silent = true, desc = "Close ACP compose" })
  vim.keymap.set("n", "<C-c>", function()
    require("acp").cancel()
  end, { buffer = compose_buf, silent = true, desc = "ACP: cancel in-flight request" })
  vim.cmd("startinsert")
end

function M.send_compose(bufnr)
  bufnr = bufnr or current_buffer()
  local state = current_state(bufnr)

  if state.compose_start and is_transcript_path(vim.api.nvim_buf_get_name(bufnr)) then
    local from = state.compose_start
    state.compose_start = nil
    local typed = vim.api.nvim_buf_get_lines(bufnr, from, -1, false)
    local text = vim.trim(table.concat(typed, "\n"))
    if text == "" then
      notify("ACP compose region is empty", vim.log.levels.WARN)
      return
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, from, -1, false, {})
    write_buffer(bufnr)
    M.send(text)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  if vim.trim(text) == "" then
    notify("ACP compose buffer is empty", vim.log.levels.WARN)
    return
  end

  local target = vim.b[bufnr].acp_compose_target
  if target and vim.api.nvim_buf_is_valid(target) then
    vim.api.nvim_set_current_buf(target)
  end

  M.send(text)

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.cmd("bd! " .. bufnr)
  end
end

function M.send(text)
  local bufnr = ensure_transcript_buffer()
  local payload = text
  if not payload or payload == "" then
    payload = vim.fn.input("acp> ")
  end
  if payload == "" then
    return
  end

  local lines = {
    "",
    "## user",
    "",
  }
  vim.list_extend(lines, text_lines(payload))
  reset_streaming(bufnr)
  append_lines(bufnr, lines)

  local state = current_state(bufnr)
  table.insert(state.queued_prompts, payload)
  start(bufnr)
  if state.ready then
    drain_prompts(bufnr)
  end
end

function M.send_git_diff(mode)
  local diff_mode = mode ~= "" and mode or "repo"
  local cmd = { "git", "diff", "--no-ext-diff" }

  if diff_mode == "staged" then
    cmd = { "git", "diff", "--cached", "--no-ext-diff" }
  elseif diff_mode == "file" then
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" then
      notify("No current file for AcpSend! file", vim.log.levels.WARN)
      return
    end
    cmd = { "git", "diff", "--no-ext-diff", "--", name }
  end

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    notify(result.stderr ~= "" and result.stderr or "git diff failed", vim.log.levels.ERROR)
    return
  end
  if not result.stdout or result.stdout == "" then
    notify("No diff to send", vim.log.levels.WARN)
    return
  end

  M.send(result.stdout)
end

function M.review_git_diff(mode)
  local diff_mode = mode ~= "" and mode or "staged"
  local cmd = { "git", "diff", "--no-ext-diff" }

  if diff_mode == "staged" then
    cmd = { "git", "diff", "--cached", "--no-ext-diff" }
  elseif diff_mode == "file" then
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" then
      notify("No current file for ACP diff review", vim.log.levels.WARN)
      return
    end
    cmd = { "git", "diff", "--no-ext-diff", "--", name }
  end

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    notify(result.stderr ~= "" and result.stderr or "git diff failed", vim.log.levels.ERROR)
    return
  end
  if not result.stdout or result.stdout == "" then
    notify("No diff to review", vim.log.levels.WARN)
    return
  end

  M.send(table.concat({
    "Review this diff for bugs, regressions, and risky changes.",
    "Focus on actionable findings.",
    "",
    "```diff",
    result.stdout,
    "```",
  }, "\n"))
end

function M.review_neogit_selection()
  local ctx, err = require("core.neogit_ctx").collect()
  if not ctx then
    notify(err or "no Neogit context", vim.log.levels.WARN)
    return
  end
  M.send(require("core.neogit_ctx").review_prompt(ctx))
end

local function send_permission_selected(bufnr, pending, option)
  send_response(bufnr, pending.request_id, {
    outcome = {
      outcome = "selected",
      optionId = option.optionId,
    },
  })
  current_state(bufnr).pending_permission = nil
end

local function first_reject_option(options)
  for _, option in ipairs(options or {}) do
    if
      option.kind == "reject_once"
      or option.kind == "reject_always"
      or option.kind == "reject"
    then
      return option
    end
  end
  return nil
end

function M.approve(option_query)
  local bufnr = ensure_transcript_buffer()
  local state = current_state(bufnr)
  local pending = state.pending_permission
  if not pending then
    notify("No pending ACP permission request", vim.log.levels.WARN)
    return
  end

  if option_query and option_query ~= "" then
    local option = find_option(pending.options, option_query)
    if not option then
      notify("No matching ACP permission option", vim.log.levels.ERROR)
      return
    end
    send_permission_selected(bufnr, pending, option)
    return
  end

  local items = {}
  for _, opt in ipairs(pending.options) do
    table.insert(items, {
      name = opt.name or opt.optionId,
      kind = "option",
      option = opt,
    })
  end

  if first_reject_option(pending.options) then
    table.insert(items, {
      name = "Reject with feedback…",
      kind = "reject_with_text",
    })
  end

  pick(items, {
    prompt = "ACP permission",
    format_item = function(item)
      if item.kind == "option" then
        return string.format("%s (%s)", item.name, item.option.kind or "?")
      end
      return item.name
    end,
  }, function(item)
    if not item then
      return
    end

    if item.kind == "option" then
      send_permission_selected(bufnr, pending, item.option)
      return
    end

    local reject_opt = first_reject_option(pending.options)
    if not reject_opt then
      notify("No reject option offered by agent", vim.log.levels.ERROR)
      return
    end

    local feedback = input_value("Reject feedback: ")
    send_permission_selected(bufnr, pending, reject_opt)
    if feedback and trim(feedback) ~= "" then
      M.send(feedback)
    end
  end)
end

function M.cancel()
  local bufnr = ensure_transcript_buffer()
  local state = current_state(bufnr)

  if state.pending_permission then
    send_response(bufnr, state.pending_permission.request_id, {
      outcome = {
        outcome = "cancelled",
      },
    })
    state.pending_permission = nil
  end

  if state.session_id then
    send_notify(bufnr, "session/cancel", {
      sessionId = state.session_id,
    })
  end
end

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  local group = vim.api.nvim_create_augroup("acp_minimal", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    pattern = "*",
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if not is_transcript_path(path) then
        return
      end

      local meta = ensure_header(args.buf)
      vim.bo[args.buf].filetype = "markdown"
      apply_transcript_folds()
      vim.keymap.set("n", "<C-c>", function()
        require("acp").cancel()
      end, { buffer = args.buf, silent = true, desc = "ACP: cancel in-flight request" })
      if args.event == "BufReadPost" and meta.session_id and meta.session_id ~= "" then
        start(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    pattern = "*",
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if is_transcript_path(path) then
        apply_transcript_folds()
        recollapse_transcript(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    pattern = "*",
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if is_transcript_path(path) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(args.buf) then
            recollapse_transcript(args.buf)
          end
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "NeogitStatus", "NeogitPopup", "NeogitCommitView", "NeogitCommitMessage" },
    callback = function(args)
      vim.keymap.set({ "n", "x" }, "a", function()
        require("acp").review_neogit_selection()
      end, { buffer = args.buf, silent = true, desc = "Review Neogit diff with ACP" })
    end,
  })

  vim.api.nvim_create_user_command("AcpSessions", function(opts)
    if opts.bang then
      require("acp").sessions()
    else
      require("acp").sessions_qf()
    end
  end, { bang = true, desc = "List ACP sessions in quickfix (! = picker)" })
end

local function transcript_foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("^### tool") or line:match("^### permission") or line:match("^### output") then
    return ">1"
  elseif line:match("^## ") then
    return "<1"
  end
  return "="
end

local function transcript_foldtext()
  local fstart = vim.v.foldstart
  local fend = vim.v.foldend
  local first = vim.fn.getline(fstart)
  local kind = first:match("^###%s*(.+)$") or "block"
  local title, status
  for i = fstart, math.min(fstart + 12, fend) do
    local l = vim.fn.getline(i)
    title = title or l:match("^title:%s*(.+)$")
    status = status or l:match("^status:%s*(.+)$")
    if title and status then break end
  end
  return string.format(
    "▸ %s — %s [%s] (%d lines)",
    kind,
    title or "—",
    status or "?",
    fend - fstart + 1
  )
end

_G._acp_foldexpr = function() return transcript_foldexpr(vim.v.lnum) end
_G._acp_foldtext = transcript_foldtext

apply_transcript_folds = function()
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = "v:lua._acp_foldexpr()"
  vim.wo.foldtext = "v:lua._acp_foldtext()"
  vim.wo.foldenable = true
  vim.wo.foldlevel = 0
  pcall(function()
    vim.opt_local.fillchars:append({ fold = " " })
  end)
end

recollapse_transcript = function(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      pcall(vim.api.nvim_win_call, win, function()
        vim.cmd("normal! zx")
      end)
    end
  end
end

function M.shutdown_all()
  for bufnr in pairs(state_by_buf) do
    pcall(close_job, bufnr, false)
  end
end

function M.active_session_count()
  local count = 0
  for bufnr, state in pairs(state_by_buf) do
    if vim.api.nvim_buf_is_valid(bufnr) and state.session_id and state.session_id ~= "" then
      count = count + 1
    end
  end
  return count
end

function M.current_mode(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = current_buffer()
  end
  local state = state_by_buf[bufnr]
  if not state or not state.modes then
    return nil
  end
  return state.modes.currentModeId
end

M._testing = {
  pending_permission = function(bufnr)
    if bufnr == 0 then
      bufnr = current_buffer()
    end
    local state = state_by_buf[bufnr]
    return state and state.pending_permission or nil
  end,
  state = function(bufnr)
    return current_state(bufnr)
  end,
  defaults = function()
    return {
      provider = default_provider(),
      agent = default_agent(),
    }
  end,
}

return M
