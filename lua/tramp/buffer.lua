local M = {}

function M.set_content(lines)
  local bufnr = vim.api.nvim_get_current_buf()

  vim.bo[bufnr].modifiable = true

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].modified = false
end

function M.get_content()
  local bufnr = vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

function M.is_remote()
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name and name:match("^/ssh:")
end

function M.get_remote_path()
  if not M.is_remote() then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_name(bufnr)
end

return M
