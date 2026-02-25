local M = {}

M.clients = {}

M.clients_by_buffer = {}

M.buffer_to_session = {}

local stale_cleanup_timer = nil

function M.register_client(session_id, process, opts)
  opts = opts or {}
  local chat_buf = opts.chat_buf

  M.clients[session_id] = {
    process = process,
    chat_buf = chat_buf,
    created_at = os.time(),
    last_activity = os.time(),
  }

  if chat_buf then
    M.clients_by_buffer[chat_buf] = session_id
    M.buffer_to_session[chat_buf] = session_id

    vim.api.nvim_buf_attach(chat_buf, false, {
      on_detach = function()
        M.on_buffer_closed(chat_buf)
      end
    })
  end

  if opts.debug then
    vim.notify(
      string.format("[lifecycle] Registered client %s for buffer %s", session_id, tostring(chat_buf)),
      vim.log.levels.DEBUG
    )
  end
end

function M.unregister_client(session_id, opts)
  opts = opts or {}
  local client_info = M.clients[session_id]

  if not client_info then
    return
  end

  local chat_buf = client_info.chat_buf
  if chat_buf then
    M.clients_by_buffer[chat_buf] = nil
    M.buffer_to_session[chat_buf] = nil
  end

  M.clients[session_id] = nil

  if opts.debug then
    vim.notify(
      string.format("[lifecycle] Unregistered client %s from buffer %s", session_id, tostring(chat_buf)),
      vim.log.levels.DEBUG
    )
  end
end

function M.get_client(session_id)
  local info = M.clients[session_id]
  return info and info.process or nil
end

function M.get_client_by_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local session_id = M.clients_by_buffer[buf]
  if not session_id then
    return nil
  end
  return M.get_client(session_id)
end

function M.get_session_id_by_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return M.clients_by_buffer[buf]
end

function M.on_buffer_closed(buf)
  local session_id = M.clients_by_buffer[buf]
  if session_id then
    local client_info = M.clients[session_id]
    if client_info and client_info.process then
      pcall(function()
        client_info.process:cleanup()
      end)
    end
    M.unregister_client(session_id)
  end
end

function M.update_activity(session_id)
  local info = M.clients[session_id]
  if info then
    info.last_activity = os.time()
  end
end

function M.cleanup_stale_clients(max_idle_seconds)
  max_idle_seconds = max_idle_seconds or 3600
  local now = os.time()
  local to_cleanup = {}

  for session_id, info in pairs(M.clients) do
    local idle_time = now - info.last_activity
    if idle_time > max_idle_seconds then
      table.insert(to_cleanup, session_id)
    end
  end

  for _, session_id in ipairs(to_cleanup) do
    local info = M.clients[session_id]
    if info and info.process then
      info.process:cleanup()
    end
    M.unregister_client(session_id)
  end

  return #to_cleanup
end

function M.cleanup_all_clients()
  local count = 0
  for session_id, info in pairs(M.clients) do
    if info.process then
      pcall(function()
        info.process:cleanup()
      end)
    end
    count = count + 1
  end

  M.clients = {}
  M.clients_by_buffer = {}
  M.buffer_to_session = {}

  return count
end

function M.get_active_count()
  local count = 0
  for _ in pairs(M.clients) do
    count = count + 1
  end
  return count
end

function M.setup_auto_cleanup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("AiReplLifecycle", { clear = true }),
    callback = function()
      M.cleanup_timers()
      local count = M.cleanup_all_clients()
      if count > 0 then
        vim.notify(
          string.format("[ai_repl] Cleaned up %d client(s)", count),
          vim.log.levels.INFO
        )
      end
    end,
  })

  if stale_cleanup_timer then
    stale_cleanup_timer:stop()
    stale_cleanup_timer:close()
  end
  stale_cleanup_timer = vim.uv.new_timer()
  stale_cleanup_timer:start(300000, 300000, vim.schedule_wrap(function()
    local cleaned = M.cleanup_stale_clients(3600)
    if cleaned > 0 then
      vim.notify(
        string.format("[ai_repl] Cleaned up %d stale client(s)", cleaned),
        vim.log.levels.INFO
      )
    end
  end))
end

function M.cleanup_timers()
  if stale_cleanup_timer then
    stale_cleanup_timer:stop()
    stale_cleanup_timer:close()
    stale_cleanup_timer = nil
  end
end

return M
