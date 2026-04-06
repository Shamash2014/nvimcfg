local M = {}

local enable_warned = false

local function opted_out()
  local v = vim.env.NVIM_UI2
  if v == nil or v == "" then
    return false
  end
  v = string.lower(vim.trim(v))
  return v == "0"
    or v == "false"
    or v == "no"
    or v == "off"
    or v == "n"
    or v == "disabled"
end

local function err_is_missing_module(err)
  local s = tostring(err or ""):lower()
  if s:find("ui2", 1, true) == nil then
    return false
  end
  return s:find("not found", 1, true) ~= nil
    or s:find("cannot find", 1, true) ~= nil
    or s:find("can't find", 1, true) ~= nil
end

local function enable()
  if opted_out() then
    return
  end
  local ok, err = pcall(function()
    require("vim._core.ui2").enable({})
  end)
  if ok or err_is_missing_module(err) then
    return
  end
  if not enable_warned then
    enable_warned = true
    vim.notify("[ui2] enable failed: " .. tostring(err), vim.log.levels.WARN)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("UIEnter", {
    group = vim.api.nvim_create_augroup("UserUi2", { clear = true }),
    pattern = "*",
    callback = enable,
  })
  vim.schedule(enable)
end

return M
