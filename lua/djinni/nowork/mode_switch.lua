local M = {}

M.modes = { "routine", "autorun", "planner" }

function M.apply(droid, mode_name, opts)
  opts = opts or {}
  if not droid or not mode_name or mode_name == droid.mode then return false end
  local ok, policy = pcall(require, "djinni.nowork.modes." .. mode_name)
  if not ok then
    if opts.notify_error ~= false then
      vim.notify("nowork: failed to load mode '" .. tostring(mode_name) .. "'", vim.log.levels.ERROR)
    end
    return false
  end
  droid.mode = mode_name
  droid.policy = policy
  if droid.log_buf and droid.log_buf.append then
    droid.log_buf:append("[mode → " .. mode_name .. "]")
  end
  require("djinni.nowork.status_panel").update()
  if opts.after_switch then
    opts.after_switch(droid, mode_name, policy)
  end
  return true, policy
end

function M.select(droid, opts)
  opts = opts or {}
  Snacks.picker.select(opts.modes or M.modes, {
    prompt = opts.prompt or "switch mode",
  }, function(mode_name)
    if not mode_name then return end
    local ok = M.apply(droid, mode_name, opts)
    if ok and opts.on_switched then
      opts.on_switched(droid, mode_name, droid.policy)
    end
  end)
end

return M
