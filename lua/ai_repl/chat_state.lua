local M = {}

local global_state = {
  config = nil,
  active_session = nil,
  original_updatetime = vim.o.updatetime,
  active_chat_buffers = 0,
  last_non_chat_file = nil,
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
      activity_phase = nil,
      activity_phase_start = nil,
      activity_total_start = nil,
      activity_tool_index = 0,
      activity_tool_total = 0,
      activity_tool_name = nil,
    }
  end
  return buffer_states[buf]
end

function M.cleanup_buffer_state(buf)
  local state = buffer_states[buf]
  if not state then return end

  if state.spinner_timer then
    state.spinner_timer:stop()
    if not state.spinner_timer:is_closing() then state.spinner_timer:close() end
  end

  for _, indicator in pairs(state.tool_indicators or {}) do
    if indicator.timer then
      indicator.timer:stop()
      if not indicator.timer:is_closing() then indicator.timer:close() end
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
  if global_state.active_chat_buffers == 1 and vim.o.updatetime > 300 then
    global_state.original_updatetime = vim.o.updatetime
    vim.o.updatetime = 300
  end
end

function M.decrement_active_buffers()
  global_state.active_chat_buffers = math.max(0, global_state.active_chat_buffers - 1)
  if global_state.active_chat_buffers == 0 then
    vim.o.updatetime = global_state.original_updatetime
  end
end

function M.set_activity_phase(buf, phase, opts)
  local state = M.get_buffer_state(buf)
  opts = opts or {}
  state.activity_phase = phase
  state.activity_phase_start = vim.uv.hrtime()
  if phase == nil then
    state.activity_total_start = nil
    state.activity_tool_index = 0
    state.activity_tool_total = 0
    state.activity_tool_name = nil
  elseif phase == "thinking" and not state.activity_total_start then
    state.activity_total_start = vim.uv.hrtime()
  end
  if opts.tool_name then
    state.activity_tool_name = opts.tool_name
  end
  if opts.increment_tool then
    state.activity_tool_index = state.activity_tool_index + 1
    state.activity_tool_total = state.activity_tool_total + 1
  end
end

function M.get_activity_elapsed(buf)
  local state = buffer_states[buf]
  if not state or not state.activity_phase_start then return nil end
  return (vim.uv.hrtime() - state.activity_phase_start) / 1e9
end

function M.get_statusline_info(buf)
  local state = buffer_states[buf]
  if not state then return {} end
  local proc = state.process
  local elapsed = state.activity_phase_start
    and math.floor((vim.uv.hrtime() - state.activity_phase_start) / 1e9) or 0
  local total_elapsed = state.activity_total_start
    and math.floor((vim.uv.hrtime() - state.activity_total_start) / 1e9) or 0
  local session_cost = proc and proc.ui and proc.ui.session_cost
  local cost_str = nil
  if session_cost and session_cost > 0 then
    local cost_mod = require("ai_repl.cost")
    cost_str = cost_mod.format(session_cost)
  end
  return {
    phase = state.activity_phase,
    elapsed = elapsed,
    total_elapsed = total_elapsed,
    tool = state.activity_tool_name,
    tool_progress = state.activity_tool_index > 0
      and (state.activity_tool_index .. "/" .. state.activity_tool_total) or nil,
    busy = proc and proc.state and proc.state.busy or false,
    permission_pending = proc and proc.ui and proc.ui.permission_active or false,
    cost = cost_str,
  }
end

function M.set_last_non_chat_file(path)
  if path and path ~= "" and not path:match("%.chat$") then
    global_state.last_non_chat_file = path
  end
end

function M.get_last_non_chat_file()
  return global_state.last_non_chat_file
end

return M
