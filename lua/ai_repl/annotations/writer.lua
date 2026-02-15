local M = {}

function M.append(session_state, capture_mode, selection, note)
  local location

  if selection.start_line == selection.end_line then
    location = string.format("`%s:%d`", selection.file, selection.start_line)
  else
    location = string.format("`%s:%d-%d`", selection.file, selection.start_line, selection.end_line)
  end

  local lines = {}

  if note ~= "" then
    table.insert(lines, string.format("- **%s** — %s", location, note))
  else
    table.insert(lines, string.format("- **%s**", location))
  end

  if capture_mode == "snippet" and selection.text then
    local lang = selection.filetype or ""
    table.insert(lines, " ```" .. lang)
    for _, line in ipairs(vim.split(selection.text, "\n")) do
      table.insert(lines, "" .. line)
    end
    table.insert(lines, " ```")
  end

  table.insert(lines, "")
  table.insert(lines, "")

  local bufnr = session_state.bufnr
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent write")
  end)

  local window = require("ai_repl.annotations.window")
  window.refresh(bufnr)
end

return M
