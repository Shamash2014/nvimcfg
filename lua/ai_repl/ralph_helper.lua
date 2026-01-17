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
    table.insert(lines, string.format("│   🔨 Implementation: %d iters", summary.phase_iterations.implementation or 0))
    table.insert(lines, string.format("│   🔍 Review: %d iters", summary.phase_iterations.review or 0))
    table.insert(lines, string.format("│   🧪 Testing: %d iters", summary.phase_iterations.testing or 0))
    table.insert(lines, string.format("│   ✅ Completion: %d iters", summary.phase_iterations.completion or 0))
  end

  table.insert(lines, "│")
  table.insert(lines, "│ Quality Gates:")
  table.insert(lines, string.format("│   Requirements: %s", quality_gates.requirements_approved and "✅" or "⏳"))
  table.insert(lines, string.format("│   Design: %s", quality_gates.design_approved and "✅" or "⏳"))
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

  if not should_continue then
    local status = ralph.get_status()

    if reason and reason:match("^requirements_complete:") then
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
      ralph.transition_to_execution(response_text)
      ralph.quality_gates.design_approved = true
      local plan_status = ralph.get_status()
      vim.schedule(function()
        show_phase_transition(buf, "design", "implementation", ralph)
        if plan_status.steps and #plan_status.steps > 0 then
          proc.ui.current_plan = plan_status.steps
          render.render_plan(buf, plan_status.steps)
        end
      end)

      local execution_prompt = ralph.get_execution_prompt()
      vim.defer_fn(function()
        if ralph.is_enabled() and not ralph.is_paused() then
          proc:send_prompt(execution_prompt, { silent = true })
        end
      end, 500)
      return true
    end

    if reason and reason:match("^review_complete:") then
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

function M.reset()
  reset_ace_cycle()
end

return M
