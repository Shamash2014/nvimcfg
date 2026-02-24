local M = {}

local processes = {}
local active_session_id = nil
local save_timer = nil

local function get_chat_buf(proc)
  if proc and proc.ui and proc.ui.chat_buf then
    local buf = proc.ui.chat_buf
    if vim.api.nvim_buf_is_valid(buf) then
      return buf
    end
  end
  return nil
end

local config = {
  sessions_file = vim.fn.stdpath("data") .. "/ai_repl_sessions.json",
  messages_dir = vim.fn.stdpath("data") .. "/ai_repl_messages",
  save_interval = 30000,
  max_sessions_per_project = 20,
}

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
  if vim.fn.isdirectory(config.messages_dir) == 0 then
    vim.fn.mkdir(config.messages_dir, "p")
  end
end

function M.get(session_id)
  return processes[session_id]
end

function M.set(session_id, process)
  processes[session_id] = process
end

function M.remove(session_id)
  local proc = processes[session_id]
  if proc then
    proc:kill()
  end
  processes[session_id] = nil
  if active_session_id == session_id then
    active_session_id = nil
  end
end

function M.unregister(session_id)
  processes[session_id] = nil
  if active_session_id == session_id then
    active_session_id = nil
  end
end

function M.all()
  return processes
end

function M.count()
  local n = 0
  for _ in pairs(processes) do n = n + 1 end
  return n
end

function M.active()
  if active_session_id then
    return processes[active_session_id]
  end
  return nil
end

function M.active_session_id()
  return active_session_id
end

function M.set_active(session_id)
  active_session_id = session_id
end

function M.get_by_buffer(buf)
  for sid, proc in pairs(processes) do
    local chat_buf = get_chat_buf(proc)
    if chat_buf and chat_buf == buf then
      return proc, sid
    end
  end
  return nil, nil
end

function M.get_by_job_id(job_id)
  for sid, proc in pairs(processes) do
    if proc.job_id == job_id then
      return proc, sid
    end
  end
  return nil, nil
end

function M.list_running()
  local result = {}
  for sid, proc in pairs(processes) do
    if proc:is_alive() then
      table.insert(result, { session_id = sid, process = proc })
    end
  end
  return result
end

function M.list_for_project(cwd)
  local result = {}
  for sid, proc in pairs(processes) do
    if proc.data.cwd == cwd then
      table.insert(result, { session_id = sid, process = proc })
    end
  end
  return result
end

function M.kill_all()
  for sid, proc in pairs(processes) do
    proc:kill()
  end
  processes = {}
  active_session_id = nil
end

function M.start_autosave()
  if save_timer then return end
  save_timer = vim.fn.timer_start(config.save_interval, function()
    vim.schedule(function()
      M.save_to_disk()
    end)
  end, { ["repeat"] = -1 })
end

function M.stop_autosave()
  if save_timer then
    pcall(vim.fn.timer_stop, save_timer)
    save_timer = nil
  end
end

function M.save_to_disk()
  local data = {}
  for sid, proc in pairs(processes) do
    if not sid:match("^temp_") then
      data[sid] = {
        session_id = sid,
        name = proc.data.name,
        cwd = proc.data.cwd,
        env = proc.data.env,
        provider = proc.data.provider,
        mode = proc.state.mode,
        agent_info = proc.state.agent_info,
        created_at = proc._created_at or os.time(),
        last_saved = os.time(),
      }
    end
  end

  local f = io.open(config.sessions_file, "w")
  if f then
    f:write(vim.json.encode({ sessions = data, active = active_session_id }))
    f:close()
  end
end

function M.load_from_disk()
  local f = io.open(config.sessions_file, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and data and data.sessions then
    return data.sessions, data.active
  end
  return {}
end

function M.get_messages_file(session_id)
  return config.messages_dir .. "/" .. session_id .. ".json"
end

function M.load_messages(session_id)
  local file = M.get_messages_file(session_id)
  local f = io.open(file, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and data and data.messages then
    return data.messages
  end
  return {}
end

function M.save_messages(session_id, messages)
  local file = M.get_messages_file(session_id)
  local f = io.open(file, "w")
  if f then
    f:write(vim.json.encode({ messages = messages }))
    f:close()
  end
end

function M.append_message(session_id, role, content, tool_calls)
  local proc = processes[session_id]
  if not proc then return end

  local msg = {
    role = role,
    content = content,
    timestamp = os.time(),
  }
  if tool_calls and #tool_calls > 0 then
    msg.tool_calls = tool_calls
  end

  table.insert(proc.data.messages, msg)

  if #proc.data.messages > 1000 then
    local to_remove = #proc.data.messages - 1000
    for _ = 1, to_remove do
      table.remove(proc.data.messages, 1)
    end
  end
end

function M.delete_session(session_id)
  M.remove(session_id)

  local sessions = M.load_from_disk()
  sessions[session_id] = nil
  local f = io.open(config.sessions_file, "w")
  if f then
    f:write(vim.json.encode({ sessions = sessions, active = active_session_id }))
    f:close()
  end

  local msg_file = M.get_messages_file(session_id)
  if vim.fn.filereadable(msg_file) == 1 then
    vim.fn.delete(msg_file)
  end
end

function M.get_sessions_for_project(cwd)
  local sessions, _ = M.load_from_disk()
  local result = {}
  for sid, info in pairs(sessions) do
    if info.cwd == cwd then
      info.has_process = processes[sid] ~= nil and processes[sid]:is_alive()
      info.is_active = sid == active_session_id
      table.insert(result, info)
    end
  end
  table.sort(result, function(a, b)
    return (a.last_saved or 0) > (b.last_saved or 0)
  end)
  return result
end

function M.export_chat(session_id, output_path)
  local chat_serializer = require("ai_repl.chat_serializer")
  return chat_serializer.save_chat_file(session_id, output_path)
end

function M.import_chat(file_path)
  local chat_serializer = require("ai_repl.chat_serializer")
  return chat_serializer.load_chat_file(file_path)
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    M.stop_autosave()
    M.save_to_disk()
    for sid, proc in pairs(processes) do
      M.save_messages(sid, proc.data.messages)
      -- Also export to .chat format for archival
      local chat_dir = vim.fn.stdpath("data") .. "/ai_repl_chats"
      vim.fn.mkdir(chat_dir, "p")
      local chat_serializer = require("ai_repl.chat_serializer")
      chat_serializer.save_chat_file(sid, chat_dir .. "/" .. sid .. ".chat")
    end
    M.kill_all()
  end
})

return M
