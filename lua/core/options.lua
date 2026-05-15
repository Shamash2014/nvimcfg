local M = {}

function M.setup()
  local opt = vim.opt

  opt.number = true
  opt.relativenumber = true
  opt.hidden = true
  opt.splitbelow = true
  opt.splitright = true
  opt.termguicolors = true
  opt.updatetime = 250
  opt.timeoutlen = 300
  opt.clipboard = "unnamedplus"
end

return M
