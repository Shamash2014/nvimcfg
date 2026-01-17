local M = {}

local PHASE_INFO = {
  requirements = { name = "Requirements", icon = "📝", order = 1 },
  design = { name = "Design", icon = "🎨", order = 2 },
  tasks = { name = "Tasks", icon = "✅", order = 3 },
  implementation = { name = "Implementation", icon = "🔨", order = 4 },
  review = { name = "Review", icon = "🔍", order = 5 },
  testing = { name = "Testing", icon = "🧪", order = 6 },
  completion = { name = "Completion", icon = "✅✅", order = 7 },
}

function M.get_phase_info(phase_id)
  return PHASE_INFO[phase_id]
end

function M.list_phases()
  local phases = {}
  for id, info in pairs(PHASE_INFO) do
    table.insert(phases, vim.tbl_extend("force", { id = id }, info))
  end
  table.sort(phases, function(a, b) return a.order < b.order end)
  return phases
end

function M.get_next_phase(current_phase)
  local current_order = PHASE_INFO[current_phase].order
  for id, info in pairs(PHASE_INFO) do
    if info.order == current_order + 1 then
      return id
    end
  end
  return nil
end

function M.get_prev_phase(current_phase)
  local current_order = PHASE_INFO[current_phase].order
  for id, info in pairs(PHASE_INFO) do
    if info.order == current_order - 1 then
      return id
    end
  end
  return nil
end

return M
