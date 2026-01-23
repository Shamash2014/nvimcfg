local M = {}

local MODE_INFO = {
  chat = { name = "Chat", icon = "💬", description = "Free-form conversation" },
  ralph_wiggum = { name = "Ralph Wiggum", icon = "🔄", description = "Persistent looping until task completion" },
}

local current_mode = "ralph_wiggum"

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

local MODE_ALIASES = {
  ralph = "ralph_wiggum",
}

function M.switch_mode(mode_id)
  mode_id = MODE_ALIASES[mode_id] or mode_id
  if not MODE_INFO[mode_id] then
    return false, "Unknown mode: " .. mode_id
  end
  if mode_id == current_mode then
    return true, "already_in_mode"
  end
  
  -- Disable previous mode if needed
  if current_mode == "ralph_wiggum" then
    local ralph = require("ai_repl.modes.ralph_wiggum")
    ralph.disable()
  end
  
  current_mode = mode_id
  
  -- Enable new mode if needed
  if mode_id == "ralph_wiggum" then
    local ralph = require("ai_repl.modes.ralph_wiggum")
    ralph.enable()
  end
  
  return true, { info = MODE_INFO[mode_id] }
end

function M.is_ralph_wiggum_mode()
  return current_mode == "ralph_wiggum"
end

return M
