local M = {}

local state = {
  continuation_count = 0,
  max_continuations = 5,
  tool_failure_counts = {},
  consecutive_failures = 0,
  max_consecutive_failures = 3,
  max_retries_per_tool = 2,
  recovery_prompt = nil,
}

local INCOMPLETE_SIGNALS = {
  "Let me", "I'll now", "Next,", "I need to", "I'll ", "Now I",
  "Moving on", "Continuing", "Let's ", "I will ",
}

local QUESTION_SIGNALS = {
  "let me know", "would you like", "shall I", "what do you think",
  "do you want", "should I", "would you prefer", "any preference",
}

local TRANSIENT_PATTERNS = {
  "timeout", "ECONNRESET", "rate limit", "503", "502",
  "connection refused", "ETIMEDOUT", "ECONNREFUSED",
}

local function looks_complete(text)
  local trimmed = text:match("(.-)%s*$") or text
  if trimmed == "" then return true end

  local last_char = trimmed:sub(-1)
  if last_char == "." or last_char == "?" or last_char == "!" then return true end
  if trimmed:sub(-3) == "```" then return true end
  if trimmed:match("%-%-%-$") or trimmed:match("%*%*%*$") then return true end

  local last_line = ""
  for line in trimmed:gmatch("[^\n]+") do
    if line:match("%S") then last_line = line end
  end
  local ll = last_line:match("^%s*(.-)%s*$") or ""
  if ll:match("%.$") or ll:match("%?$") or ll:match("!$") then return true end
  if ll:match("^```") then return true end

  return false
end

local function has_incomplete_signals(text)
  local tail = text:sub(-500)
  for _, signal in ipairs(INCOMPLETE_SIGNALS) do
    if tail:find(signal, 1, true) then
      return true
    end
  end
  return false
end

local function has_question_signals(text)
  local lower = text:lower()
  for _, signal in ipairs(QUESTION_SIGNALS) do
    if lower:find(signal, 1, true) then
      return true
    end
  end
  return false
end

local function is_transient_error(raw_output)
  if not raw_output or raw_output == "" then return false end
  local lower = raw_output:lower()
  for _, pattern in ipairs(TRANSIENT_PATTERNS) do
    if lower:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

function M.maybe_auto_continue(proc, response_text, stop_reason)
  if stop_reason ~= "end_turn" then return false end
  if state.continuation_count >= state.max_continuations then return false end
  if not response_text or response_text == "" then return false end
  if #response_text < 80 then return false end
  if has_question_signals(response_text) then return false end

  local dominated_by_incomplete = not looks_complete(response_text)
    and has_incomplete_signals(response_text)

  if not dominated_by_incomplete then return false end

  state.continuation_count = state.continuation_count + 1
  vim.defer_fn(function()
    if proc:is_alive() and not proc.state.busy then
      proc:send_prompt(
        "Continue from where you left off. Complete the task you were working on.",
        { silent = true }
      )
    end
  end, 200)
  return true
end

function M.on_tool_failure(_, tool)
  local tool_id = tool.id or "unknown"
  state.tool_failure_counts[tool_id] = (state.tool_failure_counts[tool_id] or 0) + 1
  state.consecutive_failures = state.consecutive_failures + 1

  local raw = tool.rawOutput or ""
  if is_transient_error(raw)
    and state.tool_failure_counts[tool_id] <= state.max_retries_per_tool
    and state.consecutive_failures < state.max_consecutive_failures then
    local first_line = raw:match("([^\n]+)") or raw:sub(1, 120)
    state.recovery_prompt = "The tool call failed with a transient error: "
      .. first_line .. ". Please retry the operation."
  end
end

function M.on_tool_success()
  state.consecutive_failures = 0
end

function M.check_recovery_prompt(proc)
  if not state.recovery_prompt then return false end
  local prompt = state.recovery_prompt
  state.recovery_prompt = nil
  vim.defer_fn(function()
    if proc:is_alive() and not proc.state.busy then
      proc:send_prompt(prompt, { silent = true })
    end
  end, 200)
  return true
end

function M.reset_continuation()
  state.continuation_count = 0
  state.tool_failure_counts = {}
  state.recovery_prompt = nil
end

function M.gather_initial_context(proc)
  local cwd = proc.data.cwd or vim.fn.getcwd()
  local parts = {}

  local function safe_cmd(cmd, max_lines)
    local ok, result = pcall(vim.fn.systemlist, cmd)
    if not ok or type(result) ~= "table" or #result == 0 then return nil end
    if vim.v.shell_error ~= 0 then return nil end
    if #result > max_lines then
      local truncated = {}
      for i = 1, max_lines do truncated[i] = result[i] end
      truncated[max_lines + 1] = "... (" .. (#result - max_lines) .. " more lines)"
      return table.concat(truncated, "\n")
    end
    return table.concat(result, "\n")
  end

  local git_status = safe_cmd("cd " .. vim.fn.shellescape(cwd) .. " && git status --short 2>/dev/null", 30)
  if git_status then
    table.insert(parts, "Git Status:\n" .. git_status)
  end

  local git_log = safe_cmd("cd " .. vim.fn.shellescape(cwd) .. " && git log --oneline -5 2>/dev/null", 5)
  if git_log then
    table.insert(parts, "Recent Commits:\n" .. git_log)
  end

  local git_diff = safe_cmd("cd " .. vim.fn.shellescape(cwd) .. " && git diff --stat HEAD~3..HEAD 2>/dev/null", 20)
  if git_diff then
    table.insert(parts, "Recent Changes:\n" .. git_diff)
  end

  local ok, entries = pcall(vim.fn.readdir, cwd)
  if ok and entries then
    local limited = {}
    for i = 1, math.min(#entries, 30) do
      limited[i] = entries[i]
    end
    if #entries > 30 then
      table.insert(limited, "... (" .. (#entries - 30) .. " more)")
    end
    table.insert(parts, "Structure:\n" .. table.concat(limited, ", "))
  end

  if #parts == 0 then return nil end
  return "[Project Context]\n" .. table.concat(parts, "\n\n")
end

function M.inject_context(prompt, context_text)
  if type(prompt) == "string" then
    return context_text .. "\n\n" .. prompt
  elseif type(prompt) == "table" then
    local new_prompt = { { type = "text", text = context_text } }
    for _, block in ipairs(prompt) do
      table.insert(new_prompt, block)
    end
    return new_prompt
  end
  return prompt
end

return M
