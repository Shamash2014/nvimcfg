local M = {}

local function run_async(cmd, args, callback)
  local stdout_lines = {}
  local stderr_lines = {}
  vim.fn.jobstart({ cmd, unpack(args) }, {
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
      vim.schedule(function()
        callback(code == 0, stdout_lines, stderr_lines)
      end)
    end,
  })
end

function M.is_available(callback)
  run_async("git", { "worktree", "list" }, function(ok, lines)
    if not ok then
      callback(false)
      return
    end
    callback(#lines > 1)
  end)
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

function M.get_worktree_path(branch, callback)
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

local statusline_cache = ""
local statusline_timer = nil

local function refresh_statusline()
  run_async("wt", { "list", "statusline", "--format=claude-code" }, function(ok, lines)
    if ok and #lines > 0 then
      statusline_cache = lines[1]
    else
      statusline_cache = ""
    end
    vim.cmd("redrawstatus")
  end)
end

function M.statusline()
  return statusline_cache
end

function M.start_statusline(interval_ms)
  if statusline_timer then return end
  if vim.fn.executable("wt") ~= 1 then return end

  interval_ms = interval_ms or 5000
  refresh_statusline()

  local timer = vim.uv.new_timer()
  if not timer then return end
  statusline_timer = timer
  statusline_timer:start(interval_ms, interval_ms, vim.schedule_wrap(refresh_statusline))
end

function M.stop_statusline()
  if statusline_timer then
    statusline_timer:stop()
    statusline_timer:close()
    statusline_timer = nil
  end
  statusline_cache = ""
end

function M.shutdown()
  M.stop_statusline()
end

return M
