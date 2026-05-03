local M = {}

function M.open_neogit(opts)
  pcall(vim.cmd, "packadd neogit")
  require("neogit").open(opts or { kind = "replace" })
end

return M
