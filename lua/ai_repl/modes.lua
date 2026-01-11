local M = {}

local MODE_INFO = {
  chat = { name = "Chat", icon = "💬", description = "Free-form conversation" },
  spec = { name = "Spec", icon = "📋", description = "Spec-driven: Requirements→Design→Tasks→Implementation" },
}

local current_mode = "chat"

function M.get_current_mode()
  return current_mode
end

function M.get_mode_info(mode_id)
  return MODE_INFO[mode_id or current_mode]
end

function M.list_modes()
  local modes = {}
  for id, info in pairs(MODE_INFO) do
    table.insert(modes, vim.tbl_extend("force", { id = id }, info))
  end
  return modes
end

function M.switch_mode(mode_id)
  if not MODE_INFO[mode_id] then
    return false, "Unknown mode: " .. mode_id
  end
  if mode_id == current_mode then
    return true, "already_in_mode"
  end
  current_mode = mode_id
  return true, { info = MODE_INFO[mode_id] }
end

function M.is_spec_mode()
  return current_mode == "spec"
end

return M
