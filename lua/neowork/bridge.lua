local M = {}

local Client = require("djinni.acp.client")
local Provider = require("djinni.acp.provider")
local config = require("neowork.config")
local store = require("neowork.store")
local util = require("neowork.util")
local const = require("neowork.const")

local get_document = util.lazy("neowork.document")
local get_stream = util.lazy("neowork.stream")

local function notify_index()
  local ok, index = pcall(require, "neowork.index")
  if ok and index and index.refresh_all then
    vim.schedule(function() pcall(index.refresh_all) end)
  end
end

M._sessions = {}
M._bufs = {}
M._clients = {}
M._streaming = {}
M._stream_gen = {}
M._sub_handles = {}
M._modes = {}
M._providers = {}
M._inflight = {}
M._turn_started_at = {}
M._turn_elapsed_ms = {}
M._usage = {}
M._diff_stats = {}
M._spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
M._spinner_frame = 0
M._redraw_timer = nil

local function _redraw_tick()
  if M._redraw_timer then return end
  M._redraw_timer = vim.uv.new_timer()
  M._redraw_timer:start(0, 150, vim.schedule_wrap(function()
    local any = false
    for b, v in pairs(M._streaming) do
      if v and vim.api.nvim_buf_is_valid(b) then any = true break end
    end
    if not any then
      if M._redraw_timer then
        M._redraw_timer:stop()
        M._redraw_timer:close()
        M._redraw_timer = nil
      end
      return
    end
    M._spinner_frame = M._spinner_frame + 1
    pcall(vim.cmd.redrawstatus)
  end))
end

function M._begin_turn(buf)
  M._turn_started_at[buf] = vim.uv.hrtime()
  _redraw_tick()
end

function M._end_turn(buf, usage, cost)
  local started = M._turn_started_at[buf]
  if started then
    M._turn_elapsed_ms[buf] = math.floor((vim.uv.hrtime() - started) / 1e6)
  end
  M._turn_started_at[buf] = nil
  if usage then
    M._usage[buf] = M._usage[buf] or {}
    M._usage[buf].input_tokens = usage.inputTokens or usage.input_tokens or M._usage[buf].input_tokens or 0
    M._usage[buf].output_tokens = usage.outputTokens or usage.output_tokens or M._usage[buf].output_tokens or 0
  end
  if cost then
    M._usage[buf] = M._usage[buf] or {}
    M._usage[buf].cost = cost
  end
end

function M._record_diff(buf, added, deleted)
  M._diff_stats[buf] = M._diff_stats[buf] or { files = 0, added = 0, deleted = 0 }
  M._diff_stats[buf].files = M._diff_stats[buf].files + 1
  M._diff_stats[buf].added = M._diff_stats[buf].added + (added or 0)
  M._diff_stats[buf].deleted = M._diff_stats[buf].deleted + (deleted or 0)
end

function M._ensure_client(buf, callback)
  local existing = M._clients[buf]
  if existing then
    existing:when_ready(function(err)
      if err then
        M._clients[buf] = nil
        M._ensure_client(buf, callback)
        return
      end
      callback(nil, existing)
    end)
    return
  end

  local doc = get_document()
  local provider_name = doc.read_frontmatter_field(buf, "provider") or config.get("provider")
  local root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
  local provider = Provider.get(provider_name)
  if not provider then
    local err = { message = "unknown provider: " .. tostring(provider_name) }
    callback(err)
    return
  end

  local client = Client.new(provider.command, provider.args or {}, root)
  M._clients[buf] = client

  client:when_ready(function(ready_err)
    if ready_err then
      M._clients[buf] = nil
      callback(ready_err)
      return
    end
    callback(nil, client)
  end)
end

function M.create_session(buf, callback)
  if M._sessions[buf] then
    local sid = M._sessions[buf]
    if callback then
      vim.schedule(function() callback(nil, sid) end)
    end
    return
  end

  if M._inflight[buf] then
    if callback then table.insert(M._inflight[buf], callback) end
    return
  end

  M._inflight[buf] = callback and { callback } or {}

  local function finish(err, sid)
    local queue = M._inflight[buf] or {}
    M._inflight[buf] = nil
    for _, cb in ipairs(queue) do
      pcall(cb, err, sid)
    end
  end

  M._ensure_client(buf, function(err, client)
    if err then
      finish(err)
      return
    end

    local doc = get_document()
    local root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd()

    local req = { cwd = vim.fn.fnamemodify(root, ":p"):gsub("/+$", ""), mcpServers = setmetatable({}, { __jsontype = "array" }) }
    client:request("session/new", req, function(req_err, result)
      if req_err then
        finish(req_err)
        return
      end

      local sid = result and result.sessionId
      if not sid then
        finish({ message = "no sessionId in session/new response" })
        return
      end

      M._sessions[buf] = sid
      M._bufs[sid] = buf
      M._stream_gen[buf] = 0

      if result.modes then
        M._modes[buf] = {
          available = result.modes.availableModes or {},
          current_id = result.modes.currentModeId,
        }
      end

      doc.set_frontmatter_fields(buf, { session = sid, status = const.session_status.idle })

      M._subscribe(buf, sid, client)
      store.ensure_dirs(root)

      finish(nil, sid)
    end, { timeout = 90000 })
  end)
end

local function supports_load_session(client)
  local caps = client and (client.server_capabilities or client.agent_capabilities)
  if not caps then return false end
  if caps.loadSession then return true end
  local session_caps = caps.sessionCapabilities
  return session_caps and session_caps.resume or false
end

function M.resume_session(buf, session_id, callback)
  if M._sessions[buf] == session_id then
    if callback then vim.schedule(function() callback(nil, session_id) end) end
    return
  end

  M._ensure_client(buf, function(err, client)
    if err then
      if callback then callback(err) end
      return
    end

    local function fall_back_to_new()
      local old_sid = M._sessions[buf]
      if old_sid then M._bufs[old_sid] = nil end
      M._sessions[buf] = nil
      get_document().set_frontmatter_field(buf, "session", "")
      M._sub_handles[buf] = nil
      M.create_session(buf, callback)
    end

    if not supports_load_session(client) then
      fall_back_to_new()
      return
    end

    M._sessions[buf] = session_id
    M._bufs[session_id] = buf
    M._stream_gen[buf] = 0
    M._subscribe(buf, session_id, client)

    local doc = get_document()
    local root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
    local req = {
      sessionId = session_id,
      cwd = vim.fn.fnamemodify(root, ":p"):gsub("/+$", ""),
      mcpServers = setmetatable({}, { __jsontype = "array" }),
    }
    client:request("session/load", req, function(req_err, result)
      if req_err then
        local sub = M._sub_handles[buf]
        if sub then
          pcall(function() sub.client:unsubscribe(session_id, sub.handle) end)
          M._sub_handles[buf] = nil
        end
        fall_back_to_new()
        return
      end
      if result and result.modes then
        M._modes[buf] = {
          available = result.modes.availableModes or {},
          current_id = result.modes.currentModeId,
        }
      end
      doc.set_frontmatter_field(buf, "status", const.session_status.idle)
      store.ensure_dirs(root)
      if callback then callback(nil, session_id) end
    end, { timeout = 90000 })
  end)
end

M._last_user_row = M._last_user_row or {}

function M._retry_with_new_session(buf, text)
  local doc = get_document()
  local you_row = M._last_user_row[buf]
  if you_row and doc.truncate_after_user_row then
    pcall(doc.truncate_after_user_row, buf, you_row)
  end

  local old_sid = M._sessions[buf]
  if old_sid then M._bufs[old_sid] = nil end
  M._sessions[buf] = nil
  M._inflight[buf] = nil
  M._streaming[buf] = false
  M._stream_gen[buf] = (M._stream_gen[buf] or 0) + 1

  M.create_session(buf, function(err, new_sid)
    if err then
      vim.notify("neowork: retry failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
      return
    end
    M._do_send(buf, new_sid, text)
  end)
end

function M._subscribe(buf, session_id, client)
  local existing = M._sub_handles[buf]
  if existing then
    existing.client:unsubscribe(session_id, existing.handle)
  end

  local handle = {
    on_update = function(params)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local su = params.update or params
      if su.sessionUpdate == const.event.modes and su.availableModes then
        M._modes[buf] = M._modes[buf] or {}
        M._modes[buf].available = su.availableModes
        if su.currentModeId then M._modes[buf].current_id = su.currentModeId end
      elseif su.sessionUpdate == const.event.current_mode_update and su.modeId then
        M._modes[buf] = M._modes[buf] or { available = {} }
        M._modes[buf].current_id = su.modeId
      end
      local gen = M._stream_gen[buf]
      vim.schedule(function()
        get_stream().on_event(buf, su, gen)
      end)
    end,
    on_permission = function(params, respond)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      vim.schedule(function()
        M._handle_permission(buf, params, respond)
      end)
    end,
  }

  client:subscribe(session_id, handle)
  M._sub_handles[buf] = { client = client, handle = handle, session_id = session_id }
end

function M.send(buf, text)
  local sid = M._sessions[buf]
  if not sid then
    M.create_session(buf, function(err, new_sid)
      if err then return end
      M._do_send(buf, new_sid, text)
    end)
    return
  end
  M._do_send(buf, sid, text)
end

function M._do_send(buf, session_id, text)
  local client = M._clients[buf]
  if not client or not client:is_alive() then return end

  local gen = (M._stream_gen[buf] or 0) + 1
  M._stream_gen[buf] = gen
  M._streaming[buf] = true

  local doc = get_document()
  local root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
  doc.set_frontmatter_field(buf, "status", const.session_status.running)

  store.append_event(session_id, root, { type = "user", content = text })
  notify_index()

  local summary_mod = require("neowork.summary")
  if summary_mod.get(buf) == "" then
    local first_line = text:match("^[^\n]*") or text
    local seed = first_line:gsub("^%s+", ""):gsub("%s+$", "")
    if #seed > 80 then seed = seed:sub(1, 79) .. "…" end
    if seed ~= "" then summary_mod.set(buf, seed) end
  end

  if doc.find_last_role_row then
    M._last_user_row[buf] = doc.find_last_role_row(buf, "You")
  end

  M._begin_turn(buf)
  local turn_started = M._turn_started_at[buf] or vim.uv.hrtime()

  get_stream().start(buf, gen)

  client:request("session/prompt", {
    sessionId = session_id,
    prompt = { { type = "text", text = text } },
  }, function(err, result)
    vim.schedule(function()
      M._streaming[buf] = false
      get_stream().stop(buf, gen)
      notify_index()

      if not vim.api.nvim_buf_is_valid(buf) then return end

      local fields = { status = const.session_status.review }

      if result and result.tokenUsage then
        local usage = result.tokenUsage
        local total = (usage.inputTokens or 0) + (usage.outputTokens or 0)
        fields.tokens = total >= 1000 and string.format("%.1fk", total / 1000) or tostring(total)
      end

      local cost_num = result and tonumber(result.cost)
      if cost_num then
        fields.cost = string.format("%.4f", cost_num)
      end

      M._end_turn(buf, result and result.tokenUsage, cost_num)

      local elapsed_ms = math.floor((vim.uv.hrtime() - turn_started) / 1e6)
      if elapsed_ms >= 60000 then
        fields.elapsed = string.format("%dm%02ds", math.floor(elapsed_ms / 60000), math.floor((elapsed_ms % 60000) / 1000))
      elseif elapsed_ms >= 1000 then
        fields.elapsed = string.format("%.1fs", elapsed_ms / 1000)
      else
        fields.elapsed = elapsed_ms .. "ms"
      end

      doc.set_frontmatter_fields(buf, fields)

      store.append_event(session_id, root, {
        type = const.event.result,
        tokens = result and result.tokenUsage or vim.empty_dict(),
        cost = result and result.cost or 0,
      })

      if err then
        local msg = tostring(err.message or err)
        if msg:match("Session not found") or (err.code and err.code == -32603) then
          M._retry_with_new_session(buf, text)
          return
        end
      end

      doc.ensure_composer(buf)

      if config.get("auto_compact") then
        doc.compact(buf)
      end

      if config.get("auto_save") and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent! write")
        end)
      end

      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        vim.api.nvim_win_call(win, function()
          pcall(function()
            local compose = doc.find_compose_line(buf)
            if compose then
              local lc = vim.api.nvim_buf_line_count(buf)
              local target = math.min(compose + 1, lc)
              vim.cmd(target .. "foldopen!")
            end
          end)
          pcall(doc.goto_compose, buf)
        end)
      end
    end)
  end)
end

function M.interrupt(buf)
  local sid = M._sessions[buf]
  local client = M._clients[buf]
  if sid and client and client:is_alive() then
    client:notify("session/cancel", { sessionId = sid })
    notify_index()
  end
end

M._pending_permission = {}
M._permission_ns = vim.api.nvim_create_namespace("neowork_permission")

local function remove_permission_ui(buf, perm)
  if not perm or not perm.mark_id then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, M._permission_ns, perm.mark_id, { details = true })
  pcall(vim.api.nvim_buf_del_extmark, buf, M._permission_ns, perm.mark_id)
  if not pos or not pos[1] then return end
  local start_row = pos[1]
  local end_row = pos[3] and pos[3].end_row or (start_row + perm.line_count)
  local lc = vim.api.nvim_buf_line_count(buf)
  if start_row >= lc then return end
  end_row = math.min(end_row, lc)
  pcall(vim.api.nvim_buf_set_lines, buf, start_row, end_row, false, {})
end

function M._handle_permission(buf, params, respond)
  local options = {}
  for _, opt in ipairs(params.options or {}) do
    options[#options + 1] = {
      label = opt.name or opt.kind,
      kind = opt.kind,
      id = opt.optionId,
    }
  end
  local title = (params.toolCall and params.toolCall.title) or "Permission request"
  local doc = get_document()
  local compose = doc.find_compose_line(buf)
  local mark_id
  local lines = {
    "",
    const.role.system,
    "Permission:" .. title,
    "  [s] pick  [ya] allow  [yn] deny  [yA] always",
    "",
  }
  if compose then
    local start_row = compose - 1
    vim.api.nvim_buf_set_lines(buf, start_row, start_row, false, lines)
    mark_id = vim.api.nvim_buf_set_extmark(buf, M._permission_ns, start_row, 0, {
      end_row = start_row + #lines,
      end_col = 0,
      right_gravity = false,
      end_right_gravity = true,
    })
  end
  notify_index()
  M._pending_permission[buf] = {
    options = options,
    respond = respond,
    title = title,
    tool_desc = params.toolCall and params.toolCall.title,
    tool_kind = params.toolCall and params.toolCall.kind,
    raw_input = params.toolCall and params.toolCall.rawInput,
    content = params.toolCall and params.toolCall.content,
    locations = params.toolCall and params.toolCall.locations,
    mark_id = mark_id,
    line_count = #lines,
  }
  notify_index()
end

function M.permission_action(buf, action)
  local perm = M._pending_permission[buf]
  if not perm then
    vim.notify("No pending permission", vim.log.levels.WARN)
    return
  end

  if action == "select" then
    local labels = {}
    for _, opt in ipairs(perm.options) do
      labels[#labels + 1] = opt.label
    end
    vim.ui.select(labels, { prompt = perm.title }, function(_, idx)
      if not idx then return end
      M._pending_permission[buf] = nil
      remove_permission_ui(buf, perm)
      pcall(perm.respond, { outcome = { outcome = "selected", optionId = perm.options[idx].id } })
      notify_index()
    end)
    return
  end

  local kind_map = { allow = "allow_once", deny = "reject_once", always = "allow_always" }
  local target_kind = kind_map[action]
  local option_id
  for _, opt in ipairs(perm.options) do
    if opt.kind == target_kind then
      option_id = opt.id
      break
    end
  end

  if not option_id then
    M.permission_action(buf, "select")
    return
  end

  M._pending_permission[buf] = nil
  remove_permission_ui(buf, perm)
  pcall(perm.respond, { outcome = { outcome = "selected", optionId = option_id } })
  notify_index()
end

function M.has_pending_permission(buf)
  return M._pending_permission[buf] ~= nil
end

function M.get_pending_permission(buf)
  local p = M._pending_permission[buf]
  if not p then return nil end
  return {
    title = p.title,
    tool_kind = p.tool_kind,
    tool_desc = p.tool_desc,
    raw_input = p.raw_input,
    content = p.content,
    locations = p.locations,
    options = p.options,
  }
end

function M.is_streaming(buf)
  return M._streaming[buf] == true
end

function M.get_session_id(buf)
  return M._sessions[buf]
end

function M.get_client(buf)
  return M._clients[buf]
end

function M.get_mode(buf)
  local m = M._modes[buf]
  if not m or not m.current_id then return nil end
  for _, mode in ipairs(m.available or {}) do
    if mode.id == m.current_id then return mode end
  end
  return { id = m.current_id, name = m.current_id }
end

function M.set_mode_id(buf, mode_id)
  local m = M._modes[buf]
  if not m then
    vim.notify("neowork: no modes reported for this session", vim.log.levels.WARN)
    return
  end
  local sid = M._sessions[buf]
  local client = M._clients[buf]
  if not sid or not client or not client:is_alive() then
    vim.notify("neowork: no active session", vim.log.levels.WARN)
    return
  end
  local target
  for _, mode in ipairs(m.available or {}) do
    if mode.id == mode_id then target = mode break end
  end
  if not target then
    vim.notify("neowork: unknown mode " .. tostring(mode_id), vim.log.levels.WARN)
    return
  end

  local doc = get_document()
  local provider_name = doc.read_frontmatter_field(buf, "provider") or config.get("provider")
  local Session = require("djinni.acp.session")

  Session.set_mode(nil, sid, target.id, provider_name, function(err)
    vim.schedule(function()
      if err then
        vim.notify("neowork: mode switch failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
        return
      end
      m.current_id = target.id
      doc.set_frontmatter_field(buf, "mode", target.id)
      vim.notify("neowork: mode " .. (target.name or target.id), vim.log.levels.INFO)
    end)
  end)
end

function M.set_mode(buf)
  local m = M._modes[buf]
  if not m or not m.available or #m.available == 0 then
    vim.notify("neowork: no modes reported yet (send a message first)", vim.log.levels.WARN)
    return
  end
  if #m.available < 2 then
    vim.notify("neowork: only one mode available (" .. (m.available[1].name or m.available[1].id) .. ")", vim.log.levels.WARN)
    return
  end
  local idx = 1
  for i, mode in ipairs(m.available) do
    if mode.id == m.current_id then idx = i break end
  end
  local next_mode = m.available[(idx % #m.available) + 1]
  M.set_mode_id(buf, next_mode.id)
end

function M.switch_model(buf)
  local sid = M._sessions[buf]
  local client = M._clients[buf]
  if not sid or not client or not client:is_alive() then
    vim.notify("neowork: no active session", vim.log.levels.WARN)
    return
  end
  local doc = get_document()
  local provider_name = doc.read_frontmatter_field(buf, "provider") or config.get("provider")
  local Session = require("djinni.acp.session")
  local session_models = Session.get_available_models(sid)
  local items = Provider.list_models(session_models, provider_name)
  if #items == 0 then
    vim.notify("neowork: no models reported by " .. provider_name, vim.log.levels.WARN)
    return
  end
  vim.ui.select(items, {
    prompt = "Model (" .. provider_name .. "):",
    format_item = function(it) return it.label end,
  }, function(choice)
    if not choice then return end
    local ok, err = pcall(Session.set_model, nil, sid, choice.id, provider_name)
    if not ok then
      vim.notify("neowork: set_model failed: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    doc.set_frontmatter_field(buf, "model", choice.id)
    vim.notify("neowork: model " .. choice.label, vim.log.levels.INFO)
  end)
end

function M.switch_provider(buf)
  local names = Provider.list()
  if not names or #names == 0 then
    vim.notify("neowork: no providers available", vim.log.levels.WARN)
    return
  end
  vim.ui.select(names, { prompt = "Provider:" }, function(choice)
    if not choice then return end

    local doc = get_document()
    local sub = M._sub_handles[buf]
    local old_sid = M._sessions[buf]
    if sub and old_sid then
      pcall(function() sub.client:unsubscribe(old_sid, sub.handle) end)
    end
    local client = M._clients[buf]
    if client then
      pcall(function()
        if old_sid then client:notify("session/cancel", { sessionId = old_sid }) end
        client:shutdown(true)
      end)
    end
    if old_sid then M._bufs[old_sid] = nil end
    M._sessions[buf] = nil
    M._clients[buf] = nil
    M._sub_handles[buf] = nil
    M._modes[buf] = nil
    M._streaming[buf] = nil
    M._inflight[buf] = nil

    doc.set_frontmatter_fields(buf, { provider = choice, session = "" })

    M.create_session(buf, function(err)
      if err then
        vim.notify("neowork: provider switch failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
        return
      end
      vim.notify("neowork: provider " .. choice, vim.log.levels.INFO)
    end)
  end)
end

function M.detach(buf)
  local sid = M._sessions[buf]
  local sub = M._sub_handles[buf]

  if sub and sid then
    pcall(function()
      sub.client:unsubscribe(sid, sub.handle)
    end)
  end

  local client = M._clients[buf]
  if client then
    pcall(function()
      if sid then
        client:notify("session/cancel", { sessionId = sid })
      end
      client:shutdown(true)
    end)
  end

  if sid then
    M._bufs[sid] = nil
  end

  M._sessions[buf] = nil
  M._clients[buf] = nil
  M._streaming[buf] = nil
  M._stream_gen[buf] = nil
  M._sub_handles[buf] = nil
  M._modes[buf] = nil
  M._inflight[buf] = nil
end

return M
