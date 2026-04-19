local M = {}

M._by_session = {}
M._by_buf = {}

function M.attach(buf, session_id, client, handlers)
  M.detach(buf)

  local handle = {
    on_update = handlers.on_update,
    on_permission = handlers.on_permission,
  }

  client:subscribe(session_id, handle)

  local record = {
    buf = buf,
    session_id = session_id,
    client = client,
    handle = handle,
  }

  M._by_buf[buf] = record
  M._by_session[session_id] = record
  return record
end

function M.detach(buf)
  local record = M._by_buf[buf]
  if not record then return end
  pcall(function()
    record.client:unsubscribe(record.session_id, record.handle)
  end)
  M._by_buf[buf] = nil
  if M._by_session[record.session_id] == record then
    M._by_session[record.session_id] = nil
  end
end

function M.detach_session(session_id)
  local record = M._by_session[session_id]
  if not record then return end
  M.detach(record.buf)
end

function M.get(buf)
  return M._by_buf[buf]
end

function M.buf_for_session(session_id)
  local record = M._by_session[session_id]
  return record and record.buf or nil
end

return M
