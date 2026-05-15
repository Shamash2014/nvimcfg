local M = {}

local did_setup = false
local applied = {}

local function capture(cmd, cwd)
  if vim.fn.executable(cmd[1]) ~= 1 then
    return {}
  end

  local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 or result.stdout == "" then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, result.stdout)
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  local env = {}
  for key, value in pairs(decoded) do
    if type(key) == "string" and type(value) == "string" then
      env[key] = value
    end
  end
  return env
end

function M.sync()
  local cwd = vim.fn.getcwd(0)
  local next_env = {}

  for key, value in pairs(capture({ "mise", "env", "-J", "-C", cwd }, cwd)) do
    next_env[key] = value
  end

  for key, value in pairs(capture({ "direnv", "export", "json", cwd }, cwd)) do
    next_env[key] = value
  end

  for key in pairs(applied) do
    if next_env[key] == nil then
      vim.env[key] = nil
    end
  end

  for key, value in pairs(next_env) do
    if vim.env[key] ~= value then
      vim.env[key] = value
    end
  end

  applied = next_env
end

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  local group = vim.api.nvim_create_augroup("nvim3-env", { clear = true })

  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
    group = group,
    callback = function()
      M.sync()
    end,
  })

  vim.api.nvim_create_user_command("EnvSync", function()
    M.sync()
  end, { desc = "Re-sync mise + direnv env into vim.env" })

  M.sync()
end

return M
