local M = {}

local function acp_label(droid)
  if not droid.acp_modes or not droid.acp_modes.current_id then return nil end
  local id = droid.acp_modes.current_id
  for _, mode in ipairs(droid.acp_modes.available or {}) do
    if mode.id == id then
      return mode.name or mode.id
    end
  end
  return id
end

function M.compact(droid)
  if not droid then return "" end
  local bits = { "[" .. (droid.id or "?") .. "]" }
  if droid.status and droid.status ~= "" then
    bits[#bits + 1] = droid.status
  end
  if droid.model_name and droid.model_name ~= "" then
    bits[#bits + 1] = "model:" .. droid.model_name
  end
  local acp = acp_label(droid)
  if acp then
    bits[#bits + 1] = "acp:" .. acp
  end
  if droid.mode and droid.mode ~= "" then
    bits[#bits + 1] = "policy:" .. droid.mode
  end
  return table.concat(bits, "  ")
end

return M
