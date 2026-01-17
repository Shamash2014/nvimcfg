-- Ralph Wiggum Mode: Persistent iterative looping until task completion
-- Works with ALL providers (Claude, Cursor, Goose, OpenCode, Codex)

local M = {}

local ralph_state = {
  enabled = false,
  paused = false,
  max_iterations = 50,
  current_iteration = 0,
  iteration_history = {},
  original_prompt = nil,
  last_response_hash = nil,
  stuck_count = 0,
  backoff_delay = 500,
}

local COMPLETION_PATTERNS = {
  "%[DONE%]",
  "%[COMPLETE%]",
  "%[FINISHED%]",
  "%[TASK[%s_-]?COMPLETE%]",
  "^##%s*Status:%s*COMPLETE",
  "^##%s*Status:%s*DONE",
  "Task is now complete%.",
  "I have completed the task%.",
  "All tasks? %w+ been completed%.",
  "The implementation is complete%.",
}

local function hash_response(text)
  if not text then return nil end
  local sample = text:sub(-500)
  local hash = 0
  for i = 1, #sample do
    hash = (hash * 31 + sample:byte(i)) % 2147483647
  end
  return hash
end

function M.enable(opts)
  opts = opts or {}
  ralph_state.enabled = true
  ralph_state.paused = false
  ralph_state.max_iterations = opts.max_iterations or 50
  ralph_state.current_iteration = 0
  ralph_state.iteration_history = {}
  ralph_state.original_prompt = nil
  ralph_state.last_response_hash = nil
  ralph_state.stuck_count = 0
  ralph_state.backoff_delay = 500
  return true
end

function M.disable()
  ralph_state.enabled = false
  ralph_state.paused = false
  ralph_state.current_iteration = 0
  ralph_state.original_prompt = nil
  ralph_state.last_response_hash = nil
  ralph_state.stuck_count = 0
end

function M.pause()
  if ralph_state.enabled then
    ralph_state.paused = true
    return true
  end
  return false
end

function M.resume()
  if ralph_state.enabled and ralph_state.paused then
    ralph_state.paused = false
    return true
  end
  return false
end

function M.is_enabled()
  return ralph_state.enabled
end

function M.is_paused()
  return ralph_state.paused
end

function M.set_original_prompt(prompt)
  ralph_state.original_prompt = prompt
end

function M.get_iteration_count()
  return ralph_state.current_iteration
end

function M.get_history()
  return ralph_state.iteration_history
end

function M.check_completion(response_text)
  if not response_text then return false, nil end

  for _, pattern in ipairs(COMPLETION_PATTERNS) do
    if response_text:match(pattern) then
      return true, pattern
    end
  end

  local last_200 = response_text:sub(-200):upper()
  local end_tokens = { "DONE", "COMPLETE", "FINISHED" }
  for _, token in ipairs(end_tokens) do
    if last_200:match(token .. "[%.!]?%s*$") then
      return true, token
    end
  end

  return false, nil
end

function M.check_stuck(response_text)
  local current_hash = hash_response(response_text)
  if current_hash and current_hash == ralph_state.last_response_hash then
    ralph_state.stuck_count = ralph_state.stuck_count + 1
    return true, ralph_state.stuck_count
  end
  ralph_state.last_response_hash = current_hash
  ralph_state.stuck_count = 0
  return false, 0
end

function M.get_backoff_delay()
  local base = ralph_state.backoff_delay
  local multiplier = math.min(ralph_state.stuck_count, 5)
  return base * (2 ^ multiplier)
end

function M.should_continue(response_text)
  if not ralph_state.enabled then
    return false, "ralph_disabled"
  end

  if ralph_state.paused then
    return false, "paused"
  end

  if ralph_state.current_iteration >= ralph_state.max_iterations then
    return false, "max_iterations"
  end

  local completed, pattern = M.check_completion(response_text)
  if completed then
    return false, "completed:" .. (pattern or "unknown")
  end

  local is_stuck, stuck_count = M.check_stuck(response_text)
  if is_stuck and stuck_count >= 3 then
    return false, "stuck"
  end

  return true, nil
end

function M.record_iteration(response)
  ralph_state.current_iteration = ralph_state.current_iteration + 1

  table.insert(ralph_state.iteration_history, {
    iteration = ralph_state.current_iteration,
    timestamp = os.time(),
    response_length = response and #response or 0,
    response_summary = response and response:sub(1, 300) or nil,
    stuck_count = ralph_state.stuck_count,
  })
end

function M.get_continuation_prompt()
  local iteration = ralph_state.current_iteration + 1
  local original = ralph_state.original_prompt or "the task"

  if iteration <= 3 then
    return string.format(
      "[Iteration %d/%d] Continue working on: %s\n\nWhen complete, end with [DONE].",
      iteration, ralph_state.max_iterations, original
    )
  elseif iteration <= 10 then
    return string.format(
      "[Iteration %d/%d] Continue the task. Focus on remaining work.\n\nOriginal: %s\n\nIf blocked, explain what's blocking. When complete, end with [DONE].",
      iteration, ralph_state.max_iterations, original
    )
  elseif iteration <= 20 then
    return string.format(
      "[Iteration %d/%d] We're making progress. What remains to be done?\n\nOriginal task: %s\n\nList remaining items, then continue. End with [DONE] when finished.",
      iteration, ralph_state.max_iterations, original
    )
  else
    return string.format(
      "[Iteration %d/%d] High iteration count. Please:\n1. Summarize what's been done\n2. List what's left\n3. Continue or explain blockers\n\nOriginal: %s\n\nEnd with [DONE] when complete.",
      iteration, ralph_state.max_iterations, original
    )
  end
end

function M.get_summary()
  if #ralph_state.iteration_history == 0 then
    return nil
  end

  local total_chars = 0
  for _, entry in ipairs(ralph_state.iteration_history) do
    total_chars = total_chars + (entry.response_length or 0)
  end

  local start_time = ralph_state.iteration_history[1].timestamp
  local end_time = ralph_state.iteration_history[#ralph_state.iteration_history].timestamp
  local duration = end_time - start_time

  return {
    iterations = ralph_state.current_iteration,
    total_response_chars = total_chars,
    duration_seconds = duration,
    original_prompt = ralph_state.original_prompt,
    history = ralph_state.iteration_history,
  }
end

function M.get_status()
  if not ralph_state.enabled then
    return { enabled = false }
  end

  return {
    enabled = true,
    paused = ralph_state.paused,
    iteration = ralph_state.current_iteration,
    max_iterations = ralph_state.max_iterations,
    progress_pct = math.floor((ralph_state.current_iteration / ralph_state.max_iterations) * 100),
    stuck_count = ralph_state.stuck_count,
    backoff_delay = M.get_backoff_delay(),
  }
end

function M.save_state()
  return {
    enabled = ralph_state.enabled,
    paused = ralph_state.paused,
    max_iterations = ralph_state.max_iterations,
    current_iteration = ralph_state.current_iteration,
    iteration_history = ralph_state.iteration_history,
    original_prompt = ralph_state.original_prompt,
    stuck_count = ralph_state.stuck_count,
  }
end

function M.restore_state(state)
  if not state then return false end
  ralph_state.enabled = state.enabled or false
  ralph_state.paused = state.paused or false
  ralph_state.max_iterations = state.max_iterations or 50
  ralph_state.current_iteration = state.current_iteration or 0
  ralph_state.iteration_history = state.iteration_history or {}
  ralph_state.original_prompt = state.original_prompt
  ralph_state.stuck_count = state.stuck_count or 0
  return true
end

return M
