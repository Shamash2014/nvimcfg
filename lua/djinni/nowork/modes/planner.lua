local markers = require("djinni.nowork.markers")
local log_render = require("djinni.nowork.log_render")
local qfix_share = require("djinni.nowork.qfix_share")
local tasks_parser = require("djinni.nowork.tasks_parser")
local templates = require("djinni.nowork.templates")

local function checkpoint(droid)
  pcall(function()
    require("djinni.nowork.archive").write_state(droid)
  end)
end

local function render_task_qf(droid, opts)
  qfix_share.render_tasks(droid, vim.tbl_extend("force", { title = "planner tasks" }, opts or {}))
end

local function auto_respond(params, respond, allow_kinds)
  local kind = params and params.toolCall and params.toolCall.kind
  local options = params and params.options or {}
  local target_id
  local allowed = false
  if kind then
    for _, k in ipairs(allow_kinds or {}) do
      if k == kind then
        allowed = true
        break
      end
    end
  end
  for _, opt in ipairs(options) do
    if allowed and (opt.kind == "allow_once" or opt.kind == "allow_always") then
      target_id = opt.optionId
      break
    elseif not allowed and (opt.kind == "reject_once" or opt.kind == "reject_always") then
      target_id = opt.optionId
      break
    end
  end
  if not target_id and options[1] then target_id = options[1].optionId end
  respond({ outcome = { outcome = "selected", optionId = target_id } })
end

local function next_open_task(topo_order, tasks_map)
  for _, id in ipairs(topo_order) do
    local t = tasks_map[id]
    if t and t.status ~= "to_verify" and t.status ~= "done" then
      return id
    end
  end
  return nil
end

local function sprint_index(topo_order, id)
  for i, tid in ipairs(topo_order or {}) do
    if tid == id then return i end
  end
  return nil
end

local function extract_feedback_block(text)
  local interior = text:match("<Feedback>%s*\n?(.-)\n?%s*</Feedback>")
  return interior and vim.trim(interior) or ""
end

local function handle_plan(text, droid)
  local name, payload = markers.detect(text)
  if name == markers.QUESTION then
    local options = markers.extract_options(text)
    require("djinni.nowork.ask").ask_and_resume(droid, vim.trim(payload or ""), options)
    return "suspend"
  end

  local existing = droid.state.plan_compose
  local has_existing = existing and existing.alive and existing.release

  if name ~= markers.PLAN_COMPLETE then
    if has_existing then
      existing.release()
      return "suspend"
    end
    return "await_user"
  end

  local compose = require("djinni.nowork.compose")
  local initial_md = require("djinni.nowork.compose_planner").extract_tasks_block(text)

  if has_existing then
    existing.release(initial_md)
    return "suspend"
  end

  compose.open_plan(droid, { initial = initial_md })
  return "suspend"
end

local function handle_generate(text, droid)
  local name, payload = markers.detect(text)
  local cap = droid.opts.turns_per_task_cap or 8

  if not name then
    droid.state.turns_on_task = (droid.state.turns_on_task or 0) + 1
    if droid.state.turns_on_task >= cap then
      droid.log_buf:append("[halt] cap hit on " .. tostring(droid.state.current_task_id))
      droid.status = "blocked"
      return "done"
    end
    droid.state.next_prompt = "Continue."
    return "next"
  end

  if name == markers.TASK_COMPLETE then
    local id = payload and vim.trim(payload) or droid.state.current_task_id
    if droid.state.tasks and droid.state.tasks[id] then
      droid.state.tasks[id].status = "to_verify"
    end
    -- render_task_qf(droid)
    droid.state.phase = "evaluate"
    droid.state.current_task_id = id
    droid.state.turns_on_task = 0
    droid.state.next_prompt = "Evaluate sprint " .. id .. "."
    checkpoint(droid)
    require("djinni.nowork.status_panel").update()
    return "next"
  end

  if name == markers.TASK_BLOCKED then
    droid.log_buf:append("[blocked] " .. tostring(payload))
    local id = payload and vim.trim(payload) or droid.state.current_task_id
    if id and droid.state.tasks and droid.state.tasks[id] then
      droid.state.tasks[id].status = "blocked"
    end
    -- render_task_qf(droid)
    checkpoint(droid)
    droid.status = "blocked"
    return "done"
  end

  if name == markers.QUESTION then
    local options = markers.extract_options(text)
    require("djinni.nowork.ask").ask_and_resume(droid, vim.trim(payload or ""), options)
    return "suspend"
  end

  droid.state.turns_on_task = (droid.state.turns_on_task or 0) + 1
  if droid.state.turns_on_task >= cap then
    droid.log_buf:append("[halt] cap hit on " .. tostring(droid.state.current_task_id))
    droid.status = "blocked"
    return "done"
  end
  droid.state.next_prompt = "Continue."
  return "next"
end

local function handle_evaluate(text, droid)
  local name, payload = markers.detect(text)
  if name == markers.QUESTION then
    local options = markers.extract_options(text)
    require("djinni.nowork.ask").ask_and_resume(droid, vim.trim(payload or ""), options)
    return "suspend"
  end

  if name == markers.EVAL_PASS then
    local id = payload and vim.trim(payload) or droid.state.current_task_id
    if id and droid.state.tasks and droid.state.tasks[id] then
      droid.state.tasks[id].status = "done"
    end
    local next_id = next_open_task(droid.state.topo_order or {}, droid.state.tasks or {})
    -- render_task_qf(droid, { open = next_id == nil })
    if not next_id then
      local droid_mod = require("djinni.nowork.droid")
      local compose = require("djinni.nowork.compose")
      local lines = { "## Sprints", "" }
      for _, tid in ipairs(droid.state.topo_order or {}) do
        local t = (droid.state.tasks or {})[tid]
        if t then
          lines[#lines + 1] = "- [" .. tid .. "] " .. (t.desc or "") .. " — " .. (t.status or "done")
        end
      end
      local content = table.concat(lines, "\n")
      compose.open(droid, {
        title = " planner done — all sprints complete ",
        label = "planner",
        initial = content,
        on_submit = function()
          droid.state.phase = "done"
          require("djinni.nowork.status_panel").update()
          droid_mod._resume(droid, "done")
        end,
        on_close = function()
          droid.status = "cancelled"
          droid_mod._resume(droid, "done")
        end,
      })
      return "suspend"
    end
    droid.state.phase = "generate"
    droid.state.current_task_id = next_id
    droid.state.turns_on_task = 0
    droid.state.next_prompt = "Begin sprint " .. next_id .. "."
    checkpoint(droid)
    require("djinni.nowork.status_panel").update()
    return "next"
  end

  if name == markers.EVAL_FAIL then
    local id = payload and vim.trim(payload) or droid.state.current_task_id
    local feedback = extract_feedback_block(text)
    droid.state.eval_feedback = droid.state.eval_feedback or {}
    droid.state.eval_feedback[id] = feedback
    droid.state.sprint_retries = droid.state.sprint_retries or {}
    local retries = (droid.state.sprint_retries[id] or 0) + 1
    droid.state.sprint_retries[id] = retries
    local retry_cap = droid.opts.sprint_retry_cap or 3
    if retries > retry_cap then
      droid.log_buf:append("[halt] sprint retry cap hit on " .. tostring(id))
      if droid.state.tasks and droid.state.tasks[id] then
        droid.state.tasks[id].status = "blocked"
      end
      -- render_task_qf(droid)
      checkpoint(droid)
      droid.status = "blocked"
      return "done"
    end
    if droid.state.tasks and droid.state.tasks[id] then
      droid.state.tasks[id].status = "open"
    end
    -- render_task_qf(droid)
    droid.state.phase = "generate"
    droid.state.current_task_id = id
    droid.state.turns_on_task = 0
    droid.state.next_prompt = ("Evaluator rejected sprint %s (attempt %d/%d). Address the feedback and re-run the sprint."):format(id, retries, retry_cap)
    checkpoint(droid)
    require("djinni.nowork.status_panel").update()
    return "next"
  end

  droid.state.turns_on_task = (droid.state.turns_on_task or 0) + 1
  local cap = droid.opts.turns_per_task_cap or 8
  if droid.state.turns_on_task >= cap then
    droid.log_buf:append("[halt] eval cap hit on " .. tostring(droid.state.current_task_id))
    droid.status = "blocked"
    return "done"
  end
  droid.state.next_prompt = "Continue evaluation."
  return "next"
end

local function handle_validate(text, droid)
  local name, payload = markers.detect(text)
  if name == markers.QUESTION then
    local options = markers.extract_options(text)
    require("djinni.nowork.ask").ask_and_resume(droid, vim.trim(payload or ""), options)
    return "suspend"
  end

  if name == markers.VALIDATION_PASSED then
    droid.log_buf:append("[validate] passed")
    local first = next_open_task(droid.state.topo_order or {}, droid.state.tasks or {})
    droid.state.phase = "generate"
    droid.state.current_task_id = first
    droid.state.turns_on_task = 0
    droid.state.next_prompt = "Validation passed. Begin sprint " .. (first or "") .. "."
    checkpoint(droid)
    require("djinni.nowork.status_panel").update()
    return "next"
  end

  if name == markers.VALIDATION_FAILED then
    droid.log_buf:append("[validate] failed: " .. tostring(payload or ""))
    droid.state.next_prompt = "Validation failed. Revise the plan or tasks based on your findings and re-emit the <Tasks> block."
    -- We stay in validate phase until it passes or they replan
    return "next"
  end

  droid.state.next_prompt = "Continue validation."
  return "next"
end

local function push_locations(text, droid)
  local items, title = qfix_share.extract_review(text, { cwd = droid.opts and droid.opts.cwd })
  qfix_share.collect_to_droid(droid, {
    items = items,
    title = title,
    default_title = "nowork planner: " .. (droid.initial_prompt or ""),
    qfix_mode = "replace",
    open = false,
    log_prefix = "planner",
    notify_prefix = "nowork planner",
    empty_notify = false,
  })
end

return {
  name = "planner",
  tail_stream = false,
  log_render = log_render.render_slices,
  template_wrap = function(user_prompt, state, opts)
    state = state or {}
    opts = opts or {}
    local phase = state.phase or "plan"
    local tail
    if phase == "plan" then
      tail = templates.leader_phase_tail("plan", {})
    else
      local id = state.current_task_id
      local total = state.topo_order and #state.topo_order or 0
      local idx = id and sprint_index(state.topo_order, id) or nil
      local feedback = id and state.eval_feedback and state.eval_feedback[id] or ""
      tail = templates.leader_phase_tail(phase, {
        current_task_id = id,
        sprint_no = idx,
        sprint_total = total > 0 and total or nil,
        eval_feedback = feedback,
        grade_threshold = opts.grade_threshold,
      })
    end
    return user_prompt .. "\n\n" .. (tail or "")
  end,
  on_turn_end = function(text, droid)
    local phase = droid.state.phase or "plan"
    local action
    if phase == "plan" then
      action = handle_plan(text, droid)
    elseif phase == "generate" then
      action = handle_generate(text, droid)
    elseif phase == "evaluate" then
      action = handle_evaluate(text, droid)
    elseif phase == "validate" then
      action = handle_validate(text, droid)
    elseif phase == "dispatched" then
      action = "done"
    else
      action = "done"
    end
    if action ~= "suspend" and phase ~= "plan" then
      push_locations(text, droid)
    end
    return action
  end,
  on_permission = function(params, respond, droid)
    local kind = params and params.toolCall and params.toolCall.kind
    local allow = kind == "read" or kind == "search" or kind == "fetch" or kind == "think"
    local options = params and params.options or {}
    local target_id
    if kind then
      for _, k in ipairs(allow and { kind } or {}) do
        -- already determined above
      end
    end
    for _, opt in ipairs(options) do
      if allow and (opt.kind == "allow_once" or opt.kind == "allow_always") then
        target_id = opt.optionId
        break
      elseif not allow and (opt.kind == "reject_once" or opt.kind == "reject_always") then
        target_id = opt.optionId
        break
      end
    end
    if not target_id and options[1] then target_id = options[1].optionId end
    respond({ outcome = { outcome = "selected", optionId = target_id } })
  end,
}
