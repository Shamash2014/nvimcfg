local M = {}

local HL_CHECKED = "DiagnosticOk"
local HL_RUNNING = "DiagnosticWarn"
local HL_UNCHECKED = "Comment"
local HL_STATUS = "Special"

function M.get_plan_header_line(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("^### Plan%s*$") then
      return i - 1
    end
  end
  return nil
end

function M.parse_plan(lines, start_line)
  local steps = {}
  local i = 1
  while i <= #lines do
    if lines[i]:match("^### Plan%s*$") then
      i = i + 1
      break
    end
    i = i + 1
  end
  if i > #lines then return steps end

  while i <= #lines do
    local line = lines[i]
    if line:match("^###") or line:match("^%-%-%-") then break end
    local checked, text = line:match("^%- %[(x?)%] (.+)$")
    if checked ~= nil then
      local base_text = text
      local status_text = nil
      local s = text:match("[✓●].+$")
      if s then
        status_text = s
        base_text = vim.trim(text:sub(1, #text - #s))
      end
      table.insert(steps, {
        text = base_text,
        checked = checked == "x",
        status_text = status_text,
        line_nr = (start_line or 0) + i - 1,
      })
    elseif line:match("^%S") then
      break
    end
    i = i + 1
  end
  return steps
end

function M.update_step(buf, step_index, checked, status_text)
  local header = M.get_plan_header_line(buf)
  if not header then return end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local steps = M.parse_plan(lines, 0)
  local step = steps[step_index]
  if not step then return end

  local mark = checked and "x" or " "
  local new_line = ("- [%s] %s"):format(mark, step.text)
  if status_text then
    new_line = new_line .. " " .. status_text
  end
  vim.api.nvim_buf_set_lines(buf, step.line_nr, step.line_nr + 1, false, { new_line })
end

function M.add_step(buf, text)
  local header = M.get_plan_header_line(buf)
  if not header then return end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local steps = M.parse_plan(lines, 0)
  local num = #steps + 1
  local insert_line = header + 1
  if #steps > 0 then
    insert_line = steps[#steps].line_nr + 1
  end
  local new_line = ("- [ ] %d. %s"):format(num, text)
  vim.api.nvim_buf_set_lines(buf, insert_line, insert_line, false, { new_line })
end

function M.remove_step(buf, step_index)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local steps = M.parse_plan(lines, 0)
  local step = steps[step_index]
  if not step then return end
  vim.api.nvim_buf_set_lines(buf, step.line_nr, step.line_nr + 1, false, {})
end

function M.apply_extmarks(buf, ns)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local steps = M.parse_plan(lines, 0)
  for _, step in ipairs(steps) do
    local line = lines[step.line_nr + 1]
    if not line then goto continue end

    local hl = HL_UNCHECKED
    if step.checked then
      hl = HL_CHECKED
    elseif step.status_text and step.status_text:match("●") then
      hl = HL_RUNNING
    end

    vim.api.nvim_buf_set_extmark(buf, ns, step.line_nr, 0, {
      end_col = #line,
      hl_group = hl,
    })

    if step.status_text then
      local status_start = line:find(step.status_text, 1, true)
      if status_start then
        vim.api.nvim_buf_set_extmark(buf, ns, step.line_nr, status_start - 1, {
          end_col = #line,
          hl_group = HL_STATUS,
          priority = 200,
        })
      end
    end

    ::continue::
  end
end

return M
