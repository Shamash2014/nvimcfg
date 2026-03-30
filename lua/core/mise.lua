local M = {}

local cache = {}
local cache_ttl = 30
local refreshing = {}

local function parse_mise_output(output)
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
  return env
end

function M.refresh_env(cwd)
  cwd = cwd or vim.fn.getcwd()

  if refreshing[cwd] then
    return
  end

  local mise_bin = vim.fn.exepath("mise")
  if mise_bin == "" then
    return
  end

  refreshing[cwd] = true

  vim.system(
    { mise_bin, "env", "--shell", "bash" },
    { cwd = cwd, text = true },
    function(obj)
      vim.schedule(function()
        refreshing[cwd] = nil
        if obj.code == 0 and obj.stdout then
          cache[cwd] = { env = parse_mise_output(obj.stdout), time = os.time() }
        end
      end)
    end
  )
end

function M.get_env(cwd)
  cwd = cwd or vim.fn.getcwd()

  local now = os.time()
  local cached = cache[cwd]

  if cached and (now - cached.time) < cache_ttl then
    return cached.env
  end

  M.refresh_env(cwd)

  return cached and cached.env or {}
end

function M.clear_cache(cwd)
  if cwd then
    cache[cwd] = nil
  else
    cache = {}
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("MiseEnv", { clear = true })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      M.refresh_env(vim.fn.getcwd())
    end,
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      M.refresh_env(vim.fn.getcwd())
    end,
  })
end

M.setup()

return M
