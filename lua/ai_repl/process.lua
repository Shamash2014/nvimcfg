local Process = {}
Process.__index = Process

local CLIENT_INFO = {
  name = "ai_repl.nvim",
  title = "AI REPL for Neovim",
  version = "2.0.0"
}

local EMPTY_ARRAY = setmetatable({}, { __is_list = true })

function Process.new(session_id, opts)
  opts = opts or {}
  local self = setmetatable({}, Process)
  self.session_id = session_id
  self.job_id = nil
  self.conn = {
    message_id = 1,
    callbacks = {},
    callback_timeouts = {},
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
    provider = opts.provider or "claude",
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
    permission_queue = {},
    permission_active = false,
  }
  return self
end

function Process:start()
  local mise = require("core.mise")
  local mise_env = mise.get_env(self.config.cwd)
  local env = vim.tbl_extend("force", vim.fn.environ(), mise_env, self.config.env)
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
    -- Track callback creation time for timeout monitoring
    self.conn.callback_timeouts[id] = {
      created_at = os.time(),
      method = method
    }
  end

  -- Add error handling for chansend
  local ok, err = pcall(function()
    vim.fn.chansend(self.job_id, vim.json.encode(msg) .. "\n")
  end)

  if not ok then
    if self._on_debug and self.config.debug then
      self:_on_debug("chansend failed: " .. tostring(err))
    end
    -- Channel might be closed, mark job as invalid
    if err:match("channel") or err:match("job") then
      self:_on_exit(1)
    end
    return nil
  end

  return id
end

function Process:notify(method, params)
  if not self.job_id then return end

  local msg = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }

  -- Add error handling for chansend
  local ok, err = pcall(function()
    vim.fn.chansend(self.job_id, vim.json.encode(msg) .. "\n")
  end)

  if not ok then
    if self._on_debug and self.config.debug then
      self:_on_debug("notify chansend failed: " .. tostring(err))
    end
    -- Channel might be closed, mark job as invalid
    if err:match("channel") or err:match("job") then
      self:_on_exit(1)
    end
  end
end

function Process:kill()
  if self.job_id then
    local pid = vim.fn.jobpid(self.job_id)
    if pid and pid > 0 then
      pcall(vim.uv.kill, -pid, "sigterm")
    end
    pcall(vim.fn.jobstop, self.job_id)
    self.job_id = nil
  end
  self.state.initialized = false
  self.state.session_ready = false
  self.state.busy = false
  self.state.mode = "plan"
  self.data.prompt_queue = {}
  self.ui.streaming_response = ""
  self.ui.streaming_start_line = nil
  self.ui.pending_tool_calls = {}
  self.ui.active_tools = {}
  self.ui.current_plan = {}
end

function Process:cleanup()
  -- Full cleanup before process is destroyed
  self:kill()

  -- Clear all callbacks
  self.conn.callbacks = {}
  self.conn.callback_timeouts = {}

  -- Clear all data
  self.data.messages = {}
  self.data.context_files = {}
  self.data.terminals = {}
  self.data.slash_commands = {}
  self.data.prompt_queue = {}
end

function Process:is_alive()
  if not self.job_id then return false end

  -- Verify the job is actually still running
  -- Use jobwait() with timeout=0 to check without blocking
  local pid = vim.fn.jobpid(self.job_id)
  if pid and pid > 0 then
    -- Job exists, verify it's running
    local info = vim.fn.jobwait({self.job_id}, 0)
    -- jobwait returns: -1 if still running, -2 if invalid, 0+ if exited
    if info and info[1] == -1 then
      return true
    end
    -- Job has exited or is invalid
    if info and (info[1] >= 0 or info[1] == -2) then
      self.job_id = nil
      return false
    end
  end

  -- Fallback: if we can't check, assume alive if job_id is set
  return true
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
      -- Log ACP protocol errors if present
      if msg.error and self._on_debug then
        self:_on_debug("ACP error response: " .. vim.inspect(msg.error))
      end
    end
    -- Clean up both callback and timeout tracking
    self.conn.callbacks[msg.id] = nil
    self.conn.callback_timeouts[msg.id] = nil
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

function Process:_notify_status(status, data)
  if self._on_status then
    self:_on_status(status, data)
  end
end

function Process:_extract_prompt_text(prompt)
  if type(prompt) == "string" then
    return prompt
  elseif type(prompt) == "table" then
    local parts = {}
    for _, block in ipairs(prompt) do
      if block.type == "text" then
        parts[#parts + 1] = block.text or ""
      end
    end
    return table.concat(parts)
  end
  return ""
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

  self:_notify_status("initializing")

  self:send("initialize", {
    protocolVersion = 1,
    clientInfo = CLIENT_INFO,
    clientCapabilities = self.state.client_capabilities
  }, function(result, err)
    if err then
      self:_notify_status("init_failed", err)
      return
    end

    self.state.agent_info = result.agentInfo
    self.state.agent_capabilities = result.agentCapabilities or {}
    self.state.initialized = true

    if self.state.agent_capabilities.loadSession then
      self.state.supports_load_session = true
    end

    self.state.auth_methods = result.authMethods or {}
    self:_notify_status("auth_methods_available", self.state.auth_methods)

    self:_notify_status("initialized", result)

    self:_acp_create_or_load_session()
  end)
end

function Process:_acp_authenticate(method_id, on_success)
  self:_notify_status("authenticating", { methodId = method_id })

  local auth_done = false
  local msg_id = self:send("authenticate", {
    methodId = method_id
  }, function(_, err)
    auth_done = true
    if err then
      self:_notify_status("auth_failed", err)
      return
    end
    self:_notify_status("authenticated")
    if on_success then
      on_success()
    else
      self:_acp_create_or_load_session()
    end
  end)

  vim.defer_fn(function()
    if not auth_done and msg_id then
      self.conn.callbacks[msg_id] = nil
      self:_notify_status("auth_timeout", {
        message = "Auth timed out, retrying session...",
        hint = self.config.cmd .. " auth login",
      })
      if on_success then
        on_success()
      else
        self:_acp_create_or_load_session()
      end
    end
  end, 30000)
end

function Process:_acp_create_or_load_session()
  if not self.state.initialized then return end

  local cwd = self.data.cwd or vim.fn.getcwd()

  if self.config.load_session_id and self.state.supports_load_session then
    self:_notify_status("loading_session")

    self:send("session/load", {
      sessionId = self.config.load_session_id,
      cwd = cwd,
      mcpServers = EMPTY_ARRAY
    }, function(result, err)
      if err then
        self:_notify_status("session_load_failed", err)
        self:_acp_create_new_session(cwd)
        return
      end

      self:_handle_session_result(result)
      self:_notify_status("session_loaded", result)
    end)
  else
    self:_acp_create_new_session(cwd)
  end
end

function Process:_acp_create_new_session(cwd)
  self:_notify_status("creating_session")

  self:send("session/new", {
    cwd = cwd,
    mcpServers = EMPTY_ARRAY
  }, function(result, err)
    if err then
      self:_notify_status("session_error_detail", err)
      self:_notify_status("session_failed", err)
      return
    end

    self:_handle_session_result(result)
    self:_notify_status("session_created", result)
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

function Process:send_prompt(prompt, opts)
  opts = opts or {}

  -- Check if process is alive (has job_id)
  if not self:is_alive() then
    if self.config.debug and self._on_debug then
      self:_on_debug("send_prompt: not alive")
    end
    return nil
  end

  -- Check if session is ready (initialized)
  -- Note: After cancellation, session_ready should remain true if we've initialized
  if not self.state.session_ready and not self.state.initialized then
    if self.config.debug and self._on_debug then
      self:_on_debug("send_prompt: not ready (not initialized)")
    end
    return nil
  end

  -- Queue if busy
  if self.state.busy then
    local text = self:_extract_prompt_text(prompt)
    table.insert(self.data.prompt_queue, { prompt = prompt, text = text, opts = opts })
    if self.config.debug and self._on_debug then
      self:_on_debug("send_prompt: busy, queued")
    end
    return nil
  end

  -- Mark as busy before sending
  self.state.busy = true
  self.ui.streaming_response = ""
  self.ui.streaming_start_line = nil
  self.ui.pending_tool_calls = {}

  if self.config.debug and self._on_debug then
    self:_on_debug("send_prompt: sending to session " .. self.session_id)
  end

  prompt = self:_transform_ultrathink(prompt)

  -- Transform prompt to ACP array format if needed
  local formatted_prompt = prompt
  if type(prompt) == "string" then
    formatted_prompt = { { type = "text", text = prompt } }
  elseif type(prompt) == "table" and #prompt > 0 and type(prompt[1]) == "string" then
    -- Handle case where prompt is an array of strings
    local new_prompt = {}
    for _, text in ipairs(prompt) do
      table.insert(new_prompt, { type = "text", text = text })
    end
    formatted_prompt = new_prompt
  end

  local request_params = {
    sessionId = self.session_id,
    prompt = formatted_prompt
  }

  -- Wrap the send in pcall to catch any errors during send
  local ok, result_id = pcall(function()
    return self:send("session/prompt", request_params, function(result, err)
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
  end)

  if not ok then
    -- Send failed, reset state
    if self._on_debug then
      self:_on_debug("send_prompt failed: " .. tostring(result_id))
    end
    self.state.busy = false
    return nil
  end

  return result_id
end

function Process:cancel()
  if not self:is_alive() then return end
  
  -- Send cancellation notification
  self:notify("session/cancel", { sessionId = self.session_id })
  
  -- Reset streaming and UI state
  self.ui.streaming_response = ""
  self.ui.streaming_start_line = nil
  self.ui.pending_tool_calls = {}
  self.ui.active_tools = {}
  
  -- Mark as not busy to allow new operations
  -- The agent will send a 'stop' update when it actually cancels
  self.state.busy = false
  
  -- Ensure session_ready is true to allow new messages
  -- If we've initialized once, we should be ready to send new messages
  self.state.session_ready = true
end

function Process:cancel_and_clear_queue()
  if not self:is_alive() then return end
  self:notify("session/cancel", { sessionId = self.session_id })
  -- Cancel current operation AND clear the queue
  self.state.busy = false
  self.data.prompt_queue = {}
  if not self.state.session_ready then
    self.state.session_ready = self.state.initialized or false
  end
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
    if type(next_prompt) == "table" and next_prompt.prompt then
      self:send_prompt(next_prompt.prompt, next_prompt.opts)
    else
      self:send_prompt(next_prompt)
    end
  end
end

function Process:get_queue()
  return self.data.prompt_queue
end

function Process:get_queued_item(index)
  return self.data.prompt_queue[index]
end

function Process:update_queued_item(index, new_prompt)
  if index < 1 or index > #self.data.prompt_queue then
    return false
  end
  local item = self.data.prompt_queue[index]
  if type(item) == "table" then
    item.prompt = new_prompt
    item.text = type(new_prompt) == "string" and new_prompt or (new_prompt[1] and new_prompt[1].text or "")
  else
    self.data.prompt_queue[index] = { prompt = new_prompt, text = type(new_prompt) == "string" and new_prompt or "" }
  end
  return true
end

function Process:remove_queued_item(index)
  if index < 1 or index > #self.data.prompt_queue then
    return nil
  end
  return table.remove(self.data.prompt_queue, index)
end

function Process:cleanup_stale_callbacks(max_age_seconds)
  max_age_seconds = max_age_seconds or 300 -- Default 5 minutes
  local now = os.time()
  local stale_ids = {}

  for id, timeout_info in pairs(self.conn.callback_timeouts) do
    if now - timeout_info.created_at > max_age_seconds then
      table.insert(stale_ids, id)
    end
  end

  for _, id in ipairs(stale_ids) do
    if self._on_debug and self.config.debug then
      local timeout_info = self.conn.callback_timeouts[id]
      self:_on_debug("Cleaning up stale callback " .. id .. " for " .. timeout_info.method)
    end
    self.conn.callbacks[id] = nil
    self.conn.callback_timeouts[id] = nil
  end

  return #stale_ids
end

function Process:get_pending_callback_count()
  local count = 0
  for _ in pairs(self.conn.callbacks) do
    count = count + 1
  end
  return count
end

function Process:clear_queue()
  self.data.prompt_queue = {}
end

function Process:restart()
  self:kill()
  vim.defer_fn(function()
    self:start()
  end, 100)
end

function Process:reset_session_with_context(injection_prompt, callback)
  if not self.state.initialized then
    if callback then callback(false, "not initialized") end
    return
  end

  local cwd = self.data.cwd or vim.fn.getcwd()
  local old_session_id = self.session_id

  self.state.session_ready = false
  self.state.busy = false
  self.data.prompt_queue = {}
  self.ui.streaming_response = ""
  self.ui.active_tools = {}
  self.ui.pending_tool_calls = {}

  self:_notify_status("resetting_session")

  self:send("session/new", {
    cwd = cwd,
    mcpServers = EMPTY_ARRAY
  }, function(result, err)
    if err then
      self:_notify_status("session_reset_failed", err)
      if callback then callback(false, err) end
      return
    end

    self:_handle_session_result(result)
    self:_notify_status("session_reset", { old_id = old_session_id, new_id = self.session_id })

    if injection_prompt then
      vim.defer_fn(function()
        self:send_prompt(injection_prompt, { silent = true })
        if callback then callback(true, nil) end
      end, 100)
    else
      if callback then callback(true, nil) end
    end
  end)
end

function Process:get_agent_name()
  if self.state.agent_info and self.state.agent_info.name then
    local name = self.state.agent_info.name:gsub("^@[^/]+/", "")
    local friendly = { ["claude-code-acp"] = "Claude Code" }
    return friendly[name] or name
  end
  return "Agent"
end

function Process:_transform_ultrathink(prompt)
  local ULTRATHINK_KEYWORDS = {
    "ultrathink:",
    "think harder:",
    "megathink:",
    "ultrathought:",
  }

  local text = self:_extract_prompt_text(prompt)

  local has_ultrathink = false
  local keyword_found = nil
  for _, keyword in ipairs(ULTRATHINK_KEYWORDS) do
    if text:lower():match(keyword:lower():gsub(":", "")) then
      has_ultrathink = true
      keyword_found = keyword
      break
    end
  end

  if not has_ultrathink then
    return prompt
  end

  local provider_id = self.data.provider or "claude"

  if provider_id == "claude" then
    return prompt
  end

  local enhanced_prompt = text:gsub(keyword_found:gsub(":", ""), "")
  enhanced_prompt = [[I need you to think deeply and carefully about this task. Take your time to:

1. Break down the problem into key components
2. Consider multiple approaches and their trade-offs
3. Think through edge cases and potential issues
4. Reason step-by-step through the solution
5. Validate your reasoning before responding

Task: ]] .. enhanced_prompt

  if type(prompt) == "string" then
    return enhanced_prompt
  elseif type(prompt) == "table" then
    local new_prompt = {}
    for _, block in ipairs(prompt) do
      if block.type == "text" then
        table.insert(new_prompt, { type = "text", text = enhanced_prompt })
      else
        table.insert(new_prompt, block)
      end
    end
    return new_prompt
  end

  return prompt
end

return Process
