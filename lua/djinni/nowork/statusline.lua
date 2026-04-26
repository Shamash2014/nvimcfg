local M = {}

function M.component()
  local ok_droid, droid_mod = pcall(require, "djinni.nowork.droid")
  if not ok_droid or not droid_mod or not droid_mod.active then return "" end
  local lifecycle = require("djinni.nowork.state")
  local active = {}
  for _, d in pairs(droid_mod.active) do
    if not lifecycle.is_finished(d) then active[#active + 1] = d end
  end
  if #active == 0 then return "" end
  local ok, out = pcall(require("djinni.nowork.status_components").statusline_render, active)
  if not ok then return "" end
  return out or ""
end

return M
