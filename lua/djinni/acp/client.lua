local M = {}
M.__index = M

local log = require("djinni.nowork.log")

local STDERR_IGNORE = {
  "consuming background task",
  "Session not found",
  "session/prompt",
  "Spawning Claude Code",
  "No onPostToolUseHook",
  "Experiments loaded",
  "%[Object%]",
  "^%s",
}

local MAX_RECONNECT = 3
local RECONNECT_DELAY = 2000

function M.new(cmd, args, cwd)
  local self = setmetatable({}, M)
  self._cmd = cmd
  self._args = args
  self.cwd = cwd
  self.request_id = 0
  self.pending_requests = {}
  self.event_handlers = {}
  self._buffer_parts = {}
  self._update_queue = {}
  self.state = "disconnected"
  self._ready = false
  self._ready_callbacks = {}
  self.request_handlers = {}
  self.subscribers = {}
  self._reconnect_count = 0
  self._shutting_down = false

  self:_spawn()
  return self
end

function M:_spawn()
  self.state = "connecting"
  self._buffer_parts = {}

  log.info("spawning: " .. self._cmd .. " " .. table.concat(self._args, " ") .. " cwd=" .. (self.cwd or "nil"))

  self.job_id = vim.fn.jobstart(vim.list_extend({ self._cmd }, self._args), {
    cwd = self.cwd,
    on_stdout = function(_, data)
      self:_on_stdout(data)
    end,
    on_stderr = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line ~= "" then
          local ignore = false
          for _, pat in ipairs(STDERR_IGNORE) do
            if line:match(pat) then ignore = true; break end
          end
          if not ignore then
            log.warn("stderr: " .. line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      log.warn("process exited with code " .. tostring(code))
      self.exit_code = code
      self.job_id = nil
      self.state = "disconnected"
      self._ready = false
      self:_flush_ready_error("process exited with code " .. tostring(code))
      local pending = self.pending_requests
      self.pending_requests = {}
      for _, cb in pairs(pending) do
        vim.schedule(function()
          cb({ code = -1, message = "process exited" }, nil)
        end)
      end
      if not self._shutting_down and self._reconnect_count < MAX_RECONNECT then
        self._reconnect_count = self._reconnect_count + 1
        log.info("auto-reconnect attempt " .. self._reconnect_count .. "/" .. MAX_RECONNECT)
        vim.defer_fn(function()
          if self.state == "disconnected" and not self._shutting_down then
            self:_spawn()
          end
        end, RECONNECT_DELAY)
      end
    end,
    stdin = "pipe",
    stdout_buffered = false,
  })

  if self.job_id and self.job_id > 0 then
    self.pid = vim.fn.jobpid(self.job_id)
    self.state = "connected"
    log.info("job started, id=" .. tostring(self.job_id))
    vim.defer_fn(function()
      self:_initialize()
    end, 50)
    self._init_timer = vim.defer_fn(function()
      if not self._ready then
        self:_flush_ready_error("initialize timeout (10s)")
      end
    end, 10000)
  else
    log.err("job failed to start, job_id=" .. tostring(self.job_id))
    self.job_id = nil
    self.state = "error"
  end
end

function M:_initialize()
  log.info("sending initialize request")
  self:request("initialize", {
    protocolVersion = 1,
    clientInfo = { name = "djinni.nvim", version = "0.1.0" },
    clientCapabilities = vim.empty_dict(),
  }, function(err, result)
    if err then
      log.warn("initialize failed: " .. vim.inspect(err))
      self:_flush_ready_error("initialize failed: " .. (err.message or "unknown"))
      return
    end
    log.info("initialize OK caps=" .. tostring(result and result.agentCapabilities ~= nil) .. " auth=" .. tostring(result and result.authMethods ~= nil))
    if result then
      self.agent_capabilities = result.agentCapabilities
      self.agent_info = result.agentInfo
      self.auth_methods = result.authMethods
    end
    if self.auth_methods and #self.auth_methods > 0 then
      if self._init_timer then
        self._init_timer:stop()
        self._init_timer = nil
      end
      self:_authenticate(function(auth_err)
        if auth_err then
          log.warn("authenticate failed (non-blocking): " .. (auth_err.message or tostring(auth_err)))
        end
        self:_mark_ready()
      end)
    else
      self:_mark_ready()
    end
  end)
end

function M:_authenticate(callback)
  local method = self.auth_methods[1]
  local method_id = method.id or method.methodId
  log.info("authenticating with method=" .. tostring(method_id))
  self:request("authenticate", { methodId = method_id }, function(err)
    if err then
      log.warn("authenticate error: " .. vim.inspect(err))
      callback(err)
      return
    end
    log.info("authenticate OK")
    callback(nil)
  end, { timeout = 15000 })
end

function M:_mark_ready()
  local was_reconnect = self._reconnect_count > 0
  self.state = "ready"
  self._ready = true
  self._reconnect_count = 0
  for _, cb in ipairs(self._ready_callbacks) do
    cb(nil)
  end
  self._ready_callbacks = {}
  if was_reconnect then
    local handlers = self.event_handlers["client_reconnected"]
    if handlers then
      for _, handler in ipairs(handlers) do
        pcall(handler)
      end
    end
  end
end

function M:_flush_ready_error(msg)
  log.warn(msg)
  local cbs = self._ready_callbacks
  self._ready_callbacks = {}
  for _, cb in ipairs(cbs) do
    vim.schedule(function()
      cb({ message = msg })
    end)
  end
end

function M:when_ready(callback)
  if self._ready then
    callback(nil)
  elseif not self:is_alive() then
    callback({ message = "client not running" })
  else
    table.insert(self._ready_callbacks, callback)
  end
end

local CHUNK_TYPES = {
  agent_message_chunk = true,
  agent_thought_chunk = true,
  usage_update = true,
}

local function coalesce_updates(queue)
  local out = {}
  local i = 1
  while i <= #queue do
    local params = queue[i]
    local su = params.update or params
    local utype = su.sessionUpdate
    if utype and CHUNK_TYPES[utype] and su.content then
      local texts = { su.content.text or "" }
      local last_params = params
      local j = i + 1
      while j <= #queue do
        local nparams = queue[j]
        local nsu = nparams.update or nparams
        if nsu.sessionUpdate == utype and nsu.content then
          texts[#texts + 1] = nsu.content.text or ""
          last_params = nparams
          j = j + 1
        else
          break
        end
      end
      if j > i + 1 then
        local last_su = last_params.update or last_params
        last_su.content.text = table.concat(texts)
        out[#out + 1] = last_params
      else
        out[#out + 1] = params
      end
      i = j
    else
      out[#out + 1] = params
      i = i + 1
    end
  end
  return out
end

function M:_on_stdout(data)
  if not data then return end
  for i, chunk in ipairs(data) do
    if i == 1 then
      self._buffer_parts[#self._buffer_parts + 1] = chunk
    else
      local line = table.concat(self._buffer_parts)
      self._buffer_parts = { chunk }
      if line ~= "" then
        local pq = self._parse_queue
        if not pq then
          pq = {}
          self._parse_queue = pq
        end
        pq[#pq + 1] = line
      end
    end
  end
  self:_start_drain()
end

function M:_start_drain()
  if self._drain_timer then return end
  self._drain_timer = vim.uv.new_timer()
  local client = self
  self._drain_scheduled = false
  self._drain_timer:start(8, 50, function()
    if client._drain_scheduled then return end
    client._drain_scheduled = true
    vim.schedule(function()
      client._drain_scheduled = false
      client:_drain_all()
    end)
  end)
end

local MAX_PARSE_PER_DRAIN = 50

function M:_drain_all()
  local pq = self._parse_queue
  if pq and #pq > 0 then
    local n = #pq
    if n <= MAX_PARSE_PER_DRAIN then
      self._parse_queue = nil
      for _, raw in ipairs(pq) do
        local ok, msg = pcall(vim.json.decode, raw)
        if ok and type(msg) == "table" then
          self:_route_message(msg)
        end
      end
    else
      local batch = {}
      for i = 1, MAX_PARSE_PER_DRAIN do
        batch[i] = pq[i]
      end
      local remaining = {}
      for i = MAX_PARSE_PER_DRAIN + 1, n do
        remaining[#remaining + 1] = pq[i]
      end
      self._parse_queue = remaining
      for _, raw in ipairs(batch) do
        local ok, msg = pcall(vim.json.decode, raw)
        if ok and type(msg) == "table" then
          self:_route_message(msg)
        end
      end
    end
  end

  local has_work = false
  for sid, uq in pairs(self._update_queue) do
    local sub = self.subscribers[sid]
    if sub and sub.on_update then
      has_work = true
      self._update_queue[sid] = nil
      local coalesced = coalesce_updates(uq)
      for _, params in ipairs(coalesced) do
        local h_ok, h_err = pcall(sub.on_update, params)
        if not h_ok then
          log.err("subscriber update error: " .. tostring(h_err))
        end
      end
    elseif #uq > 0 then
      has_work = true
    end
  end

  if not has_work and not self._parse_queue then
    if self._drain_timer and not self._drain_timer:is_closing() then
      self._drain_timer:stop()
      self._drain_timer:close()
    end
    self._drain_timer = nil
  end
end

function M:_route_message(msg)
  if msg.id and self.pending_requests[msg.id] then
    local cb = self.pending_requests[msg.id]
    self.pending_requests[msg.id] = nil
    if msg.error then
      cb(msg.error, nil)
    else
      cb(nil, msg.result)
    end
  elseif msg.method and msg.id then
    local respond = function(result)
      if not self:is_alive() then error("client is not alive") end
      local resp = vim.json.encode({
        jsonrpc = "2.0",
        id = msg.id,
        result = result,
      })
      vim.fn.chansend(self.job_id, resp .. "\n")
    end
    local sid = msg.params and msg.params.sessionId
    local sub = sid and self.subscribers[sid]
    if sub and sub.on_permission and msg.method == "session/request_permission" then
      local s_ok, err = pcall(sub.on_permission, msg.params, respond)
      if not s_ok then
        log.err("subscriber permission error: " .. tostring(err))
      end
    elseif self.request_handlers[msg.method] then
      local s_ok, err = pcall(self.request_handlers[msg.method], msg.params, respond)
      if not s_ok then
        log.err("request handler error: " .. tostring(err))
      end
    end
  elseif msg.method and not msg.id then
    local sid = msg.params and msg.params.sessionId
    if sid and msg.method == "session/update" then
      local uq = self._update_queue[sid]
      if not uq then
        uq = {}
        self._update_queue[sid] = uq
      end
      uq[#uq + 1] = msg.params
    end
    local handlers = self.event_handlers[msg.method]
    if handlers then
      for _, handler in ipairs(handlers) do
        local h_ok, err = pcall(handler, msg.params)
        if not h_ok then
          log.err("event handler error: " .. tostring(err))
        end
      end
    end
  end
end

function M:request(method, params, callback, opts)
  if not self:is_alive() then
    if callback then
      vim.schedule(function()
        callback({ code = -1, message = "client not running" }, nil)
      end)
    end
    return
  end

  self.request_id = self.request_id + 1
  local id = self.request_id

  if callback then
    self.pending_requests[id] = callback

    local timeout_ms = opts and opts.timeout
    if timeout_ms then
      vim.defer_fn(function()
        local cb = self.pending_requests[id]
        if cb then
          self.pending_requests[id] = nil
          cb({ code = -1, message = "request timeout (" .. (timeout_ms / 1000) .. "s)" }, nil)
        end
      end, timeout_ms)
    end
  end

  local msg = vim.json.encode({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  })

  vim.fn.chansend(self.job_id, msg .. "\n")
  return id
end

function M:notify(method, params)
  if not self:is_alive() then
    return
  end

  local msg = vim.json.encode({
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  })

  vim.fn.chansend(self.job_id, msg .. "\n")
end

function M:on(event, handler)
  if not self.event_handlers[event] then
    self.event_handlers[event] = {}
  end
  table.insert(self.event_handlers[event], handler)
end

function M:on_request(method, handler)
  self.request_handlers[method] = handler
end

function M:off(event, handler)
  local handlers = self.event_handlers[event]
  if not handlers then return end
  for i, h in ipairs(handlers) do
    if h == handler then
      table.remove(handlers, i)
      return
    end
  end
end

function M:subscribe(session_id, handlers)
  self.subscribers[session_id] = handlers
  self:_start_drain()
end

function M:unsubscribe(session_id)
  self.subscribers[session_id] = nil
end

function M:is_alive()
  return self.job_id ~= nil
end

function M:kill_tree()
  self._shutting_down = true
  if not self.job_id then return end
  if self.pid then
    pcall(vim.uv.kill, -self.pid, "sigkill")
  end
  pcall(vim.fn.jobstop, self.job_id)
  self.job_id = nil
  self.pid = nil
  self.state = "disconnected"
  self._ready = false
  self.pending_requests = {}
  self.event_handlers = {}
  self.subscribers = {}
  self.request_handlers = {}
  self._ready_callbacks = {}
  self._buffer_parts = {}
end

function M:shutdown(force)
  self._shutting_down = true
  if self._drain_timer and not self._drain_timer:is_closing() then
    self._drain_timer:stop()
    self._drain_timer:close()
  end
  self._drain_timer = nil
  self._parse_queue = nil
  self._update_queue = {}
  if not self:is_alive() then
    return
  end
  self:notify("exit")
  self.pending_requests = {}
  self.event_handlers = {}
  self.subscribers = {}
  self.request_handlers = {}
  self._ready_callbacks = {}
  self._buffer_parts = {}
  if force then
    if self.job_id then
      vim.fn.jobstop(self.job_id)
      self.job_id = nil
    end
  else
    vim.defer_fn(function()
      if self.job_id then
        vim.fn.jobstop(self.job_id)
        self.job_id = nil
      end
    end, 500)
  end
end

return M
