local M = {}

local base = {
  number = true,
  relativenumber = true,
  signcolumn = "yes",
  cursorline = true,
  termguicolors = true,
  background = "dark",
  expandtab = true,
  shiftwidth = 2,
  softtabstop = 2,
  tabstop = 2,
  smartindent = true,
  wrap = false,
  breakindent = true,
  ignorecase = true,
  smartcase = true,
  incsearch = true,
  hlsearch = true,
  splitbelow = true,
  splitright = true,
  scrolloff = 8,
  sidescrolloff = 8,
  updatetime = 200,
  timeoutlen = 400,
  completeopt = { "menu", "menuone", "noselect" },
  swapfile = false,
  backup = false,
  undofile = true,
  clipboard = "unnamedplus",
  mouse = "a",
  list = true,
  listchars = {
    tab = "» ",
    trail = "·",
    nbsp = "␣",
    extends = "›",
    precedes = "‹",
  },
}

local profiles = {
  default = {},
  focus = {
    number = false,
    relativenumber = false,
    cursorline = false,
    signcolumn = "auto",
    scrolloff = 4,
    sidescrolloff = 4,
  },
}

function M.apply()
  local profile = require("config.profile").current()
  local opt = vim.opt

  for key, value in pairs(base) do
    opt[key] = value
  end

  local override = profiles[profile] or profiles.default
  for key, value in pairs(override) do
    opt[key] = value
  end

  vim.diagnostic.config({
    virtual_text = true,
    signs = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    float = { border = "rounded" },
  })
end

return M
