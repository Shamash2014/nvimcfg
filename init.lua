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

-- Prepend mise shims to PATH
vim.env.PATH = vim.env.HOME .. "/.local/share/mise/shims:" .. vim.env.PATH

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

-- Fix for LSP sync errors with conform.nvim
-- This prevents the "attempt to get length of local 'prev_line' (a nil value)" error
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then
      -- Increase the sync timeout to prevent race conditions
      if client.config and client.config.flags then
        client.config.flags.debounce_text_changes = 150
      end
      
      -- Ensure proper synchronization for incremental changes
      if client.server_capabilities then
        client.server_capabilities.textDocumentSync = client.server_capabilities.textDocumentSync or {}
        if type(client.server_capabilities.textDocumentSync) == "table" then
          -- Force incremental sync to be more conservative
          client.server_capabilities.textDocumentSync.change = 2 -- Incremental
        end
      end
    end
  end,
  desc = "Configure LSP client to prevent sync errors"
})

-- Bare repository and worktree support with proper root detection
local function get_git_root()
  -- First check if we're in a worktree
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
  
  if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end
  
  -- Check if we're in a bare repository
  local is_bare = vim.fn.system("git rev-parse --is-bare-repository 2>/dev/null"):gsub("\n", "") == "true"
  if is_bare then
    local git_dir = vim.fn.system("git rev-parse --git-dir 2>/dev/null"):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return vim.fn.fnamemodify(git_dir, ":h")
  end
  
  return nil
end

local function setup_bare_repo_support()
  local git_root = get_git_root()
  
  if not git_root then
    return
  end
  
  -- Check if we're in a bare repo
  local is_bare = vim.fn.system("git rev-parse --is-bare-repository 2>/dev/null"):gsub("\n", "") == "true"
  
  if is_bare then
    vim.g.bare_repo = true
    -- For bare repos, we should be in a worktree subdirectory
    -- Don't print on every directory change
    if vim.g.bare_repo_notified ~= true then
      vim.notify("Bare repository detected - use <leader>gw for worktree operations", vim.log.levels.INFO)
      vim.g.bare_repo_notified = true
    end
  else
    -- Check if we're in a worktree
    local git_common_dir = vim.fn.system("git rev-parse --git-common-dir 2>/dev/null"):gsub("\n", "")
    if git_common_dir:match("%.git/worktrees") then
      vim.g.in_worktree = true
      -- Set the root to the worktree root
      vim.fn.chdir(git_root)
    end
  end
  
  -- Update the root pattern for project detection
  vim.g.git_root = git_root
end

-- Run bare repo setup on startup and when changing directories
vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "BufEnter" }, {
  callback = setup_bare_repo_support,
  desc = "Setup bare repository support"
})

-- Override vim.fn.finddir and vim.fn.findfile to respect git worktree roots
local original_finddir = vim.fn.finddir
local original_findfile = vim.fn.findfile

vim.fn.finddir = function(name, path, ...)
  if name == ".git" and vim.g.git_root then
    return vim.g.git_root .. "/.git"
  end
  return original_finddir(name, path, ...)
end

vim.fn.findfile = function(name, path, ...)
  if vim.g.git_root and path == nil then
    path = vim.g.git_root
  end
  return original_findfile(name, path, ...)
end

-- Helper command for bare repository cloning
vim.api.nvim_create_user_command("BareClone", function(opts)
  local url = opts.args
  if url == "" then
    print("Usage: :BareClone <repository-url> [target-dir]")
    return
  end
  
  local parts = vim.split(url, " ")
  local repo_url = parts[1]
  local target = parts[2]
  
  if not target then
    -- Extract repo name from URL
    target = repo_url:match("([^/]+)%.git$") or repo_url:match("([^/]+)$")
    target = target .. ".git"
  end
  
  -- Clone as bare repository
  local cmd = string.format("git clone --bare %s %s", repo_url, target)
  local result = vim.fn.system(cmd)
  
  if vim.v.shell_error == 0 then
    print(string.format("Cloned bare repository to: %s", target))
    print("cd into the directory and use <leader>gwa to create a worktree")
  else
    print("Failed to clone repository: " .. result)
  end
end, { nargs = "+", desc = "Clone repository as bare" })
