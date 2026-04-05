local M = {}

local HL_CONNECTOR = "Comment"
local HL_TOOL_NAME = "Function"
local HL_MCP = "Special"
local HL_OK = "DiagnosticOk"

function M.parse_tool_calls(lines, start_line)
  local calls = {}
  local current = nil
  local offset = start_line or 0

  for i, line in ipairs(lines) do
    local connector, rest = line:match("^([├└])─ (.+)$")
    if connector then
      if current then
        table.insert(calls, current)
      end
      local is_last = connector == "└"
      local is_mcp = rest:match("^mcp:") ~= nil
      local name, args = rest:match("^([%w_:%.]+)%((.-)%)$")
      if not name then
        name = rest:match("^([%w_:%.]+)") or rest
        args = ""
      end
      current = {
        name = name,
        args = args,
        result_lines = {},
        is_last = is_last,
        line_nr = offset + i - 1,
        is_mcp = is_mcp,
      }
    elseif current and (line:match("^│") or (current.is_last and line:match("^   "))) then
      local result = line:match("^│  (.*)$") or line:match("^   (.*)$") or ""
      table.insert(current.result_lines, result)
    else
      if current then
        table.insert(calls, current)
        current = nil
      end
    end
  end
  if current then
    table.insert(calls, current)
  end
  return calls
end

function M.format_tool_call(name, args, result, is_last)
  local out = {}
  local connector = is_last and "└─" or "├─"
  local arg_str = args or ""
  table.insert(out, ("%s %s(%s)"):format(connector, name, arg_str))

  if result then
    local result_lines = type(result) == "table" and result or { result }
    local prefix = is_last and "   " or "│  "
    for _, r in ipairs(result_lines) do
      table.insert(out, prefix .. r)
    end
  end
  return out
end

function M.append_tool_call(buf, name, args)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local insert_at = #lines

  for i = #lines, 1, -1 do
    if lines[i]:match("^%-%-%-") then
      insert_at = i - 1
      break
    end
  end

  for i = insert_at, 1, -1 do
    if lines[i]:match("^└─") then
      local old = lines[i]:gsub("^└─", "├─")
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { old })
      break
    end
  end

  local arg_str = args or ""
  local new_line = ("├─ %s(%s)"):format(name, arg_str)
  vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, { new_line })
end

function M.append_tool_result(buf, tool_line, result_text)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local line = lines[tool_line + 1]
  if not line then return end

  local is_last = line:match("^└─") ~= nil
  local prefix = is_last and "   " or "│  "

  local insert_at = tool_line + 1
  for i = tool_line + 2, #lines do
    local l = lines[i]
    if l:match("^│") or l:match("^   %S") then
      insert_at = i
    else
      break
    end
  end

  local result_lines = type(result_text) == "table" and result_text or { result_text }
  local new_lines = {}
  for _, r in ipairs(result_lines) do
    table.insert(new_lines, prefix .. r)
  end
  vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, new_lines)
end

function M.apply_extmarks(buf, ns)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local row = i - 1

    local connector_match = line:match("^[├└│]")
    if not connector_match then goto continue end

    local conn_end = line:find("─ ") or line:find("  ") or 1
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
      end_col = math.min(conn_end + 1, #line),
      hl_group = HL_CONNECTOR,
    })

    local tool_start, tool_end = line:find("[├└]─ (.-)%(")
    if tool_start then
      local name_start = line:find("─ ") + 2
      local paren = line:find("%(", name_start)
      if paren then
        local mcp_start = line:find("mcp:", name_start, true)
        if mcp_start and mcp_start == name_start then
          vim.api.nvim_buf_set_extmark(buf, ns, row, mcp_start - 1, {
            end_col = mcp_start + 3,
            hl_group = HL_MCP,
            priority = 200,
          })
          vim.api.nvim_buf_set_extmark(buf, ns, row, mcp_start + 3, {
            end_col = paren - 1,
            hl_group = HL_TOOL_NAME,
          })
        else
          vim.api.nvim_buf_set_extmark(buf, ns, row, name_start - 1, {
            end_col = paren - 1,
            hl_group = HL_TOOL_NAME,
          })
        end
      end
    end

    local ok_pos = line:find("✓")
    if ok_pos then
      vim.api.nvim_buf_set_extmark(buf, ns, row, ok_pos - 1, {
        end_col = ok_pos + 2,
        hl_group = HL_OK,
      })
    end

    ::continue::
  end
end

function M.extract_tool_at_cursor(lines, row)
  local line = lines[row]
  if not line then return nil end
  local name, args = line:match("^[├└]─ ([%w_:%.]+)%((.-)%)$")
  if not name then
    name = line:match("^[├└]─ ([%w_:%.]+)")
  end
  if name then
    return { name = name, args = args or "" }
  end
  return nil
end

return M
