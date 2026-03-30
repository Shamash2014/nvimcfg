local Client = require("djinni.acp.client")
local Provider = require("djinni.acp.provider")


local M = {}
M.sessions = {}
M.idle_guards = {}

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

local function touch_activity(project_root)
  local session = M.sessions[project_root]
  if not session then
    return
  end
  session.last_activity = vim.uv.now()
end

local function schedule_idle_check(project_root)
  local config = get_config()
  local timeout = config.idle_timeout or 1800000

  vim.defer_fn(function()
    local session = M.sessions[project_root]
    if not session or not session.client:is_alive() then
      return
    end

    local elapsed = vim.uv.now() - session.last_activity
    if elapsed >= timeout then
      local guarded = false
      for _, guard in ipairs(M.idle_guards) do
        if guard(project_root) then
          guarded = true
          break
        end
      end
      if guarded then
        touch_activity(project_root)
        schedule_idle_check(project_root)
      else
        M.shutdown_project(project_root)
      end
    else
      schedule_idle_check(project_root)
    end
  end, timeout)
end

function M.get_or_create(project_root)
  local session = M.sessions[project_root]
  if session and session.client:is_alive() then
    touch_activity(project_root)
    return session.client
  end

  local config = get_config()
  local provider = Provider.get(config.provider)

  local client = Client.new(provider.command, provider.args, project_root)
  M.sessions[project_root] = {
    client = client,
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

  schedule_idle_check(project_root)
  return client
end

function M.create_task_session(project_root, callback, opts)
  opts = opts or {}
  local client = M.get_or_create(project_root)
  touch_activity(project_root)

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
        local session = M.sessions[project_root]
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
          local config = get_config()
          local model_id = Provider.resolve_model(config.provider, opts.model, M.get_available_models(project_root))
          if model_id then
            M.set_model(project_root, session_id, model_id)
          end
        end
      end

      if callback then
        callback(nil, session_id, result)
      end
    end, { timeout = 30000 })
  end)
end

function M.set_model(project_root, session_id, model_id)
  local client = M.get_or_create(project_root)
  touch_activity(project_root)
  local session = M.sessions[project_root]
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
  local client = M.get_or_create(project_root)
  touch_activity(project_root)

  client:when_ready(function()
    local config = get_config()
    local provider = Provider.get(config.provider)
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
        local session = M.sessions[project_root]
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

      if not err and opts and opts.model and opts.model ~= "" then
        local config = get_config()
        local model_id = Provider.resolve_model(config.provider, opts.model, M.get_available_models(project_root))
        if model_id then
          M.set_model(project_root, session_id, model_id)
        end
      end

      if callback then
        callback(err, result)
      end
    end, { timeout = 30000 })
  end)
end

function M.send_message(project_root, session_id, content, callback, images)
  local client = M.get_or_create(project_root)
  touch_activity(project_root)

  client:when_ready(function(ready_err)
    if ready_err then
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
    client:request("session/prompt", {
      sessionId = session_id,
      prompt = prompt,
    }, function(err, result)
      touch_activity(project_root)
      if callback then
        callback(err, result)
      end
    end)
  end)
end

function M.set_mode(project_root, session_id, mode_id)
  local client = M.get_or_create(project_root)
  touch_activity(project_root)
  client:notify("session/set_mode", { sessionId = session_id, modeId = mode_id })
end

function M.interrupt(project_root, session_id)
  local client = M.get_or_create(project_root)
  touch_activity(project_root)
  client:notify("session/cancel", { sessionId = session_id })
end

function M.close_task_session(project_root, session_id)
  if not session_id or session_id == "" then return end
  local s = M.sessions[project_root]
  if not s then return end
  if s.client:is_alive() then
    s.client:notify("session/cancel", { sessionId = session_id })
  end
  s.task_sessions[session_id] = nil
end

function M.on_event(project_root, event, handler)
  local client = M.get_or_create(project_root)
  client:on(event, handler)
end

function M.shutdown_project(project_root, force)
  local session = M.sessions[project_root]
  if not session then
    return
  end
  for sid in pairs(session.task_sessions) do
    if session.client:is_alive() then
      session.client:notify("session/cancel", { sessionId = sid })
    end
  end
  session.client:shutdown(force)
  M.sessions[project_root] = nil
end

function M.shutdown_all()
  for root in pairs(M.sessions) do
    M.shutdown_project(root, true)
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    M.shutdown_all()
  end,
})

function M.get_available_models(project_root)
  local s = M.sessions[project_root]
  if not s then return nil end
  return s.model_config_option or s.available_models or nil
end

return M
