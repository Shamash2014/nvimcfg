local M = {}

local MAX_ROUTINE_TURNS = 5

local function render_task(t)
  local lines = { "## " .. (t.id or "?") .. " — " .. (t.desc or "") }
  if t.deps and #t.deps > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### Deps"
    for _, d in ipairs(t.deps) do lines[#lines + 1] = "- " .. d end
  end
  if t.subtasks and #t.subtasks > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### Subtasks"
    for _, s in ipairs(t.subtasks) do
      local mark = s.done and "[x]" or "[ ]"
      lines[#lines + 1] = "- " .. mark .. " " .. (s.text or "")
    end
  end
  if t.acceptance and #t.acceptance > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### Acceptance"
    for _, a in ipairs(t.acceptance) do
      local tag = a.required and "required" or "optional"
      lines[#lines + 1] = "- " .. tag .. ": " .. (a.text or "")
    end
  end
  return table.concat(lines, "\n")
end

local function render_plan_block(state)
  if not state.topo_order or #state.topo_order == 0 then return "" end
  local lines = { "<Tasks>" }
  for _, id in ipairs(state.topo_order) do
    local t = state.tasks and state.tasks[id]
    if t then
      lines[#lines + 1] = ""
      lines[#lines + 1] = render_task(t)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "</Tasks>"
  return table.concat(lines, "\n")
end

local function status_summary(state)
  local done, total = 0, #(state.topo_order or {})
  for _, id in ipairs(state.topo_order or {}) do
    local t = state.tasks and state.tasks[id]
    if t and t.status == "done" then done = done + 1 end
  end
  return done, total
end

local function build_autorun_preamble(state)
  local phase = state.phase or "plan"
  local id = state.current_task_id or "?"
  local retries = (state.sprint_retries and state.sprint_retries[id]) or 0
  local feedback = state.eval_feedback and state.eval_feedback[id] or ""
  local done, total = status_summary(state)
  local original = state.initial_prompt or "(no original prompt recorded)"

  local header = {
    "You are resuming a previously-interrupted autorun session. The prior nvim / network was killed mid-flight; a new agent session is now attached. Continue from where you left off — do not re-ask for approval of the plan unless something material is missing.",
    "",
    "Original user prompt:",
    "> " .. original:gsub("\n", "\n> "),
    "",
    ("Progress so far: %d / %d sprints done."):format(done, total),
  }

  if phase == "plan" then
    header[#header + 1] = ""
    header[#header + 1] = "Resume point: **plan phase** — no approved `<Tasks>` block survived the interruption. Re-emit a full `<Tasks>` block and end with `PLAN_COMPLETE`."
  elseif phase == "generate" then
    header[#header + 1] = ""
    header[#header + 1] = ("Resume point: **generate · sprint `%s`** (attempt %d). Continue implementing the sprint and end the turn with `TASK_COMPLETE:%s`, `TASK_BLOCKED:%s`, or a `QUESTION`."):format(id, retries + 1, id, id)
  elseif phase == "evaluate" then
    header[#header + 1] = ""
    header[#header + 1] = ("Resume point: **evaluate · sprint `%s`**. Complete the end-to-end evaluation and emit `EVAL_PASS:%s` or `EVAL_FAIL:%s` with a `<Feedback>` block."):format(id, id, id)
  else
    header[#header + 1] = ""
    header[#header + 1] = "Resume point: unknown phase `" .. tostring(phase) .. "` — treat as a fresh plan."
  end

  local plan_block = render_plan_block(state)
  if plan_block ~= "" then
    header[#header + 1] = ""
    header[#header + 1] = "Approved sprint plan (from prior session):"
    header[#header + 1] = ""
    header[#header + 1] = plan_block
  end

  if feedback ~= "" then
    header[#header + 1] = ""
    header[#header + 1] = ("Prior evaluator feedback for sprint `%s` — address every point:"):format(id)
    header[#header + 1] = "<Feedback>"
    header[#header + 1] = feedback
    header[#header + 1] = "</Feedback>"
  end

  return table.concat(header, "\n")
end

local function tail_turns_from_log(log_path, n)
  if not log_path then return {} end
  local fh = io.open(log_path, "r")
  if not fh then return {} end
  local content = fh:read("*a") or ""
  fh:close()
  local turns = {}
  for block in content:gmatch("─── turn [^\n]*\n(.-)\n─── turn ") do
    turns[#turns + 1] = block
  end
  local tail_block = content:match("─── turn [^\n]*\n(.-)$")
  if tail_block then turns[#turns + 1] = tail_block end
  local start = math.max(1, #turns - n + 1)
  local out = {}
  for i = start, #turns do
    local t = turns[i]
    if #t > 2000 then t = t:sub(1, 2000) .. "\n…(truncated)" end
    out[#out + 1] = t
  end
  return out
end

local function build_routine_preamble(state, log_path, extra)
  local original = state.initial_prompt or "(no original prompt recorded)"
  local lines = {
    "You are resuming a previously-interrupted routine session. Previous chat history is below for context — do not re-run tool calls already performed, just continue the conversation.",
    "",
    "Original user prompt:",
    "> " .. original:gsub("\n", "\n> "),
  }
  local tail = tail_turns_from_log(log_path, MAX_ROUTINE_TURNS)
  if #tail > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("Last %d turn(s):"):format(#tail)
    for i, t in ipairs(tail) do
      lines[#lines + 1] = ""
      lines[#lines + 1] = "--- prior turn " .. i .. " ---"
      lines[#lines + 1] = t
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "The next user message in this new session continues the conversation immediately. Do not spend a turn acknowledging the resume unless the user asks about it."
  if extra and extra.carried_refs and #extra.carried_refs > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "The user's first instruction below re-references files (`@path/...`). Open those files fresh before replying — don't assume prior-session state."
  end
  return table.concat(lines, "\n")
end

function M.build_preamble(state, log_path, extra)
  if not state then return nil end
  if state.mode == "autorun" then
    return build_autorun_preamble(state)
  elseif state.mode == "routine" then
    return build_routine_preamble(state, log_path, extra)
  end
  return "Resuming prior session. Original prompt:\n> " .. (state.initial_prompt or "(none)")
end

return M
