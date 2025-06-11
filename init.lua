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

-- Basic settings
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Neovim 0.11+ performance optimizations
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- Disable netrw to use oil.nvim as default file explorer
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Disable only truly unused builtin plugins for faster startup
vim.g.loaded_gzip = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1
vim.g.loaded_tutor_mode_plugin = 1
-- Keep: matchit, man, health, shada (all useful)

-- Configure vim-matchup for better performance
vim.g.matchup_matchparen_enabled = 0 -- Will be handled by vim-matchup plugin
vim.g.matchup_motion_enabled = 1
vim.g.matchup_text_obj_enabled = 1

-- Essential options
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.smartindent = true
vim.opt.autoindent = true
vim.opt.wrap = false
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 50

-- Performance optimizations - defer non-critical options
vim.schedule(function()
  -- Clipboard sync (expensive operation)
  vim.opt.clipboard = "unnamedplus"
  
  -- Visual enhancements that can wait
  vim.opt.list = true
  vim.opt.listchars = "trail:~,tab:┊─,nbsp:␣,extends:◣,precedes:◢"
  vim.opt.cursorline = true
  vim.opt.showmatch = true
  
  -- Wildmenu optimizations
  vim.opt.wildignore:append("*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.o,*/target/*,*/node_modules/*")
  vim.opt.wildmode = "list:longest,full"
  
  -- Fold settings for large files
  vim.opt.foldcolumn = "1"
  vim.opt.foldminlines = 10
  vim.opt.foldenable = false
end)

-- Immediate performance settings
vim.opt.lazyredraw = true
vim.opt.hidden = true
vim.opt.showmode = false
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Faster redraw and responsiveness
vim.opt.redrawtime = 1500
vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 10

-- Memory and swap optimizations
vim.opt.history = 1000
vim.opt.undolevels = 1000
vim.opt.maxmempattern = 20000

-- Window management (Doom Emacs/Spacemacs style)
local set = vim.keymap.set

-- Window navigation
set('n', '<leader>wh', '<C-w><C-h>', { desc = 'Move focus to the left window' })
set('n', '<leader>wl', '<C-w><C-l>', { desc = 'Move focus to the right window' })
set('n', '<leader>wj', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
set('n', '<leader>wk', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Window splits
set('n', '<leader>ws', '<C-w><C-s>', { desc = 'Split window below' })
set('n', '<leader>wv', '<C-w><C-v>', { desc = 'Split window vertically' })

-- Window closing
set('n', '<leader>wd', '<C-w>c', { desc = 'Close window' })
set('n', '<leader>wo', '<C-w>o', { desc = 'Close other windows' })

-- Window movement
set('n', '<leader>wH', '<C-w>H', { desc = 'Move window to the left' })
set('n', '<leader>wL', '<C-w>L', { desc = 'Move window to the right' })
set('n', '<leader>wJ', '<C-w>J', { desc = 'Move window down' })
set('n', '<leader>wK', '<C-w>K', { desc = 'Move window up' })

-- Window resizing
set('n', '<leader>w=', '<C-w>=', { desc = 'Equalize window sizes' })
set('n', '<leader>w+', '<C-w>+', { desc = 'Increase window height' })
set('n', '<leader>w-', '<C-w>-', { desc = 'Decrease window height' })
set('n', '<leader>w>', '<C-w>>', { desc = 'Increase window width' })
set('n', '<leader>w<', '<C-w><', { desc = 'Decrease window width' })

-- Filetype associations for R, Jupyter, and Astro
vim.filetype.add({
  extension = {
    qmd = "quarto",
    ipynb = "json",
    astro = "astro",
  },
  filename = {
    ["Rprofile"] = "r",
    [".Rprofile"] = "r",
  },
  pattern = {
    ["%.Rmd"] = "rmd",
    ["%.rmd"] = "rmd",
    ["%.R"] = "r",
    ["%.r"] = "r",
  },
})

-- Filetype detection for fast buffer loading
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.r", "*.R", "*.Rmd", "*.rmd", "*.qmd", "*.astro" },
  callback = function()
    vim.schedule(function()
      local ext = vim.fn.fnamemodify(vim.fn.expand("%"), ":e"):lower()
      if ext == "astro" then
        vim.bo.filetype = "astro"
      else
        vim.bo.filetype = ext
      end
    end)
  end,
})

-- Setup lazy.nvim with safe performance optimizations
require("lazy").setup("plugins", {
  defaults = {
    lazy = true, -- Make all plugins lazy by default
  },
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = true,
    rtp = {
      reset = true,
      disabled_plugins = {
        -- Only disable truly unused plugins
        "gzip",
        "matchparen", -- We use vim-matchup instead
        "netrwPlugin", -- We use oil.nvim
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
        -- Keep: man, health, shada_plugin (all useful)
      },
    },
  },
  install = {
    missing = true,
    colorscheme = { "lavender" },
  },
  checker = {
    enabled = false, -- Disable for faster startup
    notify = false,
  },
  change_detection = {
    enabled = false, -- Disable for better performance
    notify = false,
  },
})

-- Setup performance monitoring
require("performance").setup()

-- Load LSP configuration after UI is ready
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    require("lsp")
  end,
})