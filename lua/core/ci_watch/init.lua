local M = {}

local uv = vim.uv or vim.loop

local registry = {}
local saved_statusline = nil

local TITLE = "CI Watch"

local function run_cmd(cmd, cb)
  local stdout_data, stderr_data = {}, {}
  local ok, job = pcall(vim.fn.jobstart, cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, d) stdout_data = d or {} end,
    on_stderr = function(_, d) stderr_data = d or {} end,
    on_exit = function(_, code)
      cb(table.concat(stdout_data, "\n"), table.concat(stderr_data, "\n"), code)
    end,
  })
  if not ok or job <= 0 then
    cb("", "failed to spawn: " .. table.concat(cmd, " "), -1)
  end
end

local function git_current_branch(callback)
  run_cmd({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, function(out, err, code)
    if code ~= 0 then
      callback(nil, (err ~= "" and err or out))
      return
    end
    local branch = vim.trim(out)
    if branch == "" or branch == "HEAD" then
      callback(nil, "detached HEAD")
      return
    end
    callback(branch, nil)
  end)
end

M.git_current_branch = git_current_branch

local function detect_backend(callback)
  run_cmd({ "git", "remote", "get-url", "origin" }, function(out, err, code)
    if code ~= 0 then
      callback(nil, nil, (err ~= "" and err or out))
      return
    end
    local url = vim.trim(out)
    if url:find("github%.com") then
      callback("github", require("core.ci_watch.github"), nil)
    elseif url:find("gitlab") then
      callback("gitlab", require("core.ci_watch.gitlab"), nil)
    else
      callback(nil, nil, "unsupported remote: " .. url)
    end
  end)
end

local function compute_counts(items)
  local terminal, total = 0, #items
  for _, it in ipairs(items) do
    if it.status ~= "running" and it.status ~= "pending" then
      terminal = terminal + 1
    end
  end
  return terminal, total
end

local function format_elapsed(seconds)
  if seconds < 0 then seconds = 0 end
  if seconds < 60 then
    return string.format("%ds", seconds)
  elseif seconds < 3600 then
    return string.format("%dm%02ds", math.floor(seconds / 60), seconds % 60)
  end
  return string.format("%dh%02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

local STATUS_EXPR = " %{%v:lua.require'core.ci_watch'.statusline()%}"
local DEFAULT_STATUSLINE = "%<%f %h%m%r%=%-14.(%l,%c%V%) %P"

local function mount_statusline()
  if saved_statusline ~= nil then return end
  saved_statusline = vim.o.statusline
  if saved_statusline == nil or saved_statusline == "" then
    vim.o.statusline = DEFAULT_STATUSLINE .. STATUS_EXPR
  else
    vim.o.statusline = saved_statusline .. STATUS_EXPR
  end
end

local function unmount_statusline()
  if saved_statusline == nil then return end
  vim.o.statusline = saved_statusline
  saved_statusline = nil
  pcall(vim.cmd.redrawstatus)
end

function M.statusline()
  if next(registry) == nil then return "" end
  local now = os.time()
  local parts = {}
  for _, w in pairs(registry) do
    local c = w.counts
    local elapsed = format_elapsed(now - (w.started_at or now))
    if c then
      local hl = "%#DiagnosticWarn#"
      if c.overall == "failure" then
        hl = "%#DiagnosticError#"
      elseif c.overall == "success" then
        hl = "%#DiagnosticOk#"
      end
      if c.overall == "running" or c.overall == "pending" then
        parts[#parts + 1] = string.format("%sCI %s %d/%d · %s%%*", hl, w.branch, c.terminal, c.total, elapsed)
      else
        parts[#parts + 1] = string.format("%sCI %s %d/%d%%*", hl, w.branch, c.terminal, c.total)
      end
    else
      parts[#parts + 1] = string.format("%%#DiagnosticWarn#CI %s · %s%%*", w.branch, elapsed)
    end
  end
  return table.concat(parts, "  ")
end

local finish
local tick

finish = function(watcher, reason, result, err_msg)
  if watcher.done then return end
  watcher.done = true
  if watcher.timer then
    pcall(function()
      watcher.timer:stop()
      watcher.timer:close()
    end)
    watcher.timer = nil
  end
  registry[watcher.id] = nil
  if next(registry) == nil then
    unmount_statusline()
  else
    pcall(vim.cmd.redrawstatus)
  end

  local branch = watcher.branch
  local elapsed = format_elapsed(os.time() - (watcher.started_at or os.time()))
  local url = result and result.ref_url or ""
  local items = (result and result.items) or {}
  local total = #items
  local failed = {}
  for _, it in ipairs(items) do
    if it.status == "failure" then failed[#failed + 1] = it.name end
  end

  if reason == "success" then
    local msg = string.format("CI passed for %s in %s: %d/%d checks", branch, elapsed, total, total)
    if url ~= "" then msg = msg .. "\n" .. url end
    vim.notify(msg, vim.log.levels.INFO, { title = TITLE })
  elseif reason == "failure" then
    M._record_failure(result)
    local msg = string.format("CI failed for %s in %s: %d/%d failed — %s", branch, elapsed, #failed, total, failed[1] or "?")
    if url ~= "" then msg = msg .. "\n" .. url end
    msg = msg .. "\n:CILogs to view failed output"
    vim.notify(msg, vim.log.levels.ERROR, { title = TITLE })
  elseif reason == "cancelled" then
    local msg = string.format("CI cancelled for %s after %s", branch, elapsed)
    if url ~= "" then msg = msg .. "\n" .. url end
    vim.notify(msg, vim.log.levels.WARN, { title = TITLE })
  elseif reason == "timeout" then
    local minutes = math.floor(watcher.timeout_s / 60)
    vim.notify(string.format("CI timed out after %dm for %s (ran %s)", minutes, branch, elapsed), vim.log.levels.WARN, { title = TITLE })
  elseif reason == "error" then
    vim.notify(string.format("CI watch error for %s after %s: %s", branch, elapsed, err_msg or "?"), vim.log.levels.ERROR, { title = TITLE })
  end
end

tick = function(watcher)
  if watcher.done then return end
  if os.time() - watcher.started_at >= watcher.timeout_s then
    finish(watcher, "timeout")
    return
  end
  watcher.backend.fetch({ branch = watcher.branch }, function(result, err)
    if watcher.done then return end
    if err or not result then
      watcher.errors = (watcher.errors or 0) + 1
      if watcher.errors > 3 then
        finish(watcher, "error", nil, err)
      end
      return
    end
    watcher.errors = 0
    watcher.last_result = result
    local terminal, total = compute_counts(result.items)
    watcher.counts = { terminal = terminal, total = total, overall = result.overall }
    pcall(vim.cmd.redrawstatus)
    if result.overall ~= "running" then
      finish(watcher, result.overall, result)
    end
  end)
end

local function start_watcher(backend_name, backend, branch, timeout_s, interval_ms)
  local id = backend_name .. ":" .. branch
  if registry[id] then
    local existing = registry[id]
    existing.done = true
    if existing.timer then
      pcall(function()
        existing.timer:stop()
        existing.timer:close()
      end)
    end
    registry[id] = nil
  end
  local w = {
    id = id,
    backend_name = backend_name,
    backend = backend,
    branch = branch,
    started_at = os.time(),
    timeout_s = timeout_s,
    counts = nil,
    errors = 0,
    done = false,
    last_result = nil,
  }
  local timer = uv.new_timer()
  w.timer = timer
  registry[id] = w
  mount_statusline()
  timer:start(0, interval_ms, vim.schedule_wrap(function() tick(w) end))
  pcall(vim.cmd.redrawstatus)
  return id
end

function M.watch(opts)
  opts = opts or {}
  local timeout_s = math.max(60, (opts.timeout_minutes or 30) * 60)
  local interval_ms = math.max(3000, (opts.interval_seconds or 15) * 1000)

  local function go(branch)
    detect_backend(function(name, backend, err)
      if not backend then
        vim.notify("CI Watch: " .. (err or "unsupported remote"), vim.log.levels.ERROR, { title = TITLE })
        return
      end
      start_watcher(name, backend, branch, timeout_s, interval_ms)
    end)
  end

  if opts.branch and opts.branch ~= "" then
    go(opts.branch)
  else
    git_current_branch(function(branch, err)
      if not branch then
        vim.notify("CI Watch: not on a branch (" .. (err or "?") .. ")", vim.log.levels.ERROR, { title = TITLE })
        return
      end
      go(branch)
    end)
  end
end

function M.cancel(id)
  local w = registry[id]
  if not w then return false end
  w.done = true
  if w.timer then
    pcall(function()
      w.timer:stop()
      w.timer:close()
    end)
    w.timer = nil
  end
  registry[id] = nil
  if next(registry) == nil then
    unmount_statusline()
  else
    pcall(vim.cmd.redrawstatus)
  end
  return true
end

function M.cancel_all()
  local ids = {}
  for id, _ in pairs(registry) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do M.cancel(id) end
  return #ids
end

function M.list()
  local out = {}
  for _, w in pairs(registry) do
    out[#out + 1] = {
      id = w.id,
      backend = w.backend_name,
      branch = w.branch,
      started_at = w.started_at,
      counts = w.counts,
    }
  end
  return out
end

local last_failed = { run_id = nil, url = nil }

function M.last_failed_run_id()
  return last_failed.run_id
end

function M._record_failure(result)
  if not result or type(result.items) ~= "table" then return end
  for _, it in ipairs(result.items) do
    if it.status == "failure" and it.url and it.url ~= "" then
      local id = it.url:match("/runs/(%d+)") or it.url:match("/checks/(%d+)")
      if id then
        last_failed.run_id = id
        last_failed.url = it.url
        return
      end
    end
  end
end

function M.lualine_component()
  return {
    function() return M.statusline() end,
    cond = function() return next(registry) ~= nil end,
  }
end

local did_setup = false

function M.setup()
  if did_setup then return end
  did_setup = true

  vim.api.nvim_create_user_command("CIWatch", function(cmd)
    local arg = vim.trim(cmd.args or "")
    if arg == "" then
      M.watch({})
    elseif tonumber(arg) then
      M.watch({ timeout_minutes = tonumber(arg) })
    else
      M.watch({ branch = arg })
    end
  end, {
    nargs = "?",
    desc = "Watch CI: no arg (current branch), <N> (timeout min), <branch> (specific branch)",
  })

  vim.api.nvim_create_user_command("CIPicker", function()
    require("core.ci_watch.picker").open()
  end, { desc = "Pick from open PRs and recent workflow runs" })

  vim.api.nvim_create_user_command("CILogs", function(cmd)
    local arg = vim.trim(cmd.args or "")
    local run_id = arg ~= "" and arg or M.last_failed_run_id()
    if not run_id then
      vim.notify("No run id and no recent failed watcher. Use :CILogs <run_id>", vim.log.levels.WARN, { title = TITLE })
      return
    end
    require("core.ci_watch.logs").view(run_id)
  end, {
    nargs = "?",
    desc = "View CI run logs; arg = run id, default = most recent failed check",
  })

  vim.api.nvim_create_user_command("CIWatchCancel", function()
    local n = M.cancel_all()
    if n > 0 then
      vim.notify(string.format("Cancelled %d CI watcher%s", n, n == 1 and "" or "s"), vim.log.levels.INFO, { title = TITLE })
    else
      vim.notify("No active CI watchers", vim.log.levels.INFO, { title = TITLE })
    end
  end, { desc = "Cancel all active CI watchers" })

  vim.api.nvim_create_user_command("CIWatchList", function()
    local list = M.list()
    if #list == 0 then
      vim.notify("No active CI watchers", vim.log.levels.INFO, { title = TITLE })
      return
    end
    local lines = {}
    for _, w in ipairs(list) do
      local c = w.counts
      local counts_str = c and string.format("%d/%d %s", c.terminal, c.total, c.overall) or "…"
      lines[#lines + 1] = string.format("  %s (%s) — %s", w.branch, w.backend, counts_str)
    end
    vim.notify("Active CI watchers:\n" .. table.concat(lines, "\n"), vim.log.levels.INFO, { title = TITLE })
  end, { desc = "List active CI watchers" })

  vim.keymap.set("n", "<leader>gw", function()
    require("core.ci_watch.picker").open({ use_current_branch = true, fallback_watch_current = true })
  end, { desc = "CI watch: pick (current branch default)" })
  vim.keymap.set("n", "<leader>gW", "<cmd>CIWatchCancel<cr>", { desc = "Cancel CI watchers" })
  vim.keymap.set("n", "<leader>gp", "<cmd>CIPicker<cr>", { desc = "Pick from open PRs and recent runs" })
  vim.keymap.set("n", "<leader>gl", "<cmd>CILogs<cr>", { desc = "View latest failed CI logs" })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("CIWatchCleanup", { clear = true }),
    callback = function()
      for id, w in pairs(registry) do
        w.done = true
        if w.timer then
          pcall(function()
            w.timer:stop()
            w.timer:close()
          end)
        end
        registry[id] = nil
      end
    end,
  })
end

return M
