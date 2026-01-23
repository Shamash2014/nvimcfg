local M = {}

local cache = {}
local cache_ttl = 30

function M.get_env(cwd)
  cwd = cwd or vim.fn.getcwd()

  local now = os.time()
  local cached = cache[cwd]
  if cached and (now - cached.time) < cache_ttl then
    return cached.env
  end

  local mise_bin = vim.fn.exepath("mise")
  if mise_bin == "" then
    return {}
  end

  local output = vim.fn.system(string.format(
    "cd %s && %s env --shell bash 2>/dev/null",
    vim.fn.shellescape(cwd),
    mise_bin
  ))

  if vim.v.shell_error ~= 0 then
    return {}
  end

  local env = {}
  for line in output:gmatch("[^\n]+") do
    local key, value = line:match("^export ([%w_]+)='(.-)'$")
    if not key then
      key, value = line:match('^export ([%w_]+)="(.-)"$')
    end
    if not key then
      key, value = line:match("^export ([%w_]+)=(.-)$")
    end
    if key and value then
      env[key] = value
    end
  end

  cache[cwd] = { env = env, time = now }
  return env
end

function M.clear_cache(cwd)
  if cwd then
    cache[cwd] = nil
  else
    cache = {}
  end
end

return M
