local M = {}

local Client = require("djinni.acp.client")
local Provider = require("djinni.acp.provider")
local ui = require("djinni.integrations.snacks_ui")
local config = require("neowork.config")
local store = require("neowork.store")
local util = require("neowork.util")
local const = require("neowork.const")

local get_document = util.lazy("neowork.document")
local get_stream = util.lazy("neowork.stream")
local Session = require("djinni.acp.session")
local subscribers = require("neowork.session.subscribers")
local session_store = require("neowork.session.store")

local _notify_index_pending = false
local function notify_index()
  if _notify_index_pending then return end
  _notify_index_pending = true
  vim.schedule(function()
    _notify_index_pending = false
    local ok, index = pcall(require, "neowork.index")
    if ok and index and index.refresh_all then
      pcall(index.refresh_all)
    end
  end)
end

local function classify_error(msg, code)
  msg = tostring(msg or "")
  local lower = msg:lower()
  if lower:match("unauthor") or lower:match("authenticat") or lower:match("invalid api key")
    or lower:match("not logged in") or lower:match("login required") or code == 401 then
    return { kind = "auth", label = "Authentication required", message = msg }
  end
  if lower:match("rate limit") or lower:match("429") or lower:match("too many requests") then
    return { kind = "rate_limit", label = "Rate limit", message = msg }
  end
  if lower:match("quota") or lower:match("usage limit") or lower:match("5%-hour")
    or lower:match("5 hour limit") or lower:match("insufficient credit") or lower:match("billing") then
    return { kind = "quota", label = "Usage limit reached", message = msg }
  end
  if lower:match("context.*exceed") or lower:match("maximum context") or lower:match("too many tokens")
    or lower:match("token limit") or lower:match("context window") then
    return { kind = "context_limit", label = "Context limit", message = msg }
  end
  if lower:match("session not found") or code == -32603 then
    return { kind = "session", label = "Session expired", message = msg }
  end
  return { kind = "error", label = "Error", message = msg }
end

local function report_error(buf, err, client)
  local raw = err and (err.message or tostring(err)) or "unknown error"
  local hint = client and client.get_error_hint and client:get_error_hint() or nil
  local classified = classify_error(raw, err and err.code)
  if hint and classified.kind == "error" then
    classified = classify_error(hint)
  end
  local full = classified.label .. ": " .. (classified.message or raw)
  if hint and not full:find(hint, 1, true) then
    full = full .. " | " .. hint
  end
  if classified.kind == "auth" or classified.kind == "rate_limit" or classified.kind == "quota" or classified.kind == "context_limit" then
    vim.notify("neowork: " .. full, vim.log.levels.ERROR)
  end
  return classified, full
end

M._sessions = {}
M._bufs = {}
M._clients = {}
M._streaming = {}
M._stream_gen = {}
M._modes = {}
M._providers = {}
M._inflight = {}
M._last_session_id = {}
M._send_queue = {}
M._pending_context = {}
M._turn_started_at = {}
M._turn_elapsed_ms = {}
M._usage = {}
M._diff_stats = {}
M._runtime_status = {}
M._runtime_meta = {}
M._spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
M._spinner_frame = 0
M._redraw_timer = nil

local function redraw_status()
  vim.schedule(function()
    pcall(vim.cmd.redrawstatus)
  end)
end

local function persisted_status_for(status, opts)
  opts = opts or {}
  if opts.persisted ~= nil then return opts.persisted end
  if status == const.session_status.connecting then return const.session_status.ready end
  if status == const.session_status.submitting then return const.session_status.running end
  if status == const.session_status.streaming then return const.session_status.running end
  if status == const.session_status.tool then return const.session_status.running end
  return status
end

local function set_runtime_status(buf, status, opts)
  opts = opts or {}
  if M._runtime_status[buf] == status and M._runtime_meta[buf] == opts.meta then
    return
  end
  M._runtime_status[buf] = status
  M._runtime_meta[buf] = opts.meta

  if opts.persist ~= false and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].neowork_chat then
    local persisted = persisted_status_for(status, opts)
    if persisted and persisted ~= "" then
      get_document().set_frontmatter_field(buf, "status", persisted)
    end
  end

  notify_index()
  redraw_status()
end

local function clear_runtime_status(buf)
  M._runtime_status[buf] = nil
  M._runtime_meta[buf] = nil
  notify_index()
  redraw_status()
end

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
  set_runtime_status(buf, const.session_status.connecting, { persist = false })

  client:when_ready(function(ready_err)
    if ready_err then
      M._clients[buf] = nil
      local classified, full = report_error(buf, ready_err, client)
      set_runtime_status(buf, const.session_status.error, {
        persisted = const.session_status.review,
        meta = { message = full, kind = classified.kind },
      })
      callback(ready_err)
      return
    end
    if M._sessions[buf] then
      set_runtime_status(buf, const.session_status.ready)
    else
      set_runtime_status(buf, const.session_status.connecting, { persist = false })
    end
    callback(nil, client)
  end)
end

function M.create_session(buf, callback)
  if M._inflight[buf] then
    if callback then table.insert(M._inflight[buf], callback) end
    return
  end

  if M._sessions[buf] then
    M.reset_session(buf)
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
      Session.attach_new_session(sid, client, provider_name, root, result)

      if result.modes then
        M._modes[buf] = {
          available = result.modes.availableModes or {},
          current_id = result.modes.currentModeId,
        }
      end

      local seed_cmds = result.availableCommands or result.commands
      if type(seed_cmds) == "table" and #seed_cmds > 0 then
        local ok_s, stream = pcall(require, "neowork.stream")
        if ok_s and stream then
          stream._available_commands[buf] = seed_cmds
        end
      end

      doc.set_frontmatter_fields(buf, { session = sid, status = const.session_status.ready })
      set_runtime_status(buf, const.session_status.ready)

      M._subscribe(buf, sid, client)
      store.ensure_dirs(root)

      local kind = M._last_session_id[buf] and "restarted" or "started"
      M._insert_session_system_block(buf, kind)

      finish(nil, sid)
    end, { timeout = 90000 })
  end)
end

local function resolve_resume_method(client, provider_name)
  local caps = client and (client.server_capabilities or client.agent_capabilities)
  local session_caps = caps and caps.sessionCapabilities or nil
  if (caps and caps.loadSession) or (session_caps and session_caps.resume) then
    return "session/load", true
  end
  local provider = Provider.get(provider_name)
  local resume = provider and provider.resume or { method = "session/resume" }
  return resume.method, resume.needs_cwd == true
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

    local doc = get_document()
    local provider_name = doc.read_frontmatter_field(buf, "provider") or config.get("provider")
    local root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd()

    local function fall_back_to_new()
      local old_sid = M._sessions[buf]
      if old_sid then M._bufs[old_sid] = nil end
      if old_sid then Session.detach_client_session(old_sid) end
      M._sessions[buf] = nil
      get_document().set_frontmatter_field(buf, "session", "")
      subscribers.detach(buf)
      if not M._pending_context[buf] then
        local ctx = M._build_context_from_buffer(buf)
        if ctx then M._pending_context[buf] = ctx end
      end
      M.create_session(buf, callback)
    end

    local method, needs_cwd = resolve_resume_method(client, provider_name)

    M._sessions[buf] = session_id
    M._bufs[session_id] = buf
    M._stream_gen[buf] = 0
    M._subscribe(buf, session_id, client)

    local req = { sessionId = session_id }
    if needs_cwd then
      req.cwd = vim.fn.fnamemodify(root, ":p"):gsub("/+$", "")
      req.mcpServers = setmetatable({}, { __jsontype = "array" })
    end
    client:request(method, req, function(req_err, result)
      if req_err then
        subscribers.detach(buf)
        fall_back_to_new()
        return
      end
      if result and result.modes then
        M._modes[buf] = {
          available = result.modes.availableModes or {},
          current_id = result.modes.currentModeId,
        }
      end
      Session.attach_client_session(session_id, client, provider_name, root, result)
      doc.set_frontmatter_field(buf, "status", const.session_status.ready)
      set_runtime_status(buf, const.session_status.ready)
      store.ensure_dirs(root)
      if callback then callback(nil, session_id) end
    end, { timeout = 90000 })
  end)
end

M._last_user_row = M._last_user_row or {}

function M.reset_session(buf)
  local old_sid = M._sessions[buf]
  if old_sid then
    M._bufs[old_sid] = nil
    Session.detach_client_session(old_sid)
  end
  M._sessions[buf] = nil
  M._inflight[buf] = nil
  M._streaming[buf] = false
  M._stream_gen[buf] = (M._stream_gen[buf] or 0) + 1
end

local MAX_CONTEXT_CHARS = 20000

function M._build_context_from_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local ok_ast, ast = pcall(require, "neowork.ast")
  if not ok_ast then return nil end
  local turns = ast.turns(buf) or {}
  if #turns == 0 then return nil end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parts = {}
  for _, t in ipairs(turns) do
    if not t.is_compose then
      parts[#parts + 1] = "# " .. t.role
      for i = t.content_start, t.end_line do
        parts[#parts + 1] = lines[i] or ""
      end
      parts[#parts + 1] = ""
    end
  end
  local body = vim.trim(table.concat(parts, "\n"))
  if body == "" then return nil end
  if #body > MAX_CONTEXT_CHARS then
    body = "…[truncated]…\n" .. body:sub(-MAX_CONTEXT_CHARS)
  end
  return "<previous_conversation>\n" .. body .. "\n</previous_conversation>"
end

function M.restart(buf)
  local doc = get_document()
  local fm_sid = doc.read_frontmatter_field(buf, "session") or ""
  local context
  if fm_sid == "" then
    context = M._build_context_from_buffer(buf)
  end
  M.detach(buf)
  if context then
    M._pending_context[buf] = context
  end
  local function done(err)
    vim.schedule(function()
      if err then
        vim.notify("neowork: restart failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
        return
      end
      local label
      if fm_sid ~= "" then
        label = "session resumed " .. fm_sid:sub(1, 8)
      elseif context then
        label = "session restarted (with context)"
      else
        label = "session restarted"
      end
      vim.notify("neowork: " .. label, vim.log.levels.INFO)
    end)
  end
  if fm_sid ~= "" then
    M.resume_session(buf, fm_sid, done)
  else
    M.create_session(buf, done)
  end
end

function M._retry_with_new_session(buf, text)
  local doc = get_document()
  local you_row = M._last_user_row[buf]
  if you_row and doc.truncate_after_user_row then
    pcall(doc.truncate_after_user_row, buf, you_row)
  end

  M.reset_session(buf)

  M.create_session(buf, function(err, new_sid)
    if err then
      vim.notify("neowork: retry failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
      return
    end
    M._do_send(buf, new_sid, text)
  end)
end

function M._subscribe(buf, session_id, client)
  subscribers.attach(buf, session_id, client, {
    on_update = function(params)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local su = params.update or params
      if su.sessionUpdate == const.event.modes and su.availableModes then
        M._modes[buf] = M._modes[buf] or {}
        M._modes[buf].available = su.availableModes
        if su.currentModeId then M._modes[buf].current_id = su.currentModeId end
        redraw_status()
      elseif su.sessionUpdate == const.event.current_mode_update and su.modeId then
        M._modes[buf] = M._modes[buf] or { available = {} }
        M._modes[buf].current_id = su.modeId
        redraw_status()
      elseif su.sessionUpdate == const.event.available_commands_update then
        local ok_s, stream = pcall(require, "neowork.stream")
        if ok_s and stream then
          stream._available_commands[buf] = su.availableCommands or su.commands or {}
        end
        redraw_status()
      end
      local max_output = config.get("max_tool_output_lines") or 50
      pcall(session_store.apply_event, buf, su, { max_output = max_output })
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
  })
end

function M.send(buf, text)
  if M._streaming[buf] then
    M._send_queue[buf] = M._send_queue[buf] or {}
    table.insert(M._send_queue[buf], text)
    notify_index()
    redraw_status()
    vim.notify(
      string.format("neowork: queued (%d waiting) — Djinni is busy", #M._send_queue[buf]),
      vim.log.levels.INFO
    )
    return
  end
  local sid = M._sessions[buf]
  if not sid then
    local fm_sid = get_document().read_frontmatter_field(buf, "session") or ""
    local after = function(err, new_sid)
      if err then return end
      M._do_send(buf, new_sid, text)
    end
    if fm_sid ~= "" then
      M.resume_session(buf, fm_sid, after)
    else
      M.create_session(buf, after)
    end
    return
  end
  M._do_send(buf, sid, text)
end

function M.queue_depth(buf)
  local q = M._send_queue[buf]
  return q and #q or 0
end

local function drain_send_queue(buf)
  local q = M._send_queue[buf]
  if not q or #q == 0 then return end
  local text = table.remove(q, 1)
  if #q == 0 then M._send_queue[buf] = nil end
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local doc = get_document()
    pcall(doc.insert_turn, buf, "You", text)
    M.send(buf, text)
  end)
end

function M.send_fresh(buf, text)
  M.reset_session(buf)
  M.send(buf, text)
end

function M._do_send(buf, session_id, text)
  local client = M._clients[buf]
  if not client or not client:is_alive() then return end

  local gen = (M._stream_gen[buf] or 0) + 1
  M._stream_gen[buf] = gen
  M._streaming[buf] = true

  local doc = get_document()
  local root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
  set_runtime_status(buf, const.session_status.submitting, {
    persisted = const.session_status.running,
  })

  store.append_event(session_id, root, { type = "user", content = text })
  pcall(session_store.add_user_message, buf, text)
  notify_index()

  if doc.find_last_role_row then
    M._last_user_row[buf] = doc.find_last_role_row(buf, "You")
  end

  M._begin_turn(buf)
  local turn_started = M._turn_started_at[buf] or vim.uv.hrtime()

  get_stream().start(buf, gen)

  local prompt_text = text
  local ctx = M._pending_context[buf]
  if ctx and ctx ~= "" then
    prompt_text = ctx .. "\n\n" .. text
    M._pending_context[buf] = nil
  end

  client:request("session/prompt", {
    sessionId = session_id,
    prompt = { { type = "text", text = prompt_text } },
  }, function(err, result)
    vim.schedule(function()
      M._streaming[buf] = false
      get_stream().stop(buf, gen)
      notify_index()

      if not vim.api.nvim_buf_is_valid(buf) then return end

      local fields = {}

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

      if err then
        local msg = tostring(err.message or err)
        if msg:match("Session not found") or (err.code and err.code == -32603) then
          vim.notify("neowork: session lost — run :NwRestart to start a new one", vim.log.levels.WARN)
        end
      end

      doc.set_frontmatter_fields(buf, fields)

      store.append_event(session_id, root, {
        type = const.event.result,
        tokens = result and result.tokenUsage or vim.empty_dict(),
        cost = result and result.cost or 0,
      })

      if err then
        local classified, full = report_error(buf, err, M._clients[buf])
        set_runtime_status(buf, const.session_status.error, {
          persisted = const.session_status.review,
          meta = { message = full, kind = classified.kind },
        })
      else
        local stop_reason = result and result.stopReason or nil
        if stop_reason == "cancelled" then
          set_runtime_status(buf, const.session_status.interrupted, {
            persisted = const.session_status.ready,
          })
        else
          set_runtime_status(buf, const.session_status.ready)
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
          pcall(vim.cmd, "normal! zb")
        end)
      end

      drain_send_queue(buf)
    end)
  end)
end

function M.interrupt(buf)
  local sid = M._sessions[buf]
  local client = M._clients[buf]
  if sid and client and client:is_alive() then
    set_runtime_status(buf, const.session_status.interrupted, { persist = false })
    client:notify("session/cancel", { sessionId = sid })
    notify_index()
    vim.notify("neowork: interrupted — session/cancel sent", vim.log.levels.INFO)
  else
    vim.notify("neowork: nothing to interrupt", vim.log.levels.WARN)
  end
end

M._pending_permission = {}
M._permission_ns = vim.api.nvim_create_namespace("neowork_permission")

local function one_line(s)
  return (tostring(s or ""):gsub("[\r\n]+", " "))
end

local KIND_KEY = {
  [const.permission_kind.allow_once] = "ya",
  [const.permission_kind.reject_once] = "yn",
  [const.permission_kind.allow_always] = "yA",
  [const.permission_kind.reject_always] = "yN",
}

local function format_option_hints(options)
  local parts = { "[s] pick" }
  for _, opt in ipairs(options or {}) do
    local key = KIND_KEY[opt.kind]
    local label = one_line(opt.label or opt.kind or "option")
    if key then
      parts[#parts + 1] = "[" .. key .. "] " .. label
    else
      parts[#parts + 1] = label
    end
  end
  return "  " .. table.concat(parts, "  ")
end

local function render_permission_command(raw_input)
  if type(raw_input) == "string" and raw_input ~= "" then
    return raw_input
  end
  if type(raw_input) ~= "table" then
    return nil
  end

  local command = raw_input.command or raw_input.cmd
  if type(command) == "string" and command ~= "" then
    local desc = raw_input.description
    if type(desc) == "string" and desc ~= "" then
      return "$ " .. command .. "  — " .. desc
    end
    return "$ " .. command
  end

  if type(raw_input.file_path) == "string" and raw_input.file_path ~= "" then
    if raw_input.old_string or raw_input.new_string or raw_input.patch then
      return "✎ " .. raw_input.file_path
    end
    if raw_input.content ~= nil then
      return "📝 " .. raw_input.file_path
    end
    return raw_input.file_path
  end

  if type(raw_input.path) == "string" and raw_input.path ~= "" then
    if raw_input.old_string or raw_input.new_string or raw_input.patch then
      return "✎ " .. raw_input.path
    end
    if raw_input.content ~= nil then
      return "📝 " .. raw_input.path
    end
    return raw_input.path
  end

  if type(raw_input.url) == "string" and raw_input.url ~= "" then
    return "↗ " .. raw_input.url
  end
  if type(raw_input.pattern) == "string" and raw_input.pattern ~= "" then
    return "🔎 " .. raw_input.pattern
  end
  if type(raw_input.query) == "string" and raw_input.query ~= "" then
    return "? " .. raw_input.query
  end
  if type(raw_input.description) == "string" and raw_input.description ~= "" then
    return raw_input.description
  end
  return nil
end

local function permission_lines(title, command, outcome, options)
  local lines = {
    const.role.system,
    "",
    "Permission: " .. one_line(title ~= nil and title ~= "" and title or "Permission request"),
  }
  if command and command ~= "" then
    lines[#lines + 1] = "Command: " .. one_line(command)
  end
  if outcome and outcome ~= "" then
    lines[#lines + 1] = "Status: " .. one_line(outcome)
  else
    lines[#lines + 1] = format_option_hints(options)
  end
  lines[#lines + 1] = ""
  return lines
end

local function insert_permission_ui(buf, title, command, options)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local doc = get_document()
  doc.invalidate_compose_cache(buf)
  local compose = doc.find_compose_line(buf)
  local insert_row
  local probe_row
  if compose then
    insert_row = compose - 1
    probe_row = compose - 3
  else
    insert_row = vim.api.nvim_buf_line_count(buf)
    probe_row = insert_row - 2
  end
  local has_sep = false
  if probe_row and probe_row >= 0 then
    local prev = vim.api.nvim_buf_get_lines(buf, probe_row, probe_row + 1, false)[1] or ""
    has_sep = prev:match("^[%-_%*][%-_%*][%-_%*]+%s*$") ~= nil
  end
  local block = permission_lines(title, command, nil, options)
  local lines
  if has_sep then
    lines = block
  else
    lines = { "---", "" }
    for _, l in ipairs(block) do lines[#lines + 1] = l end
  end
  vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, lines)
  local mark_id = vim.api.nvim_buf_set_extmark(buf, M._permission_ns, insert_row, 0, {
    end_row = insert_row + #lines,
    end_col = 0,
    right_gravity = false,
    end_right_gravity = true,
  })
  return mark_id, #lines, has_sep
end

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

local function update_permission_ui(buf, perm, outcome)
  if not perm or not perm.mark_id then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, M._permission_ns, perm.mark_id, { details = true })
  if not pos or not pos[1] then return end
  local start_row = pos[1]
  local details = pos[3] or {}
  local end_row = details.end_row or (start_row + (perm.line_count or 0))
  local lines = permission_lines(perm.title, perm.command, outcome, perm.options)
  if not perm.has_sep then
    local prefixed = { "---", "" }
    for _, l in ipairs(lines) do prefixed[#prefixed + 1] = l end
    lines = prefixed
  end
  vim.api.nvim_buf_set_lines(buf, start_row, end_row, false, lines)
  pcall(vim.api.nvim_buf_del_extmark, buf, M._permission_ns, perm.mark_id)
  perm.mark_id = vim.api.nvim_buf_set_extmark(buf, M._permission_ns, start_row, 0, {
    end_row = start_row + #lines,
    end_col = 0,
    right_gravity = false,
    end_right_gravity = true,
  })
  perm.line_count = #lines
end

function M._insert_session_system_block(buf, kind)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local doc = get_document()
  local compose = doc.find_compose_line(buf)
  if not compose then return end

  local sid = M._sessions[buf]
  local short_sid = sid and sid:sub(1, 8) or "?"
  local provider = doc.read_frontmatter_field(buf, "provider") or "?"
  local model = doc.read_frontmatter_field(buf, "model") or "?"
  local root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
  local root_display = vim.fn.fnamemodify(root, ":~")
  local mode = M.get_mode(buf)
  local mode_name = mode and (mode.name or mode.id) or "-"

  local label = (kind == "restarted") and "Session restarted" or "Session started"
  local header_line = label .. "  " .. short_sid
  local meta_line = string.format("provider=%s  model=%s  mode=%s", provider, model, mode_name)
  local root_line = "root=" .. root_display

  local has_sep = false
  if compose >= 3 then
    local prev = vim.api.nvim_buf_get_lines(buf, compose - 3, compose - 2, false)[1] or ""
    has_sep = prev:match("^[%-_%*][%-_%*][%-_%*]+%s*$") ~= nil
  end

  local lines = has_sep
    and { const.role.system, "", header_line, meta_line, root_line, "" }
    or { "---", "", const.role.system, "", header_line, meta_line, root_line, "" }

  local start_row = compose - 1
  pcall(vim.api.nvim_buf_set_lines, buf, start_row, start_row, false, lines)

  M._last_session_id[buf] = sid
end

local function resume_permission(co, value)
  if not co or coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co, value)
  if not ok then
    vim.notify("neowork: permission coroutine error: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M._handle_permission(buf, params, respond)
  local prev = M._pending_permission[buf]
  if prev and prev.co then
    M._pending_permission[buf] = nil
    resume_permission(prev.co, { cancelled = true })
  end

  local options = {}
  for _, opt in ipairs(params.options or {}) do
    options[#options + 1] = {
      label = opt.name or opt.kind,
      kind = opt.kind,
      id = opt.optionId,
    }
  end
  local title = (params.toolCall and params.toolCall.title) or "Permission request"
  local tool_desc = params.toolCall and params.toolCall.title
  local tool_kind = params.toolCall and params.toolCall.kind
  local raw_input = params.toolCall and params.toolCall.rawInput
  local content = params.toolCall and params.toolCall.content
  local locations = params.toolCall and params.toolCall.locations
  local previous_status = M._runtime_status[buf] or const.session_status.submitting
  local command = render_permission_command(raw_input)

  local perm
  local co = coroutine.create(function()
    local ok, err = pcall(function()
      set_runtime_status(buf, const.session_status.awaiting, {
        meta = { title = tool_desc, kind = tool_kind },
      })
      local mark_id, line_count, has_sep = insert_permission_ui(buf, title, command, options)
      perm.mark_id = mark_id
      perm.line_count = line_count
      perm.has_sep = has_sep
      M._pending_permission[buf] = perm
      notify_index()
    end)
    if not ok then
      vim.notify("neowork: permission setup failed: " .. tostring(err), vim.log.levels.ERROR)
      pcall(respond, { outcome = { outcome = "cancelled" } })
      return
    end

    local resolution = coroutine.yield() or { cancelled = true }

    if M._pending_permission[buf] == perm then
      M._pending_permission[buf] = nil
    end

    if resolution.cancelled then
      update_permission_ui(buf, perm, "cancelled")
    elseif resolution.option then
      local label = resolution.status and (resolution.status .. ": " .. resolution.option.label)
        or resolution.option.label
      update_permission_ui(buf, perm, label)
    end

    set_runtime_status(buf, previous_status, {
      persisted = previous_status == const.session_status.awaiting and const.session_status.running or nil,
    })

    if resolution.cancelled or not resolution.option then
      pcall(respond, { outcome = { outcome = "cancelled" } })
    else
      pcall(respond, { outcome = { outcome = "selected", optionId = resolution.option.id } })
    end

    notify_index()
  end)

  perm = {
    co = co,
    options = options,
    title = title,
    tool_desc = tool_desc,
    tool_kind = tool_kind,
    command = command,
    raw_input = raw_input,
    content = content,
    locations = locations,
  }

  resume_permission(co)
end

function M.permission_action(buf, action)
  local perm = M._pending_permission[buf]
  if not perm or not perm.co or coroutine.status(perm.co) == "dead" then
    vim.notify("No pending permission", vim.log.levels.WARN)
    return
  end

  if action == "select" then
    ui.select(perm.options, {
      prompt = perm.title,
      format_item = function(opt) return opt.label end,
    }, function(choice)
      if not choice then return end
      resume_permission(perm.co, {
        option = choice,
        status = choice.kind == const.permission_kind.reject_once and "denied"
          or choice.kind == const.permission_kind.reject_always and "denied always"
          or choice.kind == const.permission_kind.allow_always and "approved always"
          or "approved",
      })
    end)
    return
  end

  local kind_map = {
    allow = const.permission_kind.allow_once,
    deny = const.permission_kind.reject_once,
    always = const.permission_kind.allow_always,
  }
  local target_kind = kind_map[action]
  local option
  for _, opt in ipairs(perm.options) do
    if opt.kind == target_kind then
      option = opt
      break
    end
  end

  if not option then
    M.permission_action(buf, "select")
    return
  end

  local status_label = action == "allow" and "approved"
    or action == "always" and "approved always"
    or action == "deny" and "denied"
    or action
  resume_permission(perm.co, { option = option, status = status_label })
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

function M.get_status(buf)
  local status = M._runtime_status[buf]
  if status and status ~= "" then
    return status, M._runtime_meta[buf]
  end
  local ok, document = pcall(require, "neowork.document")
  if ok and vim.api.nvim_buf_is_valid(buf) then
    return document.read_frontmatter_field(buf, "status") or const.session_status.idle, nil
  end
  return const.session_status.idle, nil
end

function M.get_status_bucket(buf)
  local status, meta = M.get_status(buf)
  if status == const.session_status.awaiting then return const.session_status.awaiting, meta end
  if status == const.session_status.connecting then return const.session_status.running, meta end
  if status == const.session_status.submitting then return const.session_status.running, meta end
  if status == const.session_status.streaming then return const.session_status.running, meta end
  if status == const.session_status.tool then return const.session_status.running, meta end
  if status == const.session_status.interrupted then return const.session_status.review, meta end
  if status == const.session_status.error then return const.session_status.review, meta end
  if status == const.session_status.idle then return const.session_status.ready, meta end
  return status, meta
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

function M.seed_mode_from_frontmatter(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local fm_mode = get_document().read_frontmatter_field(buf, "mode")
  if not fm_mode or fm_mode == "" then return end
  M._modes[buf] = M._modes[buf] or { available = {} }
  if not M._modes[buf].current_id then
    M._modes[buf].current_id = fm_mode
    redraw_status()
  end
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
      redraw_status()
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
  ui.select(items, {
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
  ui.select(names, { prompt = "Provider:" }, function(choice)
    if not choice then return end

    local doc = get_document()
    local old_sid = M._sessions[buf]
    subscribers.detach(buf)
    local client = M._clients[buf]
    if client then
      pcall(function()
        if old_sid then client:notify("session/cancel", { sessionId = old_sid }) end
        client:shutdown(true)
      end)
    end
    if old_sid then
      M._bufs[old_sid] = nil
      Session.detach_client_session(old_sid)
    end
    M._sessions[buf] = nil
    M._clients[buf] = nil
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

function M.detach(buf, opts)
  opts = opts or {}
  local sid = M._sessions[buf]
  local current_sid = opts.session_id or sid
  local sub = subscribers.get(buf)

  local perm = M._pending_permission[buf]
  if perm then
    M._pending_permission[buf] = nil
    if perm.co and coroutine.status(perm.co) ~= "dead" then
      resume_permission(perm.co, { cancelled = true })
    else
      remove_permission_ui(buf, perm)
    end
  end

  if sub and sub.session_id and sub.session_id ~= "" then
    current_sid = sub.session_id
  end

  subscribers.detach(buf)
  session_store.detach(buf)

  local client = M._clients[buf]
  if client then
    pcall(function()
      if current_sid and current_sid ~= "" then
        client:notify("session/cancel", { sessionId = current_sid })
      end
      client:shutdown(true)
    end)
  end

  if current_sid and current_sid ~= "" then
    M._bufs[current_sid] = nil
    Session.detach_client_session(current_sid)
  end
  if sid and sid ~= "" and sid ~= current_sid then
    M._bufs[sid] = nil
    Session.detach_client_session(sid)
  end

  local inflight = M._inflight[buf]
  M._inflight[buf] = nil
  if inflight then
    for _, cb in ipairs(inflight) do
      vim.schedule(function()
        pcall(cb, { code = -32002, message = "client shutdown" })
      end)
    end
  end

  M._sessions[buf] = nil
  M._clients[buf] = nil
  M._streaming[buf] = nil
  M._stream_gen[buf] = nil
  M._modes[buf] = nil
  M._turn_started_at[buf] = nil
  M._turn_elapsed_ms[buf] = nil
  M._usage[buf] = nil
  M._diff_stats[buf] = nil
  M._last_user_row[buf] = nil
  pcall(function() require("neowork.ast").invalidate(buf) end)
  clear_runtime_status(buf)
end

return M
