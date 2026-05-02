local M = {}
local transport = require("acp.transport")
local rpc_mod   = require("acp.rpc")

local sessions = {}  -- [cwd] -> session

local INIT_PARAMS = {
  protocolVersion = 1,
  clientCapabilities = {
    fs       = { readTextFile = true, writeTextFile = false },
    terminal = false,
  },
  clientInfo = { name = "nvim-acp", version = "0.1.0" },
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "acp" })
end

-- callback: fn(err: string|nil, session: table|nil)
-- Provider resolved dynamically via agents.resolve(cwd) — no agent_cfg param.
function M.get_or_create(cwd, callback)
  local s = sessions[cwd]
  if s then
    if s.state == "ready" then
      callback(nil, s)
    elseif s.state == "initializing" then
      table.insert(s.queue, callback)
    else  -- dead
      sessions[cwd] = nil
      M.get_or_create(cwd, callback)
    end
    return
  end

  local stub = { state = "initializing", cwd = cwd, queue = {}, rpc = nil }
  sessions[cwd] = stub

  local function on_exit(code)
    if sessions[cwd] then sessions[cwd].state = "dead" end
    sessions[cwd] = nil
    if code ~= 0 then
      notify("ACP server exited (code " .. code .. ")", vim.log.levels.WARN)
    end
  end

  -- Dynamic provider resolution — picker shown here if needed
  require("acp.agents").resolve(cwd, function(a_err, provider)
    if a_err then
      sessions[cwd] = nil
      callback("provider error: " .. a_err, nil)
      return
    end

    local cmd = require("acp.agents").cmd(provider)
    local th, spawn_err = transport.spawn(cmd, function(line)
      if stub.rpc then stub.rpc:_dispatch(line) end
    end, on_exit)

    if not th then
      sessions[cwd] = nil
      callback("spawn failed: " .. (spawn_err or ""), nil)
      return
    end

    stub.transport = th
    stub.rpc = rpc_mod.new(th)

    stub.rpc:request("initialize", INIT_PARAMS, function(e, _)
      if e then
        sessions[cwd] = nil
        transport.close(th)
        callback("initialize failed: " .. vim.inspect(e), nil)
        return
      end

      stub.rpc:request("session/new", { cwd = cwd, mcpServers = {} }, function(e2, res)
        if e2 or not res then
          sessions[cwd] = nil
          transport.close(th)
          callback("session/new failed: " .. vim.inspect(e2), nil)
          return
        end

        stub.session_id = res.sessionId
        stub.state = "ready"
        callback(nil, stub)

        for _, cb in ipairs(stub.queue) do cb(nil, stub) end
        stub.queue = {}
      end)
    end)
  end)
end

function M.close(cwd)
  local s = sessions[cwd]
  if s and s.transport then
    transport.close(s.transport)
    sessions[cwd] = nil
  end
end

function M.active()
  local out = {}
  for cwd, s in pairs(sessions) do
    table.insert(out, { cwd = cwd, state = s.state, session_id = s.session_id })
  end
  return out
end

return M
