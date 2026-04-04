local M = {}

local SEPARATOR_CHAR = "~"
M.SEPARATOR = string.rep(SEPARATOR_CHAR, 45)

function M.find_separator(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = #lines, 1, -1 do
    if lines[i]:match("^" .. SEPARATOR_CHAR .. "+$") then
      return i - 1
    end
  end
  return nil
end

function M.get_input_text(buf)
  local sep = M.find_separator(buf)
  if not sep then
    return ""
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  if sep + 1 > line_count then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(buf, sep + 1, -1, false)
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("^▎ ", "")
  end
  local text = table.concat(lines, "\n")
  return text:match("^%s*(.-)%s*$")
end

function M.clear_input(buf)
  local sep = M.find_separator(buf)
  if not sep then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, sep + 1, line_count, false, { "" })
end

function M.insert_above_separator(buf, lines)
  local sep = M.find_separator(buf)
  if not sep then
    return
  end
  vim.api.nvim_buf_set_lines(buf, sep, sep, false, lines)
end

function M.jump_to_input(buf)
  local sep = M.find_separator(buf)
  if not sep then
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end
  vim.api.nvim_win_set_cursor(win, { sep + 2, 0 })
  vim.cmd("startinsert")
end

function M.ensure_separator(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first = nil
  local extras = {}
  for i, line in ipairs(lines) do
    if line:match("^" .. SEPARATOR_CHAR .. "+$") then
      if not first then
        first = i - 1
      else
        table.insert(extras, i - 1)
      end
    end
  end
  for j = #extras, 1, -1 do
    vim.api.nvim_buf_set_lines(buf, extras[j], extras[j] + 1, false, {})
  end
  if not first then
    local line_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { "", M.SEPARATOR, "" })
  end
end

return M
