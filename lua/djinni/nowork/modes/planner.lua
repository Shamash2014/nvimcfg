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
  opts = opts or {}
  local items = {}
  for _, id in ipairs(droid.state.topo_order or {}) do
    local t = (droid.state.tasks or {})[id]
    if t then
      local status = t.status or "open"
      items[#items + 1] = {
        text = ("[%s] %-10s %s"):format(id, status, t.desc or ""),
        valid = 0,
      }
    end
  end
  if #items == 0 then return end
  require("djinni.nowork.qfix").set(items, {
    mode = "replace",
    open = opts.open == true,
    title = "nowork autorun tasks: " .. (droid.initial_prompt or droid.id),
  })
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

local function extract_tasks_block(text)
  local interior = text:match("<Tasks>%s*\n(.-)\n?%s*</Tasks>")
  if interior then
    return "<Tasks>\n" .. interior .. "\n</Tasks>"
  end
  return text
end

local function extract_feedback_block(text)
  local interior = text:match("<Feedback>%s*\n?(.-)\n?%s*</Feedback>")
  return interior and vim.trim(interior) or ""
end

local function save_plan(edited, droid)
  local cwd = droid.opts and droid.opts.cwd and vim.fn.isdirectory(droid.opts.cwd) == 1 and droid.opts.cwd or vim.fn.getcwd()
  local plans_dir = cwd .. "/nowork/plans"
  local ok, err = pcall(vim.fn.mkdir, plans_dir, "p")
  if not ok then return end

  local date_str = os.date("%Y-%m-%d")
  local prompt_hash = string.sub(tostring(droid.initial_prompt or "untitled"), 1, 32)
    :gsub("[^a-zA-Z0-9]", "")
    :lower()
  local base_name = string.format("%s/%s-%s", plans_dir, date_str, prompt_hash)
  local plan_file = base_name .. ".md"
  local counter = 1
  while vim.loop.fs_stat(plan_file) do
    counter = counter + 1
    plan_file = string.format("%s-%d.md", base_name, counter)
  end

  local fh, fh_err = io.open(plan_file, "w")
  if not fh then return end
  local prompt = (droid.initial_prompt or "Untitled Plan")
  fh:write("---\n")
  fh:write("title: " .. prompt:gsub("\n", " ") .. "\n")
  fh:write("date: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
  fh:write("prompt: " .. prompt:gsub("\n", " ") .. "\n")
  fh:write("---\n\n")
  fh:write(vim.trim(edited or ""))
  fh:write("\n")
  fh:close()

  return plan_file
end

local function handle_plan(text, droid)
  local name, payload = markers.detect(text)
  if name == markers.QUESTION then
    local options = markers.extract_options(text)
    require("djinni.nowork.ask").ask_and_resume(droid, vim.trim(payload or ""), options)
    return "suspend"
  end
  if name ~= markers.PLAN_COMPLETE then
    return "await_user"
  end

  local droid_mod = require("djinni.nowork.droid")
  local plan_buffer = require("djinni.nowork.plan_buffer")
  local initial_md = extract_tasks_block(text)

  plan_buffer.open({
    title = " autorun plan — <C-s> approve · <C-r> replan · <C-c> cancel ",
    footer = " <C-s> approve · <C-r> ask agent to revise per edits · <C-c> cancel ",
    content = initial_md,
    filetype = "markdown",
    extra_keys = {
      ["<C-r>"] = function(close)
        local cur = vim.api.nvim_get_current_buf()
        local edited = table.concat(vim.api.nvim_buf_get_lines(cur, 0, -1, false), "\n")
        close()
        droid.state.next_prompt = "Revise the sprint plan. My edits/notes:\n\n"
          .. edited
          .. "\n\nRe-emit a valid markdown <Tasks> block ending with `PLAN_COMPLETE`."
        droid_mod._resume(droid, "next")
      end,
    },
    on_submit = function(edited)
      local tasks, err = tasks_parser.parse(edited)
      if err or not tasks then return false, err or "parse failed" end
      if tasks_parser.has_cycle(tasks) then return false, "cycle detected in task deps" end
      local topo, terr = tasks_parser.topo_sort(tasks)
      if terr or not topo then return false, terr or "topo sort failed" end

      local tasks_map = {}
      for _, t in ipairs(tasks) do
        t.status = t.status or "open"
        tasks_map[t.id] = t
      end

      droid.state.pending_retry = false
      droid.state.tasks = tasks_map
      droid.state.topo_order = topo
      droid.state.eval_feedback = {}
      droid.state.sprint_retries = {}

      local first = next_open_task(topo, tasks_map)
      droid.state.phase = "generate"
      droid.state.current_task_id = first
      droid.state.turns_on_task = 0
      droid.state.next_prompt = "Begin sprint " .. (first or "") .. "."

      render_task_qf(droid, { open = true })

      local plan_file = save_plan(edited, droid)
      if plan_file then
        droid.state.plan_file = plan_file
        droid.log_buf:append("[plan saved] " .. plan_file)
      end

      checkpoint(droid)
      require("djinni.nowork.status_panel").update()
      droid_mod._resume(droid, "next")
      return true
    end,
    on_cancel = function()
      droid.status = "cancelled"
      droid_mod._resume(droid, "done")
    end,
  })
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
    render_task_qf(droid)
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
    render_task_qf(droid)
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
    render_task_qf(droid, { open = next_id == nil })
    if not next_id then
      local droid_mod = require("djinni.nowork.droid")
      local plan_buffer = require("djinni.nowork.plan_buffer")
      local lines = { "## Sprints", "" }
      for _, tid in ipairs(droid.state.topo_order or {}) do
        local t = (droid.state.tasks or {})[tid]
        if t then
          lines[#lines + 1] = "- [" .. tid .. "] " .. (t.desc or "") .. " — " .. (t.status or "done")
        end
      end
      local content = table.concat(lines, "\n")
      plan_buffer.open({
        title = " autorun done — <C-s> close · <C-c> cancel ",
        footer = " <C-s> close · <C-c> cancel ",
        content = content,
        filetype = "markdown",
        readonly = true,
        on_submit = function()
          droid.state.phase = "done"
          require("djinni.nowork.status_panel").update()
          droid_mod._resume(droid, "done")
          return true
        end,
        on_cancel = function()
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
      render_task_qf(droid)
      checkpoint(droid)
      droid.status = "blocked"
      return "done"
    end
    if droid.state.tasks and droid.state.tasks[id] then
      droid.state.tasks[id].status = "open"
    end
    render_task_qf(droid)
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

local function push_locations(text, droid)
  local items, title = qfix_share.extract_review(text, { cwd = droid.opts and droid.opts.cwd })
  qfix_share.collect_to_droid(droid, {
    items = items,
    title = title,
    default_title = "nowork planner: " .. (droid.initial_prompt or ""),
    qfix_mode = "replace",
    open = true,
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
    local phase = state.phase or "plan"
    local tail
    if phase == "plan" then
      tail = templates.autorun_phase_tail("plan", {})
    else
      local id = state.current_task_id
      local total = state.topo_order and #state.topo_order or 0
      local idx = id and sprint_index(state.topo_order, id) or nil
      local feedback = id and state.eval_feedback and state.eval_feedback[id] or ""
      tail = templates.autorun_phase_tail(phase, {
        current_task_id = id,
        sprint_no = idx,
        sprint_total = total > 0 and total or nil,
        eval_feedback = feedback,
        grade_threshold = opts.grade_threshold or 3,
        test_cmd = opts.test_cmd,
      })
    end
    if tail and tail ~= "" then
      return user_prompt .. "\n\n" .. tail
    end
    return user_prompt
  end,
  on_turn_end = function(text, droid)
    local phase = droid.state.phase
    local action
    if phase == "plan" then
      action = handle_plan(text, droid)
    elseif phase == "generate" then
      action = handle_generate(text, droid)
    elseif phase == "evaluate" then
      action = handle_evaluate(text, droid)
    else
      action = "done"
    end
    if action ~= "suspend" then
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
