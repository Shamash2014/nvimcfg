local M = {}
local xml = require("djinni.pragmas.xml")

local function build_section(entries, name)
  if not entries or #entries == 0 then
    return ""
  end
  local items = {}
  for _, entry in ipairs(entries) do
    local desc = (entry.desc and entry.desc ~= "") and entry.desc or "(no description)"
    local attrs = {}
    if entry.file then
      attrs.file = entry.file .. (entry.line and (":" .. entry.line) or "")
    end
    table.insert(items, "  " .. xml.tag(name, attrs, desc))
  end
  return table.concat(items, "\n")
end

function M.assemble(scan_result)
  local parts = {}

  local project_section = build_section(scan_result.project, "project")
  if project_section ~= "" then
    table.insert(parts, project_section)
  end

  local constraint_section = build_section(scan_result.constraint, "constraint")
  if constraint_section ~= "" then
    table.insert(parts, constraint_section)
  end

  local stack_section = build_section(scan_result.stack, "stack")
  if stack_section ~= "" then
    table.insert(parts, stack_section)
  end

  local convention_section = build_section(scan_result.convention, "convention")
  if convention_section ~= "" then
    table.insert(parts, convention_section)
  end

  if #parts > 0 then
    return "<project>\n" .. table.concat(parts, "\n") .. "\n</project>"
  end
  return ""
end

return M
