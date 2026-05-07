local M = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "worktrunk" })
end

local function run_async(args, opts, callback)
  if not opts then
    opts = {}
  end

  local command = { "wt" }
  vim.list_extend(command, args)

  local ok, result = pcall(vim.system, command, vim.tbl_extend("force", { text = true }, opts), function(job)
    vim.schedule(function()
      callback(job.code == 0, vim.trim(job.stdout or ""), vim.trim(job.stderr or ""), job)
    end)
  end)

  if not ok then
    vim.schedule(function()
      callback(false, "", tostring(result), nil)
    end)
  end
end

local function current_branch(cwd)
  local result = vim.system({ "git", "branch", "--show-current" }, {
    cwd = cwd or vim.fn.getcwd(),
    text = true,
  }):wait()

  if result.code ~= 0 then
    return nil
  end

  local branch = vim.trim(result.stdout or "")
  if branch == "" then
    return nil
  end

  return branch
end

local function session_name(cwd)
  local branch = current_branch(cwd)
  if branch then
    return "wt:" .. branch
  end
  return cwd or vim.fn.getcwd()
end

function M.current_branch(cwd)
  return current_branch(cwd)
end

function M.session_name(cwd)
  return session_name(cwd)
end

local function save_session(cwd)
  local ok, resession = pcall(require, "resession")
  if not ok then
    return false
  end
  return pcall(resession.save, session_name(cwd), { dir = "dirsession", notify = false })
end

local function load_session(cwd)
  local ok, resession = pcall(require, "resession")
  if not ok then
    return false
  end
  return pcall(resession.load, session_name(cwd), { dir = "dirsession", silence_errors = true })
end

local function clear_windows()
  local scratch = vim.api.nvim_create_buf(true, true)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_buf(win, scratch)
    end
  end
end

local function apply_switch(branch, path, callback)
  vim.schedule(function()
    local previous_cwd = vim.fn.getcwd()
    save_session(previous_cwd)
    clear_windows()
    vim.cmd("tcd " .. vim.fn.fnameescape(path))
    load_session(path)

    local buffers = vim.tbl_filter(function(bufnr)
      return vim.bo[bufnr].buflisted and vim.api.nvim_buf_get_name(bufnr) ~= ""
    end, vim.api.nvim_list_bufs())
    if #buffers == 0 then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end

    notify("Switched to " .. branch, vim.log.levels.INFO)
    if callback then
      callback(path)
    end
  end)
end

local function decode_json(payload)
  local ok, data = pcall(vim.json.decode, payload, { luanil = { object = true, array = true } })
  if not ok or type(data) ~= "table" then
    return nil, "failed to parse JSON"
  end
  return data
end

function M.available()
  return vim.fn.executable("wt") == 1
end

function M.session_name(cwd)
  return session_name(cwd)
end

function M.list(opts, callback)
  opts = opts or {}
  if not M.available() then
    callback(nil, "wt is not installed")
    return
  end

  local args = { "list", "--format=json" }
  if opts.branches then
    table.insert(args, "--branches")
  end
  if opts.remotes then
    table.insert(args, "--remotes")
  end
  if opts.full then
    table.insert(args, "--full")
  end

  run_async(args, { cwd = opts.cwd }, function(ok, stdout, stderr)
    if not ok then
      callback(nil, stderr ~= "" and stderr or stdout)
      return
    end

    local data, err = decode_json(stdout)
    if not data then
      callback(nil, err)
      return
    end

    callback(data)
  end)
end

function M.get_path(branch, callback)
  M.list({ branches = true }, function(entries, err)
    if not entries then
      callback(nil, err)
      return
    end

    for _, entry in ipairs(entries) do
      if entry.branch == branch and entry.path then
        callback(entry.path)
        return
      end
    end

    callback(nil, "worktree not found")
  end)
end

function M.select_worktree(prompt, opts, callback)
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end

  opts = opts or {}
  M.list(opts, function(entries, err)
    if not entries or #entries == 0 then
      notify(err or "No worktrees found", vim.log.levels.WARN)
      return
    end

    local items = {}
    for _, entry in ipairs(entries) do
      if not opts.worktrees_only or entry.kind == "worktree" then
        items[#items + 1] = entry
      end
    end

    if #items == 0 then
      notify("No worktrees found", vim.log.levels.WARN)
      return
    end

    vim.ui.select(items, {
      prompt = prompt or "Worktrees",
      format_item = function(entry)
        local parts = {}
        if entry.is_current then
          parts[#parts + 1] = "*"
        end
        parts[#parts + 1] = entry.branch or "(detached)"
        if entry.path and entry.path ~= "" then
          parts[#parts + 1] = vim.fn.fnamemodify(entry.path, ":~")
        end
        if entry.symbols and entry.symbols ~= "" then
          parts[#parts + 1] = entry.symbols
        end
        return table.concat(parts, "  ")
      end,
    }, function(item)
      if item and callback then
        callback(item)
      end
    end)
  end)
end

function M.switch_to(branch, opts, callback)
  opts = opts or {}
  if not M.available() then
    callback(false, "wt is not installed")
    return
  end

  local args = { "switch" }
  if opts.create then
    args[#args + 1] = "--create"
  end
  if opts.base then
    args[#args + 1] = "--base=" .. opts.base
  end
  if opts.clobber then
    args[#args + 1] = "--clobber"
  end
  if opts.yes then
    args[#args + 1] = "--yes"
  end
  if opts.no_verify then
    args[#args + 1] = "--no-verify"
  end
  if branch and branch ~= "" then
    args[#args + 1] = branch
  end

  run_async(args, { cwd = opts.cwd }, function(ok, stdout, stderr)
    if not ok then
      callback(false, stderr ~= "" and stderr or stdout)
      return
    end

    local path
    for line in stdout:gmatch("[^\r\n]+") do
      path = line:match("worktree @ (.+)")
      if path then
        break
      end
    end

    if path and path ~= "" then
      apply_switch(branch or vim.fn.fnamemodify(path, ":t"), path, function(switched_path)
        if callback then
          callback(true, switched_path)
        end
      end)
      return
    end

    M.get_path(branch, function(found_path, err)
      if not found_path then
        callback(false, err or "could not resolve worktree path")
        return
      end
      apply_switch(branch, found_path, function(switched_path)
        if callback then
          callback(true, switched_path)
        end
      end)
    end)
  end)
end

function M.create(branch, opts, callback)
  opts = opts or {}
  opts.create = true
  M.switch_to(branch, opts, callback)
end

function M.remove(branches, opts, callback)
  opts = opts or {}
  if not M.available() then
    callback(false, "wt is not installed")
    return
  end

  local args = { "remove" }
  if opts.force then
    args[#args + 1] = "--force"
  end
  if opts.force_delete then
    args[#args + 1] = "--force-delete"
  end
  if opts.no_delete_branch then
    args[#args + 1] = "--no-delete-branch"
  end
  if opts.foreground then
    args[#args + 1] = "--foreground"
  end
  if opts.yes then
    args[#args + 1] = "--yes"
  end
  if type(branches) == "table" then
    vim.list_extend(args, branches)
  elseif branches and branches ~= "" then
    args[#args + 1] = branches
  end

  run_async(args, { cwd = opts.cwd }, function(ok, stdout, stderr)
    callback(ok, ok and stdout or stderr)
  end)
end

function M.merge(opts, callback)
  opts = opts or {}
  if not M.available() then
    callback(false, "wt is not installed")
    return
  end

  local args = { "merge" }
  if opts.target and opts.target ~= "" then
    args[#args + 1] = opts.target
  end
  if opts.no_squash then
    args[#args + 1] = "--no-squash"
  end
  if opts.no_commit then
    args[#args + 1] = "--no-commit"
  end
  if opts.no_rebase then
    args[#args + 1] = "--no-rebase"
  end
  if opts.no_remove then
    args[#args + 1] = "--no-remove"
  end
  if opts.no_ff then
    args[#args + 1] = "--no-ff"
  end
  if opts.stage then
    args[#args + 1] = "--stage=" .. opts.stage
  end
  if opts.yes then
    args[#args + 1] = "--yes"
  end

  run_async(args, { cwd = opts.cwd }, function(ok, stdout, stderr)
    callback(ok, ok and stdout or stderr)
  end)
end

function M.open_picker()
  M.select_worktree("Worktrees", { branches = true, full = true }, function(item)
    if item and item.branch then
      M.switch_to(item.branch, {}, function() end)
    end
  end)
end

function M.prompt_switch()
  vim.ui.input({ prompt = "Worktree or branch: " }, function(branch)
    if branch and branch ~= "" then
      M.switch_to(branch, {}, function(ok, msg)
        if not ok then
          notify(msg or "wt switch failed", vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

function M.prompt_create()
  vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
    if branch and branch ~= "" then
      vim.ui.input({ prompt = "Base branch or worktree [@]: " }, function(base)
        local opts = {}
        if base and base ~= "" then
          opts.base = base
        else
          opts.base = "@"
        end
        M.create(branch, opts, function(ok, msg)
          if not ok then
            notify(msg or "wt create failed", vim.log.levels.ERROR)
          end
        end)
      end)
    end
  end)
end

function M.prompt_remove()
  M.select_worktree("Remove worktree", { worktrees_only = true }, function(item)
    if not item or not item.branch then
      return
    end
    M.remove(item.branch, { yes = true }, function(ok, msg)
      if ok then
        notify("Removed worktree: " .. item.branch, vim.log.levels.INFO)
      else
        notify(msg or "wt remove failed", vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.prompt_merge()
  vim.ui.input({ prompt = "Merge into (empty=default): " }, function(target)
    if target == nil then
      return
    end
    M.merge({ target = target ~= "" and target or nil, yes = true }, function(ok, msg)
      if ok then
        notify("Merged worktree", vim.log.levels.INFO)
      else
        notify(msg or "wt merge failed", vim.log.levels.ERROR)
      end
    end)
  end)
end

return M
