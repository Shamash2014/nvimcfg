local M = {}

M.droid = {
  booting = "booting",
  idle = "idle",
  running = "running",
  blocked = "blocked",
  cancelled = "cancelled",
  done = "done",
}

M.discussion = {
  idle = "idle",
  composing = "composing",
  sending = "sending",
  awaiting_user = "awaiting_user",
  queued = "queued",
  staged = "staged",
  closed = "closed",
}

local function sync_compat(state)
  local discussion = state.discussion
  if not discussion then return nil end
  discussion.queue = discussion.queue or state.queue or {}
  if state.queue and discussion.queue ~= state.queue and #discussion.queue == 0 then
    discussion.queue = state.queue
  end
  discussion.composer = discussion.composer or {}
  discussion.composer.persistent = discussion.composer.persistent == true or state.composer_persistent == true
  state.queue = discussion.queue
  state.next_prompt = discussion.next_prompt
  state.pending_prompt = discussion.pending_prompt
  state.staged_input = discussion.staged_input
  state.close_session_on_idle = discussion.close_session_on_idle == true
  state.composer_persistent = discussion.composer.persistent == true
  return discussion
end

function M.ensure_discussion(droid_or_state)
  local state = droid_or_state and droid_or_state.state or droid_or_state
  if not state then return nil end
  if not state.discussion then
    state.discussion = {
      phase = M.discussion.idle,
      queue = state.queue or {},
      next_prompt = state.next_prompt,
      pending_prompt = state.pending_prompt,
      staged_input = state.staged_input,
      pending_initial = state.pending_initial,
      resume_preamble = state.resume_preamble,
      close_session_on_idle = state.close_session_on_idle == true,
      composer = {
        persistent = state.composer_persistent == true,
      },
    }
  end
  return sync_compat(state)
end

function M.discussion_phase(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.phase or nil
end

function M.set_discussion_phase(droid_or_state, phase)
  local state = droid_or_state and droid_or_state.state or droid_or_state
  if not state then return end
  local discussion = M.ensure_discussion(state)
  discussion.phase = phase
  sync_compat(state)
end

function M.set_droid_status(droid, status)
  if not droid then return end
  droid.status = status
end

function M.is_finished(droid)
  local status = droid and droid.status or nil
  return status == M.droid.done or status == M.droid.cancelled or status == M.droid.blocked
end

function M.set_composer_persistent(droid_or_state, persistent)
  local state = droid_or_state and droid_or_state.state or droid_or_state
  if not state then return end
  local discussion = M.ensure_discussion(state)
  discussion.composer.persistent = persistent == true
  sync_compat(state)
end

function M.is_composer_persistent(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.composer and discussion.composer.persistent == true or false
end

function M.pending_initial(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.pending_initial or nil
end

function M.set_pending_initial(droid_or_state, text)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return end
  discussion.pending_initial = text
  sync_compat(droid_or_state.state or droid_or_state)
end

function M.take_pending_initial(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return nil end
  local text = discussion.pending_initial
  discussion.pending_initial = nil
  sync_compat(droid_or_state.state or droid_or_state)
  return text
end

function M.resume_preamble(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.resume_preamble or nil
end

function M.set_resume_preamble(droid_or_state, text)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return end
  discussion.resume_preamble = text
  sync_compat(droid_or_state.state or droid_or_state)
end

function M.take_resume_preamble(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return nil end
  local text = discussion.resume_preamble
  discussion.resume_preamble = nil
  sync_compat(droid_or_state.state or droid_or_state)
  return text
end

function M.pending_prompt(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.pending_prompt or nil
end

function M.set_pending_prompt(droid_or_state, prompt)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return end
  discussion.pending_prompt = prompt
  if prompt then
    discussion.phase = M.discussion.awaiting_user
  elseif discussion.phase == M.discussion.awaiting_user then
    discussion.phase = M.discussion.idle
  end
  sync_compat(droid_or_state.state or droid_or_state)
end

function M.next_prompt(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.next_prompt or nil
end

function M.set_next_prompt(droid_or_state, text)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return end
  discussion.next_prompt = text
  sync_compat(droid_or_state.state or droid_or_state)
end

function M.take_next_prompt(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return nil end
  local text = discussion.next_prompt
  discussion.next_prompt = nil
  sync_compat(droid_or_state.state or droid_or_state)
  return text
end

function M.queue(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.queue or {}
end

function M.enqueue(droid_or_state, text)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return end
  discussion.queue[#discussion.queue + 1] = text
  discussion.phase = M.discussion.queued
  sync_compat(droid_or_state.state or droid_or_state)
end

function M.dequeue(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion or #discussion.queue == 0 then return nil end
  local text = table.remove(discussion.queue, 1)
  if #discussion.queue == 0 and discussion.phase == M.discussion.queued then
    discussion.phase = M.discussion.idle
  end
  sync_compat(droid_or_state.state or droid_or_state)
  return text
end

function M.clear_queue(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return 0 end
  local count = #discussion.queue
  discussion.queue = {}
  if discussion.phase == M.discussion.queued then
    discussion.phase = M.discussion.idle
  end
  sync_compat(droid_or_state.state or droid_or_state)
  return count
end

function M.staged_input(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.staged_input or nil
end

function M.set_staged_input(droid_or_state, text)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return end
  discussion.staged_input = text
  discussion.phase = text and text ~= "" and M.discussion.staged or M.discussion.idle
  sync_compat(droid_or_state.state or droid_or_state)
end

function M.take_staged_input(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return nil end
  local text = discussion.staged_input
  discussion.staged_input = nil
  if discussion.phase == M.discussion.staged then
    discussion.phase = M.discussion.idle
  end
  sync_compat(droid_or_state.state or droid_or_state)
  return text
end

function M.request_close_session_on_idle(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return end
  discussion.close_session_on_idle = true
  sync_compat(droid_or_state.state or droid_or_state)
end

function M.should_close_session_on_idle(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  return discussion and discussion.close_session_on_idle == true or false
end

function M.clear_close_session_on_idle(droid_or_state)
  local discussion = M.ensure_discussion(droid_or_state)
  if not discussion then return end
  discussion.close_session_on_idle = false
  sync_compat(droid_or_state.state or droid_or_state)
end

return M
