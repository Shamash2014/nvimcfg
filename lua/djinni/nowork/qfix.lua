local M = {}

function M.build_item(opts)
  if not opts or not opts.filename then return nil end
  local text = opts.text or ""
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  return {
    filename = opts.filename,
    lnum = tonumber(opts.lnum) or 1,
    col = tonumber(opts.col) or 1,
    text = text,
  }
end

function M.set(items, opts)
  opts = opts or {}
  local action = opts.mode == "append" and "a" or " "
  local what = { items = items }
  if opts.title then what.title = opts.title end
  vim.fn.setqflist({}, action, what)
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "NoworkQfChanged" })
  if opts.open then
    vim.cmd("copen")
  end
end

return M
