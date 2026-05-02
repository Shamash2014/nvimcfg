vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.loader.enable()

require("config.profile").setup()
require("config.filetypes")
require("config.zpack")
require("config.project")
require("config.env")
require("config.lsp")
require("config.autocmds")
require("config.keymaps")
require("acp").setup()
