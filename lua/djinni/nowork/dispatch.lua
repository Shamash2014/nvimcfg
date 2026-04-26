local M = {}

function M.spawn_subdroids(parent, tasks_list, opts)
  opts = opts or {}
  local droid_mod = require("djinni.nowork.droid")

  parent.state.tasks = parent.state.tasks or {}
  parent.state.topo_order = parent.state.topo_order or {}

  for _, t in ipairs(tasks_list) do
    if not parent.state.tasks[t.id] then
      parent.state.tasks[t.id] = t
      table.insert(parent.state.topo_order, t.id)
    end

    local sub_cwd = parent.opts and parent.opts.cwd
    if opts.isolate then
      local wt_path = sub_cwd .. "/.nowork/worktrees/" .. t.id
      vim.fn.mkdir(vim.fn.fnamemodify(wt_path, ":h"), "p")
      local branch = "nowork-" .. t.id
      local obj = vim.system({ "git", "-C", sub_cwd, "worktree", "add", "-B", branch, wt_path }, { text = true }):wait()
      if obj.code == 0 then
        sub_cwd = wt_path
        t.worktree = wt_path
        t.branch = branch
      else
        vim.notify("dispatch: failed to create worktree for " .. t.id .. ": " .. (obj.stderr or "?"), vim.log.levels.ERROR)
      end
    end

    local context = t.context and table.concat(t.context, "\n") or "none"
    local implementation = t.implementation and table.concat(t.implementation, "\n") or "none"
    local skills = t.skills and table.concat(t.skills, ", ") or "none"
    local acceptance = {}
    for _, a in ipairs(t.acceptance or {}) do
      table.insert(acceptance, (a.required and "[REQ] " or "[OPT] ") .. a.text)
    end

    local sub_prompt = string.format([[
You are a worker sub-droid for task %s: %s

### Context
%s

### Implementation Blueprint
%s

### Skills to Use
%s

### Acceptance Criteria
%s

Please execute this task and keep a detailed record of your work.
]], t.id, t.desc or "untitled", context, implementation, skills, table.concat(acceptance, "\n"))

    local sub = droid_mod.new("routine", sub_prompt, {
      parent_id = parent.id,
      task_id = t.id,
      cwd = sub_cwd,
      provider = parent.opts and parent.opts.provider,
      skills = t.skills or {},
    })
    parent.state.tasks[t.id].droid_id = sub.id
    parent.state.tasks[t.id].status = "running"
    if parent._log_fh then
      parent._log_fh:write(string.format("[trace] spawned sub-droid %s for task %s in %s\n", sub.id, t.id, sub_cwd))
      parent._log_fh:flush()
    end
  end

  local qfix_share = require("djinni.nowork.qfix_share")
  qfix_share.render_tasks(parent, { title = "multitask status" })
end

return M
