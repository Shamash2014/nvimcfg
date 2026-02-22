-- Disable unused providers for faster startup
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- Disable unused built-in plugins
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
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1

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

-- Leaders
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Add mise shims to PATH for LSP and tool access
vim.env.PATH = vim.env.HOME .. "/.local/share/mise/shims:" .. vim.env.PATH

-- Setup lazy with plugins from lua/plugins directory
require("lazy").setup("plugins", {
  -- Lazy.nvim performance settings
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = true,
    rtp = {
      reset = true,
      paths = {},
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
  -- Default lazy load settings
  defaults = {
    lazy = false,
    version = nil,
  },
})

-- Performance optimized options
local opt = vim.opt

-- Core settings
opt.number = true
opt.relativenumber = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true
opt.wrap = false

-- File handling
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.undodir = os.getenv("HOME") .. "/.vim/undodir"

-- Search
opt.hlsearch = false
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true

-- UI
opt.termguicolors = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.signcolumn = "yes"
opt.colorcolumn = "80"
opt.cursorline = false  -- Disable for performance

-- Command line and messages
opt.cmdheight = 1        -- Keep command line at exactly 1 line
opt.showmode = false     -- Don't show mode in command line (shown in statusline)
opt.showcmd = false      -- Don't show partial commands in command line
opt.ruler = false        -- Don't show cursor position in command line
opt.shortmess:append("filnxtToOFcI")  -- Shorten messages to fit in one line

-- Performance critical settings
opt.updatetime = 300     -- Faster completion (default 4000ms)
opt.timeoutlen = 300     -- Faster key sequence completion
opt.ttimeoutlen = 10     -- Faster escape key response
opt.lazyredraw = true    -- Don't redraw during macros
opt.synmaxcol = 300      -- Limit syntax highlighting for long lines
opt.redrawtime = 10000   -- Time before redraw timeout
opt.maxmempattern = 20000 -- Max memory for pattern matching
opt.history = 1000       -- Command history
opt.hidden = true        -- Allow hidden buffers

-- Clipboard support
opt.clipboard = "unnamedplus"

-- Completion behavior
opt.completeopt = "menu,menuone,noselect"
opt.pumheight = 10       -- Limit completion menu height

-- Split behavior
opt.splitbelow = true
opt.splitright = true

-- Window movement keymaps (from current nvim config)
-- Better escape
vim.keymap.set('i', 'jk', '<Esc>', { desc = 'Exit insert mode' })

-- Terminal mode exit with jk (same as insert mode)
vim.keymap.set('t', 'jk', '<C-\\><C-n>', { desc = "Exit terminal mode to normal mode" })

-- Window navigation
vim.keymap.set('n', '<leader>wh', '<C-w>h', { desc = "Go to left window" })
vim.keymap.set('n', '<leader>wj', '<C-w>j', { desc = "Go to bottom window" })
vim.keymap.set('n', '<leader>wk', '<C-w>k', { desc = "Go to top window" })
vim.keymap.set('n', '<leader>wl', '<C-w>l', { desc = "Go to right window" })

-- Window resizing
vim.keymap.set('n', '<leader>wH', '<C-w><', { desc = "Decrease window width" })
vim.keymap.set('n', '<leader>wL', '<C-w>>', { desc = "Increase window width" })
vim.keymap.set('n', '<leader>wJ', '<C-w>-', { desc = "Decrease window height" })
vim.keymap.set('n', '<leader>wK', '<C-w>+', { desc = "Increase window height" })

-- Window splitting
vim.keymap.set('n', '<leader>ws', '<C-w>s', { desc = "Split horizontally" })
vim.keymap.set('n', '<leader>wv', '<C-w>v', { desc = "Split vertically" })
vim.keymap.set('n', '<leader>wq', '<C-w>q', { desc = "Close window" })

-- Clear highlights
vim.keymap.set('n', '<Esc>', ':nohlsearch<CR>', { desc = "Clear search highlights" })

-- Stay in indent mode
vim.keymap.set('v', '<', '<gv')
vim.keymap.set('v', '>', '>gv')

-- Tab navigation
vim.keymap.set('n', '[t', '<cmd>tabprevious<cr>', { desc = 'Previous Tab' })
vim.keymap.set('n', ']t', '<cmd>tabnext<cr>', { desc = 'Next Tab' })

-- Tab management with leader
vim.keymap.set('n', '<leader>tt', '<cmd>tabnew<cr>', { desc = 'New Tab' })
vim.keymap.set('n', '<leader>tj', '<cmd>tabnext<cr>', { desc = 'Next Tab' })
vim.keymap.set('n', '<leader>tk', '<cmd>tabprevious<cr>', { desc = 'Previous Tab' })

-- Config management with leader
vim.keymap.set('n', '<leader>or', function()
  local success, err = pcall(function()
    -- Reload init.lua
    vim.cmd('source ~/.config/nvim/init.lua')
    -- Sync lazy.nvim plugins
    vim.cmd('Lazy sync')
    -- Clear caches and reload
    vim.cmd('silent! lua package.loaded[vim.fn.expand("%:t")] = nil')
  end)

  if success then
    vim.notify('Config reloaded successfully', vim.log.levels.INFO)
  else
    vim.notify('Error reloading config: ' .. tostring(err), vim.log.levels.ERROR)
  end
end, { desc = 'Reload config' })

-- Load core modules
require("core.utils").setup_auto_root()
require("core.tasks").setup()

-- LSP keymaps (only active when LSP is attached)
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", {}),
  callback = function(ev)
    -- Print which LSP attached for debugging
    -- Silent LSP attach (don't print to avoid expanding command line)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    -- Comment out the print to keep command line at 1 line
    -- if client then
    --   print("LSP attached: " .. client.name)
    -- end

    local opts = { buffer = ev.buf, noremap = true, silent = true }
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "<leader>cr", function()
      return ":IncRename " .. vim.fn.expand("<cword>")
    end, { buffer = ev.buf, expr = true, desc = "LSP Rename" })
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "<leader>f", function()
      vim.lsp.buf.format { async = true }
    end, opts)

    -- Additional helpful keymaps
    vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
    vim.keymap.set("n", "<leader>ds", vim.lsp.buf.document_symbol, opts)
    vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
  end,
})