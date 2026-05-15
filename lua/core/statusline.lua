local M = {}

local mode_labels = {
  n = "NORMAL",
  no = "OP-PENDING",
  i = "INSERT",
  ic = "INSERT",
  v = "VISUAL",
  V = "V-LINE",
  ["\22"] = "V-BLOCK",
  c = "COMMAND",
  R = "REPLACE",
  Rv = "V-REPLACE",
  s = "SELECT",
  S = "S-LINE",
  t = "TERMINAL",
}

local function vim_mode_label()
  local mode = vim.api.nvim_get_mode().mode
  return mode_labels[mode] or mode
end

local function wt_piece()
  local ok, wt = pcall(require, "core.wt")
  if not ok then return "" end
  return wt.piece()
end

local function agent_term_piece()
  local ok, at = pcall(require, "core.agent_term")
  if not ok then return "" end
  local n, wt = at.count_current_project()
  if n == 0 then return "" end
  if wt and wt > 0 then
    return string.format(" [a:%d wt:%d] ", n, wt)
  end
  return " [a:" .. n .. "] "
end

function M.render()
  return table.concat({
    " ",
    vim_mode_label(),
    " %f %m%r ",
    "%=",
    wt_piece(),
    agent_term_piece(),
    "%y %l:%c ",
  })
end

function M.setup()
  _G._nvim3_statusline = M.render
  vim.o.statusline = "%!v:lua._nvim3_statusline()"
  vim.o.laststatus = 3
  pcall(function() require("core.wt").setup() end)
end

return M
