local M = {}

function M.new(transport_handle)
  local rpc = {
    _t           = transport_handle,
    _id          = 0,
    _callbacks   = {},   -- [id] -> fn(err, result)
    _subscribers = {},   -- [session_id] -> fn(notification)[]
  }

  -- installed as transport's on_line
  function rpc:_dispatch(raw_line)
    local ok, msg = pcall(vim.json.decode, raw_line)
    if not ok then return end

    if msg.id ~= nil and (msg.result ~= nil or msg.error ~= nil) then
      -- Response to one of our requests
      local cb = self._callbacks[msg.id]
      if cb then
        self._callbacks[msg.id] = nil
        cb(msg.error, msg.result)
      end
    elseif msg.method and msg.id ~= nil then
      -- Server-initiated request (expects a response)
      require("acp.handlers").dispatch(self, msg)
    elseif msg.method then
      -- Server notification or server-initiated request
      local session_id = msg.params and msg.params.sessionId
      if session_id then
        local subs = self._subscribers[session_id] or {}
        for _, fn in ipairs(subs) do
          fn(msg)
        end
      end
    end
  end

  function rpc:request(method, params, callback)
    self._id = self._id + 1
    local id = self._id
    self._callbacks[id] = callback
    local payload = vim.json.encode({
      jsonrpc = "2.0", id = id, method = method, params = params,
    })
    require("acp.transport").write(self._t, payload)
  end

  function rpc:notify(method, params)
    local payload = vim.json.encode({
      jsonrpc = "2.0", method = method, params = params,
    })
    require("acp.transport").write(self._t, payload)
  end

  function rpc:respond(id, result)
    local payload = vim.json.encode({
      jsonrpc = "2.0", id = id, result = result,
    })
    require("acp.transport").write(self._t, payload)
  end

  function rpc:subscribe(session_id, fn)
    self._subscribers[session_id] = self._subscribers[session_id] or {}
    table.insert(self._subscribers[session_id], fn)
  end

  function rpc:drain_callbacks(err)
    for _, cb in pairs(self._callbacks) do cb(err, nil) end
    self._callbacks = {}
  end

  return rpc
end

return M
