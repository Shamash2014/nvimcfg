local M = {}

local phases = require("ai_repl.phases")

local spec_state = {
  current_phase = "requirements",
  session_id = nil,
  artifacts_dir = nil,
}

function M.init_spec_session(session_id)
  local artifacts_dir = ".ai-repl/specs/" .. session_id
  vim.fn.mkdir(artifacts_dir, "p")

  spec_state = {
    current_phase = "requirements",
    session_id = session_id,
    artifacts_dir = artifacts_dir,
  }
  return true
end

function M.get_current_phase()
  return spec_state.current_phase
end

function M.get_phase_info(phase_id)
  return phases.get_phase_info(phase_id or spec_state.current_phase)
end

function M.advance_to_next_phase()
  local next_phase = phases.get_next_phase(spec_state.current_phase)
  if not next_phase then
    return false, "Already at final phase"
  end
  spec_state.current_phase = next_phase
  return true, { current_phase = next_phase }
end

function M.move_to_previous_phase()
  local prev_phase = phases.get_prev_phase(spec_state.current_phase)
  if not prev_phase then
    return false, "Already at first phase"
  end
  spec_state.current_phase = prev_phase
  return true, { current_phase = prev_phase }
end

function M.jump_to_phase(target_phase)
  if target_phase == spec_state.current_phase then
    return true, "already_in_phase"
  end
  spec_state.current_phase = target_phase
  return true, { current_phase = target_phase }
end

function M.get_artifact_path(phase_id)
  phase_id = phase_id or spec_state.current_phase
  return spec_state.artifacts_dir .. "/" .. phase_id .. ".md"
end

function M.get_phase_progress()
  local phase_list = phases.list_phases()
  local current_info = phases.get_phase_info(spec_state.current_phase)
  return {
    completed = current_info.order - 1,
    total = #phase_list,
    percentage = math.floor(((current_info.order - 1) / #phase_list) * 100),
    current_phase = spec_state.current_phase,
  }
end

function M.format_progress_display()
  local progress = M.get_phase_progress()
  local phase_info = M.get_phase_info()
  return string.format("%s %s (%d/%d)", phase_info.icon, phase_info.name, progress.completed, progress.total)
end

function M.export_spec()
  local output_path = spec_state.artifacts_dir .. "/SPEC.md"
  local parts = { "# Spec: " .. spec_state.session_id, "", "Generated: " .. os.date("%Y-%m-%d %H:%M:%S"), "" }

  for _, phase_info in ipairs(phases.list_phases()) do
    local artifact_path = M.get_artifact_path(phase_info.id)
    if vim.fn.filereadable(artifact_path) == 1 then
      table.insert(parts, "## " .. phase_info.icon .. " " .. phase_info.name)
      table.insert(parts, "")
      local file = io.open(artifact_path, "r")
      if file then
        table.insert(parts, file:read("*all"))
        file:close()
        table.insert(parts, "")
      end
    end
  end

  local file = io.open(output_path, "w")
  if not file then
    return false, "Cannot write spec file"
  end
  file:write(table.concat(parts, "\n"))
  file:close()
  return true, output_path
end

return M
