local const = require("neowork.const")

local M = {}

M.phase = {
  idle = "idle",
  connecting = "connecting",
  ready = "ready",
  submitting = "submitting",
  streaming = "streaming",
  awaiting_perm = "awaiting_perm",
  tool = "tool",
  interrupted = "interrupted",
  error = "error",
}

local function phase_to_status(phase)
  if phase == M.phase.idle then return const.session_status.idle end
  if phase == M.phase.connecting then return const.session_status.connecting end
  if phase == M.phase.ready then return const.session_status.ready end
  if phase == M.phase.submitting then return const.session_status.submitting end
  if phase == M.phase.streaming then return const.session_status.streaming end
  if phase == M.phase.awaiting_perm then return const.session_status.awaiting end
  if phase == M.phase.tool then return const.session_status.tool end
  if phase == M.phase.interrupted then return const.session_status.interrupted end
  if phase == M.phase.error then return const.session_status.error end
  return phase
end

local function persisted_status_for(status, opts)
  opts = opts or {}
  if opts.persisted ~= nil then return opts.persisted end
  if status == const.session_status.connecting then return const.session_status.ready end
  if status == const.session_status.submitting then return const.session_status.running end
  if status == const.session_status.streaming then return const.session_status.running end
  if status == const.session_status.tool then return const.session_status.running end
  return status
end

local States = {}
States.__index = States

function M.new(buf)
  return setmetatable({
    buf = buf,
    phase = M.phase.idle,
    meta = nil,
    pre_awaiting_phase = nil,
    ready_listeners = {},
    observers = {},
  }, States)
end

function States:on_change(fn)
  self.observers[#self.observers + 1] = fn
end

function States:_notify()
  for _, fn in ipairs(self.observers) do
    pcall(fn, self.phase, self.meta)
  end
end

function States:transition(next_phase, meta)
  if next_phase == M.phase.awaiting_perm and self.phase ~= M.phase.awaiting_perm then
    self.pre_awaiting_phase = self.phase
  end
  self.phase = next_phase
  self.meta = meta
  self:_notify()
end

function States:resume_after_awaiting()
  local target = self.pre_awaiting_phase or M.phase.submitting
  self.pre_awaiting_phase = nil
  self:transition(target)
  return target
end

function States:is(phase)
  return self.phase == phase
end

function States:current_status()
  return phase_to_status(self.phase), self.meta
end

function States:persisted_status(opts)
  return persisted_status_for(phase_to_status(self.phase), opts)
end

function States:on_ready(cb)
  if self.phase == M.phase.ready or self.phase == M.phase.streaming or self.phase == M.phase.submitting then
    vim.schedule(function() cb(nil) end)
    return
  end
  table.insert(self.ready_listeners, cb)
end

function States:flush_ready(err)
  local queue = self.ready_listeners
  self.ready_listeners = {}
  for _, cb in ipairs(queue) do
    pcall(cb, err)
  end
end

M.persisted_status_for = persisted_status_for
M.phase_to_status = phase_to_status

return M
