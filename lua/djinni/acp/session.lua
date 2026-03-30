local Client = require("djinni.acp.client")
local Provider = require("djinni.acp.provider")


local M = {}
M.sessions = {}
M.idle_guards = {}
M.reconnect_callbacks = {}

local function extract_model_config_option(config_options)
  if not config_options then return nil end
  for _, opt in ipairs(config_options) do
    if opt.category == "model" and opt.type == "select" then
      return {
        optionId = opt.id,
        options = opt.options or {},
        currentValue = opt.currentValue,
      }
    end
  end
  return nil
end

local function get_config()
  local ok, djinni = pcall(require, "djinni")
  if ok and djinni.config and djinni.config.acp then
    return djinni.config.acp
  end
  return {
    provider = "claude-code",
    idle_timeout = 300000,
  }
end

local function touch_activity(key)
  local session = M.sessions[key]
  if not session then return end
  session.last_activity = vim.uv.now()
end

function M.touch_activity(project_root, provider_name)
  touch_activity(M.session_key(project_root, provider_name))
end

local function schedule_idle_check(key)
  local config = get_config()
  local timeout = config.idle_timeout or 1800000

  vim.defer_fn(function()
    local session = M.sessions[key]
    if not session or not session.client:is_alive() then
      return
    end

    local elapsed = vim.uv.now() - session.last_activity
    if elapsed >= timeout then
      local project_root = key:match("^(.+):")
      local guarded = false
      for _, guard in ipairs(M.idle_guards) do
        if guard(project_root) then
          guarded = true
          break
        end
      end
      if guarded then
        touch_activity(key)
        schedule_idle_check(key)
      else
        M.shutdown_key(key)
      end
    else
      schedule_idle_check(key)
    end
  end, timeout)
end

function M.session_key(project_root, provider_name)
  if not provider_name or provider_name == "" then
    provider_name = get_config().provider
  end
  return project_root .. ":" .. provider_name
end

function M.get_or_create(project_root, provider_name)
  local config = get_config()
  provider_name = provider_name or config.provider
  local key = M.session_key(project_root, provider_name)

  local session = M.sessions[key]
  if session and session.client:is_alive() then
    touch_activity(key)
    return session.client, provider_name
  end

  if session then
    session.task_sessions = {}
  end

  local provider = Provider.get(provider_name)

  local client = Client.new(provider.command, provider.args, project_root)
  M.sessions[key] = {
    client = client,
    provider_name = provider_name,
    task_sessions = {},
    last_activity = vim.uv.now(),
  }

  client:on_request("session/request_permission", function(params, respond)
    local handlers = client.event_handlers["permission_request"]
    if handlers then
      for _, h in ipairs(handlers) do
        h(params, respond)
      end
    end
  end)

  client:on("client_reconnected", function()
    local s = M.sessions[key]
    if s then
      s.task_sessions = {}
    end
    for _, cb in ipairs(M.reconnect_callbacks) do
      pcall(cb, project_root, provider_name)
    end
  end)

  schedule_idle_check(key)
  return client, provider_name
end

function M.create_task_session(project_root, callback, opts)
  opts = opts or {}
  local provider_name = opts.provider
  local client = M.get_or_create(project_root, provider_name)
  local key = M.session_key(project_root, provider_name)

  client:when_ready(function(ready_err)
    if ready_err then
      if callback then callback(ready_err, nil) end
      return
    end
    local mcp_dict = opts.mcpServers or {}
    local mcp_servers = {}
    for name, cfg in pairs(mcp_dict) do
      local env = {}
      for k, v in pairs(cfg.env or {}) do
        env[#env + 1] = { name = k, value = v }
      end
      mcp_servers[#mcp_servers + 1] = {
        name    = name,
        command = cfg.command,
        args    = cfg.args or {},
        env     = env,
      }
    end
    local req = { cwd = project_root, mcpServers = mcp_servers }
    client:request("session/new", req, function(err, result)
      if err then
        if callback then
          callback(err, nil)
        end
        return
      end

      local session_id = result and result.sessionId
      if session_id then
        local session = M.sessions[key]
        if session then
          session.task_sessions[session_id] = true
          local model_opt = result and extract_model_config_option(result.configOptions)
          if model_opt then
            session.model_config_option = model_opt
          elseif result and (result.models or result.availableModels) then
            session.available_models = result.models or result.availableModels
          end
        end
        if opts.model and opts.model ~= "" then
          local model_id = Provider.resolve_model(provider_name or get_config().provider, opts.model, M.get_available_models(project_root, provider_name))
          if model_id then
            M.set_model(project_root, session_id, model_id, provider_name)
          end
        end
      end

      if callback then
        callback(nil, session_id, result)
      end
    end, { timeout = 30000 })
  end)
end

function M.set_model(project_root, session_id, model_id, provider_name)
  local client = M.get_or_create(project_root, provider_name)
  local key = M.session_key(project_root, provider_name)
  touch_activity(key)
  local session = M.sessions[key]
  if session and session.model_config_option then
    client:request("session/set_config_option", {
      sessionId = session_id,
      optionId = session.model_config_option.optionId,
      value = model_id,
    }, function() end)
  else
    client:request("session/set_model", { sessionId = session_id, modelId = model_id }, function() end)
  end
end

function M.load_task_session(project_root, session_id, callback, opts)
  opts = opts or {}
  local provider_name = opts.provider
  local client = M.get_or_create(project_root, provider_name)
  local key = M.session_key(project_root, provider_name)
  touch_activity(key)

  client:when_ready(function()
    local provider = Provider.get(provider_name or get_config().provider)
    local resume_cfg = provider.resume or { method = "session/resume" }

    local params
    if resume_cfg.needs_cwd then
      local mcp_dict = (opts and opts.mcpServers) or {}
      local mcp_servers = {}
      for name, cfg in pairs(mcp_dict) do
        local env = {}
        for k, v in pairs(cfg.env or {}) do
          env[#env + 1] = { name = k, value = v }
        end
        mcp_servers[#mcp_servers + 1] = {
          name    = name,
          command = cfg.command,
          args    = cfg.args or {},
          env     = env,
        }
      end
      params = { sessionId = session_id, cwd = project_root, mcpServers = mcp_servers }
    else
      params = { sessionId = session_id }
    end

    client:request(resume_cfg.method, params, function(err, result)
      if not err then
        local session = M.sessions[key]
        if session then
          session.task_sessions[session_id] = true
          local model_opt = result and extract_model_config_option(result.configOptions)
          if model_opt then
            session.model_config_option = model_opt
          elseif result and (result.models or result.availableModels) then
            session.available_models = result.models or result.availableModels
          end
        end
      end

      if not err and opts.model and opts.model ~= "" then
        local model_id = Provider.resolve_model(provider_name or get_config().provider, opts.model, M.get_available_models(project_root, provider_name))
        if model_id then
          M.set_model(project_root, session_id, model_id, provider_name)
        end
      end

      if callback then
        callback(err, result)
      end
    end, { timeout = 30000 })
  end)
end

function M.send_message(project_root, session_id, content, callback, images, provider_name)
  local log = require("djinni.nowork.log")
  local client = M.get_or_create(project_root, provider_name)
  local key = M.session_key(project_root, provider_name)
  touch_activity(key)

  log.info("send_message: sid=" .. tostring(session_id) .. " ready=" .. tostring(client._ready) .. " alive=" .. tostring(client:is_alive()) .. " sub=" .. tostring(client.subscribers[session_id] ~= nil))

  client:when_ready(function(ready_err)
    if ready_err then
      log.warn("send_message: when_ready error: " .. tostring(ready_err.message or ready_err))
      if callback then callback(ready_err, nil) end
      return
    end
    local prompt = { { type = "text", text = content } }
    if images then
      for _, img in ipairs(images) do
        prompt[#prompt + 1] = {
          type = "image",
          source = { type = "base64", media_type = img.media_type, data = img.data },
        }
      end
    end
    log.info("send_message: sending session/prompt sid=" .. session_id .. " prompt_len=" .. tostring(#content))
    client:request("session/prompt", {
      sessionId = session_id,
      prompt = prompt,
    }, function(err, result)
      log.info("send_message: callback err=" .. tostring(err and (err.message or vim.inspect(err))) .. " result=" .. tostring(result ~= nil))
      touch_activity(key)
      if callback then
        callback(err, result)
      end
    end)
  end)
end

function M.set_mode(project_root, session_id, mode_id, provider_name)
  local client = M.get_or_create(project_root, provider_name)
  touch_activity(M.session_key(project_root, provider_name))
  client:request("session/set_mode", {
    sessionId = session_id,
    modeId = mode_id,
  }, function() end)
end

function M.interrupt(project_root, session_id, provider_name)
  local client = M.get_or_create(project_root, provider_name)
  touch_activity(M.session_key(project_root, provider_name))
  client:notify("session/cancel", { sessionId = session_id })
end

function M.close_task_session(project_root, session_id, provider_name)
  if not session_id or session_id == "" then return end
  local key = M.session_key(project_root, provider_name)
  local s = M.sessions[key]
  if not s then return end
  if s.client:is_alive() then
    s.client:notify("session/cancel", { sessionId = session_id })
  end
  s.task_sessions[session_id] = nil
end

function M.on_event(project_root, event, handler, provider_name)
  local client = M.get_or_create(project_root, provider_name)
  client:on(event, handler)
end

function M.subscribe_session(project_root, session_id, handlers, provider_name)
  local client = M.get_or_create(project_root, provider_name)
  client:subscribe(session_id, handlers)
end

function M.unsubscribe_session(project_root, session_id, provider_name)
  local key = M.session_key(project_root, provider_name)
  local s = M.sessions[key]
  if s and s.client then
    s.client:unsubscribe(session_id)
  end
end

function M.shutdown_key(key)
  local session = M.sessions[key]
  if not session then return end
  for sid in pairs(session.task_sessions) do
    if session.client:is_alive() then
      session.client:notify("session/cancel", { sessionId = sid })
    end
  end
  session.client:shutdown(true)
  M.sessions[key] = nil
end

function M.shutdown_project(project_root, force, provider_name)
  local key = M.session_key(project_root, provider_name)
  local session = M.sessions[key]
  if not session then
    return
  end
  for sid in pairs(session.task_sessions) do
    if session.client:is_alive() then
      session.client:notify("session/cancel", { sessionId = sid })
    end
  end
  session.client:shutdown(force)
  M.sessions[key] = nil
end

function M.shutdown_all()
  for key in pairs(M.sessions) do
    M.shutdown_key(key)
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    M.shutdown_all()
  end,
})

function M.get_available_models(project_root, provider_name)
  local key = M.session_key(project_root, provider_name)
  local s = M.sessions[key]
  if not s then return nil end
  return s.model_config_option or s.available_models or nil
end

return M
