-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out,                            "WarningMsg" },
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
vim.opt.scrolloff = 15
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 100
vim.opt.bufhidden = "hide"
vim.opt.clipboard = "unnamedplus"
vim.opt.completeopt = { "menuone", "noselect", "popup" }

-- Omnifunc completion setup with AI and snippet integration
local function enhanced_omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local start = col
    
    -- Find start of word
    while start > 0 and line:sub(start, start):match("[%w_]") do
      start = start - 1
    end
    
    return start
  else
    local completions = {}
    
    -- Try snippets first if LuaSnip is available
    local luasnip_ok, luasnip = pcall(require, "luasnip")
    if luasnip_ok then
      local snippets = luasnip.get_snippets(vim.bo.filetype)
      for _, snippet in pairs(snippets or {}) do
        if snippet.trigger:match("^" .. vim.pesc(base)) then
          table.insert(completions, {
            word = snippet.trigger,
            menu = "[Snippet]",
            info = snippet.description or snippet.name or "",
            kind = "Snippet"
          })
        end
      end
    end
    
    
    -- Fallback to LSP omnifunc
    if vim.lsp.omnifunc then
      local lsp_completions = vim.lsp.omnifunc(0, base)
      if type(lsp_completions) == "table" then
        for _, completion in ipairs(lsp_completions) do
          table.insert(completions, completion)
        end
      end
    end
    
    return completions
  end
end

-- Helper function to check if buffer is a text buffer
local function is_text_buffer()
  local ft = vim.bo.filetype
  local bt = vim.bo.buftype
  
  -- Only enable in text file types and normal buffers
  local text_filetypes = {
    "text", "markdown", "asciidoc", "org", "rst", "tex", "latex", "plaintex",
    "mail", "gitcommit", "help", "man", "info", "conf", "config", "yaml", "yml",
    "toml", "json", "xml", "html", "css", "scss", "sass", "less", "javascript",
    "typescript", "lua", "python", "sh", "bash", "zsh", "fish", "vim", "vimdoc",
    "r", "rmd", "quarto", "dart", "swift", "rust", "go", "c", "cpp", "java",
    "kotlin", "scala", "haskell", "elixir", "erlang", "ruby", "php", "perl",
    "astro", "svelte", "vue", "jsx", "tsx", "dockerfile", "makefile", "cmake",
    "sql", "proto", "graphql", "prisma", "solidity", "zig", "nim", "crystal",
    "julia", "ocaml", "fsharp", "reason", "elm", "purescript", "clojure",
    "racket", "scheme", "lisp", "commonlisp", "fennel", "janet", "wren", "raku"
  }
  
  -- Exclude special buffer types
  if bt ~= "" and bt ~= "help" and bt ~= "quickfix" then
    return false
  end
  
  -- Check if filetype is in our text filetypes list
  for _, text_ft in ipairs(text_filetypes) do
    if ft == text_ft then
      return true
    end
  end
  
  return false
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    if vim.bo.omnifunc == "" and is_text_buffer() then
      vim.bo.omnifunc = "v:lua.enhanced_omnifunc"
    end
  end,
})

-- Make the function globally available
_G.enhanced_omnifunc = enhanced_omnifunc

-- Enhanced completion mappings
vim.keymap.set("i", "<C-x><C-o>", "<C-x><C-o>", { desc = "Omnifunc completion" })
vim.keymap.set("i", "<C-x><C-l>", "<C-x><C-l>", { desc = "Line completion" })
vim.keymap.set("i", "<C-x><C-f>", "<C-x><C-f>", { desc = "File completion" })

-- Auto-trigger omnifunc completion (only in text buffers)
vim.api.nvim_create_autocmd("InsertCharPre", {
  callback = function()
    if not is_text_buffer() then
      return
    end
    
    if vim.v.char:match("[%w_.]") then
      local line = vim.api.nvim_get_current_line()
      local col = vim.api.nvim_win_get_cursor(0)[2]
      local before_cursor = line:sub(1, col)
      
      -- Trigger completion after typing identifier characters
      if before_cursor:match("[%w_]+$") and #before_cursor:match("[%w_]+$") >= 2 then
        vim.schedule(function()
          if vim.fn.pumvisible() == 0 then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-o>", true, false, true), "n", false)
          end
        end)
      end
    end
  end,
})

-- Performance optimizations - defer non-critical options
vim.schedule(function()
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
vim.opt.redrawtime = 2000
vim.opt.timeoutlen = 400
vim.opt.ttimeoutlen = 5

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

-- Tab control (perfect tab management)
set('n', '<leader>wgn', ':tabnew<CR>', { desc = 'New tab' })
set('n', '<leader>wgc', ':tabclose<CR>', { desc = 'Close tab' })
set('n', '<leader>wgo', ':tabonly<CR>', { desc = 'Close other tabs' })
set('n', '<leader>wgl', ':tabnext<CR>', { desc = 'Next tab' })
set('n', '<leader>wgh', ':tabprevious<CR>', { desc = 'Previous tab' })
set('n', '<leader>wgL', ':tabmove +1<CR>', { desc = 'Move tab right' })
set('n', '<leader>wgH', ':tabmove -1<CR>', { desc = 'Move tab left' })
set('n', '<leader>wg1', '1gt', { desc = 'Go to tab 1' })
set('n', '<leader>wg2', '2gt', { desc = 'Go to tab 2' })
set('n', '<leader>wg3', '3gt', { desc = 'Go to tab 3' })
set('n', '<leader>wg4', '4gt', { desc = 'Go to tab 4' })
set('n', '<leader>wg5', '5gt', { desc = 'Go to tab 5' })
set('n', '<leader>wg6', '6gt', { desc = 'Go to tab 6' })
set('n', '<leader>wg7', '7gt', { desc = 'Go to tab 7' })
set('n', '<leader>wg8', '8gt', { desc = 'Go to tab 8' })
set('n', '<leader>wg9', '9gt', { desc = 'Go to tab 9' })
set('n', '<leader>wg0', ':tablast<CR>', { desc = 'Go to last tab' })
set('n', '<leader>wgf', ':tabfirst<CR>', { desc = 'Go to first tab' })
set('n', '<leader>wgd', ':tab split<CR>', { desc = 'Duplicate tab' })
set('n', '<leader>wge', ':tabedit ', { desc = 'Edit file in new tab' })

-- Marks mappings
set('n', '<leader>bm', ':marks<CR>', { desc = 'List marks' })
set('n', '<leader>ma', 'mA', { desc = 'Set mark A' })
set('n', '<leader>mb', 'mB', { desc = 'Set mark B' })
set('n', '<leader>mc', 'mC', { desc = 'Set mark C' })
set('n', '<leader>md', 'mD', { desc = 'Set mark D' })
set('n', '<leader>me', 'mE', { desc = 'Set mark E' })
set('n', '<leader>mf', 'mF', { desc = 'Set mark F' })
set('n', '<leader>mg', 'mG', { desc = 'Set mark G' })
set('n', '<leader>mh', 'mH', { desc = 'Set mark H' })
set('n', '<leader>mA', '\'A', { desc = 'Go to mark A' })
set('n', '<leader>mB', '\'B', { desc = 'Go to mark B' })
set('n', '<leader>mC', '\'C', { desc = 'Go to mark C' })
set('n', '<leader>mD', '\'D', { desc = 'Go to mark D' })
set('n', '<leader>mE', '\'E', { desc = 'Go to mark E' })
set('n', '<leader>mF', '\'F', { desc = 'Go to mark F' })
set('n', '<leader>mG', '\'G', { desc = 'Go to mark G' })
set('n', '<leader>mH', '\'H', { desc = 'Go to mark H' })

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
require("lazy").setup({
  spec = {
    { import = "plugins" },
    { import = "editor" },
  },
}, {
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
        "matchparen",  -- We use vim-matchup instead
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
  ui = {
    backdrop = 100, -- Dim inactive windows
  },
})

-- Initialize performance optimizations
require("performance").setup()

-- Enable LSP configuration
require("lsp")
