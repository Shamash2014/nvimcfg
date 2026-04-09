local M = {}

local function run_async(cmd, args, opts_or_cb, cb)
  local opts, callback
  if type(opts_or_cb) == "function" then
    opts = {}
    callback = opts_or_cb
  else
    opts = opts_or_cb or {}
    callback = cb
  end

  local stdout_lines = {}
  local stderr_lines = {}
  local function deliver(success)
    vim.schedule(function()
      callback(success, stdout_lines, stderr_lines)
    end)
  end

  local job_opts = {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then table.insert(stdout_lines, line) end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then table.insert(stderr_lines, line) end
      end
    end,
    on_exit = function(_, code)
      deliver(code == 0)
    end,
  }
  if opts.cwd then job_opts.cwd = opts.cwd end

  local ok, job_id = pcall(vim.fn.jobstart, { cmd, unpack(args) }, job_opts)
  if not ok then
    table.insert(stderr_lines, tostring(job_id))
    deliver(false)
    return
  end
  if type(job_id) ~= "number" or job_id <= 0 then
    deliver(false)
  end
end

function M.available()
  return vim.fn.executable("wt") == 1
end

function M.list(opts_or_cb, cb)
  local opts, callback
  if type(opts_or_cb) == "function" then
    opts = {}
    callback = opts_or_cb
  else
    opts = opts_or_cb or {}
    callback = cb
  end

  local args = { "list", "--format=json" }
  if opts.branches then table.insert(args, "--branches") end
  if opts.remotes then table.insert(args, "--remotes") end
  if opts.full then table.insert(args, "--full") end

  run_async("wt", args, function(ok, lines, stderr)
    if not ok then
      callback(nil, table.concat(stderr or {}, "\n"))
      return
    end
    local json_str = table.concat(lines, "")
    local success, data = pcall(vim.json.decode, json_str, { luanil = { object = true, array = true } })
    if not success or type(data) ~= "table" then
      callback(nil, "failed to parse JSON")
      return
    end
    callback(data)
  end)
end

function M.create(branch, opts_or_callback, callback)
  local opts, cb
  if type(opts_or_callback) == "function" then
    opts = {}
    cb = opts_or_callback
  else
    opts = opts_or_callback or {}
    cb = callback
  end
  local args = { "switch", "--create", branch }
  if opts.base then table.insert(args, "--base=" .. opts.base) end
  if opts.execute then table.insert(args, "--execute") table.insert(args, opts.execute) end
  if opts.clobber then table.insert(args, "--clobber") end
  if opts.no_cd then table.insert(args, "--no-cd") end
  if opts.yes then table.insert(args, "--yes") end
  if opts.no_verify then table.insert(args, "--no-verify") end
  run_async("wt", args, function(ok, lines, stderr)
    if ok then
      local path = nil
      for _, line in ipairs(lines) do
        local p = line:match("worktree @ (.+)")
        if p then
          path = p
          break
        end
      end
      cb(true, path)
    else
      cb(false, table.concat(stderr or lines or {}, "\n"))
    end
  end)
end

function M.remove(branches, opts_or_cb, cb)
  local opts, callback
  if type(opts_or_cb) == "function" then
    opts = {}
    callback = opts_or_cb
  else
    opts = opts_or_cb or {}
    callback = cb
  end
  local args = { "remove" }
  if opts.force then table.insert(args, "--force") end
  if opts.force_delete then table.insert(args, "--force-delete") end
  if opts.no_delete_branch then table.insert(args, "--no-delete-branch") end
  if opts.foreground then table.insert(args, "--foreground") end
  if opts.yes then table.insert(args, "--yes") end
  if type(branches) == "table" then
    for _, b in ipairs(branches) do table.insert(args, b) end
  elseif branches then
    table.insert(args, branches)
  end
  run_async("wt", args, function(ok, lines, stderr)
    callback(ok, table.concat(ok and lines or stderr or {}, "\n"))
  end)
end

function M.merge(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "merge" }
  if opts.target and opts.target ~= "" then table.insert(args, opts.target) end
  if opts.no_squash then table.insert(args, "--no-squash") end
  if opts.no_commit then table.insert(args, "--no-commit") end
  if opts.no_rebase then table.insert(args, "--no-rebase") end
  if opts.no_remove then table.insert(args, "--no-remove") end
  if opts.no_ff then table.insert(args, "--no-ff") end
  if opts.stage then table.insert(args, "--stage=" .. opts.stage) end
  if opts.yes then table.insert(args, "--yes") end
  run_async("wt", args, { cwd = opts.cwd }, function(ok, lines, stderr)
    callback(ok, table.concat(ok and lines or stderr or {}, "\n"))
  end)
end

function M.get_path(branch, callback)
  M.list(function(entries)
    if not entries then callback(nil) return end
    for _, e in ipairs(entries) do
      if e.branch == branch and e.path then
        callback(e.path)
        return
      end
    end
    callback(nil)
  end)
end

function M.switch(branch, opts_or_cb, cb)
  local opts, callback
  if type(opts_or_cb) == "function" then
    opts = {}
    callback = opts_or_cb
  else
    opts = opts_or_cb or {}
    callback = cb
  end
  local args = { "switch" }
  if opts.create then table.insert(args, "--create") end
  if opts.base then table.insert(args, "--base=" .. opts.base) end
  if opts.execute then table.insert(args, "--execute") table.insert(args, opts.execute) end
  if opts.branches then table.insert(args, "--branches") end
  if opts.remotes then table.insert(args, "--remotes") end
  if opts.clobber then table.insert(args, "--clobber") end
  if opts.no_cd then table.insert(args, "--no-cd") end
  if opts.yes then table.insert(args, "--yes") end
  if opts.no_verify then table.insert(args, "--no-verify") end
  if branch then table.insert(args, branch) end
  run_async("wt", args, function(ok, lines, stderr)
    if callback then callback(ok, lines, stderr) end
  end)
end

function M.format_stats(entry)
  if not entry then return "" end
  local parts = {}
  table.insert(parts, entry.branch or "?")
  if entry.commit then
    table.insert(parts, entry.commit.short_sha .. " " .. (entry.commit.message or ""))
  end
  local wt = entry.working_tree
  if wt then
    local flags = {}
    if wt.staged then table.insert(flags, "staged") end
    if wt.modified then table.insert(flags, "modified") end
    if wt.untracked then table.insert(flags, "untracked") end
    if #flags > 0 then table.insert(parts, table.concat(flags, " ")) end
    if wt.diff and (wt.diff.added > 0 or wt.diff.deleted > 0) then
      table.insert(parts, "+" .. wt.diff.added .. " -" .. wt.diff.deleted)
    end
  end
  if entry.main and (entry.main.ahead > 0 or entry.main.behind > 0) then
    table.insert(parts, "↑" .. entry.main.ahead .. " ↓" .. entry.main.behind)
  end
  return table.concat(parts, "  ")
end

local function save_and_clear_buffers()
  local cur = vim.fn.system("git branch --show-current"):gsub("%s+$", "")
  if cur ~= "" then
    local ok, resession = pcall(require, "resession")
    if ok then
      resession.save("wt:" .. cur, { notify = false })
    end
  end
  local scratch = vim.api.nvim_create_buf(true, true)
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_buf(win, scratch)
    end
  end
end

local function show_switch_stats(branch)
  M.list(function(entries)
    if not entries then return end
    for _, e in ipairs(entries) do
      if e.branch == branch and e.kind == "worktree" then
        vim.schedule(function()
          vim.notify("[wt] " .. M.format_stats(e), vim.log.levels.INFO)
        end)
        return
      end
    end
  end)
end

function M.switch_to(branch, callback)
  M.get_path(branch, function(path)
    if not path then
      vim.notify("[wt] Could not find worktree path for: " .. branch, vim.log.levels.ERROR)
      return
    end
    vim.schedule(function()
      save_and_clear_buffers()
      vim.cmd("tcd " .. vim.fn.fnameescape(path))
      local ok, resession = pcall(require, "resession")
      if ok then
        local loaded = pcall(resession.load, "wt:" .. branch, { silence_errors = true })
        if not loaded then
          local folder_name = vim.fn.fnamemodify(path, ":t"):lower()
          pcall(resession.load, folder_name, { silence_errors = true })
        end
      end
      local bufs = vim.tbl_filter(function(b)
        return vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) ~= ""
      end, vim.api.nvim_list_bufs())
      if #bufs == 0 then
        vim.cmd("edit " .. vim.fn.fnameescape(path))
      end
      show_switch_stats(branch)
      if callback then callback() end
    end)
  end)
end

function M.create_for_task(branch, opts_or_cb, cb)
  local opts, callback
  if type(opts_or_cb) == "function" then
    opts = {}
    callback = opts_or_cb
  else
    opts = opts_or_cb or {}
    callback = cb
  end
  M.create(branch, opts, function(ok, path)
    if ok then
      if path then
        vim.schedule(function()
          save_and_clear_buffers()
          vim.cmd("tcd " .. vim.fn.fnameescape(path))
          local rok, resession = pcall(require, "resession")
          if rok then
            local loaded = pcall(resession.load, "wt:" .. branch, { silence_errors = true })
            if not loaded then
              local folder_name = vim.fn.fnamemodify(path, ":t"):lower()
              pcall(resession.load, folder_name, { silence_errors = true })
            end
          end
          local bufs = vim.tbl_filter(function(b)
            return vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) ~= ""
          end, vim.api.nvim_list_bufs())
          if #bufs == 0 then
            vim.cmd("edit " .. vim.fn.fnameescape(path))
          end
          show_switch_stats(branch)
        end)
      end
      if callback then callback(path) end
    end
  end)
end

function M.cleanup(branch, callback)
  M.remove(branch, function(ok)
    if callback then callback(ok) end
  end)
end

function M.step_commit(callback)
  run_async("wt", { "step", "commit" }, function(ok, lines, stderr)
    callback(ok, table.concat(ok and lines or stderr or {}, "\n"))
  end)
end

function M.step_rollback(callback)
  run_async("git", { "reset", "--soft", "HEAD~1" }, function(ok, lines, stderr)
    callback(ok, table.concat(ok and lines or stderr or {}, "\n"))
  end)
end

function M.hook_show(callback)
  run_async("wt", { "hook", "show" }, callback)
end

function M.config_show(callback)
  run_async("wt", { "config", "show" }, callback)
end

function M.commit(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "step", "commit" }
  if opts.stage then table.insert(args, "--stage=" .. opts.stage) end
  if opts.yes then table.insert(args, "--yes") end
  run_async("wt", args, { cwd = opts.cwd }, callback)
end

function M.squash(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "step", "squash" }
  if opts.target then table.insert(args, opts.target) end
  if opts.stage then table.insert(args, "--stage=" .. opts.stage) end
  if opts.yes then table.insert(args, "--yes") end
  run_async("wt", args, { cwd = opts.cwd }, callback)
end

function M.rebase(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "step", "rebase" }
  if opts.target and opts.target ~= "" then table.insert(args, opts.target) end
  if opts.yes then table.insert(args, "--yes") end
  run_async("wt", args, { cwd = opts.cwd }, callback)
end

function M.push(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "step", "push" }
  if opts.target and opts.target ~= "" then table.insert(args, opts.target) end
  if opts.no_ff then table.insert(args, "--no-ff") end
  if opts.yes then table.insert(args, "--yes") end
  run_async("wt", args, { cwd = opts.cwd }, callback)
end

function M.diff(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "step", "diff" }
  if opts.target then table.insert(args, opts.target) end
  run_async("wt", args, { cwd = opts.cwd }, callback)
end

function M.copy_ignored(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "step", "copy-ignored" }
  if opts.from then table.insert(args, "--from=" .. opts.from) end
  if opts.to then table.insert(args, "--to=" .. opts.to) end
  if opts.force then table.insert(args, "--force") end
  if opts.dry_run then table.insert(args, "--dry-run") end
  run_async("wt", args, callback)
end

function M.eval(expr, callback)
  run_async("wt", { "step", "eval", expr }, callback)
end

function M.for_each(cmd, callback)
  local args = { "step", "for-each" }
  for part in cmd:gmatch("%S+") do
    table.insert(args, part)
  end
  run_async("wt", args, callback)
end

function M.promote(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  if type(opts) == "string" then opts = { branch = opts } end
  opts = opts or {}
  local args = { "step", "promote" }
  if opts.branch then table.insert(args, opts.branch) end
  run_async("wt", args, { cwd = opts.cwd }, callback)
end

function M.prune(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "step", "prune" }
  if opts.yes then table.insert(args, "--yes") end
  run_async("wt", args, callback)
end

function M.relocate(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local args = { "step", "relocate" }
  if opts.yes then table.insert(args, "--yes") end
  run_async("wt", args, callback)
end

local statusline_cache = ""
local statusline_timer = nil
local statusline_refresh_busy = false

local function refresh_statusline()
  if statusline_refresh_busy then return end
  statusline_refresh_busy = true
  run_async("wt", { "list", "statusline", "--format=claude-code" }, function(ok, lines)
    statusline_refresh_busy = false
    if ok and #lines > 0 then
      statusline_cache = lines[1]
    else
      statusline_cache = ""
    end
    pcall(vim.cmd, "redrawstatus")
  end)
end

function M.statusline()
  return statusline_cache
end

function M.start_statusline(interval_ms)
  if statusline_timer then return end
  if not M.available() then return end

  interval_ms = interval_ms or 5000
  refresh_statusline()

  local timer = vim.uv.new_timer()
  if not timer then return end
  statusline_timer = timer
  statusline_timer:start(interval_ms, interval_ms, vim.schedule_wrap(refresh_statusline))

  vim.api.nvim_create_autocmd({ "FocusGained", "DirChanged" }, {
    group = vim.api.nvim_create_augroup("worktrunk_statusline", { clear = true }),
    callback = function() refresh_statusline() end,
  })
end

function M.stop_statusline()
  if statusline_timer then
    statusline_timer:stop()
    statusline_timer:close()
    statusline_timer = nil
  end
  statusline_cache = ""
end

function M.open_diff_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "diff"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " wt diff ",
    title_pos = "center",
  })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
end

local wt_ops = {
  { key = "commit",       label = "commit — stage & commit (LLM msg)",          needs_wt = true  },
  { key = "squash",       label = "squash — squash all commits into one",        needs_wt = true  },
  { key = "update",       label = "update — fetch remote & rebase onto default",  needs_wt = true  },
  { key = "rebase",       label = "rebase — rebase onto target branch",          needs_wt = true,  prompt = "Rebase onto (empty=default):" },
  { key = "push",         label = "push — fast-forward target to branch",        needs_wt = true,  prompt = "Push to target (empty=default):" },
  { key = "diff",         label = "diff — all changes since branch point",       needs_wt = true  },
  { key = "merge",        label = "merge — squash, rebase, merge into target",   needs_wt = true,  prompt = "Merge into (empty=default):" },
  { key = "promote",      label = "promote — swap branch into main worktree",    needs_wt = false },
  { key = "copy-ignored", label = "copy-ignored — copy gitignored files",        needs_wt = false, prompt2 = { "From worktree:", "To worktree:" } },
  { key = "eval",         label = "eval — evaluate a template expression",       needs_wt = false, prompt = "Expression:" },
  { key = "for-each",     label = "for-each — run command in every worktree",    needs_wt = false, prompt = "Command:" },
  { key = "remove",       label = "remove — remove worktree",                     needs_wt = true  },
  { key = "remove-force", label = "remove --force — force remove worktree",       needs_wt = true  },
  { key = "prune",        label = "prune — remove merged worktrees/branches",    needs_wt = false },
  { key = "relocate",     label = "relocate — move worktrees to expected paths", needs_wt = false },
  { key = "hook-show",    label = "hook show — display configured hooks",        needs_wt = false },
  { key = "config-show",  label = "config show — display configuration",         needs_wt = false },
}

function M.notify_result(op, ok, lines, stderr)
  if ok then
    local out = table.concat(lines or {}, "\n")
    vim.notify("[wt] " .. op .. (out ~= "" and ": " .. out or " done"), vim.log.levels.INFO)
  else
    local parts = {}
    local out = table.concat(lines or {}, "\n")
    local err = table.concat(stderr or {}, "\n")
    if out ~= "" then table.insert(parts, out) end
    if err ~= "" then table.insert(parts, err) end
    local detail = #parts > 0 and table.concat(parts, "\n") or "unknown error"
    vim.notify("[wt] " .. op .. " failed:\n" .. detail, vim.log.levels.ERROR)
  end
end

local function resolve_cwd_and_run(branch, fn)
  if not branch or branch == "" then
    fn(nil)
    return
  end
  M.get_path(branch, function(path)
    fn(path)
  end)
end

function M.update(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  local cwd = opts.cwd
  local wt_args = function(...)
    local args = {}
    if cwd then vim.list_extend(args, { "-C", cwd }) end
    for _, a in ipairs({ ... }) do table.insert(args, a) end
    return args
  end
  local function do_rebase(target)
    local args = wt_args("step", "rebase")
    if target and target ~= "" then table.insert(args, target) end
    run_async("wt", args, function(ok, lines, stderr)
      callback(ok, lines, stderr)
    end)
  end
  local function resolve_and_rebase()
    local target = opts.target
    if target and target ~= "" then
      if not target:match("^origin/") then
        run_async("git", { "rev-parse", "--verify", "origin/" .. target }, { cwd = cwd }, function(ok)
          do_rebase(ok and ("origin/" .. target) or target)
        end)
      else
        do_rebase(target)
      end
    else
      run_async("git", { "symbolic-ref", "refs/remotes/origin/HEAD", "--short" }, { cwd = cwd }, function(ok, lines)
        do_rebase(ok and lines[1] or nil)
      end)
    end
  end
  if opts.skip_fetch then
    resolve_and_rebase()
  else
    run_async("git", { "fetch", "--prune" }, { cwd = cwd }, function(fetch_ok, _, fetch_stderr)
      if not fetch_ok then
        callback(false, {}, fetch_stderr)
        return
      end
      resolve_and_rebase()
    end)
  end
end

function M.update_all(opts, callback)
  if type(opts) == "function" then callback = opts opts = {} end
  opts = opts or {}
  run_async("git", { "fetch", "--prune" }, function(fetch_ok, _, fetch_stderr)
    if not fetch_ok then
      callback(false, {}, fetch_stderr)
      return
    end
    M.list(function(entries, err)
      if not entries then
        callback(false, {}, { err or "failed to list worktrees" })
        return
      end
      local results = {}
      local pending = #entries
      if pending == 0 then callback(true, { "no worktrees" }, {}) return end
      for _, entry in ipairs(entries) do
        if entry.path then
          M.update({ cwd = entry.path, skip_fetch = true }, function(ok, _, stderr)
            local status = ok and "ok" or "FAIL"
            table.insert(results, (entry.branch or "?") .. ": " .. status)
            if not ok then
              for _, line in ipairs(stderr or {}) do table.insert(results, "  " .. line) end
            end
            pending = pending - 1
            if pending == 0 then
              callback(true, results, {})
            end
          end)
        else
          pending = pending - 1
          if pending == 0 then callback(true, results, {}) end
        end
      end
    end)
  end)
end

function M.pick_op(branch)
  local items = {}
  for _, op in ipairs(wt_ops) do
    table.insert(items, op)
  end

  local labels = vim.tbl_map(function(op) return op.label end, items)
  local title = branch and ("wt ops — " .. branch) or "wt ops (global)"

  vim.ui.select(labels, { prompt = title .. ":" }, function(choice)
    if not choice then return end
    local op
    for _, item in ipairs(items) do
      if item.label == choice then op = item break end
    end
    if not op then return end

    local function run_op(args_extra)
      resolve_cwd_and_run(branch, function(cwd)
        if op.key == "commit" then
          M.commit({ cwd = cwd }, function(ok, lines, stderr) M.notify_result("commit", ok, lines, stderr) end)
        elseif op.key == "squash" then
          M.squash({ cwd = cwd }, function(ok, lines, stderr) M.notify_result("squash", ok, lines, stderr) end)
        elseif op.key == "update" then
          M.update({ cwd = cwd }, function(ok, lines, stderr) M.notify_result("update", ok, lines, stderr) end)
        elseif op.key == "rebase" then
          M.rebase({ target = args_extra, cwd = cwd }, function(ok, lines, stderr) M.notify_result("rebase", ok, lines, stderr) end)
        elseif op.key == "push" then
          M.push({ target = args_extra, cwd = cwd }, function(ok, lines, stderr) M.notify_result("push", ok, lines, stderr) end)
        elseif op.key == "diff" then
          M.diff({ cwd = cwd }, function(ok, lines, stderr)
            vim.schedule(function()
              if ok and #lines > 0 then M.open_diff_buf(lines)
              elseif ok then vim.notify("[wt] diff: no changes", vim.log.levels.INFO)
              else vim.notify("[wt] diff failed: " .. table.concat(stderr or {}, "\n"), vim.log.levels.ERROR)
              end
            end)
          end)
        elseif op.key == "merge" then
          M.merge({ target = args_extra, cwd = cwd, yes = true }, function(ok, msg) M.notify_result("merge", ok, { msg }, {}) end)
        elseif op.key == "promote" then
          M.promote({ branch = branch }, function(ok, lines, stderr) M.notify_result("promote", ok, lines, stderr) end)
        elseif op.key == "copy-ignored" then
          local parts = type(args_extra) == "table" and args_extra or {}
          M.copy_ignored({ from = parts[1], to = parts[2] }, function(ok, lines, stderr) M.notify_result("copy-ignored", ok, lines, stderr) end)
        elseif op.key == "eval" then
          M.eval(args_extra or "", function(ok, lines, stderr) M.notify_result("eval", ok, lines, stderr) end)
        elseif op.key == "for-each" then
          M.for_each(args_extra or "", function(ok, lines, stderr) M.notify_result("for-each", ok, lines, stderr) end)
        elseif op.key == "remove" then
          M.remove(branch, { yes = true }, function(ok, msg) M.notify_result("remove", ok, { msg }, {}) end)
        elseif op.key == "remove-force" then
          M.remove(branch, { force = true, yes = true }, function(ok, msg) M.notify_result("remove --force", ok, { msg }, {}) end)
        elseif op.key == "prune" then
          M.prune({ yes = true }, function(ok, lines, stderr) M.notify_result("prune", ok, lines, stderr) end)
        elseif op.key == "relocate" then
          M.relocate({ yes = true }, function(ok, lines, stderr) M.notify_result("relocate", ok, lines, stderr) end)
        elseif op.key == "hook-show" then
          M.hook_show(function(ok, lines, stderr)
            vim.schedule(function()
              if ok and #lines > 0 then
                M.open_diff_buf(lines)
              else
                M.notify_result("hook show", ok, lines, stderr)
              end
            end)
          end)
        elseif op.key == "config-show" then
          M.config_show(function(ok, lines, stderr)
            vim.schedule(function()
              if ok and #lines > 0 then
                M.open_diff_buf(lines)
              else
                M.notify_result("config show", ok, lines, stderr)
              end
            end)
          end)
        end
      end)
    end

    if op.prompt2 then
      vim.ui.input({ prompt = op.prompt2[1] }, function(a)
        if a == nil then return end
        vim.ui.input({ prompt = op.prompt2[2] }, function(b)
          if b == nil then return end
          run_op({ a, b })
        end)
      end)
    elseif op.prompt then
      vim.ui.input({ prompt = op.prompt }, function(arg)
        if arg == nil then return end
        run_op(arg)
      end)
    else
      run_op(nil)
    end
  end)
end

return M
