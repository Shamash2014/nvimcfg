local M = {}
local transport = require("acp.transport")
local rpc_mod   = require("acp.rpc")

local sessions = {}  -- [cwd] -> session

local PROTOCOL_VERSION = 1

local INIT_PARAMS = {
  protocolVersion = PROTOCOL_VERSION,
  clientCapabilities = {
    fs       = { readTextFile = false, writeTextFile = false },
    terminal = false,
  },
  clientInfo = { name = "nvim-acp", version = "0.1.0" },
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "acp" })
end

-- callback: fn(err: string|nil, session: table|nil)
function M.get_or_create(cwd_or_opts, callback)
  local cwd = type(cwd_or_opts) == "string" and cwd_or_opts or cwd_or_opts.cwd
  local key = type(cwd_or_opts) == "string" and cwd_or_opts or cwd_or_opts.key or cwd

  local s = sessions[key]
  if s then
    if s.state == "ready" then
      callback(nil, s)
    elseif s.state == "initializing" then
      table.insert(s.queue, callback)
    else  -- dead
      sessions[key] = nil
      M.get_or_create(cwd_or_opts, callback)
    end
    return
  end

  local stub = { state = "initializing", cwd = cwd, key = key, queue = {}, rpc = nil, config_options = {} }
  sessions[key] = stub

  function stub.set_state(new_state)
    stub.state = new_state
    if new_state == "dead" and stub.rpc then
      stub.rpc:drain_callbacks("session died")
    end
  end

  local function on_exit(code)
    if sessions[key] and sessions[key].state ~= "dead" then
      stub.set_state("dead")
    end
    sessions[key] = nil
    if code ~= 0 then
      notify("ACP server exited (code " .. code .. ")", vim.log.levels.WARN)
    end
  end

  require("acp.agents").resolve({ cwd = cwd, key = key }, function(a_err, provider)
    if a_err then
      sessions[key] = nil
      callback("provider error: " .. a_err, nil)
      return
    end

    stub.provider = provider.name
    local cmd = require("acp.agents").cmd(provider)
    local th, spawn_err = transport.spawn(cmd, function(line)
      if stub.rpc then stub.rpc:_dispatch(line) end
    end, on_exit, cwd)

    if not th then
      sessions[key] = nil
      callback("spawn failed: " .. (spawn_err or ""), nil)
      return
    end

    stub.transport = th
    stub.rpc = rpc_mod.new(th)

    stub.set_state("initializing")

    stub.rpc:request("initialize", INIT_PARAMS, function(e, init_res)
      if e then
        stub.set_state("dead")
        transport.close(th)
        callback("initialize failed: " .. vim.inspect(e), nil)
        return
      end

      init_res = init_res or {}
      stub.protocol_version  = init_res.protocolVersion
      stub.agent_capabilities = init_res.agentCapabilities or {}
      stub.agent_info         = init_res.agentInfo
      stub.auth_methods       = init_res.authMethods or {}

      if stub.protocol_version and stub.protocol_version ~= PROTOCOL_VERSION then
        notify("ACP: agent protocolVersion " .. tostring(stub.protocol_version)
               .. " differs from client " .. PROTOCOL_VERSION, vim.log.levels.WARN)
      end

      stub.rpc:request("session/new", { cwd = cwd, mcpServers = {} }, function(e2, res)
        if e2 or not res then
          stub.set_state("dead")
          transport.close(th)
          callback("session/new failed: " .. vim.inspect(e2), nil)
          return
        end

        stub.session_id         = res.sessionId
        stub.config_options     = res.configOptions or {}
        -- Normalize modes: opencode sends { currentModeId, availableModes }
        local raw_modes = res.modes or {}
        if raw_modes.availableModes then
          stub.available_modes = raw_modes.availableModes
          stub.current_mode    = raw_modes.currentModeId or res.currentModeId
        else
          stub.available_modes = raw_modes
          stub.current_mode    = res.currentModeId
        end
        stub.available_commands = {}
        stub.set_state("ready")

        local function finalize()
          stub.rpc:subscribe(stub.session_id, function(notif)
            local u = (notif.params or {}).update or {}
            if u.sessionUpdate == "config_option_update" and u.configOptions then
              stub.config_options = u.configOptions
            elseif u.sessionUpdate == "available_commands_update" and u.availableCommands then
              stub.available_commands = u.availableCommands
            elseif u.sessionUpdate == "modes_update" and u.modes then
              stub.available_modes = u.modes
            elseif u.sessionUpdate == "current_mode_update" and u.currentModeId then
              stub.current_mode = u.currentModeId
            end
          end)
          callback(nil, stub)
          for _, cb in ipairs(stub.queue) do cb(nil, stub) end
          stub.queue = {}
        end

        local saved_model = require("acp.agents").get_model_for_key(key)
                         or require("acp.agents").get_model_for_cwd(cwd)
        local has_model_opt = false
        for _, opt in ipairs(stub.config_options) do
          if opt.id == "model" then has_model_opt = true; break end
        end
        if saved_model and has_model_opt then
          stub.rpc:request("session/set_config_option", {
            sessionId = stub.session_id,
            configId  = "model",
            value     = saved_model,
          }, function(set_err, res)
            if not set_err then
              if res and type(res) == "table" and res.configOptions then
                stub.config_options = res.configOptions
              else
                for _, opt in ipairs(stub.config_options) do
                  if opt.id == "model" then opt.currentValue = saved_model; break end
                end
              end
              local label = saved_model
              for _, opt in ipairs(stub.config_options) do
                if opt.id == "model" then
                  for _, o in ipairs(opt.options or {}) do
                    if o.value == saved_model then label = o.name or saved_model; break end
                  end
                  break
                end
              end
              notify("Model set: " .. label, vim.log.levels.INFO)
            end
            finalize()
          end)
        else
          finalize()
        end
      end)
    end)
  end)
end

-- Returns configOptions array for the active session, or {}
function M.get(key)
  local s = sessions[key]
  return (s and s.state == "ready") and s or nil
end

function M.get_config_options(key)
  local s = sessions[key]
  return (s and s.config_options) or {}
end

-- Returns available slash commands for the active session, or {}
function M.get_commands(key)
  local s = sessions[key]
  return (s and s.available_commands) or {}
end

-- Send session/set_config_option; callback(err, updated_config_options)
function M.set_config_option(key, config_id, value, callback)
  local s = sessions[key]
  if not s or s.state ~= "ready" then
    if callback then callback("no active session") end
    return
  end
  s.rpc:request("session/set_config_option", {
    sessionId = s.session_id,
    configId  = config_id,
    value     = value,
  }, function(err, res)
    if not err then
      if res and res.configOptions then
        s.config_options = res.configOptions
      else
        for _, opt in ipairs(s.config_options) do
          if opt.id == config_id then opt.currentValue = value; break end
        end
      end
    end
    if callback then callback(err, s.config_options) end
  end)
end

function M.find_ready_for_cwd(cwd)
  local s = sessions[cwd]
  if s and s.state == "ready" then return s end
  for _, sess in pairs(sessions) do
    if sess.cwd == cwd and sess.state == "ready" then return sess end
  end
  return nil
end

function M.get_config_options_for_cwd(cwd)
  local s = M.find_ready_for_cwd(cwd)
  return (s and s.config_options) or {}
end

function M.set_config_option_for_cwd(cwd, config_id, value, callback)
  local targets = {}
  for _, s in pairs(sessions) do
    if s.cwd == cwd and s.state == "ready" then table.insert(targets, s) end
  end
  if #targets == 0 then
    if callback then callback("no active session") end
    return
  end
  local pending, err_seen = #targets, nil
  local last_opts = {}
  for _, s in ipairs(targets) do
    s.rpc:request("session/set_config_option", {
      sessionId = s.session_id,
      configId  = config_id,
      value     = value,
    }, function(err, res)
      if not err then
        if res and res.configOptions then
          s.config_options = res.configOptions
        else
          for _, opt in ipairs(s.config_options) do
            if opt.id == config_id then opt.currentValue = value; break end
          end
        end
        last_opts = s.config_options
      else
        err_seen = err
      end
      pending = pending - 1
      if pending == 0 and callback then callback(err_seen, last_opts) end
    end)
  end
end

function M.close(key)
  local s = sessions[key]
  if not s then return end
  sessions[key] = nil
  if s.transport then
    if s.session_id then
      require("acp.mailbox").cancel_for_session(s.session_id)
      s.rpc:notify("session/cancel", { sessionId = s.session_id })
    end
    transport.close(s.transport)
  end
end

function M.close_all()
  for key, _ in pairs(sessions) do
    M.close(key)
  end
end

function M.close_for_cwd(cwd)
  for key, s in pairs(sessions) do
    if s.cwd == cwd then M.close(key) end
  end
end

function M.cancel_turn(key)
  local s = sessions[key]
  if not s or not s.session_id then return end
  pcall(function() require("acp.mailbox").cancel_for_session(s.session_id) end)
  s.rpc:notify("session/cancel", { sessionId = s.session_id })
end

function M.cancel_for_cwd(cwd)
  for key, s in pairs(sessions) do
    if s.cwd == cwd then M.cancel_turn(key) end
  end
end

function M.set_mode(key, mode_id)
  local s = sessions[key]
  if not s or s.state ~= "ready" then return end
  s.rpc:notify("session/set_mode", { sessionId = s.session_id, modeId = mode_id })
  s.current_mode = mode_id
end

function M.active()
  local out = {}
  for key, s in pairs(sessions) do
    table.insert(out, {
      key = key,
      cwd = s.cwd,
      state = s.state,
      session_id = s.session_id,
      modes = s.available_modes,
      current_mode = s.current_mode
    })
  end
  return out
end

return M
