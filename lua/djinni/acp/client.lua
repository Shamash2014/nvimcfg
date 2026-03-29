local M = {}
M.__index = M

local function log(_msg, _level) end

function M.new(cmd, args, cwd)
  local self = setmetatable({}, M)
  self.cwd = cwd
  self.request_id = 0
  self.pending_requests = {}
  self.event_handlers = {}
  self._buffer = ""
  self._ready = false
  self._ready_callbacks = {}
  self.request_handlers = {}

  log("spawning: " .. cmd .. " " .. table.concat(args, " ") .. " cwd=" .. (cwd or "nil"))

  self.job_id = vim.fn.jobstart(vim.list_extend({ cmd }, args), {
    cwd = cwd,
    on_stdout = function(_, data)
      self:_on_stdout(data)
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" and not line:match("^%s") and not line:match("%[Object%]") then
            log("stderr: " .. line, vim.log.levels.WARN)
          end
        end
      end
    end,
    on_exit = function(_, code)
      log("process exited with code " .. tostring(code))
      self.exit_code = code
      self.job_id = nil
      self._ready = false
      self:_flush_ready_error("process exited with code " .. tostring(code))
      local pending = self.pending_requests
      self.pending_requests = {}
      for _, cb in pairs(pending) do
        vim.schedule(function()
          cb({ code = -1, message = "process exited" }, nil)
        end)
      end
    end,
    stdin = "pipe",
    stdout_buffered = false,
  })

  if self.job_id and self.job_id > 0 then
    log("job started, id=" .. tostring(self.job_id))
    vim.defer_fn(function()
      self:_initialize()
    end, 50)
    vim.defer_fn(function()
      if not self._ready then
        self:_flush_ready_error("initialize timeout (10s)")
      end
    end, 10000)
  else
    log("job failed to start, job_id=" .. tostring(self.job_id), vim.log.levels.ERROR)
    self.job_id = nil
  end

  return self
end

function M:_initialize()
  log("sending initialize request")
  self:request("initialize", {
    protocolVersion = 1,
    clientInfo = { name = "djinni.nvim", version = "0.1.0" },
    clientCapabilities = vim.empty_dict(),
  }, function(err, result)
    if err then
      log("initialize failed: " .. vim.inspect(err), vim.log.levels.WARN)
      self:_flush_ready_error("initialize failed: " .. (err.message or "unknown"))
      return
    end
    log("initialize OK")
    self._ready = true
    for _, cb in ipairs(self._ready_callbacks) do
      cb(nil)
    end
    self._ready_callbacks = {}
  end)
end

function M:_flush_ready_error(msg)
  log(msg, vim.log.levels.WARN)
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

function M:_on_stdout(data)
  if not data then return end
  for i, chunk in ipairs(data) do
    if i == 1 then
      self._buffer = self._buffer .. chunk
    else
      local line = self._buffer
      self._buffer = chunk
      if line ~= "" then
        self:_handle_message(line)
      end
    end
  end
end

function M:_handle_message(line)
  local ok, msg = pcall(vim.json.decode, line)
  if not ok or type(msg) ~= "table" then
    return
  end

  if msg.id and self.pending_requests[msg.id] then
    local cb = self.pending_requests[msg.id]
    self.pending_requests[msg.id] = nil
    vim.schedule(function()
      if msg.error then
        cb(msg.error, nil)
      else
        cb(nil, msg.result)
      end
    end)
  elseif msg.method and msg.id then
    local rh = self.request_handlers[msg.method]
    if rh then
      local respond = function(result)
        if not self:is_alive() then error("client is not alive") end
        local resp = vim.json.encode({
          jsonrpc = "2.0",
          id = msg.id,
          result = result,
        })
        vim.fn.chansend(self.job_id, resp .. "\n")
      end
      vim.schedule(function()
        rh(msg.params, respond)
      end)
    end
  elseif msg.method and not msg.id then
    local handlers = self.event_handlers[msg.method]
    if handlers then
      vim.schedule(function()
        for _, handler in ipairs(handlers) do
          handler(msg.params)
        end
      end)
    end
  end
end

function M:request(method, params, callback)
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

function M:is_alive()
  return self.job_id ~= nil
end

function M:shutdown(force)
  if not self:is_alive() then
    return
  end
  self:notify("exit")
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
