local Process = {}
Process.__index = Process

local CLIENT_INFO = {
  name = "ai_repl.nvim",
  title = "AI REPL for Neovim",
  version = "2.0.0"
}

function Process.new(session_id, opts)
  opts = opts or {}
  local self = setmetatable({}, Process)
  self.session_id = session_id
  self.job_id = nil
  self.conn = {
    message_id = 1,
    callbacks = {},
  }
  self.config = {
    cmd = opts.cmd or "claude-code-acp",
    args = opts.args or {},
    env = opts.env or {},
    cwd = opts.cwd,
    debug = opts.debug or false,
    auto_init = opts.auto_init ~= false,
    load_session_id = opts.load_session_id,
  }
  self.state = {
    initialized = false,
    session_ready = false,
    mode = "plan",
    modes = {},
    busy = false,
    agent_info = nil,
    agent_capabilities = {},
    client_capabilities = {},
    supports_load_session = false,
    reconnect_count = 0,
  }
  self.data = {
    buf = nil,
    cwd = opts.cwd,
    env = opts.env or {},
    messages = {},
    context_files = {},
    terminals = {},
    slash_commands = {},
    prompt_queue = {},
  }
  self.ui = {
    streaming_response = "",
    streaming_start_line = nil,
    active_tools = {},
    pending_tool_calls = {},
    current_plan = {},
  }
  return self
end

function Process:start()
  local env = vim.tbl_extend("force", vim.fn.environ(), self.config.env)
  local captured_self = self

  self.job_id = vim.fn.jobstart({ self.config.cmd, unpack(self.config.args) }, {
    cwd = self.config.cwd,
    env = env,
    on_stdout = function(_, data)
      for _, line in ipairs(data or {}) do
        if line and line ~= "" then
          if captured_self.config.debug and captured_self._on_debug then
            captured_self:_on_debug("stdout: " .. line:sub(1, 80))
          end
          captured_self:_handle_message(line)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line and line ~= "" and not line:match("^%s*$") then
          if captured_self.config.debug and captured_self._on_debug then
            captured_self:_on_debug("stderr: " .. line:sub(1, 100))
          end
        end
      end
    end,
    on_exit = function(_, code)
      captured_self:_on_exit(code)
    end,
    stdin = "pipe",
  })

  if self.job_id <= 0 then
    self.job_id = nil
    return false
  end

  if self.config.auto_init then
    vim.defer_fn(function()
      self:_acp_initialize()
    end, 50)
  end

  return true
end

function Process:send(method, params, callback)
  if not self.job_id then return nil end

  local id = self.conn.message_id
  self.conn.message_id = self.conn.message_id + 1

  local msg = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  if callback then
    self.conn.callbacks[id] = callback
  end

  vim.fn.chansend(self.job_id, vim.json.encode(msg) .. "\n")
  return id
end

function Process:notify(method, params)
  if not self.job_id then return end

  local msg = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }

  vim.fn.chansend(self.job_id, vim.json.encode(msg) .. "\n")
end

function Process:kill()
  if self.job_id then
    pcall(vim.fn.jobstop, self.job_id)
    self.job_id = nil
  end
  self.state.initialized = false
  self.state.session_ready = false
end

function Process:is_alive()
  return self.job_id ~= nil
end

function Process:is_ready()
  return self.job_id ~= nil and self.state.session_ready
end

function Process:_handle_message(line)
  local ok, msg = pcall(vim.json.decode, line)
  if not ok or not msg then
    if self._on_debug and self.config.debug then
      self:_on_debug("Failed to parse: " .. line:sub(1, 100))
    end
    return
  end

  if msg.method then
    if self._on_debug and self.config.debug then
      self:_on_debug("Received method: " .. msg.method)
    end
    if self._on_method then
      self:_on_method(msg.method, msg.params, msg.id)
    end
  elseif msg.id then
    local callback = self.conn.callbacks[msg.id]
    if callback then
      local cb_ok, err = pcall(callback, msg.result, msg.error)
      if not cb_ok and self._on_debug then
        self:_on_debug("Callback error: " .. tostring(err))
      end
    end
    self.conn.callbacks[msg.id] = nil
  end
end

function Process:_on_exit(code)
  local was_alive = self.job_id ~= nil
  self.job_id = nil
  self.state.initialized = false
  self.state.session_ready = false

  if self._on_process_exit then
    self:_on_process_exit(code, was_alive)
  end
end

function Process:set_handlers(handlers)
  self._on_method = handlers.on_method
  self._on_debug = handlers.on_debug
  self._on_process_exit = handlers.on_exit
  self._on_ready = handlers.on_ready
  self._on_status = handlers.on_status
end

function Process:_acp_initialize()
  if not self.job_id then return end

  self.state.client_capabilities = {
    prompt = { text = true, embeddedContext = true, image = true, audio = false }
  }

  if self._on_status then
    self:_on_status("initializing")
  end

  self:send("initialize", {
    protocolVersion = 1,
    clientInfo = CLIENT_INFO,
    clientCapabilities = self.state.client_capabilities
  }, function(result, err)
    if err then
      if self._on_status then
        self:_on_status("init_failed", err)
      end
      return
    end

    self.state.agent_info = result.agentInfo
    self.state.agent_capabilities = result.agentCapabilities or {}
    self.state.initialized = true

    if self.state.agent_capabilities.loadSession then
      self.state.supports_load_session = true
    end

    if self._on_status then
      self:_on_status("initialized", result)
    end

    self:_acp_create_or_load_session()
  end)
end

function Process:_acp_create_or_load_session()
  if not self.state.initialized then return end

  local cwd = self.data.cwd or vim.fn.getcwd()

  if self.config.load_session_id and self.state.supports_load_session then
    if self._on_status then
      self:_on_status("loading_session")
    end

    self:send("session/load", {
      sessionId = self.config.load_session_id,
      cwd = cwd,
      mcpServers = {}
    }, function(result, err)
      if err then
        if self._on_status then
          self:_on_status("session_load_failed", err)
        end
        self:_acp_create_new_session(cwd)
        return
      end

      self:_handle_session_result(result)

      if self._on_status then
        self:_on_status("session_loaded", result)
      end
    end)
  else
    self:_acp_create_new_session(cwd)
  end
end

function Process:_acp_create_new_session(cwd)
  if self._on_status then
    self:_on_status("creating_session")
  end

  self:send("session/new", {
    cwd = cwd,
    mcpServers = {}
  }, function(result, err)
    if err then
      if self._on_status then
        self:_on_status("session_failed", err)
      end
      return
    end

    self:_handle_session_result(result)

    if self._on_status then
      self:_on_status("session_created", result)
    end
  end)
end

function Process:_handle_session_result(result)
  if result.sessionId then
    local old_id = self.session_id
    self.session_id = result.sessionId

    if self._on_session_id_changed and old_id ~= result.sessionId then
      self:_on_session_id_changed(old_id, result.sessionId)
    end
  end

  if result.modes then
    self.state.modes = result.modes.availableModes or {}
    self.state.mode = result.modes.currentModeId or self.state.mode
  end

  self.state.session_ready = true

  if self._on_ready then
    self:_on_ready()
  end
end

function Process:send_prompt(prompt)
  if not self:is_ready() then
    if self.config.debug and self._on_debug then
      self:_on_debug("send_prompt: not ready")
    end
    return nil
  end
  if self.state.busy then
    table.insert(self.data.prompt_queue, prompt)
    if self.config.debug and self._on_debug then
      self:_on_debug("send_prompt: busy, queued")
    end
    return nil
  end

  self.state.busy = true
  self.ui.streaming_response = ""
  self.ui.streaming_start_line = nil
  self.ui.pending_tool_calls = {}

  if self.config.debug and self._on_debug then
    self:_on_debug("send_prompt: sending to session " .. self.session_id)
  end

  return self:send("session/prompt", {
    sessionId = self.session_id,
    prompt = prompt
  }, function(result, err)
    if err then
      if self._on_debug then
        self:_on_debug("Prompt error: " .. vim.inspect(err))
      end
      self.state.busy = false
      vim.schedule(function()
        self:process_queued_prompts()
      end)
    elseif result and result.stopReason then
      vim.schedule(function()
        if self.state.busy then
          self.state.busy = false
          self:process_queued_prompts()
        end
      end)
    end
  end)
end

function Process:cancel()
  if not self:is_ready() then return end
  self:notify("session/cancel", { sessionId = self.session_id })
  self.state.busy = false
  self.data.prompt_queue = {}
end

function Process:set_mode(mode_id)
  if not self:is_ready() then return end
  self:notify("session/set_mode", {
    sessionId = self.session_id,
    modeId = mode_id
  })
  self.state.mode = mode_id
end

function Process:process_queued_prompts()
  if self.state.busy then return end
  if #self.data.prompt_queue > 0 then
    local next_prompt = table.remove(self.data.prompt_queue, 1)
    self:send_prompt(next_prompt)
  end
end

function Process:restart()
  self:kill()
  vim.defer_fn(function()
    self:start()
  end, 100)
end

function Process:get_agent_name()
  if self.state.agent_info and self.state.agent_info.name then
    local name = self.state.agent_info.name:gsub("^@[^/]+/", "")
    local friendly = { ["claude-code-acp"] = "Claude Code" }
    return friendly[name] or name
  end
  return "Agent"
end

return Process
