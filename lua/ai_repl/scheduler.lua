local M = {}

M.schedules = {}
M._next_id = 1

local function parse_interval(str)
  local num, unit = str:match("^(%d+)([mhsMH])$")
  if not num then return nil end
  num = tonumber(num)
  if unit == "h" or unit == "H" then
    return num * 3600 * 1000
  elseif unit == "m" or unit == "M" then
    return num * 60 * 1000
  elseif unit == "s" then
    return num * 1000
  end
  return nil
end

function M.add(interval_str, prompt, opts)
  opts = opts or {}
  local interval_ms = parse_interval(interval_str)
  if not interval_ms then
    return nil, "Invalid interval: use Nm (minutes), Nh (hours), or Ns (seconds)"
  end

  if interval_ms < 30000 then
    return nil, "Minimum interval is 30s"
  end

  local id = M._next_id
  M._next_id = M._next_id + 1

  local timer = vim.uv.new_timer()
  local entry = {
    id = id,
    prompt = prompt,
    interval_str = interval_str,
    interval_ms = interval_ms,
    timer = timer,
    created_at = os.time(),
    last_run = nil,
    next_run = os.time() + math.floor(interval_ms / 1000),
    run_count = 0,
  }

  timer:start(interval_ms, interval_ms, vim.schedule_wrap(function()
    entry.last_run = os.time()
    entry.next_run = os.time() + math.floor(interval_ms / 1000)
    entry.run_count = entry.run_count + 1
    require("core.tasks").run_ai_task(entry.prompt, { background = true, scheduled = true })
  end))

  M.schedules[id] = entry
  M.save()
  return id
end

function M.remove(id)
  local entry = M.schedules[id]
  if not entry then return false end

  if entry.timer then
    entry.timer:stop()
    if not entry.timer:is_closing() then
      entry.timer:close()
    end
  end

  M.schedules[id] = nil
  M.save()
  return true
end

function M.list()
  local result = {}
  for _, entry in pairs(M.schedules) do
    table.insert(result, {
      id = entry.id,
      prompt = entry.prompt,
      interval_str = entry.interval_str,
      last_run = entry.last_run,
      next_run = entry.next_run,
      run_count = entry.run_count,
      created_at = entry.created_at,
    })
  end
  table.sort(result, function(a, b) return a.id < b.id end)
  return result
end

local function get_save_path()
  return vim.fn.stdpath("data") .. "/ai_repl_schedules.json"
end

function M.save()
  local data = {}
  for _, entry in pairs(M.schedules) do
    table.insert(data, {
      prompt = entry.prompt,
      interval_str = entry.interval_str,
    })
  end

  local json = vim.json.encode(data)
  local path = get_save_path()
  local f = io.open(path, "w")
  if f then
    f:write(json)
    f:close()
  end
end

function M.load()
  local path = get_save_path()
  local f = io.open(path, "r")
  if not f then return end

  local content = f:read("*a")
  f:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return end

  for _, item in ipairs(data) do
    if item.prompt and item.interval_str then
      M.add(item.interval_str, item.prompt)
    end
  end
end

function M.init()
  M.load()
end

function M.shutdown()
  for _, entry in pairs(M.schedules) do
    if entry.timer then
      entry.timer:stop()
      if not entry.timer:is_closing() then
        entry.timer:close()
      end
    end
  end
end

return M
