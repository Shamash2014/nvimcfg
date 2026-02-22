local M = {}

local global_state = {
  config = nil,
  active_session = nil,
  original_updatetime = vim.o.updatetime,
  active_chat_buffers = 0,
}

local buffer_states = {}

function M.get_buffer_state(buf)
  if not buffer_states[buf] then
    buffer_states[buf] = {
      session_id = nil,
      process = nil,
      streaming = false,
      ast_cache = nil,
      ast_changedtick = -1,
      locked = false,
      spinner_timer = nil,
      spinner_extmark = nil,
      tool_indicators = {},
      repo_root = nil,
      creating_session = false,
      system_sent = false,
    }
  end
  return buffer_states[buf]
end

function M.cleanup_buffer_state(buf)
  local state = buffer_states[buf]
  if not state then return end

  if state.spinner_timer then
    state.spinner_timer:stop()
    state.spinner_timer:close()
  end

  for _, indicator in pairs(state.tool_indicators or {}) do
    if indicator.timer then
      indicator.timer:stop()
      indicator.timer:close()
    end
  end

  buffer_states[buf] = nil
end

function M.set_global_config(config)
  global_state.config = config
end

function M.get_global_config()
  return global_state.config
end

function M.set_active_session(session_id)
  global_state.active_session = session_id
end

function M.get_active_session()
  return global_state.active_session
end

function M.increment_active_buffers()
  global_state.active_chat_buffers = global_state.active_chat_buffers + 1
  if global_state.active_chat_buffers == 1 and vim.o.updatetime > 100 then
    global_state.original_updatetime = vim.o.updatetime
    vim.o.updatetime = 100
  end
end

function M.decrement_active_buffers()
  global_state.active_chat_buffers = math.max(0, global_state.active_chat_buffers - 1)
  if global_state.active_chat_buffers == 0 then
    vim.o.updatetime = global_state.original_updatetime
  end
end

return M
