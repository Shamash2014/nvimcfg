local M = {}

function M.extract_tasks_block(text)
  local interior = text:match("<Tasks>%s*\n(.-)\n?%s*</Tasks>")
  if interior then
    return "<Tasks>\n" .. interior .. "\n</Tasks>"
  end
  return text
end

function M.save_plan(edited, droid)
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

  local index_dir = vim.fn.stdpath("data") .. "/djinni-nowork"
  pcall(vim.fn.mkdir, index_dir, "p")
  local idx_fh = io.open(index_dir .. "/plan-index.txt", "a")
  if idx_fh then
    idx_fh:write(plan_file .. "\n")
    idx_fh:close()
  end

  return plan_file
end

function M.ingest_plan(edited, droid)
  local tasks, err = tasks_parser.parse_tasks(edited)
  if err or not tasks then
    vim.notify("nowork: " .. (err or "parse failed") .. " — edit the plan and resubmit", vim.log.levels.WARN)
    return nil, err
  end
  if tasks_parser.has_cycle(tasks) then
    vim.notify("nowork: cycle detected in task deps", vim.log.levels.WARN)
    return nil, "cycle"
  end
  local topo, terr = tasks_parser.topo_sort(tasks)
  if terr or not topo then
    vim.notify("nowork: " .. (terr or "topo sort failed"), vim.log.levels.WARN)
    return nil, terr
  end

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

  return tasks, nil
end

function M.dispatch(droid, edited)
  local tasks, err = M.ingest_plan(edited, droid)
  if not tasks then return end

  local plan_file = M.save_plan(edited, droid)
  if plan_file then
    droid.state.plan_file = plan_file
    droid.log_buf:append("[plan saved] " .. plan_file)
  end

  local ctx_items = require("djinni.nowork.tasks_parser").extract_context_locations(tasks, {
    cwd = droid.opts and droid.opts.cwd,
  })
  require("djinni.nowork.qfix_share").collect_to_droid(droid, {
    items = ctx_items,
    default_title = "nowork planner: " .. (droid.initial_prompt or droid.id),
    qfix_mode = "replace",
    open = false,
    log_prefix = "planner",
    notify_prefix = "nowork planner",
    empty_notify = false,
  })

  local tasks_list = {}
  for _, id in ipairs(droid.state.topo_order) do
    tasks_list[#tasks_list + 1] = droid.state.tasks[id]
  end
  require("djinni.nowork.dispatch").spawn_subdroids(droid, tasks_list, { isolate = false })

  droid.status = "done"
  pcall(function() require("djinni.nowork.archive").write_state(droid) end)
  require("djinni.nowork.status_panel").update()
  require("djinni.nowork.droid")._resume(droid, "done")
end

return M
