-- Minimal Neovim configuration
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Performance optimizations
vim.loader.enable() -- Enable Lua module loader cache (Neovim 0.9+)

-- Memory optimizations
vim.o.hidden = true -- Allow hidden buffers
vim.o.lazyredraw = true -- Don't redraw while executing macros
vim.o.ttyfast = true -- Faster terminal connection
vim.o.synmaxcol = 200 -- Limit syntax highlighting to 200 columns
vim.o.re = 0 -- Use new regex engine for performance

-- Disable some builtin vim plugins for faster startup (keeping essential ones)
vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_logipat = 1
vim.g.loaded_rrhelper = 1
vim.g.loaded_spellfile_plugin = 1
vim.g.loaded_shada_plugin = 1
vim.g.loaded_tutor_mode_plugin = 1
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_gzip = 1

-- Basic settings
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 10
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.clipboard = "unnamedplus"

-- Disable netrw to use oil.nvim as default file manager
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Global jk escape mapping for insert mode
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Terminal mode escape mapping
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.keymap.set("t", "jk", "<C-\\><C-n>", { buffer = true, desc = "Exit terminal mode" })
  end,
})

-- Initialize performance optimizations
require("performance").setup()

-- Load plugin configurations with performance optimizations
require("lazy").setup("plugins", {
  defaults = {
    lazy = true, -- Make all plugins lazy by default
  },
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = true, -- Reset packpath to improve startup time
    rtp = {
      reset = true, -- Reset runtime path to improve startup time
      paths = {}, -- Add any extra paths here if needed
      disabled_plugins = {
        "netrwPlugin",
        "tohtml",
        "tutor",
        "getscript",
        "getscriptPlugin",
        "vimball",
        "vimballPlugin",
        "2html_plugin",
        "logipat",
        "rrhelper",
        "spellfile_plugin",
        "matchit",
        "matchparen",
        "tarPlugin",
        "zipPlugin",
        "gzip",
      },
    },
  },
  ui = {
    backdrop = 100, -- Backdrop opacity for UI
  },
  change_detection = {
    enabled = true,
    notify = false, -- Don't notify about config changes
  },
})