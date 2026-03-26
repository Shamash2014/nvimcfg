local M = {}

local function run_async(cmd, args, callback)
  local stdout_lines = {}
  local stderr_lines = {}
  local function deliver(success)
    vim.schedule(function()
      callback(success, stdout_lines, stderr_lines)
    end)
  end

  local ok, job_id = pcall(vim.fn.jobstart, { cmd, unpack(args) }, {
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
  })

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

function M.list(callback)
  run_async("wt", { "list" }, function(ok, lines, stderr)
    if not ok then
      callback(nil, table.concat(stderr or {}, "\n"))
      return
    end
    callback(M.parse_list(lines))
  end)
end

function M.parse_list(lines)
  local entries = {}
  for i, line in ipairs(lines) do
    if i == 1 then goto continue end
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "" then goto continue end
    if trimmed:match("^[○●]") then goto continue end

    local marker = trimmed:sub(1, 1)
    local rest = trimmed:sub(2):match("^%s*(.+)$")
    if not rest then goto continue end

    local parts = {}
    for part in rest:gmatch("%S+") do
      table.insert(parts, part)
    end

    if #parts >= 1 then
      table.insert(entries, {
        current = (marker == "@"),
        trunk = (marker == "^"),
        branch = parts[1],
        raw = trimmed,
      })
    end
    ::continue::
  end
  return entries
end

function M.create(branch, callback)
  run_async("wt", { "switch", "--create", branch }, function(ok, lines, stderr)
    if ok then
      local path = nil
      for _, line in ipairs(lines) do
        local p = line:match("worktree @ (.+)")
        if p then
          path = p
          break
        end
      end
      callback(true, path)
    else
      callback(false, table.concat(stderr or lines or {}, "\n"))
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
  local args = { "merge", target }
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

function M.switch_to(branch, callback)
  M.get_path(branch, function(path)
    if not path then return end
    vim.schedule(function()
      vim.cmd("cd " .. vim.fn.fnameescape(path))
      if callback then callback() end
    end)
  end)
end

function M.create_for_task(branch, callback)
  M.create(branch, function(ok, path)
    if ok then
      if path then
        vim.schedule(function()
          vim.cmd("cd " .. vim.fn.fnameescape(path))
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

return M
