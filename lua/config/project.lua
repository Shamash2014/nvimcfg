local M = {}

local group = vim.api.nvim_create_augroup("nvim2-project", { clear = true })

local markers = {
  ".git",
  "mix.exs",
  "pubspec.yaml",
  "go.mod",
  "Cargo.toml",
  "pyproject.toml",
  "package.json",
  "Makefile",
}

function M.find_root(path)
  local match = vim.fs.find(markers, {
    path = vim.fs.dirname(path),
    upward = true,
    stop = vim.env.HOME,
  })[1]
  if not match then
    return nil
  end
  return vim.fs.dirname(match)
end

vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function(ev)
    local name = vim.api.nvim_buf_get_name(ev.buf)
    if name == "" or vim.bo[ev.buf].buftype ~= "" then
      return
    end
    local root = M.find_root(name)
    if root and root ~= vim.fn.getcwd(0) then
      vim.cmd.lcd(root)
    end
  end,
})

return M
