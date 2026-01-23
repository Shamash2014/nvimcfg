-- Ralph Wiggum Mode Integration Helper
-- Hooks into agent responses to auto-continue until completion
-- Implements SDLC-compliant workflow:
--   1. Requirements: Gather context and clarify scope
--   2. Design: Plan architecture and implementation steps
--   3. Implementation: Execute steps with skill routing
--   4. Review: Code review and quality checks
--   5. Testing: Run tests and verify functionality
--   6. Completion: Final verification and summary
--
-- Implements ACE (Agentic Context Engineering) loop:
--   - Agent executes step with skillbook context
--   - Reflector analyzes outcome and extracts learnings
--   - SkillManager updates skillbook with new insights
--   - Loop continues with enriched context
--
-- Ralph Loop: Simple re-injection loop for ACP agents
--   - Stop hook intercepts agent exit
--   - Re-injects the SAME prompt until completion
--   - Completion detected via exact string match (completion_promise)
--   - Circuit breaker after N consecutive completion signals
--   - Response timeout kicks if agent stalls

local M = {}
local render = require("ai_repl.render")

local ACE_CYCLE = {
  EXECUTE = "execute",
  REFLECT = "reflect",
}

local ace_state = {
  cycle = ACE_CYCLE.EXECUTE,
  last_step_content = nil,
  last_step_outcome = nil,
  reflection_count = 0,
  max_reflections_per_step = 1,
  last_phase = nil,
}

local LOOP_PHASE = {
  PLANNING = "planning",
  AWAITING_CONFIRMATION = "awaiting_confirmation",
  EXECUTING = "executing",
}

local ralph_loop = {
  enabled = false,
  phase = nil,
  original_prompt = nil,
  plan_prompt = nil,
  execution_prompt = nil,
  completion_promise = nil,
  max_iterations = 150,
  current_iteration = 0,
  consecutive_completion_signals = 0,
  circuit_breaker_threshold = 5,
  response_timeout_ms = 60000,
  response_timer = nil,
  last_activity_time = nil,
  confirmation_callback = nil,
}

function M.stop_response_monitoring()
  if ralph_loop.response_timer then
    ralph_loop.response_timer:stop()
    ralph_loop.response_timer:close()
    ralph_loop.response_timer = nil
  end
end

function M.start_response_monitoring(proc)
  M.stop_response_monitoring()

  ralph_loop.last_activity_time = vim.uv.now()
  ralph_loop.response_timer = vim.uv.new_timer()

  ralph_loop.response_timer:start(ralph_loop.response_timeout_ms, 0, function()
    vim.schedule(function()
      if ralph_loop.enabled and proc and proc.job_id then
        local buf = proc.data.buf

        if ralph_loop.phase == LOOP_PHASE.PLANNING then
          render.append_content(buf, {
            "",
            string.format("[⏰ Ralph Loop: Response timeout (%ds) - continuing planning]",
              ralph_loop.response_timeout_ms / 1000)
          })
          M.continue_planning(proc)
        elseif ralph_loop.phase == LOOP_PHASE.EXECUTING then
          render.append_content(buf, {
            "",
            string.format("[⏰ Ralph Loop: Response timeout (%ds) - re-injecting prompt]",
              ralph_loop.response_timeout_ms / 1000)
          })
          M.continue_loop(proc)
        end
      end
    end)
  end)
end

function M.record_activity()
  if not ralph_loop.enabled then
    return
  end

  ralph_loop.last_activity_time = vim.uv.now()

  if ralph_loop.response_timer then
    ralph_loop.response_timer:stop()
    ralph_loop.response_timer:start(ralph_loop.response_timeout_ms, 0, function()
      vim.schedule(function()
        if ralph_loop.enabled then
          local proc = require("ai_repl.registry").active()
          if proc and proc.job_id then
            if ralph_loop.phase == LOOP_PHASE.PLANNING then
              M.continue_planning(proc)
            elseif ralph_loop.phase == LOOP_PHASE.EXECUTING then
              M.continue_loop(proc)
            end
          end
        end
      end)
    end)
  end
end

function M.should_exit_loop(response_text)
  if ralph_loop.current_iteration >= ralph_loop.max_iterations then
    return true, "max_iterations"
  end

  if ralph_loop.consecutive_completion_signals >= ralph_loop.circuit_breaker_threshold then
    return true, "circuit_breaker"
  end

  if response_text:match("EXIT_SIGNAL:%s*true") and ralph_loop.consecutive_completion_signals >= 1 then
    return true, "exit_signal"
  end

  return false, nil
end

function M.continue_loop(proc)
  if not ralph_loop.enabled then
    return
  end

  local prompt_to_send = ralph_loop.execution_prompt or ralph_loop.original_prompt
  if not prompt_to_send then
    return
  end

  local buf = proc.data.buf

  vim.schedule(function()
    render.append_content(buf, {
      "",
      string.format("[🔄 Ralph Loop: Iteration %d/%d]",
        ralph_loop.current_iteration + 1, ralph_loop.max_iterations)
    })
  end)

  vim.defer_fn(function()
    if ralph_loop.enabled and ralph_loop.phase == LOOP_PHASE.EXECUTING and proc and proc.job_id then
      proc:send_prompt(prompt_to_send, { silent = true })
      M.start_response_monitoring(proc)
    end
  end, 500)
end

function M.end_loop(proc, reason)
  M.stop_response_monitoring()
  ralph_loop.enabled = false

  local buf = proc.data.buf
  local phase_str = ralph_loop.phase == LOOP_PHASE.PLANNING and "planning"
    or ralph_loop.phase == LOOP_PHASE.AWAITING_CONFIRMATION and "awaiting confirmation"
    or "execution"

  local reason_msgs = {
    complete = "[✅ Ralph Loop: Completion promise matched - task complete!]",
    max_iterations = string.format("[⚠️ Ralph Loop: Max iterations reached (%d)]", ralph_loop.max_iterations),
    circuit_breaker = string.format("[🛑 Ralph Loop: Circuit breaker triggered (%d consecutive signals)]",
      ralph_loop.circuit_breaker_threshold),
    exit_signal = "[🏁 Ralph Loop: Exit signal received]",
    cancelled = string.format("[❌ Ralph Loop: Cancelled by user (was in %s phase)]", phase_str),
  }

  vim.schedule(function()
    render.append_content(buf, {
      "",
      reason_msgs[reason] or "[Ralph Loop: Ended]",
      string.format("Total execution iterations: %d", ralph_loop.current_iteration),
      "",
    })
  end)

  ralph_loop.phase = nil
  ralph_loop.original_prompt = nil
  ralph_loop.plan_prompt = nil
  ralph_loop.execution_prompt = nil
  ralph_loop.completion_promise = nil
  ralph_loop.current_iteration = 0
  ralph_loop.consecutive_completion_signals = 0
end

function M.on_agent_stop(proc, response_text)
  if not ralph_loop.enabled then
    return false
  end

  M.stop_response_monitoring()

  if ralph_loop.phase == LOOP_PHASE.PLANNING then
    local plan_ready = M.detect_plan_ready(response_text)
    if plan_ready then
      ralph_loop.phase = LOOP_PHASE.AWAITING_CONFIRMATION
      M.prompt_loop_confirmation(proc, response_text)
      return false
    end

    M.continue_planning(proc)
    return true
  end

  if ralph_loop.phase == LOOP_PHASE.AWAITING_CONFIRMATION then
    return false
  end

  if ralph_loop.phase == LOOP_PHASE.EXECUTING then
    ralph_loop.current_iteration = ralph_loop.current_iteration + 1

    if ralph_loop.completion_promise and response_text:match(vim.pesc(ralph_loop.completion_promise)) then
      ralph_loop.consecutive_completion_signals = ralph_loop.consecutive_completion_signals + 1
    else
      ralph_loop.consecutive_completion_signals = 0
    end

    local should_exit, reason = M.should_exit_loop(response_text)
    if should_exit then
      M.end_loop(proc, reason)
      return false
    end

    if ralph_loop.completion_promise and ralph_loop.consecutive_completion_signals >= 1 then
      M.end_loop(proc, "complete")
      return false
    end

    M.continue_loop(proc)
    return true
  end

  return false
end

function M.detect_plan_ready(response_text)
  if not response_text then return false end
  local ralph = require("ai_repl.modes.ralph_wiggum")
  local ready, _ = ralph.check_plan_ready(response_text)
  if ready then return true end

  local step_count = 0
  for _ in response_text:gmatch("%d+%.%s+[^\n]+") do
    step_count = step_count + 1
  end
  return step_count >= 3
end

function M.continue_planning(proc)
  if not ralph_loop.enabled then return end

  local buf = proc.data.buf
  vim.schedule(function()
    render.append_content(buf, { "", "[📋 Ralph Loop: Continuing to plan...]" })
  end)

  vim.defer_fn(function()
    if ralph_loop.enabled and ralph_loop.phase == LOOP_PHASE.PLANNING then
      local continuation = [[
Continue planning. When the plan is complete and ready for execution, output:

[PLAN_READY]

Make sure to include numbered steps for implementation.
]]
      proc:send_prompt(continuation, { silent = true })
      M.start_response_monitoring(proc)
    end
  end, 500)
end

function M.prompt_loop_confirmation(proc, plan_text)
  local buf = proc.data.buf

  vim.schedule(function()
    render.append_content(buf, {
      "",
      "┌─ 📋 Plan Ready ──────────────────────────────",
      "│",
      "│ The agent has created an implementation plan.",
      "│",
      "│ ⏳ AWAITING YOUR CONFIRMATION",
      "│",
      "│ Options:",
      "│   [Y] Confirm - Start autonomous execution loop",
      "│   [N] Reject  - Cancel the loop",
      "│   [E] Edit    - Provide feedback for revision",
      "│",
      "└────────────────────────────────────────────",
      "",
    })

    vim.ui.select(
      { "Yes - Execute the plan", "No - Cancel loop", "Edit - Provide feedback" },
      {
        prompt = "📋 Confirm execution plan?",
        format_item = function(item)
          return item
        end,
      },
      function(choice, idx)
        if not choice then
          vim.schedule(function()
            render.append_content(buf, {
              "",
              "[⏸️ Ralph Loop: Confirmation pending. Use /cancel-ralph to abort]",
            })
          end)
          return
        end

        if idx == 1 then
          M.confirm_loop_plan(proc)
        elseif idx == 2 then
          M.cancel_loop(proc)
        elseif idx == 3 then
          vim.ui.input({ prompt = "Feedback for plan revision: " }, function(feedback)
            if feedback and #feedback > 0 then
              M.revise_loop_plan(proc, feedback)
            else
              vim.schedule(function()
                render.append_content(buf, {
                  "",
                  "[⏸️ Ralph Loop: No feedback provided. Waiting for confirmation...]",
                })
              end)
            end
          end)
        end
      end
    )
  end)
end

function M.confirm_loop_plan(proc)
  if not ralph_loop.enabled then return end

  ralph_loop.phase = LOOP_PHASE.EXECUTING
  ralph_loop.current_iteration = 0
  ralph_loop.consecutive_completion_signals = 0

  local buf = proc.data.buf
  vim.schedule(function()
    render.append_content(buf, {
      "",
      "┌─ ✅ Plan Confirmed ──────────────────────────",
      "│",
      "│ Starting autonomous execution loop!",
      "│",
      string.format("│ Max iterations: %d", ralph_loop.max_iterations),
      string.format("│ Completion promise: %s", ralph_loop.completion_promise or "(none)"),
      "│",
      "│ Use /cancel-ralph to stop at any time",
      "│",
      "└────────────────────────────────────────────",
      "",
    })
  end)

  vim.defer_fn(function()
    if ralph_loop.enabled and ralph_loop.phase == LOOP_PHASE.EXECUTING then
      proc:send_prompt(ralph_loop.execution_prompt, { silent = true })
      M.start_response_monitoring(proc)
    end
  end, 500)
end

function M.revise_loop_plan(proc, feedback)
  if not ralph_loop.enabled then return end

  ralph_loop.phase = LOOP_PHASE.PLANNING

  local buf = proc.data.buf
  vim.schedule(function()
    render.append_content(buf, {
      "",
      "┌─ 🔄 Plan Revision ───────────────────────────",
      "│",
      "│ Your feedback: " .. feedback:sub(1, 50) .. (feedback:len() > 50 and "..." or ""),
      "│",
      "│ The agent will revise the plan.",
      "│",
      "└────────────────────────────────────────────",
      "",
    })
  end)

  local revision_prompt = string.format([[
The user has reviewed the plan and requested changes.

User feedback: %s

Please revise the implementation plan based on this feedback.
When the revised plan is ready, output: [PLAN_READY]
]], feedback)

  vim.defer_fn(function()
    if ralph_loop.enabled and ralph_loop.phase == LOOP_PHASE.PLANNING then
      proc:send_prompt(revision_prompt, { silent = true })
      M.start_response_monitoring(proc)
    end
  end, 500)
end

function M.start_loop(proc, prompt, opts)
  opts = opts or {}

  ralph_loop.enabled = true
  ralph_loop.phase = LOOP_PHASE.PLANNING
  ralph_loop.original_prompt = prompt
  ralph_loop.completion_promise = opts.completion_promise
  ralph_loop.max_iterations = opts.max_iterations or 150
  ralph_loop.current_iteration = 0
  ralph_loop.consecutive_completion_signals = 0
  ralph_loop.circuit_breaker_threshold = opts.circuit_breaker_threshold or 5
  ralph_loop.response_timeout_ms = opts.response_timeout_ms or 60000

  ralph_loop.plan_prompt = string.format([[
[Ralph Loop - 📋 PLANNING PHASE]

TASK: %s

Before executing, create an implementation plan:

1. **Understand the Task** - What exactly needs to be done?
2. **Break Down Steps** - Create numbered implementation steps
3. **Identify Dependencies** - What must happen in what order?
4. **Define Completion Criteria** - How do we know when it's done?

OUTPUT FORMAT:
## Implementation Plan

### Steps
1. [First step]
2. [Second step]
3. [Third step]
...

### Completion Criteria
- [How to verify completion]

When the plan is ready, output: [PLAN_READY]

DO NOT start implementation yet. Just create the plan.
]], prompt)

  ralph_loop.execution_prompt = string.format([[
[Ralph Loop - 🔨 EXECUTION PHASE]

Execute the approved plan for: %s

Work through each step systematically:
1. Execute the current step
2. Verify it completed successfully
3. Move to the next step

%s

When ALL steps are complete and the task is done, output: %s

Continue execution...
]], prompt,
    ralph_loop.completion_promise and ("When finished, include: " .. ralph_loop.completion_promise) or "",
    ralph_loop.completion_promise or "[DONE]")

  local buf = proc.data.buf
  vim.schedule(function()
    render.append_content(buf, {
      "",
      "┌─ 🔄 Ralph Loop Started ────────────────────",
      "│",
      "│ Phase: 📋 PLANNING (will ask for confirmation)",
      "│",
      string.format("│ Max iterations: %d", ralph_loop.max_iterations),
      string.format("│ Completion promise: %s", ralph_loop.completion_promise or "(none)"),
      string.format("│ Response timeout: %ds", ralph_loop.response_timeout_ms / 1000),
      "│",
      "│ Use /cancel-ralph to stop the loop",
      "│",
      "└────────────────────────────────────────────",
      "",
    })
  end)

  proc:send_prompt(ralph_loop.plan_prompt, { silent = false })
  M.start_response_monitoring(proc)
end

function M.cancel_loop(proc)
  if not ralph_loop.enabled then
    return false
  end

  M.end_loop(proc, "cancelled")
  return true
end

function M.is_loop_enabled()
  return ralph_loop.enabled
end

function M.get_loop_status()
  local phase_display = ralph_loop.phase == LOOP_PHASE.PLANNING and "📋 Planning"
    or ralph_loop.phase == LOOP_PHASE.AWAITING_CONFIRMATION and "⏳ Awaiting Confirmation"
    or ralph_loop.phase == LOOP_PHASE.EXECUTING and "🔨 Executing"
    or "Unknown"

  return {
    enabled = ralph_loop.enabled,
    phase = ralph_loop.phase,
    phase_display = phase_display,
    current_iteration = ralph_loop.current_iteration,
    max_iterations = ralph_loop.max_iterations,
    completion_promise = ralph_loop.completion_promise,
    consecutive_completion_signals = ralph_loop.consecutive_completion_signals,
  }
end

local function format_duration(seconds)
  if seconds < 60 then
    return string.format("%ds", seconds)
  elseif seconds < 3600 then
    return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
  else
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    return string.format("%dh %dm", hours, mins)
  end
end

local function sync_plan_to_ui(proc, ralph)
  local steps = ralph.get_plan_steps()
  if proc and proc.ui and #steps > 0 then
    proc.ui.current_plan = steps
    render.render_plan(proc.data.buf, steps)
  end
end

local function reset_ace_cycle()
  ace_state.cycle = ACE_CYCLE.EXECUTE
  ace_state.last_step_content = nil
  ace_state.last_step_outcome = nil
  ace_state.reflection_count = 0
end

local function should_trigger_reflection(ralph, completed_step, response_text)
  if ace_state.reflection_count >= ace_state.max_reflections_per_step then
    return false
  end
  if not completed_step then
    return false
  end
  local progress = ralph.get_steps_progress()
  if progress.total > 0 and progress.passed > 0 and progress.passed % 2 == 0 then
    return true
  end
  if response_text:lower():match("error") or response_text:lower():match("fail") then
    return true
  end
  return false
end

local function extract_outcome_summary(response_text)
  local lines = {}
  local count = 0
  for line in response_text:gmatch("[^\r\n]+") do
    if count < 10 then
      local trimmed = line:match("^%s*(.-)%s*$")
      if trimmed and #trimmed > 0 and #trimmed < 200 then
        table.insert(lines, trimmed)
        count = count + 1
      end
    end
  end
  return table.concat(lines, "\n")
end

local function show_summary(buf, ralph)
  local summary = ralph.get_summary()
  if not summary then return end

  local status = ralph.get_status()
  local skillbook = ralph.get_skillbook()
  local skill_count = #skillbook.helpful + #skillbook.harmful + #skillbook.neutral
  local quality_gates = summary.quality_gates or {}

  local lines = {
    "",
    "┌─ Ralph Wiggum Summary (SDLC) ───────────────",
    string.format("│ Total iterations: %d", summary.iterations or 0),
    string.format("│ Duration: %s", format_duration(summary.duration_seconds)),
  }

  if summary.phase_iterations then
    table.insert(lines, "│")
    table.insert(lines, "│ SDLC Phases:")
    table.insert(lines, string.format("│   📝 Requirements: %d iters", summary.phase_iterations.requirements or 0))
    table.insert(lines, string.format("│   🎨 Design: %d iters", summary.phase_iterations.design or 0))
    table.insert(lines, string.format("│   ✅ Tasks: %d iters", summary.phase_iterations.tasks or 0))
    table.insert(lines, string.format("│   🔨 Implementation: %d iters", summary.phase_iterations.implementation or 0))
    table.insert(lines, string.format("│   🔍 Review: %d iters", summary.phase_iterations.review or 0))
    table.insert(lines, string.format("│   🧪 Testing: %d iters", summary.phase_iterations.testing or 0))
    table.insert(lines, string.format("│   ✅✅ Completion: %d iters", summary.phase_iterations.completion or 0))
  end

  table.insert(lines, "│")
  table.insert(lines, "│ Quality Gates:")
  table.insert(lines, string.format("│   Requirements: %s", quality_gates.requirements_approved and "✅" or "⏳"))
  table.insert(lines, string.format("│   Design: %s", quality_gates.design_approved and "✅" or "⏳"))
  table.insert(lines, string.format("│   Tasks: %s", quality_gates.tasks_approved and "✅" or "⏳"))
  table.insert(lines, string.format("│   Implementation: %s", quality_gates.implementation_complete and "✅" or "⏳"))
  table.insert(lines, string.format("│   Review: %s", quality_gates.review_passed and "✅" or "⏳"))
  table.insert(lines, string.format("│   Tests: %s", quality_gates.tests_passed and "✅" or "⏳"))

  if status.steps_total and status.steps_total > 0 then
    table.insert(lines, "│")
    table.insert(lines, string.format("│ Steps: %d/%d completed (%d%%)", status.steps_passed, status.steps_total, status.steps_percent))
  end

  if summary.active_skill then
    table.insert(lines, "│")
    table.insert(lines, string.format("│ Active Skill: %s", summary.active_skill))
  end

  if skill_count > 0 then
    table.insert(lines, "│")
    table.insert(lines, string.format("│ Skills learned: %d (✓%d ✗%d ○%d)",
      skill_count, #skillbook.helpful, #skillbook.harmful, #skillbook.neutral))
  end

  table.insert(lines, "└────────────────────────────────────────────")
  table.insert(lines, "")
  render.append_content(buf, lines)

  if status.steps and #status.steps > 0 then
    render.render_plan(buf, status.steps)
  end

  if ralph.has_skills() then
    render.append_content(buf, { "", "📚 Skillbook:", ralph.format_skillbook(), "" })
  end
end

local function get_phase_transition_prompt(ralph, target_phase)
  if target_phase == "design" then
    return ralph.get_design_prompt()
  elseif target_phase == "implementation" then
    return ralph.get_execution_prompt()
  elseif target_phase == "review" then
    return ralph.get_review_prompt()
  elseif target_phase == "testing" then
    return ralph.get_testing_prompt()
  elseif target_phase == "completion" then
    return ralph.get_completion_prompt()
  end
  return ralph.get_continuation_prompt()
end

local function show_phase_transition(buf, from_phase, to_phase, ralph)
  local phase_info = ralph.PHASE_INFO[to_phase]
  if not phase_info then return end

  local lines = {
    "",
    string.format("┌─ %s Phase Transition ─────────────────────", from_phase:sub(1,1):upper() .. from_phase:sub(2)),
    string.format("│ %s %s phase complete", ralph.PHASE_INFO[from_phase] and ralph.PHASE_INFO[from_phase].icon or "✅", from_phase),
    string.format("│ Moving to: %s %s", phase_info.icon, phase_info.name),
    "└────────────────────────────────────────────",
    "",
  }
  render.append_content(buf, lines)
end

function M.check_and_continue(proc, response_text)
  local modes_module = require("ai_repl.modes")

  if not modes_module.is_ralph_wiggum_mode() then
    return false
  end

  local ralph = require("ai_repl.modes.ralph_wiggum")
  local buf = proc.data.buf
  local current_phase = ralph.get_phase()

  ralph.record_iteration(response_text)

  local completed_step_content = nil

  if ralph.is_planning_phase() then
    if ralph.is_design_phase() then
      local updated = ralph.update_draft_plan(response_text)
      if updated then
        vim.schedule(function()
          sync_plan_to_ui(proc, ralph)
        end)
      end
    end
    reset_ace_cycle()
  elseif ralph.is_implementation_phase() then
    local reflection = ralph.parse_reflection(response_text)
    local has_insights = #reflection.helpful > 0 or #reflection.harmful > 0 or #reflection.neutral > 0
    if has_insights then
      ralph.apply_reflection(reflection)
      local skill_count = #reflection.helpful + #reflection.harmful + #reflection.neutral
      vim.schedule(function()
        render.append_content(buf, {
          string.format("[📚 ACE SkillManager: +%d skill(s) added to skillbook]", skill_count)
        })
      end)
      ace_state.reflection_count = ace_state.reflection_count + 1
    end

    local completed_steps = ralph.detect_step_completion(response_text)
    local any_completed = false
    for _, step_desc in ipairs(completed_steps) do
      local marked, step_id = ralph.mark_step_by_pattern(step_desc:sub(1, 30))
      if marked then
        any_completed = true
        completed_step_content = step_desc
        ace_state.last_step_content = step_desc
        ace_state.last_step_outcome = extract_outcome_summary(response_text)
        ace_state.reflection_count = 0
      end
    end

    if any_completed then
      vim.schedule(function()
        sync_plan_to_ui(proc, ralph)
      end)
    end

    if ace_state.cycle == ACE_CYCLE.REFLECT then
      ace_state.cycle = ACE_CYCLE.EXECUTE
    end
  end

  local should_continue, reason = ralph.should_continue(response_text)

  if reason == "needs_more_planning" then
    local status = ralph.get_status()
    vim.schedule(function()
      render.append_content(buf, {
        "",
        string.format("[🔄 Ralph (Planning %d/%d): Need more planning iterations before proceeding...]",
          status.planning_iteration, status.min_planning_iterations),
      })
    end)

    local continuation_prompt = ralph.get_continuation_prompt()
    vim.defer_fn(function()
      if ralph.is_enabled() and not ralph.is_paused() then
        proc:send_prompt(continuation_prompt, { silent = true })
      end
    end, 500)
    return true
  end

  if not should_continue then
    local status = ralph.get_status()

    if reason and reason:match("^requirements_complete:") then
      ralph.set_artifact("requirements", response_text)
      ralph.transition_to_phase(ralph.PHASE.DESIGN)
      ralph.quality_gates.requirements_approved = true
      vim.schedule(function()
        show_phase_transition(buf, "requirements", "design", ralph)
      end)

      local design_prompt = ralph.get_design_prompt()
      vim.defer_fn(function()
        if ralph.is_enabled() and not ralph.is_paused() then
          proc:send_prompt(design_prompt, { silent = true })
        end
      end, 500)
      return true
    end

    if reason and reason:match("^design_complete:") then
      ralph.set_artifact("design", response_text)
      ralph.transition_to_tasks()
      vim.schedule(function()
        show_phase_transition(buf, "design", "tasks", ralph)
      end)

      local tasks_prompt = ralph.get_tasks_prompt()
      vim.defer_fn(function()
        if ralph.is_enabled() and not ralph.is_paused() then
          proc:send_prompt(tasks_prompt, { silent = true })
        end
      end, 500)
      return true
    end

    if reason and reason:match("^tasks_complete:") then
      ralph.set_artifact("tasks", response_text)
      ralph.set_plan(response_text)
      ralph.update_draft_plan(response_text)
      local plan_status = ralph.get_status()

      ralph.set_awaiting_confirmation(true, function()
        local execution_prompt = ralph.get_execution_prompt()
        vim.defer_fn(function()
          if ralph.is_enabled() and not ralph.is_paused() then
            proc:send_prompt(execution_prompt, { silent = true })
          end
        end, 300)
      end)

      vim.schedule(function()
        local lines = {
          "",
          "┌─ ✅ Tasks Phase Complete ────────────────────",
          "│",
          "│ Spec is ready for your review!",
          "│",
          "│ Planning phases complete:",
          "│   📝 Requirements ✓",
          "│   🎨 Design ✓",
          "│   ✅ Tasks ✓",
          "│",
        }
        if plan_status.steps_total and plan_status.steps_total > 0 then
          table.insert(lines, string.format("│ 📋 %d implementation steps identified", plan_status.steps_total))
          table.insert(lines, "│")
        end
        table.insert(lines, "│ ⏳ AWAITING YOUR CONFIRMATION")
        table.insert(lines, "│")
        table.insert(lines, "│ Options:")
        table.insert(lines, "│   [Y] Confirm - Start autonomous execution")
        table.insert(lines, "│   [N] Reject  - Go back to refine tasks")
        table.insert(lines, "│   [E] Edit    - Provide feedback for revision")
        table.insert(lines, "│")
        table.insert(lines, "└────────────────────────────────────────────")
        table.insert(lines, "")
        render.append_content(buf, lines)

        if plan_status.steps and #plan_status.steps > 0 then
          proc.ui.current_plan = plan_status.steps
          render.render_plan(buf, plan_status.steps)
        end

        M.prompt_plan_confirmation(proc)
      end)
      return false
    end

    if reason and reason:match("^review_complete:") then
      ralph.set_artifact("review_findings", response_text)
      ralph.transition_to_testing()
      vim.schedule(function()
        show_phase_transition(buf, "review", "testing", ralph)
      end)

      local testing_prompt = ralph.get_testing_prompt()
      vim.defer_fn(function()
        if ralph.is_enabled() and not ralph.is_paused() then
          proc:send_prompt(testing_prompt, { silent = true })
        end
      end, 500)
      return true
    end

    if reason and reason:match("^testing_complete:") then
      ralph.set_artifact("test_results", response_text)
      ralph.transition_to_completion()
      vim.schedule(function()
        show_phase_transition(buf, "testing", "completion", ralph)
      end)

      local completion_prompt = ralph.get_completion_prompt()
      vim.defer_fn(function()
        if ralph.is_enabled() and not ralph.is_paused() then
          proc:send_prompt(completion_prompt, { silent = true })
        end
      end, 500)
      return true
    end

    if reason == "max_iterations" then
      vim.schedule(function()
        render.append_content(buf, {
          "",
          "[⚠️ Ralph Wiggum: Max iterations reached (" .. status.iteration .. "/" .. status.max_iterations .. ")]",
        })
        show_summary(buf, ralph)
      end)
    elseif reason == "paused" then
      vim.schedule(function()
        render.append_content(buf, {
          "",
          "[⏸️ Ralph Wiggum: Paused at " .. status.phase_name .. " phase. Use /ralph resume to continue]",
        })
      end)
      return false
    elseif reason == "stuck" then
      vim.schedule(function()
        render.append_content(buf, {
          "",
          "[⚠️ Ralph Wiggum: Detected stuck loop (same response 3x). Stopping.]",
        })
        show_summary(buf, ralph)
      end)
    elseif reason and reason:match("^completed:") then
      vim.schedule(function()
        render.append_content(buf, {
          "",
          "[✅ Ralph Wiggum: SDLC Complete! (" .. status.iteration .. " iterations across " .. status.phase_order .. " phases)]",
        })
        show_summary(buf, ralph)
      end)
    end

    if reason ~= "paused" then
      ralph.disable()
    end
    return false
  end

  if ralph.is_implementation_phase() and ralph.all_steps_passed() then
    ralph.set_artifact("implementation_summary", response_text)
    ralph.transition_to_review()
    vim.schedule(function()
      show_phase_transition(buf, "implementation", "review", ralph)
    end)

    local review_prompt = ralph.get_review_prompt()
    vim.defer_fn(function()
      if ralph.is_enabled() and not ralph.is_paused() then
        proc:send_prompt(review_prompt, { silent = true })
      end
    end, 500)
    return true
  end

  local status = ralph.get_status()
  local delay = status.backoff_delay

  local trigger_reflection = not ralph.is_planning_phase()
      and should_trigger_reflection(ralph, completed_step_content, response_text)
      and ace_state.cycle == ACE_CYCLE.EXECUTE

  local skillbook = ralph.get_skillbook()
  local skill_count = #skillbook.helpful + #skillbook.harmful + #skillbook.neutral

  vim.schedule(function()
    local phase_indicator = string.format("%s %s", status.phase_icon or "🔄", status.phase_name or status.phase)

    local steps_info = ""
    if status.steps_total and status.steps_total > 0 then
      steps_info = string.format(" | Steps: %d/%d", status.steps_passed, status.steps_total)
    end

    local skills_info = ""
    if skill_count > 0 then
      skills_info = string.format(" | Skills: %d", skill_count)
    end

    local active_skill_info = ""
    if status.active_skill then
      active_skill_info = string.format(" | 🎯 %s", status.active_skill:match("([^:]+)$") or status.active_skill)
    end

    local msg = string.format(
      "[🔄 Ralph (SDLC %d/6): %s | Iter %d%s%s%s%s%s...]",
      status.phase_order or 1,
      phase_indicator,
      status.iteration + 1,
      ralph.is_implementation_phase() and ("/" .. status.max_iterations) or "",
      steps_info,
      skills_info,
      active_skill_info,
      status.stuck_count > 0 and " (backoff)" or ""
    )
    render.append_content(buf, { "", msg })
  end)

  local next_step = ralph.get_next_pending_step()
  if next_step and not trigger_reflection then
    ralph.mark_step_in_progress(next_step.id)
    vim.schedule(function()
      sync_plan_to_ui(proc, ralph)
    end)
  end

  local continuation_prompt
  if trigger_reflection and ace_state.last_step_content then
    ace_state.cycle = ACE_CYCLE.REFLECT
    continuation_prompt = ralph.get_reflection_prompt(
      ace_state.last_step_content,
      ace_state.last_step_outcome or "Step completed"
    )
  else
    ace_state.cycle = ACE_CYCLE.EXECUTE
    continuation_prompt = ralph.get_continuation_prompt()
  end

  vim.defer_fn(function()
    if ralph.is_enabled() and not ralph.is_paused() then
      proc:send_prompt(continuation_prompt, { silent = true })
    end
  end, delay)

  return true
end

return M
