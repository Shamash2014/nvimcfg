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
    cb("", "failed to spawn glab", -1)
  end
end

local function decode_json(s)
  if s == nil or s == "" then return nil end
  local ok, data = pcall(vim.json.decode, s)
  if not ok then return nil end
  return data
end

local function normalize_job(status)
  status = tostring(status or ""):lower()
  if status == "success" then return "success" end
  if status == "failed" then return "failure" end
  if status == "canceled" or status == "cancelled" then return "cancelled" end
  if status == "skipped" then return "skipped" end
  return "running"
end

local function overall_from_pipeline_status(status)
  status = tostring(status or ""):lower()
  if status == "success" then return "success" end
  if status == "failed" then return "failure" end
  if status == "canceled" or status == "cancelled" then return "cancelled" end
  if status == "skipped" then return "success" end
  return "running"
end

local project_id_cache = {}

local function resolve_project_id(callback)
  local key = vim.fn.getcwd()
  if project_id_cache[key] then
    callback(project_id_cache[key])
    return
  end
  run_cmd({ "glab", "repo", "view", "-F", "json" }, function(out, err, code)
    if code ~= 0 then
      callback(nil, ("glab repo view failed: %s"):format((err ~= "" and err or out):sub(1, 200)))
      return
    end
    local data = decode_json(out)
    if type(data) ~= "table" or not data.id then
      callback(nil, "failed to resolve GitLab project id")
      return
    end
    project_id_cache[key] = data.id
    callback(data.id, nil)
  end)
end

local function fetch_jobs(project_id, pipeline_id, callback)
  local path = string.format("projects/%s/pipelines/%s/jobs?per_page=100", project_id, pipeline_id)
  run_cmd({ "glab", "api", path }, function(out, err, code)
    if code ~= 0 then
      callback({}, ("glab api jobs failed: %s"):format((err ~= "" and err or out):sub(1, 200)))
      return
    end
    local data = decode_json(out) or {}
    local items = {}
    for _, job in ipairs(data) do
      items[#items + 1] = {
        name = job.name or "job",
        status = normalize_job(job.status),
        url = job.web_url or "",
      }
    end
    callback(items, nil)
  end)
end

function M.fetch(ctx, callback)
  local branch = ctx and ctx.branch
  if not branch or branch == "" then
    callback(nil, "no branch given")
    return
  end
  resolve_project_id(function(project_id, err)
    if not project_id then
      callback(nil, err or "project id unknown")
      return
    end
    local path = string.format("projects/%s/pipelines?ref=%s&per_page=1&order_by=id&sort=desc", project_id, vim.uri_encode(branch))
    run_cmd({ "glab", "api", path }, function(out, err2, code)
      if code ~= 0 then
        callback(nil, ("glab api pipelines failed: %s"):format((err2 ~= "" and err2 or out):sub(1, 200)))
        return
      end
      local list = decode_json(out)
      if type(list) ~= "table" or #list == 0 then
        callback({ overall = "running", items = {}, ref_url = "" }, nil)
        return
      end
      local pipeline = list[1]
      local pipeline_id = pipeline.id
      local pipeline_url = pipeline.web_url or ""
      local pipeline_status = pipeline.status
      fetch_jobs(project_id, pipeline_id, function(items)
        local overall = overall_from_pipeline_status(pipeline_status)
        callback({ overall = overall, items = items, ref_url = pipeline_url }, nil)
      end)
    end)
  end)
end

return M
