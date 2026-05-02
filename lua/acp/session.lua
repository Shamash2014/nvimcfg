local M = {}
local transport = require("acp.transport")
local rpc_mod   = require("acp.rpc")

local sessions = {}  -- [cwd] -> session

local INIT_PARAMS = {
  protocolVersion = 1,
  clientCapabilities = {
    fs               = { readTextFile = false, writeTextFile = false },
    terminal         = true,
    promptCapabilities = { audio = false, embeddedContext = true, image = true },
  },
  clientInfo = { name = "nvim-acp", version = "0.1.0" },
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "acp" })
end

-- callback: fn(err: string|nil, session: table|nil)
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

  local stub = { state = "initializing", cwd = cwd, queue = {}, rpc = nil, config_options = {} }
  sessions[cwd] = stub

  local function on_exit(code)
    if sessions[cwd] then sessions[cwd].state = "dead" end
    sessions[cwd] = nil
    if code ~= 0 then
      notify("ACP server exited (code " .. code .. ")", vim.log.levels.WARN)
    end
  end

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

        stub.session_id        = res.sessionId
        stub.config_options    = res.configOptions or {}
        stub.available_commands = {}
        stub.state             = "ready"

        -- Keep session state fresh from server-pushed notifications
        stub.rpc:subscribe(stub.session_id, function(notif)
          local u = (notif.params or {}).update or {}
          if u.sessionUpdate == "config_option_update" and u.configOptions then
            stub.config_options = u.configOptions
          elseif u.sessionUpdate == "available_commands_update" and u.availableCommands then
            stub.available_commands = u.availableCommands
          end
        end)

        callback(nil, stub)
        for _, cb in ipairs(stub.queue) do cb(nil, stub) end
        stub.queue = {}
      end)
    end)
  end)
end

-- Returns configOptions array for the active session, or {}
function M.get_config_options(cwd)
  local s = sessions[cwd]
  return (s and s.config_options) or {}
end

-- Returns available slash commands for the active session, or {}
function M.get_commands(cwd)
  local s = sessions[cwd]
  return (s and s.available_commands) or {}
end

-- Send session/set_config_option; callback(err, updated_config_options)
function M.set_config_option(cwd, config_id, value, callback)
  local s = sessions[cwd]
  if not s or s.state ~= "ready" then
    if callback then callback("no active session") end
    return
  end
  s.rpc:request("session/set_config_option", {
    sessionId = s.session_id,
    configId  = config_id,
    value     = value,
  }, function(err, res)
    if not err and res and res.configOptions then
      s.config_options = res.configOptions
    end
    if callback then callback(err, s.config_options) end
  end)
end

function M.close(cwd)
  local s = sessions[cwd]
  if not s then return end
  sessions[cwd] = nil
  if s.transport then
    if s.session_id then
      require("acp.mailbox").cancel_for_session(s.session_id)
      s.rpc:notify("session/cancel", { sessionId = s.session_id })
    end
    transport.close(s.transport)
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
