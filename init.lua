-- Disable unused providers for faster startup
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- Leaders
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Add mise shims to PATH for LSP and tool access
vim.env.PATH = vim.env.HOME .. "/.local/share/mise/shims:" .. vim.env.PATH

local o = vim.opt

-- Core
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.tabstop = 2
o.shiftwidth = 2
o.expandtab = true
o.smartindent = true
o.wrap = false

-- File handling
o.swapfile = false
o.backup = false
o.undofile = true
o.undodir = os.getenv("HOME") .. "/.vim/undodir"

-- Search
o.hlsearch = false
o.incsearch = true
o.ignorecase = true
o.smartcase = true

-- UI
o.termguicolors = true
o.scrolloff = 8
o.sidescrolloff = 8
o.colorcolumn = "80"
o.cursorline = false
o.equalalways = true
o.eadirection = "both"

-- Command line and messages
o.cmdheight = 1
o.showmode = false
o.showcmd = false
o.ruler = false
o.shortmess:append("filnxtToOFcI")

-- Performance
o.updatetime = 500
o.timeoutlen = 300
o.ttimeoutlen = 10
o.synmaxcol = 300
o.redrawtime = 10000
o.hidden = true

-- Clipboard
o.clipboard = "unnamedplus"

-- Completion
o.completeopt = "menu,menuone,noselect"
o.pumheight = 10

-- Splits
o.splitbelow = true
o.splitright = true

-- Mouse
o.mouse = "a"

-- Diagnostics
vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = " ",
      [vim.diagnostic.severity.WARN] = " ",
      [vim.diagnostic.severity.INFO] = " ",
      [vim.diagnostic.severity.HINT] = "󰌵 ",
    },
  },
  virtual_text = {
    prefix = "●",
    spacing = 4,
    source = "if_many",
  },
  underline = true,
  severity_sort = true,
  float = {
    border = "rounded",
    source = true,
    header = "",
    prefix = "",
  },
})

local map = vim.keymap.set

-- Better escape
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
map("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Window navigation
map("n", "<leader>wh", "<C-w>h", { desc = "Window left" })
map("n", "<leader>wj", "<C-w>j", { desc = "Window down" })
map("n", "<leader>wk", "<C-w>k", { desc = "Window up" })
map("n", "<leader>wl", "<C-w>l", { desc = "Window right" })

-- Window resizing
map("n", "<leader>wH", "<C-w><", { desc = "Decrease width" })
map("n", "<leader>wL", "<C-w>>", { desc = "Increase width" })
map("n", "<leader>wJ", "<C-w>-", { desc = "Decrease height" })
map("n", "<leader>wK", "<C-w>+", { desc = "Increase height" })

-- Window splitting
map("n", "<leader>ws", "<C-w>s", { desc = "Split horizontal" })
map("n", "<leader>wv", "<C-w>v", { desc = "Split vertical" })
map("n", "<leader>wq", "<C-w>q", { desc = "Close window" })

-- Buffer navigation
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })

-- Tab navigation
map("n", "[t", "<cmd>tabprevious<cr>", { desc = "Previous tab" })
map("n", "]t", "<cmd>tabnext<cr>", { desc = "Next tab" })

-- Clear search highlights
map("n", "<Esc>", ":nohlsearch<CR>", { desc = "Clear highlights" })

-- Stay in indent mode
map("v", "<", "<gv")
map("v", ">", ">gv")

require("core.ui2").setup()

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  defaults = { lazy = false },
  performance = {
    cache = { enabled = true },
    reset_packpath = true,
    rtp = {
      reset = true,
      disabled_plugins = {
        "gzip", "matchit", "matchparen", "netrwPlugin",
        "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
})

-- Core modules
require("core.utils").setup_auto_root()

-- LSP keymaps (only active when LSP is attached)
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", {}),
  callback = function(ev)
    local opts = { buffer = ev.buf, noremap = true, silent = true }
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
    vim.keymap.set("n", "<leader>ds", vim.lsp.buf.document_symbol, opts)
    vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
  end,
})

vim.api.nvim_create_autocmd("LspProgress", {
  callback = function(ev)
    vim.print(ev.data)
    local value = ev.data.params.value
    vim.api.nvim_echo({ { value.message or "done" } }, false, {
      id = "lsp." .. ev.data.client_id,
      kind = "progress",
      source = "vim.lsp",
      title = value.title,
      status = value.kind ~= "end" and "running" or "success",
      percent = value.percentage,
    })
  end,
})

vim.api.nvim_create_user_command("LspInfo", "checkhealth vim.lsp", {
  desc = "Show LSP Info",
})

vim.api.nvim_create_user_command("LspLog", function(_)
  local state_path = vim.fn.stdpath("state")
  local log_path = vim.fs.joinpath(state_path, "lsp.log")
  vim.cmd(string.format("edit %s", log_path))
end, {
  desc = "Show LSP log",
})

vim.api.nvim_create_user_command("LspRestart", "lsp restart", {
  desc = "Restart LSP",
})
