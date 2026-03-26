local M = {}

local HL_ACTIVE = "DiagnosticOk"
local HL_DONE = "DiagnosticInfo"
local HL_NAME = "Bold"
local HL_CONNECTOR = "Comment"

function M.parse_agents(lines, start_line)
  local agents = {}
  local offset = start_line or 0
  local i = 1

  while i <= #lines do
    if lines[i]:match("^### Agents%s*$") then
      i = i + 1
      break
    end
    i = i + 1
  end
  if i > #lines then return agents end

  local current = nil
  while i <= #lines do
    local line = lines[i]
    if line:match("^###") or line:match("^%-%-%-") then break end

    local connector, bullet, id, name = line:match("^([├└])─ ([●✓]) (agent%-[%w]+): (.+)$")
    if connector then
      if current then table.insert(agents, current) end
      current = {
        id = id,
        name = name,
        status = bullet == "✓" and "done" or "active",
        sub_tools = {},
        line_nr = offset + i - 1,
      }
    elseif current then
      local sub_conn, sub_rest = line:match("^[│ ]  ([├└])─ (.+)$")
      if sub_conn then
        table.insert(current.sub_tools, {
          text = sub_rest,
          is_last = sub_conn == "└",
          line_nr = offset + i - 1,
        })
      elseif not line:match("^[│ ]") then
        if current then table.insert(agents, current) end
        current = nil
      end
    end
    i = i + 1
  end
  if current then table.insert(agents, current) end
  return agents
end

function M.format_agent(id, name, status, sub_tools, is_last)
  local out = {}
  local connector = is_last and "└─" or "├─"
  local bullet = status == "done" and "✓" or "●"
  table.insert(out, ("%s %s %s: %s"):format(connector, bullet, id, name))

  local indent = is_last and "   " or "│  "
  sub_tools = sub_tools or {}
  for j, tool in ipairs(sub_tools) do
    local sub_conn = (j == #sub_tools) and "└─" or "├─"
    table.insert(out, indent .. sub_conn .. " " .. tool.text)
  end
  return out
end

function M.add_agent(buf, id, name)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local header_line = nil
  for i, line in ipairs(lines) do
    if line:match("^### Agents%s*$") then
      header_line = i - 1
      break
    end
  end

  if not header_line then
    local insert_at = #lines
    vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, {
      "### Agents",
      ("├─ ● %s: %s"):format(id, name),
    })
    return
  end

  local agents = M.parse_agents(lines, 0)
  local insert_at = header_line + 1
  if #agents > 0 then
    local last = agents[#agents]
    local last_line = last.line_nr
    if #last.sub_tools > 0 then
      last_line = last.sub_tools[#last.sub_tools].line_nr
    end
    insert_at = last_line + 1

    local old = lines[last.line_nr + 1]
    if old then
      local updated = old:gsub("^└─", "├─")
      vim.api.nvim_buf_set_lines(buf, last.line_nr, last.line_nr + 1, false, { updated })
    end
  end

  local new_line = ("└─ ● %s: %s"):format(id, name)
  vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, { new_line })
end

function M.update_agent_status(buf, agent_id, status)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local agents = M.parse_agents(lines, 0)

  for _, agent in ipairs(agents) do
    if agent.id == agent_id then
      local line = lines[agent.line_nr + 1]
      if not line then return end
      local old_bullet = agent.status == "done" and "✓" or "●"
      local new_bullet = status == "done" and "✓" or "●"
      local updated = line:gsub(old_bullet, new_bullet, 1)
      vim.api.nvim_buf_set_lines(buf, agent.line_nr, agent.line_nr + 1, false, { updated })
      return
    end
  end
end

function M.apply_extmarks(buf, ns)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local agents = M.parse_agents(lines, 0)

  for _, agent in ipairs(agents) do
    local line = lines[agent.line_nr + 1]
    if not line then goto continue end

    local conn_end = line:find("─ ") or 1
    vim.api.nvim_buf_set_extmark(buf, ns, agent.line_nr, 0, {
      end_col = math.min(conn_end + 1, #line),
      hl_group = HL_CONNECTOR,
    })

    local bullet_pos = line:find(agent.status == "done" and "✓" or "●")
    if bullet_pos then
      local hl = agent.status == "done" and HL_DONE or HL_ACTIVE
      vim.api.nvim_buf_set_extmark(buf, ns, agent.line_nr, bullet_pos - 1, {
        end_col = bullet_pos + (agent.status == "done" and 2 or 2),
        hl_group = hl,
      })
    end

    local name_start = line:find(agent.name, 1, true)
    if name_start then
      vim.api.nvim_buf_set_extmark(buf, ns, agent.line_nr, name_start - 1, {
        end_col = name_start - 1 + #agent.name,
        hl_group = HL_NAME,
      })
    end

    for _, tool in ipairs(agent.sub_tools) do
      local tline = lines[tool.line_nr + 1]
      if tline then
        vim.api.nvim_buf_set_extmark(buf, ns, tool.line_nr, 0, {
          end_col = #tline,
          hl_group = HL_CONNECTOR,
        })
      end
    end

    ::continue::
  end
end

return M
