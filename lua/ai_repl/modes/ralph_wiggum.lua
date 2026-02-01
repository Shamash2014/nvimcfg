-- Ralph Wiggum Mode: SDLC-Compliant Autonomous Agent
-- Works with any ACP-compatible provider
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
--
-- RLM Integration (arXiv:2512.24601):
--   - Symbolic artifact handles: metadata references instead of raw text injection
--   - Exploration strategies: peek, grep, partition+map, summarize
--   - Recursive step decomposition: complex steps self-decompose into sub-steps
--   - Context-centric task breakdown: derive steps from codebase topology
--   - Metadata-only transitions: compact summaries prevent context pollution

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

local QUESTION_FORMAT_INSTRUCTIONS = [[
When asking questions:
- Present numbered options with brief descriptions
- Mark recommended option with "(Recommended)"
- Maximum 3 questions at a time
- State your default choice and proceed if no response
]]

local EXPLORATION_STRATEGIES = [[
Exploration strategies (use in order):
1. Peek — sample file structure and entry points to understand organization
2. Grep — keyword/pattern search to narrow relevant files before deep reading
3. Partition — chunk large areas by module boundary, process each independently
4. Summarize — compress findings into constraints, key files, and decisions
]]

local SKILLBOOK_CATEGORIES = {
  { key = "helpful", title = "HELPFUL PATTERNS (what works):", icon = "✓" },
  { key = "harmful", title = "HARMFUL PATTERNS (what to avoid):", icon = "✗" },
  { key = "neutral", title = "OBSERVATIONS:", icon = "○" },
}

local PLANNING_ARTIFACT_NAMES = { "requirements", "design", "tasks" }

local MIN_PLANNING_ITERATIONS = 4
local MAX_PLANNING_ITERATIONS = 12

local ralph_state = {
  enabled = false,
  paused = false,
  phase = PHASE.REQUIREMENTS,
  max_iterations = 50,
  current_iteration = 0,
  planning_iteration = 0,
  analysis_mode = "summary",
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

local PHASE_APPROVAL_REQUIRED = {
  [PHASE.REQUIREMENTS] = false,
  [PHASE.DESIGN] = false,
  [PHASE.TASKS] = true,
  [PHASE.IMPLEMENTATION] = false,
  [PHASE.REVIEW] = false,
  [PHASE.TESTING] = false,
  [PHASE.COMPLETION] = false,
}

local phase_user_approved = {
  [PHASE.REQUIREMENTS] = false,
  [PHASE.DESIGN] = false,
  [PHASE.TASKS] = false,
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

local PLAN_READY_PATTERNS = {
  "PLAN[%s_-]?READY",
  "ready to execute",
  "plan is ready",
  "Implementation plan ready",
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

local function reset_state()
  ralph_state.paused = false
  ralph_state.phase = PHASE.REQUIREMENTS
  ralph_state.current_iteration = 0
  ralph_state.planning_iteration = 0
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
  ralph_state.awaiting_confirmation = false
  ralph_state.plan_confirmed = false
  ralph_state.confirmation_callback = nil
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
  phase_user_approved[PHASE.REQUIREMENTS] = false
  phase_user_approved[PHASE.DESIGN] = false
  phase_user_approved[PHASE.TASKS] = false
end

function M.enable(opts)
  opts = opts or {}
  reset_state()
  ralph_state.enabled = true
  ralph_state.max_iterations = opts.max_iterations or 50
  ralph_state.analysis_mode = opts.analysis_mode or "summary"
  return true
end

function M.disable()
  reset_state()
  ralph_state.enabled = false
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

function M.is_phase_approval_required(phase)
  phase = phase or ralph_state.phase
  return PHASE_APPROVAL_REQUIRED[phase] == true
end

function M.is_phase_approved(phase)
  phase = phase or ralph_state.phase
  return phase_user_approved[phase] == true
end

function M.approve_phase(phase)
  phase = phase or ralph_state.phase
  if PHASE_APPROVAL_REQUIRED[phase] then
    phase_user_approved[phase] = true
    return true
  end
  return false
end

function M.is_awaiting_phase_approval()
  local phase = ralph_state.phase
  return PHASE_APPROVAL_REQUIRED[phase] and not phase_user_approved[phase]
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
  ralph_state.artifacts[phase] = content
end

function M.get_artifacts()
  return ralph_state.artifacts
end

local function extract_artifact_metadata(content)
  if not content then return nil end
  local meta = {
    length = #content,
    line_count = select(2, content:gsub("\n", "\n")) + 1,
    key_files = {},
    decisions = {},
    constraints = {},
  }

  for file in content:gmatch("[%w_%-/]+%.[%w]+") do
    if not meta.key_files[file] then
      meta.key_files[file] = true
      meta.key_files[#meta.key_files + 1] = file
    end
  end

  for line in content:gmatch("[^\r\n]+") do
    if line:match("^%s*[%-*]%s*") or line:match("^%s*%d+%.") then
      local text = line:match("^%s*[%-*]%s*(.+)") or line:match("^%s*%d+%.%s*(.+)")
      if text and #text > 15 and #text < 150 then
        if text:lower():match("must") or text:lower():match("constraint") or text:lower():match("require") then
          table.insert(meta.constraints, text)
        elseif text:lower():match("will") or text:lower():match("chose") or text:lower():match("using") or text:lower():match("approach") then
          table.insert(meta.decisions, text)
        end
      end
    end
  end

  local max_items = 8
  while #meta.key_files > max_items do table.remove(meta.key_files) end
  while #meta.decisions > max_items do table.remove(meta.decisions) end
  while #meta.constraints > max_items do table.remove(meta.constraints) end

  return meta
end

function M.format_artifact_handle(phase_name, content)
  if not content then return "" end
  local meta = extract_artifact_metadata(content)
  if not meta then return "" end

  local lines = { string.format("### %s [%d lines]", phase_name, meta.line_count) }

  if #meta.key_files > 0 then
    table.insert(lines, "Files: " .. table.concat(meta.key_files, ", ", 1, math.min(#meta.key_files, 6)))
  end
  if #meta.constraints > 0 then
    table.insert(lines, "Constraints:")
    for i = 1, math.min(#meta.constraints, 4) do
      table.insert(lines, "  - " .. meta.constraints[i])
    end
  end
  if #meta.decisions > 0 then
    table.insert(lines, "Decisions:")
    for i = 1, math.min(#meta.decisions, 4) do
      table.insert(lines, "  - " .. meta.decisions[i])
    end
  end

  return table.concat(lines, "\n")
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

function M.is_phase(phase_name)
  return ralph_state.phase == phase_name
end

function M.is_planning_phase()
  local p = ralph_state.phase
  return p == PHASE.REQUIREMENTS or p == PHASE.DESIGN or p == PHASE.TASKS
end

function M.is_execution_phase()
  return ralph_state.phase == PHASE.IMPLEMENTATION
end

function M.is_requirements_phase() return ralph_state.phase == PHASE.REQUIREMENTS end
function M.is_design_phase() return ralph_state.phase == PHASE.DESIGN end
function M.is_tasks_phase() return ralph_state.phase == PHASE.TASKS end
function M.is_implementation_phase() return ralph_state.phase == PHASE.IMPLEMENTATION end
function M.is_review_phase() return ralph_state.phase == PHASE.REVIEW end
function M.is_testing_phase() return ralph_state.phase == PHASE.TESTING end
function M.is_completion_phase() return ralph_state.phase == PHASE.COMPLETION end

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
      sub_steps = step.sub_steps or nil,
      depth = step.depth or 0,
      parent_id = step.parent_id or nil,
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
      if step.sub_steps then
        for _, sub in ipairs(step.sub_steps) do
          if not sub.passed then
            return sub
          end
        end
        step.passed = true
        step.status = "completed"
      else
        return step
      end
    end
  end
  return nil
end

function M.decompose_step(step_id, sub_step_contents)
  local step = ralph_state.plan_steps[step_id]
  if not step then return false end

  step.sub_steps = {}
  for i, content in ipairs(sub_step_contents) do
    step.sub_steps[i] = {
      id = step_id .. "." .. i,
      content = content,
      description = content,
      status = "pending",
      passed = false,
      depth = (step.depth or 0) + 1,
      parent_id = step_id,
    }
  end
  step.status = "in_progress"
  return true
end

function M.mark_sub_step_passed(step_id, sub_step_index)
  local step = ralph_state.plan_steps[step_id]
  if not step or not step.sub_steps or not step.sub_steps[sub_step_index] then
    return false
  end
  step.sub_steps[sub_step_index].passed = true
  step.sub_steps[sub_step_index].status = "completed"

  local all_done = true
  for _, sub in ipairs(step.sub_steps) do
    if not sub.passed then
      all_done = false
      break
    end
  end
  if all_done then
    step.passed = true
    step.status = "completed"
  end
  return true
end

function M.parse_sub_steps_from_response(response_text, parent_step_id)
  local sub_steps = {}
  local in_decomposition = false
  for line in response_text:gmatch("[^\r\n]+") do
    if line:match("sub%-steps") or line:match("decompos") or line:match("breaking.*down") then
      in_decomposition = true
    end
    if in_decomposition then
      local content = line:match("^%s*%d+%.%s*(.+)$") or line:match("^%s*[%-*]%s*(.+)$")
      if content and #content > 5 and #content < 200 then
        local is_header = content:match("^%*%*") or content:match("^#")
        if not is_header then
          table.insert(sub_steps, content)
        end
      end
    end
  end
  if #sub_steps > 1 and parent_step_id then
    M.decompose_step(parent_step_id, sub_steps)
    return true
  end
  return false
end

function M.all_steps_passed()
  if #ralph_state.plan_steps == 0 then
    return false
  end
  for _, step in ipairs(ralph_state.plan_steps) do
    if step.sub_steps then
      for _, sub in ipairs(step.sub_steps) do
        if not sub.passed then return false end
      end
    elseif not step.passed then
      return false
    end
  end
  return true
end

function M.get_steps_progress()
  local total = #ralph_state.plan_steps
  local passed = 0
  local in_progress = 0
  local sub_total = 0
  local sub_passed = 0
  for _, step in ipairs(ralph_state.plan_steps) do
    if step.passed or step.status == "completed" then
      passed = passed + 1
    elseif step.status == "in_progress" then
      in_progress = in_progress + 1
    end
    if step.sub_steps then
      for _, sub in ipairs(step.sub_steps) do
        sub_total = sub_total + 1
        if sub.passed then sub_passed = sub_passed + 1 end
      end
    end
  end
  return {
    total = total,
    passed = passed,
    in_progress = in_progress,
    remaining = total - passed,
    percent = total > 0 and math.floor((passed / total) * 100) or 0,
    sub_total = sub_total,
    sub_passed = sub_passed,
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

  local existing = find_similar_skill(category, skill, opts.similarity_threshold)

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

  for _, skills in pairs(ralph_state.skillbook) do
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
  for _, cat in ipairs(SKILLBOOK_CATEGORIES) do
    local skills = ralph_state.skillbook[cat.key]
    if skills and #skills > 0 then
      table.insert(lines, cat.title)
      for _, skill in ipairs(skills) do
        table.insert(lines, "  " .. cat.icon .. " " .. skill.content)
      end
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

    local marker_content = line:match("^%s*%[helpful%]%s*(.+)")
    if marker_content and #marker_content > 5 and #marker_content < 200 then
      table.insert(reflection.helpful, marker_content)
      goto continue
    end

    marker_content = line:match("^%s*%[harmful%]%s*(.+)")
    if marker_content and #marker_content > 5 and #marker_content < 200 then
      table.insert(reflection.harmful, marker_content)
      goto continue
    end

    marker_content = line:match("^%s*%[observation%]%s*(.+)")
    if marker_content and #marker_content > 5 and #marker_content < 200 then
      table.insert(reflection.neutral, marker_content)
      goto continue
    end

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

    ::continue::
  end

  return reflection
end

function M.apply_reflection(reflection)
  local sources = {
    { "helpful", reflection.helpful },
    { "harmful", reflection.harmful },
    { "neutral", reflection.neutral },
    { "neutral", reflection.insights },
  }
  for _, source in ipairs(sources) do
    for _, skill in ipairs(source[2] or {}) do
      M.add_skill(source[1], skill)
    end
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

1. What WORKED well?
2. What should be AVOIDED?
3. What OBSERVATIONS are useful for future steps?

Format your insights as:
[helpful] pattern or strategy that worked
[harmful] pattern or mistake to avoid
[observation] useful context for future steps

After reflection, continue with the next step.
]], step_content or "unknown step", outcome or "no outcome recorded", skillbook_context)
end

function M.format_phase_summary(phase_name)
  local content = ralph_state.artifacts[phase_name]
  if not content then return "" end
  local meta = extract_artifact_metadata(content)
  if not meta then return "" end

  local parts = {}
  if #meta.key_files > 0 then
    table.insert(parts, "files:" .. table.concat(meta.key_files, ",", 1, math.min(#meta.key_files, 4)))
  end
  if #meta.constraints > 0 then
    for i = 1, math.min(#meta.constraints, 2) do
      table.insert(parts, meta.constraints[i])
    end
  end
  if #meta.decisions > 0 then
    for i = 1, math.min(#meta.decisions, 2) do
      table.insert(parts, meta.decisions[i])
    end
  end
  if #parts == 0 then
    return string.format("[%s: %d lines]", phase_name, meta.line_count)
  end
  return string.format("[%s: %s]", phase_name, table.concat(parts, " | "))
end

function M.get_phase_context_summary()
  local summaries = {}
  for _, name in ipairs(PLANNING_ARTIFACT_NAMES) do
    if ralph_state.artifacts[name] then
      table.insert(summaries, M.format_phase_summary(name))
    end
  end
  if #summaries == 0 then return "" end
  return table.concat(summaries, "\n")
end

function M.format_execution_context()
  return {
    original_prompt = ralph_state.original_prompt,
    artifacts = ralph_state.artifacts,
    plan_steps = ralph_state.plan_steps,
    skillbook = ralph_state.skillbook,
    active_skill = ralph_state.active_skill,
    quality_gates = ralph_state.quality_gates,
  }
end

function M.get_execution_injection_prompt()
  local ctx = M.format_execution_context()
  local plan_status = M.format_plan_status()
  local skillbook_text = M.has_skills() and M.format_skillbook() or ""

  local handle_parts = {}
  for _, name in ipairs(PLANNING_ARTIFACT_NAMES) do
    if ctx.artifacts[name] then
      table.insert(handle_parts, M.format_artifact_handle(name:sub(1, 1):upper() .. name:sub(2), ctx.artifacts[name]))
    end
  end
  local artifact_handles = #handle_parts > 0 and ("\n" .. table.concat(handle_parts, "\n\n")) or ""

  local skill_section = ""
  if skillbook_text ~= "" then
    skill_section = "\n\n## Learned Patterns\n" .. skillbook_text
  end

  return string.format([[
[Ralph Wiggum - 🔨 Execution | Fresh Context]

## Task
%s

## Approved Plan
%s

## Context (symbolic handles — inspect files directly when detail needed)
%s%s
---
Do NOT pause to ask questions. Decide using: codebase patterns > best practices > approved design.
Execute each step. Mark completed with [x]. Once ALL steps are done, conclude: "Implementation complete. Moving to Review..."
]], ctx.original_prompt or "Complete the task", plan_status, artifact_handles, skill_section)
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

local PHASE_GATES = {
  [PHASE.DESIGN] = "requirements_approved",
  [PHASE.TASKS] = "design_approved",
  [PHASE.REVIEW] = "implementation_complete",
  [PHASE.TESTING] = "review_passed",
  [PHASE.COMPLETION] = "tests_passed",
}

function M.transition_to_phase(target_phase)
  if not PHASE_ORDER[target_phase] then
    return false, "Invalid phase"
  end
  ralph_state.phase = target_phase
  ralph_state.stuck_count = 0
  ralph_state.last_response_hash = nil
  local gate = PHASE_GATES[target_phase]
  if gate then
    ralph_state.quality_gates[gate] = true
  end
  return true
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

  local phase = ralph_state.phase
  local phase_checks = {
    [PHASE.REQUIREMENTS] = "requirements",
    [PHASE.DESIGN] = "design",
    [PHASE.TASKS] = "tasks",
    [PHASE.REVIEW] = "review",
    [PHASE.TESTING] = "testing",
  }

  if phase_checks[phase] then
    local transition, pattern = M.check_phase_transition(response_text)
    if transition then
      if M.is_planning_phase() and M.needs_more_planning() then
        return true, "needs_more_planning"
      end
      if M.is_phase_approval_required(phase) and not M.is_phase_approved(phase) then
        return false, "awaiting_" .. phase_checks[phase] .. "_approval"
      end
      return false, phase_checks[phase] .. "_complete:" .. (pattern or "unknown")
    end
    return true, phase_checks[phase]
  end

  if phase == PHASE.COMPLETION then
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

  if M.is_planning_phase() then
    ralph_state.planning_iteration = ralph_state.planning_iteration + 1
  end

  table.insert(ralph_state.iteration_history, {
    iteration = ralph_state.current_iteration,
    phase = ralph_state.phase,
    timestamp = os.time(),
    response_length = response and #response or 0,
    response_summary = response and response:sub(1, 300) or nil,
    stuck_count = ralph_state.stuck_count,
    planning_iteration = ralph_state.planning_iteration,
  })
end

function M.get_planning_iteration()
  return ralph_state.planning_iteration
end

function M.has_significant_discoveries()
  -- Check if we have meaningful discoveries from requirements phase
  local artifacts = ralph_state.artifacts
  if artifacts.requirements then
    local req_text = artifacts.requirements
    -- Look for indicators of meaningful analysis
    return req_text:match("found") or 
           req_text:match("discovered") or 
           req_text:match("identified") or
           req_text:match("components") or
           req_text:match("architecture") or
           req_text:match("dependencies") or
           #req_text > 200  -- Substantial content
  end
  return false
end

function M.needs_more_planning()
  local min_iter = MIN_PLANNING_ITERATIONS
  local max_iter = MAX_PLANNING_ITERATIONS
  
  -- Allow adaptive iteration based on analysis mode
  if ralph_state.analysis_mode == "verbose" then
    max_iter = max_iter + 4  -- More iterations for verbose analysis
  elseif ralph_state.analysis_mode == "silent" then
    max_iter = min_iter      -- Minimum iterations for silent mode
  end
  
  -- Check if we've discovered significant information
  local has_discoveries = M.has_significant_discoveries()
  
  return ralph_state.planning_iteration < min_iter or 
         (ralph_state.planning_iteration < max_iter and not has_discoveries)
end

function M.reset_planning_iteration()
  ralph_state.planning_iteration = 0
end

function M.get_analysis_mode()
  return ralph_state.analysis_mode or "summary"
end

function M.set_analysis_mode(mode)
  ralph_state.analysis_mode = mode
end

function M.should_show_analysis(mode)
  mode = mode or "summary"
  if mode == "verbose" then return true end
  if mode == "summary" then return ralph_state.planning_iteration == 0 end
  if mode == "silent" then return false end
  return false
end

function M.get_planning_prompt(original_prompt)
  return M.get_requirements_prompt(original_prompt)
end

function M.get_requirements_prompt(original_prompt)
  local detected_skill, _ = M.detect_skill_for_task(original_prompt)
  if detected_skill then
    ralph_state.active_skill = detected_skill
  end

  return string.format([[
[📝 Requirements (1/7)]

Task: %s

%s
Present:
1. Key files and their roles
2. Constraints and dependencies
3. Ambiguities requiring clarification

%s
If no clarification is needed, state your assumptions and proceed.
Once analysis is sufficient, conclude with: "Requirements complete. Moving to Design..."
]], original_prompt, EXPLORATION_STRATEGIES, QUESTION_FORMAT_INSTRUCTIONS)
end

function M.get_design_prompt()
  local original = ralph_state.original_prompt or "the task"
  local skillbook_context = M.has_skills() and ("\n" .. M.format_skillbook()) or ""
  local req_summary = M.format_phase_summary("requirements")
  local prior_context = req_summary ~= "" and ("\n" .. req_summary .. "\n") or ""

  return string.format([[
[🎨 Design (2/7)]

Task: %s%s%s

Present your chosen approach with rationale.
Only show alternatives when tradeoffs are meaningful — present as numbered options.
Once the approach is defined, conclude with: "Design complete. Moving to Tasks..."
]], original, prior_context, skillbook_context)
end

function M.get_tasks_prompt()
  local original = ralph_state.original_prompt or "the task"
  local skillbook_context = M.has_skills() and ("\n" .. M.format_skillbook()) or ""
  local prior_context = M.get_phase_context_summary()
  local prior_section = prior_context ~= "" and ("\n" .. prior_context .. "\n") or ""

  return string.format([[
[✅ Tasks (3/7)]

Task: %s%s%s

Derive steps from codebase structure — examine file dependencies and module boundaries first.
Order by: dependency graph > module boundaries > logical sequence.
Include complexity estimate and dependencies for each step.
User reviews before execution starts.
When ready: "Tasks complete. Ready for your review."
]], original, prior_section, skillbook_context)
end

function M.get_review_prompt()
  local plan_status = M.format_plan_status()

  return string.format([[
[🔍 Review (5/7)]

%s

Review changed files for correctness, security, error handling.
Fix issues directly. Do not ask permission.
Once all issues are resolved, conclude with: "Review complete. Moving to Testing..."
]], plan_status)
end

function M.get_testing_prompt()
  return [[
[🧪 Testing (6/7)]

Run existing tests, add new tests for new functionality.
Fix failures immediately. Do not stop to report.
Once all tests pass, conclude with: "Tests pass. Moving to Completion..."
]]
end

function M.get_completion_prompt()
  local progress = M.get_steps_progress()

  return string.format([[
[✅ Completion (7/7)]

Steps: %d/%d

Summarize what was built, files changed, how to test.
End with: [DONE]
]], progress.passed, progress.total)
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
    if step.sub_steps then
      for _, sub in ipairs(step.sub_steps) do
        local sub_marker = sub.passed and "[x]" or "[ ]"
        table.insert(lines, string.format("  - %s %s", sub_marker, sub.content))
      end
    end
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
Do NOT pause to ask questions. Decide using: codebase patterns > best practices > approved design.
If a step is too complex for one pass, decompose it into sub-steps and execute each.

Execute the current step. When the step is complete, mark it with [x]:
- [x] %s

After completing a step, briefly note what worked or should be avoided:
[helpful] [what worked]
[harmful] [what to avoid]
[observation] [useful context]

When ALL steps are complete, end with [DONE].
]], iteration, ralph_state.max_iterations, original, current_step_info, plan_status,
    skillbook_context, next_step and next_step.content or "current step")
end

function M.get_continuation_prompt()
  local phase_info = M.get_phase_info()
  local iteration = ralph_state.current_iteration + 1
  local progress = M.get_steps_progress()

  if ralph_state.phase == PHASE.REQUIREMENTS then
    return string.format("[%s Requirements | Iter %d]\nContinue exploration. Present options with recommended default. Once sufficient, conclude: \"Requirements complete. Moving to Design...\"", phase_info.icon, iteration)
  end

  if ralph_state.phase == PHASE.DESIGN then
    local ctx = M.format_phase_summary("requirements")
    local ctx_line = ctx ~= "" and ("\n" .. ctx) or ""
    return string.format("[%s Design | Iter %d]%s\nContinue design. Decide autonomously where best practices are clear. Once defined, conclude: \"Design complete. Moving to Tasks...\"", phase_info.icon, iteration, ctx_line)
  end

  if ralph_state.phase == PHASE.TASKS then
    local plan_status = M.format_plan_status()
    return string.format("[%s Tasks | Iter %d]\n\n%s\n\nOnce steps are complete, conclude: \"Tasks complete. Ready for your review.\"", phase_info.icon, iteration, plan_status)
  end

  if ralph_state.phase == PHASE.REVIEW then
    return string.format("[🔍 Review | Iter %d]\nContinue review. Fix issues directly. Once resolved, conclude: \"Review complete. Moving to Testing...\"", iteration)
  end

  if ralph_state.phase == PHASE.TESTING then
    return string.format("[🧪 Testing | Iter %d]\nContinue testing. Fix failures immediately. Once passing, conclude: \"Tests pass. Moving to Completion...\"", iteration)
  end

  if ralph_state.phase == PHASE.COMPLETION then
    return M.get_completion_prompt()
  end

  local plan_status = M.format_plan_status()
  local next_step = M.get_next_pending_step()
  local focus = next_step and ("\nFocus: " .. next_step.content) or ""

  return string.format([[
[🔨 Implementation | Iter %d/%d | %d/%d steps]%s

%s

Do not stop to ask questions. Mark completed with [x]. Once all steps done, conclude: "Implementation complete. Moving to Review..."
]], iteration, ralph_state.max_iterations, progress.passed, progress.total, focus, plan_status)
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
    planning_iteration = ralph_state.planning_iteration,
    min_planning_iterations = MIN_PLANNING_ITERATIONS,
    needs_more_planning = M.needs_more_planning(),
    phase_approval_required = M.is_phase_approval_required(),
    phase_approved = M.is_phase_approved(),
    awaiting_phase_approval = M.is_awaiting_phase_approval(),
  }
end

function M.save_state()
  return {
    enabled = ralph_state.enabled,
    paused = ralph_state.paused,
    phase = ralph_state.phase,
    max_iterations = ralph_state.max_iterations,
    current_iteration = ralph_state.current_iteration,
    planning_iteration = ralph_state.planning_iteration,
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
  ralph_state.planning_iteration = state.planning_iteration or 0
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
M.MIN_PLANNING_ITERATIONS = MIN_PLANNING_ITERATIONS
M.MAX_PLANNING_ITERATIONS = MAX_PLANNING_ITERATIONS

return M
