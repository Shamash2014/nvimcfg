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
    local success, data = pcall(vim.json.decode, json_str)
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
  if opts.base then
    table.insert(args, "--base=" .. opts.base)
  end
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

function M.remove(branch, callback)
  local args = { "remove" }
  if branch then
    table.insert(args, branch)
  end
  run_async("wt", args, function(ok, lines, stderr)
    callback(ok, table.concat(ok and lines or stderr or {}, "\n"))
  end)
end

function M.merge(target, branch, callback)
  local args = { "merge" }
  if target and target ~= "" then
    table.insert(args, target)
  end
  if branch then
    table.insert(args, "--branch")
    table.insert(args, branch)
  end
  run_async("wt", args, function(ok, lines, stderr)
    callback(ok, table.concat(ok and lines or stderr or {}, "\n"))
  end)
end

function M.get_path(branch, callback)
  run_async("git", { "worktree", "list", "--porcelain" }, function(ok, lines)
    if not ok then
      callback(nil)
      return
    end
    local current_worktree = nil
    for _, line in ipairs(lines) do
      if line:match("^worktree ") then
        current_worktree = line:match("^worktree (.+)")
      elseif line:match("^branch ") then
        local branch_name = line:match("^branch refs/heads/(.+)")
        if branch_name == branch and current_worktree then
          callback(current_worktree)
          return
        end
      end
    end
    callback(nil)
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
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted and vim.api.nvim_buf_is_loaded(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, {})
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

function M.create_for_task(branch, callback)
  M.create(branch, function(ok, path)
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

function M.commit(branch, callback)
  M.get_path(branch, function(path)
    if not path then callback(false, "worktree path not found") return end
    run_async("wt", { "commit" }, { cwd = path }, callback)
  end)
end

function M.squash(branch, callback)
  M.get_path(branch, function(path)
    if not path then callback(false, "worktree path not found") return end
    run_async("wt", { "squash" }, { cwd = path }, callback)
  end)
end

function M.rebase(target, branch, callback)
  local args = { "rebase" }
  if target and target ~= "" then table.insert(args, target) end
  if branch then
    table.insert(args, "--branch")
    table.insert(args, branch)
  end
  run_async("wt", args, callback)
end

function M.push(target, branch, callback)
  local args = { "push" }
  if target and target ~= "" then table.insert(args, target) end
  if branch then
    table.insert(args, "--branch")
    table.insert(args, branch)
  end
  run_async("wt", args, callback)
end

function M.diff(branch, callback)
  local args = { "diff" }
  if branch then
    table.insert(args, "--branch")
    table.insert(args, branch)
  end
  run_async("wt", args, callback)
end

function M.copy_ignored(src, dst, callback)
  run_async("wt", { "copy-ignored", src, dst }, callback)
end

function M.eval(expr, callback)
  run_async("wt", { "eval", expr }, callback)
end

function M.for_each(cmd, callback)
  local args = { "for-each" }
  for part in cmd:gmatch("%S+") do
    table.insert(args, part)
  end
  run_async("wt", args, callback)
end

function M.promote(branch, callback)
  local args = { "promote" }
  if branch then
    table.insert(args, "--branch")
    table.insert(args, branch)
  end
  run_async("wt", args, callback)
end

function M.prune(callback)
  run_async("wt", { "prune" }, callback)
end

function M.relocate(callback)
  run_async("wt", { "relocate" }, callback)
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
  { key = "commit",       label = "commit — stage & commit (LLM msg)",       branch_only = true  },
  { key = "squash",       label = "squash — squash all commits into one",     branch_only = true  },
  { key = "rebase",       label = "rebase — rebase onto target branch",       branch_only = false, prompt = "Rebase onto:" },
  { key = "push",         label = "push — fast-forward target to branch",     branch_only = false, prompt = "Push to target (empty=trunk):" },
  { key = "diff",         label = "diff — all changes since branch point",    branch_only = false },
  { key = "promote",      label = "promote — swap branch into main worktree", branch_only = false },
  { key = "copy-ignored", label = "copy-ignored — copy gitignored files",     branch_only = false, prompt2 = { "From worktree:", "To worktree:" } },
  { key = "eval",         label = "eval — evaluate a template expression",    branch_only = false, prompt = "Expression:" },
  { key = "for-each",     label = "for-each — run command in every worktree", branch_only = false, prompt = "Command:" },
  { key = "prune",        label = "prune — remove merged worktrees/branches", branch_only = false },
  { key = "relocate",     label = "relocate — move worktrees to expected paths", branch_only = false },
}

function M.notify_result(op, ok, lines, stderr)
  if ok then
    local out = table.concat(lines or {}, "\n")
    vim.notify("[wt] " .. op .. (out ~= "" and ": " .. out or " done"), vim.log.levels.INFO)
  else
    vim.notify("[wt] " .. op .. " failed: " .. table.concat(stderr or {}, "\n"), vim.log.levels.ERROR)
  end
end

function M.pick_op(branch)
  local items = {}
  for _, op in ipairs(wt_ops) do
    if not op.branch_only or (branch and branch ~= "") then
      table.insert(items, op)
    end
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
      if op.key == "commit" then
        M.commit(branch, function(ok, lines, stderr) M.notify_result("commit", ok, lines, stderr) end)
      elseif op.key == "squash" then
        M.squash(branch, function(ok, lines, stderr) M.notify_result("squash", ok, lines, stderr) end)
      elseif op.key == "rebase" then
        M.rebase(args_extra, branch, function(ok, lines, stderr) M.notify_result("rebase", ok, lines, stderr) end)
      elseif op.key == "push" then
        M.push(args_extra, branch, function(ok, lines, stderr) M.notify_result("push", ok, lines, stderr) end)
      elseif op.key == "diff" then
        M.diff(branch, function(ok, lines, stderr)
          vim.schedule(function()
            if ok and #lines > 0 then M.open_diff_buf(lines)
            elseif ok then vim.notify("[wt] diff: no changes", vim.log.levels.INFO)
            else vim.notify("[wt] diff failed: " .. table.concat(stderr or {}, "\n"), vim.log.levels.ERROR)
            end
          end)
        end)
      elseif op.key == "promote" then
        M.promote(branch, function(ok, lines, stderr) M.notify_result("promote", ok, lines, stderr) end)
      elseif op.key == "copy-ignored" then
        local parts = type(args_extra) == "table" and args_extra or {}
        M.copy_ignored(parts[1] or "", parts[2] or "", function(ok, lines, stderr) M.notify_result("copy-ignored", ok, lines, stderr) end)
      elseif op.key == "eval" then
        M.eval(args_extra or "", function(ok, lines, stderr) M.notify_result("eval", ok, lines, stderr) end)
      elseif op.key == "for-each" then
        M.for_each(args_extra or "", function(ok, lines, stderr) M.notify_result("for-each", ok, lines, stderr) end)
      elseif op.key == "prune" then
        M.prune(function(ok, lines, stderr) M.notify_result("prune", ok, lines, stderr) end)
      elseif op.key == "relocate" then
        M.relocate(function(ok, lines, stderr) M.notify_result("relocate", ok, lines, stderr) end)
      end
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
