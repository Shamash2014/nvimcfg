-- Ralph Wiggum Mode: SDLC-Compliant Autonomous Agent
-- Works with ALL providers (Claude, Cursor, Goose, OpenCode, Codex)
-- Follows Software Development Lifecycle with skill-based delegation:
--   Phase 1: Requirements (clarify scope, gather context)
--   Phase 2: Design (architecture, approach planning)
--   Phase 3: Implementation (code generation with skill routing)
--   Phase 4: Review (code review, quality checks)
--   Phase 5: Testing (run tests, verify functionality)
--   Phase 6: Completion (final verification, cleanup)
--
-- Implements ACE (Agentic Context Engineering) from Stanford (arXiv:2510.04618):
--   - Skillbook: evolving playbook of learned strategies (helpful/harmful/neutral)
--   - Reflector: analyzes outcomes and extracts insights after each step
--   - SkillManager: delta updates with similarity checking (grow-and-refine)
--   - Three roles: Agent, Reflector, SkillManager (same model, different prompts)
--   - Prevents context collapse via incremental updates
--
-- Skill Integration:
--   - Routes tasks to appropriate skills (debugging, UI, testing, etc.)
--   - Maintains skill context across iterations
--   - Learns from skill outcomes via ACE reflection loop

local M = {}

local PHASE = {
  REQUIREMENTS = "requirements",
  DESIGN = "design",
  TASKS = "tasks",
  IMPLEMENTATION = "implementation",
  REVIEW = "review",
  TESTING = "testing",
  COMPLETION = "completion",
}

local PHASE_ORDER = {
  [PHASE.REQUIREMENTS] = 1,
  [PHASE.DESIGN] = 2,
  [PHASE.TASKS] = 3,
  [PHASE.IMPLEMENTATION] = 4,
  [PHASE.REVIEW] = 5,
  [PHASE.TESTING] = 6,
  [PHASE.COMPLETION] = 7,
}

local PHASE_INFO = {
  [PHASE.REQUIREMENTS] = { name = "Requirements", icon = "📝", description = "Clarify scope and gather context" },
  [PHASE.DESIGN] = { name = "Design", icon = "🎨", description = "Plan architecture and approach" },
  [PHASE.TASKS] = { name = "Tasks", icon = "✅", description = "Break down into implementation steps" },
  [PHASE.IMPLEMENTATION] = { name = "Implementation", icon = "🔨", description = "Write code with skill routing" },
  [PHASE.REVIEW] = { name = "Review", icon = "🔍", description = "Code review and quality checks" },
  [PHASE.TESTING] = { name = "Testing", icon = "🧪", description = "Run tests and verify functionality" },
  [PHASE.COMPLETION] = { name = "Completion", icon = "✅✅", description = "Final verification and cleanup" },
}

local SKILL_ROUTING = {
  debugging = { patterns = { "bug", "error", "fix", "debug", "issue", "broken", "failing" }, skill = "debuggins-strategies" },
  ui = { patterns = { "ui", "component", "style", "css", "tailwind", "design", "layout", "responsive" }, skill = "ui-styling" },
  figma = { patterns = { "figma", "screenshot", "mockup", "design spec", "pixel" }, skill = "figma-screenshot-implementation" },
  testing = { patterns = { "test", "playwright", "e2e", "browser", "automation" }, skill = "playwright-skill:playwright-skill" },
}

local ralph_state = {
  enabled = false,
  paused = false,
  phase = PHASE.REQUIREMENTS,
  max_iterations = 50,
  current_iteration = 0,
  iteration_history = {},
  original_prompt = nil,
  plan = nil,
  plan_steps = {},
  last_response_hash = nil,
  stuck_count = 0,
  backoff_delay = 500,
  skillbook = {
    helpful = {},
    harmful = {},
    neutral = {},
  },
  pending_reflection = nil,
  active_skill = nil,
  skill_context = {},
  quality_gates = {
    requirements_approved = false,
    design_approved = false,
    tasks_approved = false,
    implementation_complete = false,
    review_passed = false,
    tests_passed = false,
  },
  artifacts = {
    requirements = nil,
    design = nil,
    tasks = nil,
    implementation_summary = nil,
    review_findings = nil,
    test_results = nil,
  },
  awaiting_confirmation = false,
  plan_confirmed = false,
  confirmation_callback = nil,
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
  "FULLY COMPLETE",
  "All .* complete!",
}

local PHASE_TRANSITION_PATTERNS = {
  [PHASE.REQUIREMENTS] = {
    "%[REQUIREMENTS[%s_-]?COMPLETE%]",
    "Requirements complete",
    "Requirements gathered",
    "Moving to [Dd]esign",
  },
  [PHASE.DESIGN] = {
    "%[DESIGN[%s_-]?COMPLETE%]",
    "Design complete",
    "Architecture defined",
    "Moving to [Tt]asks",
  },
  [PHASE.TASKS] = {
    "%[TASKS?[%s_-]?COMPLETE%]",
    "Tasks complete",
    "Implementation plan ready",
    "Moving to [Ii]mplementation",
    "Spec is ready",
  },
  [PHASE.IMPLEMENTATION] = {
    "%[IMPLEMENTATION[%s_-]?COMPLETE%]",
    "Implementation complete",
    "Code complete",
    "Moving to [Rr]eview",
  },
  [PHASE.REVIEW] = {
    "%[REVIEW[%s_-]?COMPLETE%]",
    "Review complete",
    "Code review passed",
    "Moving to [Tt]esting",
  },
  [PHASE.TESTING] = {
    "%[TESTS?[%s_-]?PASS%w*%]",
    "Tests? pass",
    "All tests? pass",
    "Moving to [Cc]ompletion",
  },
}

local QUALITY_GATE_PATTERNS = {
  requirements = {
    pass = { "requirements approved", "scope confirmed", "requirements look good" },
    fail = { "requirements unclear", "need more details", "missing requirements" },
  },
  design = {
    pass = { "design approved", "architecture looks good", "design is solid" },
    fail = { "design concerns", "architecture issues", "needs redesign" },
  },
  tasks = {
    pass = { "tasks approved", "plan looks good", "ready to implement", "tasks complete" },
    fail = { "missing tasks", "incomplete plan", "needs more breakdown" },
  },
  review = {
    pass = { "code looks good", "review passed", "no issues found", "lgtm" },
    fail = { "needs changes", "review failed", "issues found", "bugs detected" },
  },
  testing = {
    pass = { "tests pass", "all tests pass", "test suite green", "0 failures" },
    fail = { "tests fail", "test failures", "tests broken", "%d+ fail" },
  },
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
  ralph_state.phase = PHASE.REQUIREMENTS
  ralph_state.max_iterations = opts.max_iterations or 50
  ralph_state.current_iteration = 0
  ralph_state.iteration_history = {}
  ralph_state.original_prompt = nil
  ralph_state.plan = nil
  ralph_state.plan_steps = {}
  ralph_state.last_response_hash = nil
  ralph_state.stuck_count = 0
  ralph_state.backoff_delay = 500
  ralph_state.pending_reflection = nil
  ralph_state.active_skill = nil
  ralph_state.skill_context = {}
  ralph_state.quality_gates = {
    requirements_approved = false,
    design_approved = false,
    tasks_approved = false,
    implementation_complete = false,
    review_passed = false,
    tests_passed = false,
  }
  ralph_state.artifacts = {
    requirements = nil,
    design = nil,
    tasks = nil,
    implementation_summary = nil,
    review_findings = nil,
    test_results = nil,
  }
  return true
end

function M.disable()
  ralph_state.enabled = false
  ralph_state.paused = false
  ralph_state.phase = PHASE.REQUIREMENTS
  ralph_state.current_iteration = 0
  ralph_state.original_prompt = nil
  ralph_state.plan = nil
  ralph_state.plan_steps = {}
  ralph_state.last_response_hash = nil
  ralph_state.stuck_count = 0
  ralph_state.active_skill = nil
  ralph_state.skill_context = {}
  ralph_state.awaiting_confirmation = false
  ralph_state.plan_confirmed = false
  ralph_state.confirmation_callback = nil
end

function M.is_awaiting_confirmation()
  return ralph_state.awaiting_confirmation
end

function M.set_awaiting_confirmation(value, callback)
  ralph_state.awaiting_confirmation = value
  ralph_state.confirmation_callback = callback
end

function M.is_plan_confirmed()
  return ralph_state.plan_confirmed
end

function M.confirm_plan()
  ralph_state.plan_confirmed = true
  ralph_state.awaiting_confirmation = false
  ralph_state.quality_gates.tasks_approved = true
  ralph_state.phase = PHASE.IMPLEMENTATION
  ralph_state.current_iteration = 0
  ralph_state.stuck_count = 0
  ralph_state.last_response_hash = nil

  local callback = ralph_state.confirmation_callback
  ralph_state.confirmation_callback = nil

  return true, callback
end

function M.reject_plan(feedback)
  ralph_state.awaiting_confirmation = false
  ralph_state.plan_confirmed = false
  ralph_state.phase = PHASE.TASKS
  ralph_state.confirmation_callback = nil
  return feedback
end

function M.get_phase_info(phase_id)
  return PHASE_INFO[phase_id or ralph_state.phase]
end

function M.get_phase_order()
  return PHASE_ORDER[ralph_state.phase] or 1
end

function M.get_next_phase()
  local current_order = PHASE_ORDER[ralph_state.phase]
  for phase, order in pairs(PHASE_ORDER) do
    if order == current_order + 1 then
      return phase
    end
  end
  return nil
end

function M.advance_phase()
  local next_phase = M.get_next_phase()
  if next_phase then
    ralph_state.phase = next_phase
    return true, next_phase
  end
  return false, nil
end

function M.detect_skill_for_task(task_text)
  if not task_text then return nil end
  local lower_text = task_text:lower()

  for category, config in pairs(SKILL_ROUTING) do
    for _, pattern in ipairs(config.patterns) do
      if lower_text:match(pattern) then
        return config.skill, category
      end
    end
  end
  return nil, nil
end

function M.set_active_skill(skill_name)
  ralph_state.active_skill = skill_name
end

function M.get_active_skill()
  return ralph_state.active_skill
end

function M.add_skill_context(key, value)
  ralph_state.skill_context[key] = value
end

function M.get_skill_context()
  return ralph_state.skill_context
end

function M.check_quality_gate(gate_name, response_text)
  if not response_text or not QUALITY_GATE_PATTERNS[gate_name] then
    return nil
  end

  local lower_text = response_text:lower()

  for _, pattern in ipairs(QUALITY_GATE_PATTERNS[gate_name].pass) do
    if lower_text:match(pattern) then
      ralph_state.quality_gates[gate_name .. "_approved"] = true
      return "pass"
    end
  end

  for _, pattern in ipairs(QUALITY_GATE_PATTERNS[gate_name].fail) do
    if lower_text:match(pattern) then
      return "fail"
    end
  end

  return nil
end

function M.get_quality_gates()
  return ralph_state.quality_gates
end

function M.set_artifact(phase, content)
  if ralph_state.artifacts[phase] ~= nil then
    ralph_state.artifacts[phase] = content
  end
end

function M.get_artifacts()
  return ralph_state.artifacts
end

function M.check_phase_transition(response_text)
  if not response_text then return false, nil end

  local patterns = PHASE_TRANSITION_PATTERNS[ralph_state.phase]
  if not patterns then return false, nil end

  for _, pattern in ipairs(patterns) do
    if response_text:match(pattern) then
      return true, pattern
    end
  end

  return false, nil
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

function M.get_phase()
  return ralph_state.phase
end

function M.is_planning_phase()
  return ralph_state.phase == PHASE.REQUIREMENTS
      or ralph_state.phase == PHASE.DESIGN
      or ralph_state.phase == PHASE.TASKS
end

function M.is_execution_phase()
  return ralph_state.phase == PHASE.IMPLEMENTATION
end

function M.is_requirements_phase()
  return ralph_state.phase == PHASE.REQUIREMENTS
end

function M.is_design_phase()
  return ralph_state.phase == PHASE.DESIGN
end

function M.is_tasks_phase()
  return ralph_state.phase == PHASE.TASKS
end

function M.is_implementation_phase()
  return ralph_state.phase == PHASE.IMPLEMENTATION
end

function M.is_review_phase()
  return ralph_state.phase == PHASE.REVIEW
end

function M.is_testing_phase()
  return ralph_state.phase == PHASE.TESTING
end

function M.is_completion_phase()
  return ralph_state.phase == PHASE.COMPLETION
end

function M.set_original_prompt(prompt)
  ralph_state.original_prompt = prompt
end

function M.set_plan(plan)
  ralph_state.plan = plan
end

function M.get_plan()
  return ralph_state.plan
end

function M.set_plan_steps(steps)
  ralph_state.plan_steps = {}
  for i, step in ipairs(steps) do
    local content = step.content or step.description or step
    local status = step.status or "pending"
    ralph_state.plan_steps[i] = {
      id = i,
      content = content,
      description = content,
      status = status,
      passed = status == "completed",
    }
  end
end

function M.get_plan_steps()
  return ralph_state.plan_steps
end

function M.mark_step_passed(step_id)
  if ralph_state.plan_steps[step_id] then
    ralph_state.plan_steps[step_id].passed = true
    ralph_state.plan_steps[step_id].status = "completed"
    return true
  end
  return false
end

function M.mark_step_in_progress(step_id)
  if ralph_state.plan_steps[step_id] then
    ralph_state.plan_steps[step_id].status = "in_progress"
    return true
  end
  return false
end

function M.mark_step_by_pattern(pattern)
  for _, step in ipairs(ralph_state.plan_steps) do
    if not step.passed and (step.content or step.description):lower():match(pattern:lower()) then
      step.passed = true
      step.status = "completed"
      return true, step.id
    end
  end
  return false, nil
end

function M.get_next_pending_step()
  for _, step in ipairs(ralph_state.plan_steps) do
    if not step.passed then
      return step
    end
  end
  return nil
end

function M.all_steps_passed()
  if #ralph_state.plan_steps == 0 then
    return false
  end
  for _, step in ipairs(ralph_state.plan_steps) do
    if not step.passed then
      return false
    end
  end
  return true
end

function M.get_steps_progress()
  local total = #ralph_state.plan_steps
  local passed = 0
  local in_progress = 0
  for _, step in ipairs(ralph_state.plan_steps) do
    if step.passed or step.status == "completed" then
      passed = passed + 1
    elseif step.status == "in_progress" then
      in_progress = in_progress + 1
    end
  end
  return {
    total = total,
    passed = passed,
    in_progress = in_progress,
    remaining = total - passed,
    percent = total > 0 and math.floor((passed / total) * 100) or 0,
  }
end

function M.parse_plan_steps_from_response(response_text)
  local steps = {}
  for line in response_text:gmatch("[^\r\n]+") do
    local checkbox, content = line:match("^%s*[%-*]%s*%[([%sx ])%]%s*(.+)")
    if checkbox and content then
      local status = (checkbox == "x" or checkbox == "X") and "completed" or "pending"
      table.insert(steps, { content = content, status = status })
    else
      local step = line:match("^%s*%d+%.%s*%[%s*%]%s*(.+)$")
          or line:match("^%s*[%-%*]%s*(.+)$")
          or line:match("^%s*%d+%.%s*(.+)$")
      if step and #step > 5 and #step < 200 then
        local is_header = step:match("^%*%*") or step:match("^#")
        local is_meta = step:lower():match("^step") or step:lower():match("^plan")
        if not is_header and not is_meta then
          table.insert(steps, { content = step, status = "pending" })
        end
      end
    end
  end
  return steps
end

function M.detect_step_completion(response_text)
  local completed_steps = {}
  local patterns = {
    "%[x%]%s*(.+)",
    "%[X%]%s*(.+)",
    "%[✓%]%s*(.+)",
    "%[✔%]%s*(.+)",
    "✅%s*(.+)",
    "completed:%s*(.+)",
    "done:%s*(.+)",
    "finished:%s*(.+)",
  }
  for line in response_text:gmatch("[^\r\n]+") do
    for _, pattern in ipairs(patterns) do
      local match = line:match(pattern)
      if match then
        table.insert(completed_steps, match)
      end
    end
  end
  return completed_steps
end

function M.get_iteration_count()
  return ralph_state.current_iteration
end

function M.get_history()
  return ralph_state.iteration_history
end

function M.get_skillbook()
  return ralph_state.skillbook
end

local function normalize_skill(text)
  return text:lower():gsub("[%s%p]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function skill_similarity(a, b)
  local norm_a = normalize_skill(a)
  local norm_b = normalize_skill(b)

  if norm_a == norm_b then return 1.0 end

  local words_a = {}
  for word in norm_a:gmatch("%S+") do
    words_a[word] = true
  end

  local words_b = {}
  for word in norm_b:gmatch("%S+") do
    words_b[word] = true
  end

  local intersection = 0
  local union = 0

  for word in pairs(words_a) do
    union = union + 1
    if words_b[word] then
      intersection = intersection + 1
    end
  end
  for word in pairs(words_b) do
    if not words_a[word] then
      union = union + 1
    end
  end

  if union == 0 then return 0 end
  return intersection / union
end

local function find_similar_skill(category, new_skill, threshold)
  threshold = threshold or 0.6
  if not ralph_state.skillbook[category] then return nil, nil end

  for i, existing in ipairs(ralph_state.skillbook[category]) do
    local sim = skill_similarity(existing.content, new_skill)
    if sim >= threshold then
      return existing, i
    end
  end
  return nil, nil
end

function M.add_skill(category, skill, opts)
  opts = opts or {}
  if not ralph_state.skillbook[category] then
    ralph_state.skillbook[category] = {}
  end

  local existing, idx = find_similar_skill(category, skill, opts.similarity_threshold)

  if existing then
    existing.use_count = existing.use_count + 1
    existing.last_seen = os.time()
    if opts.merge and #skill > #existing.content then
      existing.content = skill
    end
    return false, "merged"
  end

  table.insert(ralph_state.skillbook[category], {
    content = skill,
    created_at = os.time(),
    last_seen = os.time(),
    use_count = 1,
  })
  return true, "added"
end

function M.prune_skillbook(max_per_category)
  max_per_category = max_per_category or 10

  for category, skills in pairs(ralph_state.skillbook) do
    if #skills > max_per_category then
      table.sort(skills, function(a, b)
        return (a.use_count or 0) > (b.use_count or 0)
      end)

      while #skills > max_per_category do
        table.remove(skills)
      end
    end
  end
end

function M.get_skill_stats()
  local stats = {
    total = 0,
    helpful = #ralph_state.skillbook.helpful,
    harmful = #ralph_state.skillbook.harmful,
    neutral = #ralph_state.skillbook.neutral,
    most_used = nil,
  }
  stats.total = stats.helpful + stats.harmful + stats.neutral

  local max_use = 0
  for _, category in pairs(ralph_state.skillbook) do
    for _, skill in ipairs(category) do
      if (skill.use_count or 0) > max_use then
        max_use = skill.use_count
        stats.most_used = skill.content
      end
    end
  end

  return stats
end

function M.format_skillbook()
  local lines = {}
  if #ralph_state.skillbook.helpful > 0 then
    table.insert(lines, "HELPFUL PATTERNS (what works):")
    for _, skill in ipairs(ralph_state.skillbook.helpful) do
      table.insert(lines, "  ✓ " .. skill.content)
    end
  end
  if #ralph_state.skillbook.harmful > 0 then
    table.insert(lines, "HARMFUL PATTERNS (what to avoid):")
    for _, skill in ipairs(ralph_state.skillbook.harmful) do
      table.insert(lines, "  ✗ " .. skill.content)
    end
  end
  if #ralph_state.skillbook.neutral > 0 then
    table.insert(lines, "OBSERVATIONS:")
    for _, skill in ipairs(ralph_state.skillbook.neutral) do
      table.insert(lines, "  ○ " .. skill.content)
    end
  end
  return table.concat(lines, "\n")
end

function M.has_skills()
  return #ralph_state.skillbook.helpful > 0
      or #ralph_state.skillbook.harmful > 0
      or #ralph_state.skillbook.neutral > 0
end

function M.parse_reflection(response_text)
  local reflection = {
    helpful = {},
    harmful = {},
    neutral = {},
    insights = {},
  }

  local in_section = nil
  for line in response_text:gmatch("[^\r\n]+") do
    local lower = line:lower()
    if lower:match("helpful") or lower:match("worked") or lower:match("success") then
      in_section = "helpful"
    elseif lower:match("harmful") or lower:match("avoid") or lower:match("fail") then
      in_section = "harmful"
    elseif lower:match("observation") or lower:match("note") or lower:match("learned") then
      in_section = "neutral"
    end

    local skill = line:match("^%s*[✓✔%+]%s*(.+)")
        or line:match("^%s*[✗✘%-]%s*(.+)")
        or line:match("^%s*[○•]%s*(.+)")
        or line:match("^%s*[%-%*]%s*(.+)")
    if skill and #skill > 10 and #skill < 200 then
      if in_section then
        table.insert(reflection[in_section], skill)
      else
        table.insert(reflection.insights, skill)
      end
    end
  end

  return reflection
end

function M.apply_reflection(reflection)
  for _, skill in ipairs(reflection.helpful or {}) do
    M.add_skill("helpful", skill)
  end
  for _, skill in ipairs(reflection.harmful or {}) do
    M.add_skill("harmful", skill)
  end
  for _, skill in ipairs(reflection.neutral or {}) do
    M.add_skill("neutral", skill)
  end
  for _, insight in ipairs(reflection.insights or {}) do
    M.add_skill("neutral", insight)
  end
end

function M.set_pending_reflection(step_result)
  ralph_state.pending_reflection = step_result
end

function M.get_pending_reflection()
  return ralph_state.pending_reflection
end

function M.clear_pending_reflection()
  ralph_state.pending_reflection = nil
end

function M.get_reflection_prompt(step_content, outcome)
  local skillbook_context = ""
  if M.has_skills() then
    skillbook_context = "\n\nCURRENT SKILLBOOK:\n" .. M.format_skillbook()
  end

  return string.format([[
[ACE REFLECTOR - Analyzing Step Outcome]

STEP ATTEMPTED: %s

OUTCOME:
%s
%s
Analyze what happened and extract learnings:

1. What WORKED well? (mark with ✓)
2. What should be AVOIDED? (mark with ✗)
3. What OBSERVATIONS are useful for future steps? (mark with ○)

Format your insights as:
✓ [helpful pattern or strategy that worked]
✗ [harmful pattern or mistake to avoid]
○ [neutral observation or context]

After reflection, continue with the next step.
]], step_content or "unknown step", outcome or "no outcome recorded", skillbook_context)
end

function M.check_plan_ready(response_text)
  if not response_text then return false, nil end

  for _, pattern in ipairs(PLAN_READY_PATTERNS) do
    if response_text:match(pattern) then
      return true, pattern
    end
  end

  local last_300 = response_text:sub(-300):upper()
  if last_300:match("PLAN%s*READY") or last_300:match("READY%s*TO%s*EXECUTE") then
    return true, "end_marker"
  end

  return false, nil
end

function M.update_draft_plan(response_text)
  local steps = M.parse_plan_steps_from_response(response_text)
  if #steps > 0 then
    M.set_plan_steps(steps)
    return true
  end
  return false
end

function M.transition_to_execution(response_text)
  ralph_state.phase = PHASE.IMPLEMENTATION
  ralph_state.plan = response_text
  ralph_state.current_iteration = 0
  ralph_state.stuck_count = 0
  ralph_state.last_response_hash = nil
  local steps = M.parse_plan_steps_from_response(response_text)
  if #steps > 0 then
    M.set_plan_steps(steps)
  end
end

function M.transition_to_phase(target_phase)
  if not PHASE_ORDER[target_phase] then
    return false, "Invalid phase"
  end
  ralph_state.phase = target_phase
  ralph_state.stuck_count = 0
  ralph_state.last_response_hash = nil
  return true
end

function M.transition_to_tasks()
  ralph_state.phase = PHASE.TASKS
  ralph_state.quality_gates.design_approved = true
  ralph_state.stuck_count = 0
  ralph_state.last_response_hash = nil
end

function M.transition_to_review()
  ralph_state.phase = PHASE.REVIEW
  ralph_state.quality_gates.implementation_complete = true
  ralph_state.stuck_count = 0
  ralph_state.last_response_hash = nil
end

function M.transition_to_testing()
  ralph_state.phase = PHASE.TESTING
  ralph_state.quality_gates.review_passed = true
  ralph_state.stuck_count = 0
  ralph_state.last_response_hash = nil
end

function M.transition_to_completion()
  ralph_state.phase = PHASE.COMPLETION
  ralph_state.quality_gates.tests_passed = true
  ralph_state.stuck_count = 0
  ralph_state.last_response_hash = nil
end

function M.check_completion(response_text)
  if not response_text then return false, nil end

  if M.all_steps_passed() then
    return true, "all_steps_passed"
  end

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

  if ralph_state.phase == PHASE.REQUIREMENTS then
    local transition, pattern = M.check_phase_transition(response_text)
    if transition then
      return false, "requirements_complete:" .. (pattern or "unknown")
    end
    return true, "requirements"
  end

  if ralph_state.phase == PHASE.DESIGN then
    local transition, pattern = M.check_phase_transition(response_text)
    if transition then
      return false, "design_complete:" .. (pattern or "unknown")
    end
    return true, "design"
  end

  if ralph_state.phase == PHASE.TASKS then
    local transition, pattern = M.check_phase_transition(response_text)
    if transition then
      return false, "tasks_complete:" .. (pattern or "unknown")
    end
    return true, "tasks"
  end

  if ralph_state.phase == PHASE.REVIEW then
    local transition, pattern = M.check_phase_transition(response_text)
    if transition then
      return false, "review_complete:" .. (pattern or "unknown")
    end
    return true, "review"
  end

  if ralph_state.phase == PHASE.TESTING then
    local transition, pattern = M.check_phase_transition(response_text)
    if transition then
      return false, "testing_complete:" .. (pattern or "unknown")
    end
    return true, "testing"
  end

  if ralph_state.phase == PHASE.COMPLETION then
    return false, "completed:completion_phase"
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
    phase = ralph_state.phase,
    timestamp = os.time(),
    response_length = response and #response or 0,
    response_summary = response and response:sub(1, 300) or nil,
    stuck_count = ralph_state.stuck_count,
  })
end

function M.get_planning_prompt(original_prompt)
  return M.get_requirements_prompt(original_prompt)
end

function M.get_requirements_prompt(original_prompt)
  local skill_hint = ""
  local detected_skill, category = M.detect_skill_for_task(original_prompt)
  if detected_skill then
    skill_hint = string.format("\n\n💡 Suggested skill: %s (%s)\nConsider using this skill during implementation.", detected_skill, category)
    ralph_state.active_skill = detected_skill
  end

  return string.format([[
[Ralph Wiggum - 📝 REQUIREMENTS PHASE (1/7)]

SDLC Phase: Requirements Gathering
Goal: Define what needs to be built

TASK: %s
%s

REQUIREMENTS CHECKLIST:
1. **Understand the Problem** - What exactly needs to be solved?
2. **Identify Users** - Who will use this?
3. **Core Features** - What are the essential features?
4. **Acceptance Criteria** - How do we know when it's done?
5. **Constraints** - What are the boundaries and limitations?

DO:
- Read existing code to understand patterns
- Ask clarifying questions if needed
- List functional requirements clearly
- Note any technical constraints

DON'T:
- Write implementation code yet
- Make design decisions yet
- Skip reading existing code

OUTPUT FORMAT:
## Requirements: [Feature Name]

### Problem Statement
[Clear description]

### Users
- User type 1
- User type 2

### Core Features
1. Feature 1
2. Feature 2

### Acceptance Criteria
- ✅ Criterion 1
- ✅ Criterion 2

### Constraints
[Technical/business constraints]

### Non-Functional Requirements
- Performance: [requirement]
- Security: [requirement]

When requirements are clear, say: "Requirements complete. Moving to Design..."
]], original_prompt, skill_hint)
end

function M.get_design_prompt()
  local original = ralph_state.original_prompt or "the task"
  local skillbook_context = ""
  if M.has_skills() then
    skillbook_context = "\n\nLEARNED PATTERNS:\n" .. M.format_skillbook()
  end

  local skill_hint = ""
  if ralph_state.active_skill then
    skill_hint = string.format("\n\n💡 Active skill: %s", ralph_state.active_skill)
  end

  return string.format([[
[Ralph Wiggum - 🎨 DESIGN PHASE (2/7)]

SDLC Phase: Design & Architecture
Goal: Architect the solution before breaking into tasks
%s%s

Original Task: %s

DESIGN CHECKLIST:
1. **Architecture** - How will components interact?
2. **Data Flow** - How does data move through the system?
3. **API/Interface Design** - What interfaces are needed?
4. **Technology Choices** - What tools/libraries to use?
5. **Component Breakdown** - What modules/files are needed?

DO:
- Consider multiple approaches, pick the best
- Identify potential issues early
- Define clear interfaces and data models
- Explain trade-offs in your choices

DON'T:
- Write implementation code yet
- Create task lists yet (that's next phase)
- Over-engineer the solution
- Ignore existing patterns in codebase

OUTPUT FORMAT:
## Design: [Feature Name]

### Architecture
[Description or diagram]

### Components
1. Component A
   - Purpose
   - Responsibilities

### Data Models
```typescript
interface Model {
  // fields
}
```

### API Design
```
GET /api/endpoint
POST /api/endpoint
```

### Technology Stack
- [tech choices with rationale]

### Potential Risks
- [Risk 1 and mitigation]

When design is complete, say: "Design complete. Moving to Tasks..."
]], skillbook_context, skill_hint, original)
end

function M.get_tasks_prompt()
  local original = ralph_state.original_prompt or "the task"
  local skillbook_context = ""
  if M.has_skills() then
    skillbook_context = "\n\nLEARNED PATTERNS:\n" .. M.format_skillbook()
  end

  local skill_hint = ""
  if ralph_state.active_skill then
    skill_hint = string.format("\n\n💡 Active skill: %s", ralph_state.active_skill)
  end

  return string.format([[
[Ralph Wiggum - ✅ TASKS PHASE (3/7)]

SDLC Phase: Task Breakdown
Goal: Break design into ordered implementation steps
%s%s

Original Task: %s

TASKS CHECKLIST:
1. **Ordered Steps** - Create implementation steps in correct order
2. **Dependencies** - Identify what depends on what
3. **Complexity** - Estimate each task's complexity (Low/Medium/High)
4. **Testability** - Each task should be independently verifiable

DO:
- Create specific, actionable tasks
- Include subtasks for complex items
- Mark dependencies between tasks
- Keep tasks small and focused

DON'T:
- Write implementation code yet
- Skip dependency analysis
- Create vague or overly broad tasks

OUTPUT FORMAT:
## Implementation Tasks

### 1. [Task Name] (Complexity: Low/Medium/High)
- Subtask 1
- Subtask 2
Dependencies: None

### 2. [Task Name] (Complexity: Medium)
- Subtask 1
Dependencies: Task 1

### 3. [Task Name] (Complexity: Low)
Dependencies: Tasks 1, 2

[Continue for all tasks...]

---

When tasks are ready, say: "Tasks complete! Ready for your review."

⚠️ IMPORTANT: After this, you will be asked to CONFIRM before implementation begins.
]], skillbook_context, skill_hint, original)
end

function M.get_review_prompt()
  local original = ralph_state.original_prompt or "the task"
  local plan_status = M.format_plan_status()
  local skillbook_context = ""
  if M.has_skills() then
    skillbook_context = "\n\nLEARNED PATTERNS:\n" .. M.format_skillbook()
  end

  return string.format([[
[Ralph Wiggum - 🔍 REVIEW PHASE (5/7)]

SDLC Phase: Code Review & Quality Check
Goal: Verify implementation quality before testing
%s

Original Task: %s

IMPLEMENTATION STATUS:
%s

CODE REVIEW CHECKLIST:
1. **Correctness** - Does the code do what it should?
2. **Code Quality** - Is it readable and maintainable?
3. **Error Handling** - Are edge cases handled?
4. **Security** - No vulnerabilities introduced?
5. **Performance** - No obvious performance issues?
6. **Style** - Follows codebase conventions?

DO:
- Review all changed/created files
- Check for common issues (null checks, error handling)
- Verify code matches design intent
- Look for code smells or anti-patterns

DON'T:
- Skip files thinking they're fine
- Ignore error handling
- Over-optimize prematurely

OUTPUT FORMAT:
## Review Summary
- Files reviewed: [count]
- Issues found: [count]

## Findings
### Issues to Fix
- [ ] [Issue description and location]

### Suggestions (non-blocking)
- [Suggestion]

## Verdict
[PASS/NEEDS_CHANGES]

If review passes, say: "Review complete. Moving to Testing..."
If issues found, fix them and re-review.
]], skillbook_context, original, plan_status)
end

function M.get_testing_prompt()
  local original = ralph_state.original_prompt or "the task"
  local skillbook_context = ""
  if M.has_skills() then
    skillbook_context = "\n\nLEARNED PATTERNS:\n" .. M.format_skillbook()
  end

  local test_skill_hint = ""
  if ralph_state.active_skill == "playwright-skill:playwright-skill" then
    test_skill_hint = "\n\n💡 Playwright skill active - use for E2E/browser testing"
  end

  return string.format([[
[Ralph Wiggum - 🧪 TESTING PHASE (6/7)]

SDLC Phase: Testing & Verification
Goal: Verify implementation works correctly
%s%s

Original Task: %s

TESTING CHECKLIST:
1. **Run Existing Tests** - Ensure nothing is broken
2. **Add New Tests** - Cover new functionality
3. **Manual Verification** - Test the happy path
4. **Edge Cases** - Test boundary conditions
5. **Integration** - Verify components work together

DO:
- Run the test suite first
- Add tests for new functionality
- Test error conditions
- Verify success criteria from requirements

DON'T:
- Skip running existing tests
- Only test happy path
- Ignore failing tests

OUTPUT FORMAT:
## Test Results

### Existing Tests
- Status: [PASS/FAIL]
- Details: [summary]

### New Tests Added
- [Test 1]: [description]
- [Test 2]: [description]

### Manual Verification
- [x] [Scenario tested]

## Verdict
[ALL_TESTS_PASS / TESTS_FAILING]

If all tests pass, say: "Tests pass. Moving to Completion..."
If tests fail, fix issues and re-test.
]], skillbook_context, test_skill_hint, original)
end

function M.get_completion_prompt()
  local original = ralph_state.original_prompt or "the task"
  local plan_status = M.format_plan_status()
  local progress = M.get_steps_progress()
  local quality_gates = M.get_quality_gates()

  return string.format([[
[Ralph Wiggum - ✅✅ COMPLETION PHASE (7/7)]

SDLC Phase: Final Verification & Cleanup
Goal: Confirm task is truly complete

Original Task: %s

PROGRESS:
%s
Steps: %d/%d completed

QUALITY GATES:
- Requirements: %s
- Design: %s
- Tasks: %s
- Implementation: %s
- Review: %s
- Tests: %s

COMPLETION CHECKLIST:
1. **All Steps Done** - Every planned step completed?
2. **Tests Passing** - All tests green?
3. **Code Reviewed** - Quality verified?
4. **Requirements Met** - Success criteria satisfied?
5. **Cleanup** - No debug code, temp files, etc.?

OUTPUT FORMAT:
## Completion Summary

### What Was Built
[Summary of implementation]

### Files Changed
- [file1]: [change summary]
- [file2]: [change summary]

### How to Use/Test
[Brief instructions]

### Known Limitations
[Any caveats or future work]

---
🎯 FULLY COMPLETE

End with: [DONE] or "All tasks complete!"
]], original, plan_status, progress.passed, progress.total,
    quality_gates.requirements_approved and "✅" or "⏳",
    quality_gates.design_approved and "✅" or "⏳",
    quality_gates.tasks_approved and "✅" or "⏳",
    quality_gates.implementation_complete and "✅" or "⏳",
    quality_gates.review_passed and "✅" or "⏳",
    quality_gates.tests_passed and "✅" or "⏳")
end

function M.format_plan_status()
  if #ralph_state.plan_steps == 0 then
    return ""
  end
  local lines = {}
  for _, step in ipairs(ralph_state.plan_steps) do
    local marker = step.status == "completed" and "[x]"
        or step.status == "in_progress" and "[>]"
        or "[ ]"
    table.insert(lines, string.format("- %s %s", marker, step.content))
  end
  return table.concat(lines, "\n")
end

function M.get_execution_prompt()
  local iteration = ralph_state.current_iteration + 1
  local original = ralph_state.original_prompt or "the task"
  local next_step = M.get_next_pending_step()
  local plan_status = M.format_plan_status()
  local skillbook_context = ""
  if M.has_skills() then
    skillbook_context = "\n\nLEARNED SKILLS (apply these):\n" .. M.format_skillbook() .. "\n"
  end

  local current_step_info = ""
  if next_step then
    current_step_info = string.format("\nCURRENT STEP: %s\n", next_step.content)
  end

  return string.format([[
[Ralph Wiggum - EXECUTION Phase | Iteration %d/%d]

Original task: %s
%s
PLAN STATUS:
%s
%s
Execute the current step. When the step is complete, mark it with [x]:
- [x] %s

After completing a step, briefly note what worked or should be avoided:
✓ [what worked]
✗ [what to avoid]

When ALL steps are complete, end with [DONE].
]], iteration, ralph_state.max_iterations, original, current_step_info, plan_status,
    skillbook_context, next_step and next_step.content or "current step")
end

function M.get_continuation_prompt()
  local phase_info = M.get_phase_info()
  local iteration = ralph_state.current_iteration + 1

  if ralph_state.phase == PHASE.REQUIREMENTS then
    return string.format([[
[Ralph Wiggum - %s %s | Iter %d]

Continue gathering requirements:
- Read more code if needed
- Search for relevant documentation
- Clarify any remaining questions

When requirements are clear, say: "Requirements complete. Moving to Design..."
]], phase_info.icon, phase_info.name, iteration)
  end

  if ralph_state.phase == PHASE.DESIGN then
    return string.format([[
[Ralph Wiggum - %s %s | Iter %d]

Continue designing:
- Finalize architecture decisions
- Define data models and APIs
- Identify components and their responsibilities

When design is complete, say: "Design complete. Moving to Tasks..."
]], phase_info.icon, phase_info.name, iteration)
  end

  if ralph_state.phase == PHASE.TASKS then
    local draft_steps = ralph_state.plan_steps
    if #draft_steps > 0 then
      local step_list = {}
      for _, step in ipairs(draft_steps) do
        local marker = step.status == "completed" and "[x]" or "[ ]"
        table.insert(step_list, string.format("- %s %s", marker, step.content))
      end
      return string.format([[
[Ralph Wiggum - %s %s | Iter %d]

Current task list:
%s

Refine the tasks:
- Are there missing steps?
- Are dependencies correct?
- Are complexities estimated?

When tasks are ready, say: "Tasks complete! Ready for your review."
]], phase_info.icon, phase_info.name, iteration, table.concat(step_list, "\n"))
    end

    return string.format([[
[Ralph Wiggum - %s %s | Iter %d]

Continue breaking down tasks:
- Create ordered implementation steps
- Mark dependencies between tasks
- Estimate complexity (Low/Medium/High)

When tasks are ready, say: "Tasks complete! Ready for your review."
]], phase_info.icon, phase_info.name, iteration)
  end

  if ralph_state.phase == PHASE.REVIEW then
    return string.format([[
[Ralph Wiggum - %s %s | Iter %d]

Continue code review:
- Check remaining files
- Verify error handling
- Fix any issues found

When review passes, say: "Review complete. Moving to Testing..."
]], phase_info.icon, phase_info.name, iteration)
  end

  if ralph_state.phase == PHASE.TESTING then
    return string.format([[
[Ralph Wiggum - %s %s | Iter %d]

Continue testing:
- Fix any failing tests
- Add missing test coverage
- Verify functionality works

When all tests pass, say: "Tests pass. Moving to Completion..."
]], phase_info.icon, phase_info.name, iteration)
  end

  if ralph_state.phase == PHASE.COMPLETION then
    return M.get_completion_prompt()
  end

  local original = ralph_state.original_prompt or "the task"
  local next_step = M.get_next_pending_step()
  local plan_status = M.format_plan_status()
  local progress = M.get_steps_progress()
  local skillbook_context = ""
  if M.has_skills() then
    skillbook_context = "\n\nLEARNED SKILLS:\n" .. M.format_skillbook()
  end

  local skill_hint = ""
  if ralph_state.active_skill then
    skill_hint = string.format("\n💡 Active skill: %s", ralph_state.active_skill)
  end

  local step_focus = ""
  if next_step then
    step_focus = string.format("\nFOCUS ON: %s", next_step.content)
  end

  if iteration <= 5 then
    return string.format([[
[Ralph Wiggum - 🔨 Implementation | Iter %d/%d | Steps: %d/%d]%s%s

PLAN STATUS:
%s
%s
Continue implementing. Mark completed steps with [x].
Note learnings: ✓ [worked] ✗ [avoid]
When ALL implementation steps are done, say: "Implementation complete. Moving to Review..."
]], iteration, ralph_state.max_iterations, progress.passed, progress.total, step_focus, skill_hint, plan_status, skillbook_context)

  elseif iteration <= 15 then
    return string.format([[
[Ralph Wiggum - 🔨 Implementation | Iter %d/%d | Steps: %d/%d]%s%s

PLAN STATUS:
%s
%s
Continue working on remaining steps. If blocked, explain what's blocking.
Mark completed steps with [x]. Note learnings: ✓ [worked] ✗ [avoid]
When ALL implementation steps are done, say: "Implementation complete. Moving to Review..."
]], iteration, ralph_state.max_iterations, progress.passed, progress.total, step_focus, skill_hint, plan_status, skillbook_context)

  else
    return string.format([[
[Ralph Wiggum - 🔨 Implementation | Iter %d/%d | Steps: %d/%d] - High iteration count%s%s

PLAN STATUS:
%s
%s
Please:
1. Complete the current step if possible
2. If blocked, explain what's preventing progress
3. Mark any completed steps with [x]
4. Note any learnings: ✓ [worked] ✗ [avoid]

Original task: %s

When ALL steps are complete, say: "Implementation complete. Moving to Review..."
]], iteration, ralph_state.max_iterations, progress.passed, progress.total, step_focus, skill_hint, plan_status, skillbook_context, original)
  end
end

function M.get_summary()
  if #ralph_state.iteration_history == 0 then
    return nil
  end

  local total_chars = 0
  local phase_iterations = {
    requirements = 0,
    design = 0,
    tasks = 0,
    implementation = 0,
    review = 0,
    testing = 0,
    completion = 0,
  }

  for _, entry in ipairs(ralph_state.iteration_history) do
    total_chars = total_chars + (entry.response_length or 0)
    local phase = entry.phase or PHASE.IMPLEMENTATION
    if phase_iterations[phase] then
      phase_iterations[phase] = phase_iterations[phase] + 1
    end
  end

  local start_time = ralph_state.iteration_history[1].timestamp
  local end_time = ralph_state.iteration_history[#ralph_state.iteration_history].timestamp
  local duration = end_time - start_time

  return {
    iterations = ralph_state.current_iteration,
    phase_iterations = phase_iterations,
    planning_iterations = phase_iterations.requirements + phase_iterations.design + phase_iterations.tasks,
    execution_iterations = phase_iterations.implementation + phase_iterations.review + phase_iterations.testing,
    total_response_chars = total_chars,
    duration_seconds = duration,
    original_prompt = ralph_state.original_prompt,
    had_plan = ralph_state.plan ~= nil,
    history = ralph_state.iteration_history,
    quality_gates = ralph_state.quality_gates,
    active_skill = ralph_state.active_skill,
    artifacts = ralph_state.artifacts,
  }
end

function M.get_status()
  if not ralph_state.enabled then
    return { enabled = false }
  end

  local steps_progress = M.get_steps_progress()
  local phase_info = M.get_phase_info()

  return {
    enabled = true,
    paused = ralph_state.paused,
    phase = ralph_state.phase,
    phase_name = phase_info and phase_info.name or ralph_state.phase,
    phase_icon = phase_info and phase_info.icon or "🔄",
    phase_order = PHASE_ORDER[ralph_state.phase] or 1,
    total_phases = 7,
    iteration = ralph_state.current_iteration,
    max_iterations = ralph_state.max_iterations,
    progress_pct = math.floor((ralph_state.current_iteration / ralph_state.max_iterations) * 100),
    stuck_count = ralph_state.stuck_count,
    backoff_delay = M.get_backoff_delay(),
    has_plan = ralph_state.plan ~= nil,
    steps = ralph_state.plan_steps,
    steps_total = steps_progress.total,
    steps_passed = steps_progress.passed,
    steps_remaining = steps_progress.remaining,
    steps_percent = steps_progress.percent,
    active_skill = ralph_state.active_skill,
    quality_gates = ralph_state.quality_gates,
    awaiting_confirmation = ralph_state.awaiting_confirmation,
    plan_confirmed = ralph_state.plan_confirmed,
  }
end

function M.save_state()
  return {
    enabled = ralph_state.enabled,
    paused = ralph_state.paused,
    phase = ralph_state.phase,
    max_iterations = ralph_state.max_iterations,
    current_iteration = ralph_state.current_iteration,
    iteration_history = ralph_state.iteration_history,
    original_prompt = ralph_state.original_prompt,
    plan = ralph_state.plan,
    plan_steps = ralph_state.plan_steps,
    stuck_count = ralph_state.stuck_count,
    skillbook = ralph_state.skillbook,
    active_skill = ralph_state.active_skill,
    skill_context = ralph_state.skill_context,
    quality_gates = ralph_state.quality_gates,
    artifacts = ralph_state.artifacts,
    awaiting_confirmation = ralph_state.awaiting_confirmation,
    plan_confirmed = ralph_state.plan_confirmed,
  }
end

function M.restore_state(state)
  if not state then return false end
  ralph_state.enabled = state.enabled or false
  ralph_state.paused = state.paused or false
  ralph_state.phase = state.phase or PHASE.REQUIREMENTS
  ralph_state.max_iterations = state.max_iterations or 50
  ralph_state.current_iteration = state.current_iteration or 0
  ralph_state.iteration_history = state.iteration_history or {}
  ralph_state.original_prompt = state.original_prompt
  ralph_state.plan = state.plan
  ralph_state.plan_steps = state.plan_steps or {}
  ralph_state.stuck_count = state.stuck_count or 0
  ralph_state.skillbook = state.skillbook or { helpful = {}, harmful = {}, neutral = {} }
  ralph_state.active_skill = state.active_skill
  ralph_state.skill_context = state.skill_context or {}
  ralph_state.quality_gates = state.quality_gates or {
    requirements_approved = false,
    design_approved = false,
    tasks_approved = false,
    implementation_complete = false,
    review_passed = false,
    tests_passed = false,
  }
  ralph_state.artifacts = state.artifacts or {}
  ralph_state.awaiting_confirmation = state.awaiting_confirmation or false
  ralph_state.plan_confirmed = state.plan_confirmed or false
  ralph_state.confirmation_callback = nil
  return true
end

M.PHASE = PHASE
M.PHASE_INFO = PHASE_INFO
M.PHASE_ORDER = PHASE_ORDER
M.SKILL_ROUTING = SKILL_ROUTING

return M
