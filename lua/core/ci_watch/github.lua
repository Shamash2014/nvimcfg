local M = {}

local function run_cmd(cmd, cb)
  local stdout_data, stderr_data = {}, {}
  local ok, job = pcall(vim.fn.jobstart, cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, d) stdout_data = d or {} end,
    on_stderr = function(_, d) stderr_data = d or {} end,
    on_exit = function(_, code)
      local out = table.concat(stdout_data, "\n")
      local err = table.concat(stderr_data, "\n")
      cb(out, err, code)
    end,
  })
  if not ok or job <= 0 then
    cb("", "failed to spawn gh", -1)
  end
end

local function decode_json(s)
  if s == nil or s == "" then return nil end
  local ok, data = pcall(vim.json.decode, s)
  if not ok then return nil end
  return data
end

local function normalize(status, conclusion)
  status = tostring(status or ""):lower()
  conclusion = tostring(conclusion or ""):lower()
  if status == "completed" or status == "success" or status == "failure" or status == "cancelled" or status == "skipped" then
    local term = conclusion ~= "" and conclusion or status
    if term == "success" then return "success" end
    if term == "failure" then return "failure" end
    if term == "cancelled" then return "cancelled" end
    if term == "skipped" then return "skipped" end
    return "unknown"
  end
  if status == "in_progress" or status == "queued" or status == "waiting" or status == "pending" or status == "requested" then
    return "running"
  end
  return "unknown"
end

local function overall_from_items(items)
  local any_running, any_failed = false, false
  for _, it in ipairs(items) do
    if it.status == "running" or it.status == "pending" then
      any_running = true
    elseif it.status == "failure" then
      any_failed = true
    end
  end
  if any_running then return "running" end
  if any_failed then return "failure" end
  return "success"
end

local function fetch_pr_checks(pr_number, pr_url, callback)
  run_cmd({ "gh", "pr", "checks", tostring(pr_number), "--json", "name,state,conclusion,link" }, function(out, err, code)
    if code ~= 0 then
      callback(nil, ("gh pr checks failed: %s"):format((err ~= "" and err or out):sub(1, 200)))
      return
    end
    local data = decode_json(out)
    if type(data) ~= "table" then
      callback(nil, "failed to parse gh pr checks output")
      return
    end
    local items = {}
    for _, entry in ipairs(data) do
      items[#items + 1] = {
        name = entry.name or "check",
        status = normalize(entry.state, entry.conclusion),
        url = entry.link or pr_url,
      }
    end
    callback({ overall = overall_from_items(items), items = items, ref_url = pr_url }, nil)
  end)
end

local function fetch_run_list(branch, callback)
  run_cmd({ "gh", "run", "list", "--branch", branch, "--limit", "10", "--json", "databaseId,name,status,conclusion,url" }, function(out, err, code)
    if code ~= 0 then
      callback(nil, ("gh run list failed: %s"):format((err ~= "" and err or out):sub(1, 200)))
      return
    end
    local data = decode_json(out)
    if type(data) ~= "table" then
      callback(nil, "failed to parse gh run list output")
      return
    end
    if #data == 0 then
      callback({ overall = "running", items = {}, ref_url = "" }, nil)
      return
    end
    local items = {}
    local ref_url = ""
    for _, entry in ipairs(data) do
      items[#items + 1] = {
        name = entry.name or "run",
        status = normalize(entry.status, entry.conclusion),
        url = entry.url or "",
      }
      if ref_url == "" and entry.url then ref_url = entry.url end
    end
    callback({ overall = overall_from_items(items), items = items, ref_url = ref_url }, nil)
  end)
end

local function rollup_status(rollup)
  if type(rollup) ~= "table" or #rollup == 0 then return "unknown" end
  local any_running, any_failed = false, false
  for _, r in ipairs(rollup) do
    local s = normalize(r.status, r.conclusion)
    if s == "running" then any_running = true
    elseif s == "failure" then any_failed = true end
  end
  if any_running then return "running" end
  if any_failed then return "failure" end
  return "success"
end

function M.list_my_prs(callback)
  run_cmd({
    "gh", "pr", "list", "--author", "@me", "--state", "open",
    "--json", "number,title,headRefName,url,statusCheckRollup",
    "--limit", "30",
  }, function(out, err, code)
    if code ~= 0 then
      callback(nil, ("gh pr list failed: %s"):format((err ~= "" and err or out):sub(1, 200)))
      return
    end
    local data = decode_json(out)
    if type(data) ~= "table" then
      callback(nil, "failed to parse gh pr list output")
      return
    end
    local items = {}
    for _, entry in ipairs(data) do
      items[#items + 1] = {
        kind = "pr",
        number = entry.number,
        title = entry.title or "",
        branch = entry.headRefName or "",
        url = entry.url or "",
        status = rollup_status(entry.statusCheckRollup),
      }
    end
    callback(items, nil)
  end)
end

function M.list_recent_runs(callback)
  run_cmd({
    "gh", "run", "list", "--limit", "30",
    "--json", "databaseId,name,status,conclusion,headBranch,event,url,createdAt",
  }, function(out, err, code)
    if code ~= 0 then
      callback(nil, ("gh run list failed: %s"):format((err ~= "" and err or out):sub(1, 200)))
      return
    end
    local data = decode_json(out)
    if type(data) ~= "table" then
      callback(nil, "failed to parse gh run list output")
      return
    end
    local items = {}
    for _, entry in ipairs(data) do
      items[#items + 1] = {
        kind = "run",
        id = entry.databaseId,
        name = entry.name or "run",
        branch = entry.headBranch or "",
        event = entry.event or "",
        url = entry.url or "",
        created_at = entry.createdAt or "",
        status = normalize(entry.status, entry.conclusion),
      }
    end
    callback(items, nil)
  end)
end

function M.fetch_run_log(run_id, opts, callback)
  opts = opts or {}
  local cmd = { "gh", "run", "view", tostring(run_id) }
  cmd[#cmd + 1] = opts.failed_only == false and "--log" or "--log-failed"
  run_cmd(cmd, function(out, err, code)
    if code ~= 0 then
      if opts.failed_only ~= false then
        M.fetch_run_log(run_id, { failed_only = false }, callback)
        return
      end
      callback(nil, ("gh run view failed: %s"):format((err ~= "" and err or out):sub(1, 400)))
      return
    end
    callback(out, nil)
  end)
end

function M.fetch(ctx, callback)
  local branch = ctx and ctx.branch
  if not branch or branch == "" then
    callback(nil, "no branch given")
    return
  end
  run_cmd({ "gh", "pr", "view", branch, "--json", "number,url,state" }, function(out, err, code)
    if code == 0 then
      local data = decode_json(out)
      if type(data) == "table" and data.number then
        fetch_pr_checks(data.number, data.url or "", callback)
        return
      end
    end
    local stderr_lower = (err or ""):lower()
    if stderr_lower:find("no pull requests found") or stderr_lower:find("no open pull requests") or code ~= 0 then
      fetch_run_list(branch, callback)
      return
    end
    fetch_run_list(branch, callback)
  end)
end

return M
