local M = {}

M.defaults = {
  provider = "claude",
  log_buffer = { split = "below", height = 15, hidden_default = true },
  compose = {
    floating = true,
    split = "below",
    border = {
      { " ", "FloatBorder" }, { " ", "FloatBorder" }, { " ", "FloatBorder" },
      { " ", "FloatBorder" }, { " ", "FloatBorder" }, { " ", "FloatBorder" },
      { " ", "FloatBorder" }, { " ", "FloatBorder" },
    },
  },
  explore = { absolute_paths = true, copen_on_first_hit = true },
  routine = {
    skills = {},
    test_cmd = "make test",
  },
}

M.config = vim.tbl_extend("force", {}, M.defaults)

local function merged_opts(opts)
  local merged = vim.tbl_deep_extend("force", M.config, opts or {})
  if not (opts and opts.cwd) and not merged.cwd then
    merged.cwd = vim.fn.getcwd()
  end
  return merged
end

local function plan_mode_for(opts)
  local provider = opts and opts.provider or M.config.provider
  local p = require("djinni.acp.provider").get(provider)
  return (p and p.plan_mode) or "plan"
end

local function with_plan_mode(merged)
  merged.initial_acp_mode = merged.initial_acp_mode or plan_mode_for(merged)
  return merged
end

function M.explore(prompt, opts)
  if not prompt or prompt == "" then
    return M.launch("explore")
  end
  local droid = require("djinni.nowork.droid")
  return droid.new("planner", prompt, with_plan_mode(merged_opts(opts)))
end

function M.planner(prompt, opts)
  if not prompt or prompt == "" then
    return M.launch("planner")
  end
  local droid = require("djinni.nowork.droid")
  return droid.new("planner", prompt, with_plan_mode(merged_opts(opts)))
end

function M.routine(prompt, opts)
  if not prompt or prompt == "" then
    return M.launch("routine")
  end
  local droid = require("djinni.nowork.droid")
  return droid.new("routine", prompt, merged_opts(opts))
end

function M.multitask(prompt, opts)
  if not prompt or prompt == "" then
    return M.launch("multitask")
  end
  opts = opts or {}
  opts.multitask = true
  return M.routine(prompt, opts)
end

function M.run_plan(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local plans = require("djinni.nowork.plans")
  local plan_path = opts.plan_path or plans.current_plan_path(cwd)
  if not plan_path then
    plans.pick(cwd, function(p)
      M.run_plan(vim.tbl_extend("force", opts, { plan_path = p }))
    end)
    return
  end
  local plan_text = plans.read(plan_path)
  if not plan_text or vim.trim(plan_text) == "" then
    vim.notify("nowork: plan is empty: " .. plan_path, vim.log.levels.WARN)
    return
  end

  local plan_name = vim.fn.fnamemodify(plan_path, ":t")
  local prompt_parts = {
    "Implement the following plan (" .. plan_name .. ").",
    "Mark tasks as you complete them by editing " .. plan_path .. " (replace `- [ ]` with `- [x]`).",
    "",
    "## Plan",
    "",
    plan_text,
  }

  if opts.selection and opts.selection ~= "" then
    table.insert(prompt_parts, "")
    table.insert(prompt_parts, "## Selection context")
    table.insert(prompt_parts, "")
    table.insert(prompt_parts, opts.selection)
  end

  local prompt = table.concat(prompt_parts, "\n")
  local routine_opts = merged_opts({
    cwd = cwd,
    plan_snapshot = plan_text,
    plan_path = plan_path,
  })
  return M.routine(prompt, routine_opts)
end

function M.projects()
  local roots = {}
  local seen = {}

  local function add(root)
    root = root and vim.fn.fnamemodify(root, ":p"):gsub("/$", "") or nil
    if not root or root == "" or seen[root] then return end
    seen[root] = true
    roots[#roots + 1] = root
  end

  add(vim.fn.getcwd())
  local ok_projects, projects = pcall(require, "djinni.integrations.projects")
  if ok_projects and projects and projects.get then
    for _, root in ipairs(projects.get() or {}) do
      add(root)
    end
  end
  table.sort(roots)

  local items = {}
  local processed = {}

  for _, root in ipairs(roots) do
    if not processed[root] then
      local worktrees = {}
      local ok, wt_obj = pcall(function()
        return vim.system({ "git", "-C", root, "worktree", "list", "--porcelain" }, { text = true }):wait()
      end)

      if ok and wt_obj and wt_obj.code == 0 then
        local current = {}
        for line in wt_obj.stdout:gmatch("([^\n]*)\n") do
          if line:match("^worktree ") then
            current.path = vim.fn.fnamemodify(line:match("^worktree (.+)$"), ":p"):gsub("/$", "")
          elseif line:match("^branch ") then
            current.branch = line:match("^branch refs/heads/(.+)$")
          elseif line == "" then
            if current.path then table.insert(worktrees, current) end
            current = {}
          end
        end
      end

      if #worktrees > 1 then
        -- Find the "parent" (main worktree)
        local parent = worktrees[1].path
        items[#items + 1] = { label = "📁 " .. vim.fn.fnamemodify(parent, ":t"), path = parent, is_parent = true }
        processed[parent] = true
        for i = 1, #worktrees do
          local wt = worktrees[i]
          local name = vim.fn.fnamemodify(wt.path, ":t")
          local branch = wt.branch and (" [" .. wt.branch .. "]") or ""
          local prefix = (i == #worktrees) and "  └─ " or "  ├─ "
          items[#items + 1] = { label = prefix .. name .. branch, path = wt.path }
          processed[wt.path] = true
        end
      else
        items[#items + 1] = { label = "📄 " .. vim.fn.fnamemodify(root, ":t"), path = root }
        processed[root] = true
      end
    end
  end

  local labels = {}
  for _, it in ipairs(items) do labels[#labels + 1] = it.label end

  require("djinni.integrations.snacks_ui").select(labels, { prompt = "nowork projects & worktrees" }, function(_, idx)
    local it = idx and items[idx] or nil
    if not it then return end
    local root = it.path
    vim.cmd("lcd " .. vim.fn.fnameescape(root))
    vim.cmd("Oil " .. vim.fn.fnameescape(root))
  end)
end

local MODE_LABELS = { explore = "planner", routine = "routine", planner = "planner", plan = "plan", multitask = "routine" }
local MODE_DROID = { explore = "planner", routine = "routine", planner = "planner", plan = "routine", multitask = "routine" }

function M.launch(mode_name)
  if not MODE_DROID[mode_name] then
    vim.notify("nowork.launch: unknown mode '" .. tostring(mode_name) .. "'", vim.log.levels.WARN)
    return
  end

  local providers = require("djinni.acp.provider").list()
  local default = M.config.provider

  local function after_provider(provider)
    local label = " nowork " .. (MODE_LABELS[mode_name] or mode_name)
    if provider then label = label .. " [" .. provider .. "] " end
    require("djinni.nowork.compose").open(nil, {
      title = label,
      label = mode_name,
      on_submit = function(text)
        local spawn_opts = merged_opts({ provider = provider })
        if mode_name == "multitask" then spawn_opts.multitask = true end
        if mode_name == "plan" or mode_name == "routine" or mode_name == "planner" then
          spawn_opts.initial_acp_mode = plan_mode_for(spawn_opts)
        end
        local droid_mode = MODE_DROID[mode_name]
        require("djinni.nowork.droid").new(droid_mode, text, spawn_opts)
      end,
    })
  end

  if #providers <= 1 then
    after_provider(providers[1] or default)
    return
  end

  table.sort(providers, function(a, b)
    if a == default then return true end
    if b == default then return false end
    return a < b
  end)

  Snacks.picker.select(providers, { prompt = "nowork provider" }, function(chosen)
    if chosen then after_provider(chosen) end
  end)
end

local function get_visual_selection()
  local save = vim.fn.getreg("v")
  local savetype = vim.fn.getregtype("v")
  vim.cmd('noautocmd silent normal! "vy')
  local text = vim.fn.getreg("v")
  vim.fn.setreg("v", save, savetype)
  return text
end

local function resolve_target()
  local droid = require("djinni.nowork.droid")
  return droid.by_buf(vim.api.nvim_get_current_buf())
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})

  require("djinni.nowork.qf_virt").setup()

  do
    local expr = "%{%v:lua.require'djinni.nowork.statusline'.component()%}"
    local cur = vim.o.statusline or ""
    if not cur:find("djinni.nowork.statusline", 1, true) then
      if cur == "" then
        vim.o.statusline = "%<%f %h%w%m%r %=%-14.(%l,%c%V%) %P " .. expr
      else
        vim.o.statusline = cur .. " " .. expr
      end
    end
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("DjinniNoworkArchive", { clear = true }),
    callback = function()
      local droid = require("djinni.nowork.droid")
      local archive_ok, archive = pcall(require, "djinni.nowork.archive")
      for _, d in pairs(droid.active or {}) do
        pcall(function()
          if archive_ok and archive and archive.write_state then
            archive.write_state(d)
          end
        end)
        pcall(function()
          if d._log_fh then
            d._log_fh:close()
            d._log_fh = nil
          end
          if d._log_path and d.log_buf and vim.api.nvim_buf_is_valid(d.log_buf.buf) then
            local lines = vim.api.nvim_buf_get_lines(d.log_buf.buf, 0, -1, false)
            local fh = io.open(d._log_path, "w")
            if fh then
              local initial = (d.initial_prompt or ""):gsub("\n", " ")
              fh:write("# nowork session ", d.id, "\n")
              fh:write("# mode: ", d.mode or "?", "\n")
              fh:write("# status: ", d.status or "?", "\n")
              fh:write("# started_at: ", os.date("%Y-%m-%dT%H:%M:%S", d.started_at or os.time()), "\n")
              fh:write("# initial_prompt: ", initial, "\n\n")
              fh:write(table.concat(lines, "\n"))
              fh:close()
            end
          end
        end)
      end
      pcall(function()
        require("djinni.acp.session").shutdown_all()
      end)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    group = vim.api.nvim_create_augroup("DjinniNoworkQfRefine", { clear = true }),
    callback = function(args)
      local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
      if not info or info.loclist == 1 then return end
      local title = vim.fn.getqflist({ title = 0 }).title or ""
      local orig = title:match("^nowork explore: (.+)$")
      if not orig then return end
      vim.keymap.set("n", "r", function()
        require("djinni.nowork.compose").open(nil, {
          title = " refine explore ",
          initial = orig .. "\n\nalso include: ",
          alt_buf = vim.fn.bufnr("#"),
          on_submit = function(text)
            if text and text ~= "" then M.explore(text, {}) end
          end,
        })
      end, { buffer = args.buf, desc = "nowork: refine explore" })
    end,
  })

  vim.api.nvim_create_user_command("Nowork", function(info)
    local args = vim.split(vim.trim(info.args), "%s+", { trimempty = true })
    local mode = args[1]
    table.remove(args, 1)
    local prompt = table.concat(args, " ")
    if mode == "explore" then
      M.explore(prompt, {})
    elseif mode == "routine" then
      M.routine(prompt, {})
    elseif mode == "planner" or mode == "plan" then
      M.planner(prompt, {})
    else
      vim.notify("nowork: unknown mode '" .. tostring(mode) .. "'. Use: explore, routine", vim.log.levels.WARN)
    end
  end, { nargs = "+" })

  vim.api.nvim_create_user_command("NoworkSay", function(info)
    local droid = require("djinni.nowork.droid")
    local picker = require("djinni.nowork.picker")
    local text = info.args
    local target = resolve_target()
    if target then
      droid.say(target, text)
    else
      picker.pick({ on_droid = function(d) droid.say(d, text) end })
    end
  end, { nargs = "+" })

  vim.api.nvim_create_user_command("NoworkCancel", function()
    local droid = require("djinni.nowork.droid")
    local picker = require("djinni.nowork.picker")
    local target = resolve_target()
    if target then
      droid.cancel(target)
    else
      picker.pick({ on_droid = function(d) droid.cancel(d) end })
    end
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("NoworkDone", function()
    local droid = require("djinni.nowork.droid")
    local picker = require("djinni.nowork.picker")
    local target = resolve_target()
    if target then
      droid.done(target)
    else
      picker.pick({ on_droid = function(d) droid.done(d) end })
    end
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("NoworkModel", function()
    local picker = require("djinni.nowork.picker")
    local target = resolve_target()
    if target then
      require("djinni.nowork.model_picker").pick(target)
    else
      picker.pick({ on_droid = function(d) require("djinni.nowork.model_picker").pick(d) end })
    end
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("NoworkPicker", function()
    local picker = require("djinni.nowork.picker")
    picker.pick()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("NoworkChatToQfix", function(info)
    local parser = require("djinni.nowork.parser")
    local qfix = require("djinni.nowork.qfix")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local text = table.concat(lines, "\n")
    local items = parser.parse(text, { cwd = vim.fn.getcwd() })
    qfix.set(items, {
      mode = info.bang and "append" or "replace",
      open = true,
      title = "nowork",
    })
  end, { nargs = 0, bang = true })

  vim.api.nvim_create_user_command("NoworkQfixFromLog", function()
    local picker = require("djinni.nowork.picker")
    picker.pick({ on_droid = function(d)
      require("djinni.nowork.qfix_share").pull_from_droid(d)
    end })
  end, { nargs = 0 })

  vim.keymap.set("n", "<leader>as", function() require("djinni.nowork.plans").start_flow(vim.fn.getcwd()) end, { desc = "nowork: start plan flow (compose → save to plans/)" })
  vim.keymap.set("n", "<leader>aS", function() M.launch("plan") end, { desc = "nowork: chat-plan (legacy launcher)" })
  vim.keymap.set("n", "<leader>aw", function() M.launch("routine") end, { desc = "nowork: routine" })

  vim.keymap.set("n", "<leader>ar", function() M.run_plan({}) end, { desc = "nowork: run agent on plan.md" })
  vim.keymap.set("x", "<leader>ar", function()
    local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
    if l1 > l2 then l1, l2 = l2, l1 end
    vim.cmd("normal! \27")
    local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
    M.run_plan({ selection = table.concat(lines, "\n") })
  end, { desc = "nowork: run agent on plan.md (with visual selection as context)" })

  vim.keymap.set("n", "<leader>ae", function() require("djinni.nowork.events").open() end, { desc = "nowork: events (permissions + questions + blocked)" })

  vim.keymap.set("n", "<leader>av", function()
    local droid_mod = require("djinni.nowork.droid")
    local d = droid_mod.by_buf(vim.api.nvim_get_current_buf())
    if not d then
      for _, cand in pairs(droid_mod.active) do
        if cand.mode == "routine" then d = cand; break end
      end
    end
    if not d then
      vim.notify("nowork: no active routine droid", vim.log.levels.WARN)
      return
    end
    require("djinni.nowork.routine_review").open(d)
  end, { desc = "nowork: review routine droid diff" })

  vim.keymap.set("x", "<leader>av", function()
    local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
    if l1 > l2 then l1, l2 = l2, l1 end
    vim.cmd("normal! \27")
    local bufname = vim.fn.expand("%:.")
    local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
    local ft = vim.bo.filetype or ""
    local snippet = table.concat({
      "From `" .. bufname .. ":" .. l1 .. "-" .. l2 .. "`:",
      "",
      "```" .. ft,
      table.concat(lines, "\n"),
      "```",
      "",
    }, "\n")
    require("djinni.nowork.capture").route(snippet)
  end, { desc = "nowork: capture selection → routine droid" })

  vim.keymap.set("n", "<leader>aa", function()
    require("djinni.nowork.picker").pick({
      include_history = true,
      include_archive = true,
    })
  end, { desc = "nowork: logs (active + recent + archive)" })

  local function open_overview(mode, label)
    require("djinni.nowork.overview").open({ mode = mode, label = label })
  end

  vim.keymap.set("n", "<leader>ao", M.projects, { desc = "nowork: projects" })

  vim.keymap.set("n", "<leader>ao", M.projects, { desc = "nowork: projects" })

  vim.keymap.set("n", "<leader>ai", function()
    require("djinni.nowork.droid").current(function(d)
      if d then require("djinni.nowork.picker").run_action(d) end
    end)
  end, { desc = "nowork: per-droid actions menu (interact)" })

  vim.keymap.set("n", "<leader>ak", function()
    local droid = require("djinni.nowork.droid")
    local targets = {}
    for id, d in pairs(droid.active or {}) do
      if d.mode == "routine" then targets[#targets + 1] = id end
    end
    if #targets == 0 then
      vim.notify("nowork: no active routines", vim.log.levels.INFO)
      return
    end
    local choice = vim.fn.confirm(
      ("Cancel %d routine(s)?"):format(#targets),
      "&Cancel routines\n&Keep",
      2
    )
    if choice ~= 1 then return end
    for _, id in ipairs(targets) do
      pcall(droid.cancel, id)
    end
    vim.notify(("nowork: cancelled %d routine(s)"):format(#targets), vim.log.levels.INFO)
  end, { desc = "nowork: kill all routines" })

  vim.keymap.set("n", "<leader>ac", function()
    local picker = require("djinni.nowork.picker")
    local compose = require("djinni.nowork.compose")
    local alt_buf = vim.fn.bufnr("#")
    if picker.count({ mode_filter = { "routine" } }) == 0 then
      compose.open(nil, {
        alt_buf = alt_buf,
        title = " compose → new routine droid ",
        sections = { "Summary", "Review", "Observation", "Tasks" },
        on_submit = function(text) M.routine(text, {}) end,
      })
      return
    end
    picker.pick({
      mode_filter = { "routine" },
      on_droid = function(d)
        compose.toggle(d, { alt_buf = alt_buf })
      end,
    })
  end, { desc = "nowork: chat composer (routine persistent)" })

  local function share_qflist_guard()
    local info = vim.fn.getqflist({ items = 0 })
    if #(info.items or {}) == 0 then
      vim.notify("nowork: quickfix list is empty", vim.log.levels.WARN)
      return false
    end
    local picker = require("djinni.nowork.picker")
    local filter = { "routine" }
    if picker.count({ mode_filter = filter }) == 0 then
      vim.notify("nowork: no routine droids — start one with <leader>aw", vim.log.levels.WARN)
      return false
    end
    return true
  end

  vim.keymap.set("n", "<leader>yq", function()
    if not share_qflist_guard() then return end
    local share = require("djinni.nowork.qfix_share")
    local marks = require("djinni.nowork.qf_marks")
    local use_marks = marks.has_marks()
    require("djinni.nowork.picker").pick({
      mode_filter = { "routine" },
      on_droid = function(d)
        if use_marks then share.share_marked(d) else share.share_full(d) end
      end,
    })
  end, { desc = "nowork: share qflist to droid" })

  vim.keymap.set("x", "<leader>yq", function()
    if vim.bo.filetype ~= "qf" then
      vim.notify("nowork: yq visual only works in quickfix window", vim.log.levels.WARN)
      return
    end
    local l1 = vim.fn.line("v")
    local l2 = vim.fn.line(".")
    if l1 > l2 then l1, l2 = l2, l1 end
    vim.cmd("normal! \27")
    if not share_qflist_guard() then return end
    require("djinni.nowork.picker").pick({
      mode_filter = { "routine" },
      on_droid = function(d) require("djinni.nowork.qfix_share").share_range(d, l1, l2) end,
    })
  end, { desc = "nowork: share qf range to droid" })

  vim.keymap.set("n", "<leader>yQ", function()
    local picker = require("djinni.nowork.picker")
    if picker.count() == 0 then
      vim.notify("nowork: no active droids", vim.log.levels.WARN)
      return
    end
    picker.pick({ on_droid = function(d)
      local bag = d.state and d.state.touched
      if bag and bag.items and #bag.items > 0 then
        require("djinni.nowork.qfix_share").flush_touched(d)
      else
        require("djinni.nowork.qfix_share").pull_from_droid(d)
      end
    end })
  end, { desc = "nowork: pull from droid (touched→qflist or log parse)" })

  vim.api.nvim_create_user_command("NoworkPopulate", function()
    local picker = require("djinni.nowork.picker")
    picker.pick({ on_droid = function(d)
      require("djinni.nowork.qfix_share").populate(d)
    end })
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("NoworkQueueClear", function()
    local picker = require("djinni.nowork.picker")
    picker.pick({ mode_filter = { "routine" }, on_droid = function(d)
      require("djinni.nowork.droid").clear_queue(d)
    end })
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("NoworkShadow", function()
    local picker = require("djinni.nowork.picker")
    picker.pick({ mode_filter = { "routine" }, on_droid = function(d)
      require("djinni.nowork.shadow").review(d)
    end })
  end, { nargs = 0 })


  vim.api.nvim_create_user_command("NoworkMailbox", function()
    require("djinni.nowork.events").open()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("NoworkSummarizeWorklogs", function()
    require("djinni.nowork.worklog_summary").summarize_all({ cwd = vim.fn.getcwd() })
  end, { nargs = 0 })

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("NoworkQfMarks", { clear = true }),
    pattern = "qf",
    callback = function(args)
      local qm = require("djinni.nowork.qf_marks")
      vim.keymap.set("n", "m", function()
        qm.toggle(vim.fn.line("."))
      end, { buffer = args.buf, desc = "nowork: toggle qf mark" })
      vim.keymap.set("x", "m", function()
        local l1 = vim.fn.line("v")
        local l2 = vim.fn.line(".")
        if l1 > l2 then l1, l2 = l2, l1 end
        vim.cmd("normal! \27")
        qm.toggle_range(l1, l2)
      end, { buffer = args.buf, desc = "nowork: toggle qf marks (range)" })
      vim.keymap.set("n", "M", function() qm.clear() end, { buffer = args.buf, desc = "nowork: clear qf marks" })

      local function qf_delete(l1, l2)
        local info = vim.fn.getqflist({ items = 0, id = 0 })
        local items = info.items or {}
        local id = info.id
        local new = {}
        for i, item in ipairs(items) do
          if i < l1 or i > l2 then new[#new + 1] = item end
        end
        vim.fn.setqflist({}, "r", { id = id, items = new })
        local next = math.min(l1, #new)
        if next > 0 then vim.api.nvim_win_set_cursor(0, { next, 0 }) end
      end

      vim.keymap.set("n", "dd", function()
        local l = vim.fn.line(".")
        qf_delete(l, l)
      end, { buffer = args.buf, desc = "nowork: delete qf entry" })

      vim.keymap.set("x", "d", function()
        local l1 = vim.fn.line("v")
        local l2 = vim.fn.line(".")
        if l1 > l2 then l1, l2 = l2, l1 end
        vim.cmd("normal! \27")
        qf_delete(l1, l2)
      end, { buffer = args.buf, desc = "nowork: delete qf entries" })

      vim.keymap.set("n", "X", function()
        local info = vim.fn.getqflist({ id = 0 })
        vim.fn.setqflist({}, "r", { id = info.id, items = {} })
      end, { buffer = args.buf, desc = "nowork: clear qflist" })
    end,
  })

  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("NoworkSessionFile", { clear = true }),
    pattern = { "*/.nowork/*.log", "*/.nowork/logs/*/*.log" },
    callback = function(args)
      require("djinni.nowork.archive").bind_qflist_keys(args.buf, args.file)
    end,
  })

  local ok_wk, wk = pcall(require, "which-key")
  if ok_wk and wk.add then
    pcall(wk.add, {
      { "<leader>a",  group = "nowork" },
      { "<leader>as", desc = "start plan flow (empty compose → save)" },
      { "<leader>aS", desc = "chat-plan (legacy)" },
      { "<leader>ar", desc = "run agent on plan.md", mode = { "n", "x" } },
      { "<leader>ae", desc = "events (permissions + questions + blocked)" },
      { "<leader>aw", desc = "routine" },
      { "<leader>aa", desc = "logs (active + recent + archive)" },
      { "<leader>ao", desc = "projects" },
      { "<leader>ai", desc = "interact (actions menu for current droid)" },
      { "<leader>ak", desc = "kill all routines" },
      { "<leader>ac", desc = "chat composer (routine persistent)" },
      { "<leader>av", desc = "review routine / capture selection", mode = { "n", "x" } },
      { "<leader>yq", desc = "share qflist to droid" },
      { "<leader>yQ", desc = "pull from droid (touched → qflist)" },
    })
  end

end

return M
