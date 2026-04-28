local Client = require("djinni.acp.client")
local Provider = require("djinni.acp.provider")


local M = {}
M.sessions_by_id = {}

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
  }
end

local function build_mcp_servers(mcp_dict)
  local mcp_servers = {}
  for name, cfg in pairs(mcp_dict or {}) do
    local t = cfg.type
    if t == "http" or t == "sse" then
      if type(cfg.url) == "string" and cfg.url ~= "" then
        local headers = {}
        for k, v in pairs(cfg.headers or {}) do
          headers[#headers + 1] = { name = k, value = v }
        end
        mcp_servers[#mcp_servers + 1] = {
          name    = name,
          type    = t,
          url     = cfg.url,
          headers = headers,
        }
      end
    else
      if type(cfg.command) == "string" and cfg.command ~= "" then
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
    end
  end
  if #mcp_servers == 0 then
    return setmetatable({}, { __jsontype = "array" })
  end
  return mcp_servers
end

local function normalize_cwd(project_root)
  if type(project_root) ~= "string" or project_root == "" then return nil end
  local abs = vim.fn.fnamemodify(project_root, ":p")
  if abs == "" then return nil end
  abs = abs:gsub("/+$", "")
  return abs
end

local function merge_provider_args(base_args, extra_args)
  local merged = {}
  for _, arg in ipairs(base_args or {}) do
    merged[#merged + 1] = arg
  end
  for _, arg in ipairs(extra_args or {}) do
    merged[#merged + 1] = arg
  end
  return merged
end

local function effective_provider_args(provider_name, profile)
  if provider_name == "codex" and profile and profile ~= "" then
    return { "--profile", profile }
  end
  return nil
end

local function request_timeout(provider_name, method)
  if provider_name == "claude-code" and (method == "session/new" or method == "session/load") then
    return 90000
  end
  return 30000
end

local function enrich_error(client, err)
  if not err then return nil end
  local out = vim.deepcopy(err)
  local hint = client and client.get_error_hint and client:get_error_hint() or nil
  if hint and hint ~= "" then
    out.message = ((out.message and out.message ~= "") and (out.message .. " — ") or "") .. hint
  end
  return out
end

local function spawn_client(project_root, provider_name, opts)
  opts = opts or {}
  local provider = Provider.get(provider_name)
  local client = Client.new(
    provider.command,
    merge_provider_args(provider.args, effective_provider_args(provider_name, opts.profile)),
    project_root
  )

  client:on_request("session/request_permission", function(params, respond)
    local handlers = client.event_handlers["permission_request"]
    if handlers then
      for _, h in ipairs(handlers) do
        h(params, respond)
      end
    end
  end)

  return client
end

local function get_client_capabilities(client)
  if not client then return nil end
  return client.server_capabilities or client.agent_capabilities or nil
end

local function get_resume_config(client, provider_name)
  local caps = get_client_capabilities(client)
  local session_caps = caps and caps.sessionCapabilities or nil
  if (caps and caps.loadSession) or (session_caps and session_caps.resume) then
    return { method = "session/load", needs_cwd = true }
  end
  local provider = Provider.get(provider_name)
  return provider.resume or { method = "session/resume" }
end

local function supports_session_list(client)
  local caps = get_client_capabilities(client)
  local session_caps = caps and caps.sessionCapabilities or nil
  return (caps and caps.sessionList) or (session_caps and session_caps.list) or false
end

local function build_resume_params(resume_cfg, project_root, session_id, opts)
  if resume_cfg.needs_cwd then
    return {
      sessionId = session_id,
      cwd = project_root,
      mcpServers = build_mcp_servers(opts.mcpServers),
    }
  end
  return { sessionId = session_id }
end

local register_session

local function apply_session_result(entry, session_id, result, opts)
  entry.model_config_option = result and extract_model_config_option(result.configOptions)
  entry.available_models = result and (result.models or result.availableModels) or entry.available_models
  entry.skills_injected = not (opts and opts.is_new)
  register_session(session_id, entry)

  if opts.model and opts.model ~= "" then
    local model_id = Provider.resolve_model(entry.provider_name, opts.model, M.get_available_models(session_id))
    if model_id then
      M.set_model(nil, session_id, model_id)
    end
  end
end

register_session = function(session_id, entry)
  M.sessions_by_id[session_id] = entry

  entry.client:on("client_reconnected", function()
    vim.schedule(function()
      local cur = M.sessions_by_id[session_id]
      if not cur or cur.client ~= entry.client then return end
      M.sessions_by_id[session_id] = nil
      pcall(function() entry.client:shutdown(true) end)
      if entry.reconnect_cb then
        pcall(entry.reconnect_cb, entry.project_root, entry.provider_name)
      end
    end)
  end)
end

function M.attach_client_session(session_id, client, provider_name, project_root, result, opts)
  if not session_id or session_id == "" or not client then return end
  local entry = {
    client = client,
    provider_name = provider_name,
    project_root = project_root,
  }
  apply_session_result(entry, session_id, result or vim.empty_dict(), opts or {})
end

function M.attach_new_session(session_id, client, provider_name, project_root, result, opts)
  opts = vim.tbl_extend("force", opts or {}, { is_new = true })
  M.attach_client_session(session_id, client, provider_name, project_root, result, opts)
end

function M.detach_client_session(session_id)
  if not session_id or session_id == "" then return end
  M.sessions_by_id[session_id] = nil
end

function M.get_client(session_id)
  local entry = M.sessions_by_id[session_id]
  if entry then return entry.client end
  return nil
end

function M.create_task_session(project_root, callback, opts)
  opts = opts or {}
  local config = get_config()
  local provider_name = opts.provider or config.provider
  local log = require("djinni.log")

  local client = spawn_client(project_root, provider_name, opts)

  log.info("create_task_session: root=" .. project_root .. " provider=" .. tostring(provider_name))
  client:when_ready(function(ready_err)
    if ready_err then
      log.warn("create_task_session: ready error: " .. tostring(ready_err.message or ready_err))
      pcall(function() client:shutdown(true) end)
      if callback then callback(ready_err, nil) end
      return
    end

    local cwd = normalize_cwd(project_root)
    if not cwd then
      pcall(function() client:shutdown(true) end)
      local e = { message = "invalid project root: '" .. tostring(project_root) .. "'" }
      if callback then callback(e, nil) end
      return
    end
    local req = { cwd = cwd, mcpServers = build_mcp_servers(opts.mcpServers) }
    client:request("session/new", req, function(err, result)
      if err then
        err = enrich_error(client, err)
        log.warn("create_task_session: session/new error: " .. vim.inspect(err))
        pcall(function() client:shutdown(true) end)
        if callback then callback(err, nil) end
        return
      end

      local session_id = result and result.sessionId
      log.info("create_task_session: session/new OK sid=" .. tostring(session_id))
      if not session_id then
        pcall(function() client:shutdown(true) end)
        if callback then callback({ message = "no sessionId in response" }, nil) end
        return
      end

      local entry = {
        client = client,
        provider_name = provider_name,
        project_root = project_root,
      }
      local apply_opts = vim.tbl_extend("force", opts, { is_new = true })
      apply_session_result(entry, session_id, result, apply_opts)

      if callback then
        callback(nil, session_id, result)
      end
    end, { timeout = request_timeout(provider_name, "session/new") })
  end)
end

function M.load_task_session(project_root, session_id, callback, opts)
  opts = opts or {}
  local config = get_config()
  local provider_name = opts.provider or config.provider
  local log = require("djinni.log")

  local client = spawn_client(project_root, provider_name, opts)

  client:when_ready(function(ready_err)
    if ready_err then
      pcall(function() client:shutdown(true) end)
      if callback then callback(ready_err, nil) end
      return
    end

    local resume_cfg = get_resume_config(client, provider_name)
    local params = build_resume_params(resume_cfg, project_root, session_id, opts)

    client:request(resume_cfg.method, params, function(err, result)
      if err then
        err = enrich_error(client, err)
        log.warn("load_task_session: resume error sid=" .. tostring(session_id) .. " err=" .. vim.inspect(err))
        pcall(function() client:shutdown(true) end)
        if callback then callback(err, nil) end
        return
      end

      local entry = {
        client = client,
        provider_name = provider_name,
        project_root = project_root,
      }
      apply_session_result(entry, session_id, result, opts)

      if callback then callback(nil, result) end
    end, { timeout = request_timeout(provider_name, resume_cfg.method) })
  end)
end

function M.create_or_resume_session(project_root, session_id, callback, opts)
  opts = opts or {}
  local config = get_config()
  local provider_name = opts.provider or config.provider
  local log = require("djinni.log")

  local client = spawn_client(project_root, provider_name, opts)

  client:when_ready(function(ready_err)
    if ready_err then
      log.warn("create_or_resume: ready error: " .. tostring(ready_err.message or ready_err))
      pcall(function() client:shutdown(true) end)
      if callback then callback(ready_err, nil, nil) end
      return
    end

    local function do_create()
      local cwd = normalize_cwd(project_root)
      if not cwd then
        pcall(function() client:shutdown(true) end)
        local e = { message = "invalid project root: '" .. tostring(project_root) .. "'" }
        if callback then callback(e, nil, nil) end
        return
      end
      local req = { cwd = cwd, mcpServers = build_mcp_servers(opts.mcpServers) }
      client:request("session/new", req, function(err, result)
        if err then
          err = enrich_error(client, err)
          log.warn("create_or_resume: session/new error: " .. vim.inspect(err))
          pcall(function() client:shutdown(true) end)
          if callback then callback(err, nil, nil) end
          return
        end

        local new_sid = result and result.sessionId
        if not new_sid then
          pcall(function() client:shutdown(true) end)
          if callback then callback({ message = "no sessionId in response" }, nil, nil) end
          return
        end

        local entry = {
          client = client,
          provider_name = provider_name,
          project_root = project_root,
        }
        local apply_opts = vim.tbl_extend("force", opts, { is_new = true })
        apply_session_result(entry, new_sid, result, apply_opts)

        log.info("create_or_resume: new session OK sid=" .. new_sid)
        if callback then callback(nil, new_sid, result) end
      end, { timeout = request_timeout(provider_name, "session/new") })
    end

    if session_id and session_id ~= "" then
      local resume_cfg = get_resume_config(client, provider_name)
      local params = build_resume_params(resume_cfg, project_root, session_id, opts)

      log.info("create_or_resume: trying resume sid=" .. session_id)
      client:request(resume_cfg.method, params, function(err, result)
        if err then
          err = enrich_error(client, err)
          log.info("create_or_resume: resume failed sid=" .. session_id .. " — falling back to create")
          do_create()
          return
        end

        local entry = {
          client = client,
          provider_name = provider_name,
          project_root = project_root,
        }
        apply_session_result(entry, session_id, result, opts)

        log.info("create_or_resume: resume OK sid=" .. session_id)
        if callback then callback(nil, session_id, result) end
      end, { timeout = request_timeout(provider_name, resume_cfg.method) })
    else
      do_create()
    end
  end)
end

function M.list_task_sessions(project_root, callback, opts)
  opts = opts or {}
  local config = get_config()
  local provider_name = opts.provider or config.provider
  local log = require("djinni.log")
  local client = spawn_client(project_root, provider_name)

  client:when_ready(function(ready_err)
    if ready_err then
      pcall(function() client:shutdown(true) end)
      if callback then callback(ready_err, nil) end
      return
    end

    if not supports_session_list(client) then
      pcall(function() client:shutdown(true) end)
      if callback then callback({ message = "session/list not supported" }, nil) end
      return
    end

    local all_sessions = {}
    local function fetch_page(cursor)
      local params = {}
      if project_root and project_root ~= "" then
        params.cwd = project_root
      end
      if cursor and cursor ~= "" then
        params.cursor = cursor
      end
      if next(params) == nil then
        params = vim.empty_dict()
      end

      client:request("session/list", params, function(err, result)
        if err then
          err = enrich_error(client, err)
          pcall(function() client:shutdown(true) end)
          log.warn("list_task_sessions: session/list error: " .. vim.inspect(err))
          if callback then callback(err, nil) end
          return
        end

        local sessions = result and (result.sessions or result.items or result) or {}
        for _, item in ipairs(sessions) do
          all_sessions[#all_sessions + 1] = item
        end

        local next_cursor = result and result.nextCursor or nil
        if next_cursor and next_cursor ~= "" then
          fetch_page(next_cursor)
          return
        end

        pcall(function() client:shutdown(true) end)
        if callback then callback(nil, all_sessions) end
      end, { timeout = request_timeout(provider_name, "session/list") })
    end

    fetch_page(nil)
  end)
end

function M.set_model(_, session_id, model_id, _provider_name, cb)
  local log = require("djinni.log")
  local entry = M.sessions_by_id[session_id]
  if not entry then
    if cb then cb({ message = "Session not found" }, nil) end
    return
  end
  local function set_via_unstable()
    entry.client:request("session/set_model",
      { sessionId = session_id, modelId = model_id },
      function(err, result)
        if err then
          log.warn("set_model fallback failed: " .. vim.inspect(err))
        end
        if cb then cb(err, result) end
      end)
  end
  if entry.model_config_option then
    entry.client:request("session/set_config_option", {
      sessionId = session_id,
      optionId  = entry.model_config_option.optionId,
      configId  = entry.model_config_option.optionId,
      value     = model_id,
    }, function(err, result)
      if err then
        log.warn("set_config_option failed (" .. vim.inspect(err) .. "); falling back to session/set_model")
        set_via_unstable()
      else
        entry.model_config_option.currentValue = model_id
        if cb then cb(nil, result) end
      end
    end)
  else
    set_via_unstable()
  end
end

function M.send_message(_, session_id, content, callback, images, _provider_name)
  local log = require("djinni.log")
  local entry = M.sessions_by_id[session_id]
  if not entry then
    log.warn("send_message: no entry for sid=" .. tostring(session_id))
    if callback then callback({ message = "Session not found" }, nil) end
    return
  end
  local client = entry.client

  log.info("send_message: sid=" .. tostring(session_id) .. " ready=" .. tostring(client._ready) .. " alive=" .. tostring(client:is_alive()))

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
    log.info("send_message: sending session/prompt sid=" .. session_id .. " prompt_len=" .. tostring(#content))
    client:request("session/prompt", {
      sessionId = session_id,
      prompt = prompt,
    }, function(err, result)
      if callback then callback(err, result) end
    end)
  end)
end

function M.set_mode(_, session_id, mode_id, provider_name, callback)
  local entry = M.sessions_by_id[session_id]
  if not entry then
    if callback then callback({ message = "Session not found" }, nil) end
    return
  end
  entry.client:when_ready(function(ready_err)
    if ready_err then
      if callback then callback(ready_err, nil) end
      return
    end

    provider_name = provider_name or entry.provider_name
    if provider_name == "claude" or provider_name == "claude-code" then
      entry.client:request("session/prompt", {
        sessionId = session_id,
        prompt = {
          { type = "text", text = "/mode " .. mode_id },
        },
      }, function(err)
        if callback then callback(err, vim.empty_dict()) end
      end)
      return
    end

    entry.client:request("session/set_mode", {
      sessionId = session_id,
      modeId = mode_id,
    }, function(err, result)
      if callback then callback(err, result or vim.empty_dict()) end
    end)
  end)
end

function M.interrupt(_, session_id, _provider_name)
  local entry = M.sessions_by_id[session_id]
  if not entry then return end
  entry.client:notify("session/cancel", { sessionId = session_id })
end

function M.close_task_session(_, session_id, _provider_name)
  if not session_id or session_id == "" then return end
  local entry = M.sessions_by_id[session_id]
  if not entry then return end
  M.sessions_by_id[session_id] = nil
  if entry.client:is_alive() then
    pcall(function() entry.client:notify("session/cancel", { sessionId = session_id }) end)
  end
  pcall(function() entry.client:shutdown(true) end)
end

function M.on_event(_, session_id, event, handler)
  local entry = M.sessions_by_id[session_id]
  if not entry then return end
  entry.client:on(event, handler)
end

function M.subscribe_session(_, session_id, handlers, _provider_name)
  local entry = M.sessions_by_id[session_id]
  if not entry then return end
  entry.client:subscribe(session_id, handlers)
end

function M.unsubscribe_session(_, session_id, _provider_name)
  local entry = M.sessions_by_id[session_id]
  if entry and entry.client then
    entry.client:unsubscribe(session_id)
  end
end

function M.on_reconnect(session_id, cb)
  local entry = M.sessions_by_id[session_id]
  if entry then
    entry.reconnect_cb = cb
  end
end

function M.get_session_entry(session_id)
  return M.sessions_by_id[session_id]
end

function M.get_available_models(session_id)
  local entry = M.sessions_by_id[session_id]
  if not entry then return nil end
  return entry.model_config_option or entry.available_models or nil
end

function M.touch_activity(_, _)
end

function M.shutdown_all()
  local sids = {}
  for sid in pairs(M.sessions_by_id) do
    sids[#sids + 1] = sid
  end
  for _, sid in ipairs(sids) do
    local entry = M.sessions_by_id[sid]
    M.sessions_by_id[sid] = nil
    if entry then
      if entry.client:is_alive() then
        pcall(function() entry.client:notify("session/cancel", { sessionId = sid }) end)
      end
      pcall(function() entry.client:shutdown(true) end)
    end
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    M.shutdown_all()
  end,
})

return M
