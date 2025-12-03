-- Fresh Neovim Configuration with Snacks-based workflow
-- Leader keys
vim.g.mapleader = ' '
vim.g.maplocalleader = '_'

-- Load custom monochrome theme
require('theme').setup()

-- Performance optimizations
vim.o.hidden = true
vim.o.lazyredraw = true
vim.o.ttyfast = true
vim.o.synmaxcol = 200
vim.o.re = 0
vim.o.redrawtime = 1500  -- Stop redrawing after 1.5s for large files
vim.o.maxmempattern = 2000  -- Limit regex pattern memory usage

-- Disable unused plugins for performance
local disabled_plugins = {
  "getscript", "getscriptPlugin", "vimball", "vimballPlugin",
  "2html_plugin", "logipat", "rrhelper", "spellfile_plugin",
  "netrwPlugin", "tohtml", "tutor"
}
for _, plugin in ipairs(disabled_plugins) do
  vim.g["loaded_" .. plugin] = 1
end

-- Shell configuration for proper environment loading
vim.opt.shell = '/bin/zsh -l'
vim.opt.shellcmdflag = '-c'
vim.opt.shellquote = ''
vim.opt.shellxquote = ''

-- Set environment for all processes
vim.env.SHELL = '/bin/zsh'

-- Core editor options
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.linebreak = true
vim.opt.whichwrap = "h,l,<,>,[,],~"
vim.opt.breakindentopt = "shift:2,min:20"
vim.opt.showbreak = "↳ "
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 10
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.clipboard = "unnamedplus"
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true
vim.opt.undodir = vim.fn.stdpath("data") .. "/undo"
vim.opt.scrolloff = 8
vim.opt.foldlevelstart = 99
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
vim.opt.foldenable = true
vim.opt.foldcolumn = "1"
vim.opt.spelloptions = "camel"
vim.opt.laststatus = 3 -- Global statusline

-- Native completion settings
vim.opt.completeopt = { "menu", "menuone", "noselect" }
vim.opt.pumheight = 15
vim.opt.pumblend = 10

-- Core keymaps
local function map(mode, lhs, rhs, opts)
  local options = { noremap = true, silent = true }
  if opts then
    options = vim.tbl_extend('force', options, opts)
  end
  vim.keymap.set(mode, lhs, rhs, options)
end

-- Window management
map('n', '<leader>w', '<C-w>', { desc = "Window operations" })
map('n', '<C-h>', '<C-w>>', { desc = "Focus left window" })
map('n', '<C-j>', '<C-w><', { desc = "Focus bottom window" })
map('n', '<C-k>', '<C-w>-', { desc = "Focus top window" })
map('n', '<C-l>', '<C-w>+', { desc = "Focus right window" })

-- Window resizing
map('n', '<leader>wh', '<C-w>h', { desc = "Decrease window width" })
map('n', '<leader>wl', '<C-w>l', { desc = "Increase window width" })
map('n', '<leader>wj', '<C-w>j', { desc = "Decrease window height" })
map('n', '<leader>wk', '<C-w>k', { desc = "Increase window height" })

-- Window splitting
map('n', '<leader>ws', '<C-w>s', { desc = "Split horizontally" })
map('n', '<leader>wv', '<C-w>v', { desc = "Split vertically" })
map('n', '<leader>wq', '<C-w>q', { desc = "Close window" })
map('n', '<leader>wt', function()
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd('tabnew')
  vim.api.nvim_set_current_buf(buf)
end, { desc = "Move buffer to new tab" })

-- Tab navigation
map('n', '<leader>tt', function()
  vim.cmd('tabnew')
  local root = require('tasks').get_project_root()
  if root then
    vim.cmd('tcd ' .. vim.fn.fnameescape(root))
    vim.notify('New tab (root: ' .. root .. ')', vim.log.levels.INFO)
  end
end, { desc = "New tab" })
map('n', '<leader>tc', '<cmd>tabclose<cr>', { desc = "Close tab" })
map('n', '<leader>tj', '<cmd>tabnext<cr>', { desc = "Next tab" })
map('n', '<leader>tk', '<cmd>tabprevious<cr>', { desc = "Previous tab" })
map('n', '<leader>th', '<cmd>tabfirst<cr>', { desc = "First tab" })
map('n', '<leader>tl', '<cmd>tablast<cr>', { desc = "Last tab" })

-- Quick file operations
map('n', '<leader>wf', ':w<CR>', { desc = "Save file" })
map('n', '<leader>wx', ':x<CR>', { desc = "Save and exit" })
map('n', '<leader>wq', ':q<CR>', { desc = "Quit" })

-- IDE-style insert mode exit
map('i', 'jk', '<Esc>', { desc = "Exit insert mode" })

-- Terminal mode exit
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.keymap.set('t', 'jk', '<C-\\><C-n>', { buffer = true, desc = "Exit terminal mode" })
  end,
})

-- Clear highlights
map('n', '<Esc>', ':nohlsearch<CR>', { desc = "Clear search highlights" })

-- Stay in indent mode
map('v', '<', '<gv')
map('v', '>', '>gv')

-- Enable vim.loader for performance
vim.loader.enable()

-- Load LSP configuration before lazy.nvim
require('lsp')


-- Buffer pinning system
local M = {}
local pinned_buffers = {}

-- Pin/unpin buffer
function M.toggle_buffer_pin()
  local bufnr = vim.api.nvim_get_current_buf()
  if pinned_buffers[bufnr] then
    pinned_buffers[bufnr] = nil
    vim.notify('Buffer unpinned', vim.log.levels.INFO)
  else
    pinned_buffers[bufnr] = true
    vim.notify('Buffer pinned', vim.log.levels.INFO)
  end
end

-- Check if buffer is pinned
function M.is_buffer_pinned(bufnr)
  return pinned_buffers[bufnr] or false
end

-- Enhanced buffer delete that respects pins and handles terminals
function M.delete_buffer(force)
  local bufnr = vim.api.nvim_get_current_buf()
  if pinned_buffers[bufnr] and not force then
    vim.notify('Buffer is pinned! Use BufferForceDelete to delete.', vim.log.levels.WARN)
    return
  end

  -- Check if this is a terminal buffer
  local buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
  if buftype == 'terminal' then
    -- Terminal buffers need force delete to kill the running process
    vim.cmd('bdelete!')
  else
    -- Regular buffer delete
    local success, err = pcall(vim.cmd, 'bdelete')
    if not success then
      -- If normal delete fails, try force delete
      vim.cmd('bdelete!')
    end
  end
end

-- Get pinned buffer indicator for pickers
function M.get_pin_indicator(bufnr)
  return pinned_buffers[bufnr] and '📌 ' or ''
end

-- Clean up closed buffers from pin list
vim.api.nvim_create_autocmd('BufDelete', {
  callback = function(args)
    pinned_buffers[args.buf] = nil
  end,
})

-- Make functions globally available
_G.buffer_pin = M

-- Commands for command palette
vim.api.nvim_create_user_command('BufferPin', function()
  _G.buffer_pin.toggle_buffer_pin()
end, { desc = 'Toggle Buffer Pin' })

vim.api.nvim_create_user_command('BufferForceDelete', function()
  _G.buffer_pin.delete_buffer(true)
end, { desc = 'Force Delete Pinned Buffer' })

vim.api.nvim_create_user_command('TerminalKill', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
  if buftype == 'terminal' then
    vim.cmd('bdelete!')
    vim.notify('Terminal killed', vim.log.levels.INFO)
  else
    vim.notify('Current buffer is not a terminal', vim.log.levels.WARN)
  end
end, { desc = 'Kill Terminal Buffer' })

-- Toggle commands for command palette (no keybindings)
vim.api.nvim_create_user_command('ToggleDim', function()
  require('snacks').toggle.dim():toggle()
end, { desc = 'Toggle Dim Mode' })

-- Job management commands
-- Terminal error parsing command
vim.api.nvim_create_user_command('ParseTerminalErrors', function()
  require('tasks').parse_terminal_errors()
end, { desc = 'Parse errors from current terminal buffer' })

vim.api.nvim_create_user_command('KillAllJobs', function()
  local killed = 0

  -- Kill all Neovim jobs
  local jobs = vim.fn.jobwait({}, 0)
  if jobs and type(jobs) == 'table' then
    for _, job_id in ipairs(jobs) do
      if job_id > 0 then
        vim.fn.jobstop(job_id)
        killed = killed + 1
      end
    end
  end

  -- Kill all terminal processes
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buftype = pcall(vim.api.nvim_buf_get_option, buf, 'buftype')
      if buftype == 'terminal' then
        local ok, term_job_id = pcall(vim.api.nvim_buf_get_var, buf, 'terminal_job_id')
        if ok and term_job_id then
          vim.fn.jobstop(term_job_id)
          killed = killed + 1
        end
      end
    end
  end

  -- Kill child processes
  vim.cmd('silent! !pkill -P ' .. vim.fn.getpid())

  vim.notify('Killed ' .. killed .. ' jobs and child processes', vim.log.levels.INFO)
end, { desc = 'Kill All Running Jobs and Processes' })

-- Helper function for tab picker
local function show_tab_picker()
  local tabs = {}
  for i = 1, vim.fn.tabpagenr('$') do
    local winnr = vim.fn.tabpagewinnr(i)
    local bufnr = vim.fn.tabpagebuflist(i)[winnr]
    local bufname = vim.fn.bufname(bufnr)
    local name = bufname ~= "" and vim.fn.fnamemodify(bufname, ":~:.") or "[No Name]"
    table.insert(tabs, string.format("Tab %d: %s", i, name))
  end
  vim.ui.select(tabs, {
    prompt = "Select Tab:",
  }, function(choice, idx)
    if idx then vim.cmd(idx .. "tabnext") end
  end)
end

-- Custom :R command for async execution
vim.api.nvim_create_user_command('R', function(opts)
  local cmd = opts.args
  if cmd == '' then
    vim.notify('Usage: :R <command>', vim.log.levels.ERROR)
    return
  end
  require('tasks').run_command(cmd)
end, { nargs = '*', desc = 'Run command asynchronously' })

-- Lazy.nvim bootstrap
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Plugin setup
require('lazy').setup({

  -- Snacks.nvim - Core utility plugin
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      -- Essential features for task management and navigation
      bigfile = { enabled = true, size = 1.5 * 1024 * 1024 },
      quickfile = { enabled = true },
      input = {
        enabled = true,
        win = {
          wo = {
            winblend = 0,
            winhighlight = 'Normal:SnacksInput,FloatBorder:SnacksInputBorder,FloatTitle:SnacksInputTitle',
          },
        },
      },
      words = { enabled = true, debounce = 200 },
      rename = { enabled = true },
      quickfix = { enabled = true },

      -- Terminal management
      terminal = {
        enabled = true,
        shell = { '/bin/zsh', '-l' },
        cwd = function()
          -- Use tab-aware project root for quick terminals
          local tasks_ok, tasks = pcall(require, 'tasks')
          if tasks_ok then
            return tasks.get_project_root() or vim.fn.getcwd(0, 0)
          end
          return vim.fn.getcwd(0, 0)
        end,
        win = {
          position = 'bottom',
          height = 0.3,
          style = 'terminal',
          keys = {
            ["<C-r>"] = {
              function(self)
                -- Get terminal info from buffer variable
                local terminal_info = vim.b[self.buf].snacks_terminal
                if not terminal_info or not terminal_info.cmd then
                  vim.notify("No command to restart", vim.log.levels.WARN)
                  return
                end

                local cmd = terminal_info.cmd
                if type(cmd) == "table" then
                  cmd = table.concat(cmd, " ")
                end

                -- Send Ctrl+C to interrupt current process
                vim.api.nvim_feedkeys("\x03", "n", false)

                -- Wait a bit for process to terminate, then clear and restart
                vim.defer_fn(function()
                  -- Clear the terminal
                  vim.api.nvim_feedkeys("clear\n", "n", false)

                  -- Wait a bit more then restart the command
                  vim.defer_fn(function()
                    vim.api.nvim_feedkeys(cmd .. "\n", "n", false)
                    vim.notify("Restarted: " .. cmd, vim.log.levels.INFO)
                  end, 100)
                end, 200)
              end,
              desc = "Restart terminal job",
              mode = { "n", "t" }
            }
          },
        },
      },

      -- Picker with Doom-style navigation
      picker = {
        enabled = true,
        ui_select = true,
        layout = 'vscode',
        preview = false,
        win = {
          input = {
            keys = {
              ['<C-j>'] = { 'list_down', mode = { 'i', 'n' } },
              ['<C-k>'] = { 'list_up', mode = { 'i', 'n' } },
            },
            wo = {
              winblend = 0,
              winhighlight = 'Normal:SnacksPickerInput,FloatBorder:SnacksInputBorder,FloatTitle:SnacksInputTitle',
            },
          },
          list = {
            wo = {
              winblend = 0,
              winhighlight = 'Normal:SnacksPicker,FloatBorder:SnacksPickerBorder,CursorLine:SnacksPickerSelected',
            },
          },
        },
        formatters = { file = { filename_first = true } },
        matcher = {
          fuzzy = true,
          smartcase = true,
          ignorecase = true
        },
        sources = {
          projects = {
            patterns = {
              '.git', 'package.json', 'Makefile', 'Cargo.toml', 'go.mod',
              'mix.exs', 'pubspec.yaml', '.envrc', '.mise.toml', '.tool-versions',
              'flake.nix', 'shell.nix', 'default.nix', 'justfile', 'Justfile',
              'docker-compose.yml', 'docker-compose.yaml', 'build.gradle',
              'build.gradle.kts', 'pom.xml', 'CMakeLists.txt', 'setup.py',
              'pyproject.toml', 'tsconfig.json', 'composer.json', '.project',
              '.vscode', 'process-compose.yml', 'process-compose.yaml',
              '.nvmrc', '.python-version', '.ruby-version', '.java-version'
            },
            recent = true,
          },
          lines = { preview = false },
          files = { preview = false },
          grep = { preview = false },
          buffers = { preview = false },
          diagnostics = { preview = false },
          lsp_symbols = { preview = false },
        },
      },

      -- UI features
      dim = {
        enabled = true,
        -- Disable dim for terminal buffers
        filter = function(buf)
          return vim.api.nvim_buf_get_option(buf, 'buftype') ~= 'terminal'
        end,
      },

      -- Git features
      git = { enabled = true },

      -- Disabled features
      scope = { enabled = false },
      notifier = { enabled = false },
      dashboard = { enabled = false },
      zen = { enabled = false },
      scratch = { enabled = false },
    },
    config = function(_, opts)
      require("snacks").setup(opts)
      -- Force global replacement of vim.ui.select
      if vim.ui.select ~= Snacks.picker.select then
        vim.ui.select = Snacks.picker.select
      end
    end,
    keys = {
      -- File finding (using project root)
      {
        '<leader><leader>',
        function()
          local root = require('tasks').get_project_root() or vim.fn.getcwd()
          Snacks.picker.files({ cwd = root })
        end,
        desc = 'Find Files'
      },
      {
        '<leader>ff',
        function()
          local root = require('tasks').get_project_root() or vim.fn.getcwd()
          Snacks.picker.files({ cwd = root })
        end,
        desc = 'Find Files'
      },
      { '<leader>fr', function() Snacks.picker.recent() end,  desc = 'Recent Files' },
      { '<leader>fb', function() Snacks.picker.buffers() end, desc = 'Find Buffers' },

      -- Search functionality (using project root)
      {
        '<leader>sg',
        function()
          local root = require('tasks').get_project_root() or vim.fn.getcwd()
          Snacks.picker.grep({ cwd = root })
        end,
        desc = 'Grep'
      },
      {
        '<leader>sw',
        function()
          local root = require('tasks').get_project_root() or vim.fn.getcwd()
          Snacks.picker.grep_word({ cwd = root })
        end,
        desc = 'Search Word'
      },
      {
        '<leader>ss',
        function()
          vim.schedule(function()
            require('snacks').picker({ source = 'lines' })
          end)
        end,
        desc = 'Search Lines'
      },
      { '<leader>si', function() Snacks.picker.lsp_symbols() end, desc = 'Search Symbols' },
      { '<leader>sd', function() Snacks.picker.diagnostics() end, desc = 'Diagnostics' },

      -- Project management
      { '<leader>pp', function() Snacks.picker.projects() end,    desc = 'Projects' },
      {
        '<leader>pf',
        function()
          local root = require('tasks').get_project_root() or vim.fn.getcwd()
          Snacks.picker.files({ cwd = root })
        end,
        desc = 'Project Files'
      },
      {
        '<leader>ps',
        function()
          local root = require('tasks').get_project_root() or vim.fn.getcwd()
          Snacks.picker.grep({ cwd = root })
        end,
        desc = 'Project Search'
      },

      -- Help and utilities
      { '<leader>hh',  function() Snacks.picker.help() end,                     desc = 'Help Tags' },
      { '<leader>oc',  function() Snacks.picker.commands() end,                 desc = 'Command Palette' },
      { '<leader>oq',  function() Snacks.picker.qflist() end,                   desc = 'Quickfix List' },
      { '<leader>oqq', '<cmd>copen<cr>',                                        desc = 'Open Quickfix' },
      { '<leader>oqc', '<cmd>cclose<cr>',                                       desc = 'Close Quickfix' },

      -- Terminal
      { '<C-/>',       function() Snacks.terminal.open() end,                    desc = 'Toggle Terminal',    mode = { 'n', 't' } },
      { '<leader>ot',  function() Snacks.terminal.open() end,                    desc = 'Toggle Terminal' },

      -- Buffer operations
      { '<leader>bb',  function() Snacks.picker.buffers() end,                  desc = 'All Buffers' },
      { '<leader>br',  function() require('tasks').show_terminal_buffers() end, desc = 'Terminal Buffers' },
      { '<leader>bt',  show_tab_picker,                                         desc = 'Tab List' },
      { '<leader>bd',  function() _G.buffer_pin.delete_buffer(false) end,         desc = 'Delete Buffer' },
      { '<leader>bD',  function() _G.buffer_pin.delete_buffer(true) end,       desc = 'Force Delete Buffer' },

      -- Task runner
      { '<leader>rr',  function() require('tasks').show_task_picker() end,      desc = 'Run Task' },
      { '<leader>rl',  function() require('tasks').run_last_command() end,      desc = 'Run Last Command' },
      { '<leader>rR',  function() require('tasks').restart_terminal_command() end, desc = 'Restart Terminal Command' },
      { '<leader>re',  function() require('tasks').parse_terminal_errors() end, desc = 'Parse Terminal Errors' },
      {
        '<leader>rv',
        function()
          require('tasks').set_terminal_split('vertical')
          require('tasks').show_task_picker()
        end,
        desc = 'Run Task (Vertical)'
      },
      {
        '<leader>rs',
        function()
          require('tasks').set_terminal_split('horizontal')
          require('tasks').show_task_picker()
        end,
        desc = 'Run Task (Horizontal)'
      },
      {
        '<leader>rb',
        function() require('tasks').show_background_task_picker() end,
        desc = 'Run Task (Background)'
      },

      -- Quit
      { '<leader>qq', '<cmd>qa<cr>',                               desc = 'Quit All' },
      {
        '<leader>qr',
        function()
          -- Clear Lua module cache for custom modules
          local config_path = vim.fn.stdpath('config')
          local lua_path = config_path .. '/lua'

          for name, _ in pairs(package.loaded) do
            if name:match('^tasks') or name:match('^lsp') or name:match('^config') then
              package.loaded[name] = nil
            end
          end

          -- Source the main config
          vim.cmd('source ' .. config_path .. '/init.lua')

          -- Reload plugin configurations if lazy.nvim is available
          local ok, lazy = pcall(require, 'lazy')
          if ok then
            lazy.reload()
            vim.notify('Config and plugins reloaded', vim.log.levels.INFO)
          else
            vim.notify('Config reloaded', vim.log.levels.INFO)
          end
        end,
        desc = 'Reload Config'
      },



      -- Git blame
      { '<leader>gB', function() Snacks.git.blame_line() end,      desc = 'Git Blame Line' },
      { '<leader>gL', function() Snacks.picker.git_log_line() end, desc = 'Git Log Line (Picker)' },
    },
  },

  -- Oil.nvim - File explorer
  {
    'stevearc/oil.nvim',
    cmd = 'Oil',
    keys = { { '<leader>fj', '<cmd>Oil<CR>', desc = 'File Explorer' } },
    config = function()
      require('oil').setup {
        default_file_explorer = true,
        delete_to_trash = true,
        skip_confirm_for_simple_edits = true,
        view_options = {
          show_hidden = true,
          natural_order = true,
          is_always_hidden = function(name, bufnr)
            -- Hide .git and .DS_Store
            return name == '.git' or name == '.DS_Store'
          end,
        },
        float = {
          padding = 2,
          max_width = 0.9,
          max_height = 0.9,
          border = 'single',
          win_options = {
            winblend = 0,
          },
        },
        preview = {
          max_width = 0.9,
          min_width = { 40, 0.4 },
          width = nil,
          max_height = 0.9,
          min_height = { 5, 0.1 },
          height = nil,
          border = 'single',
          win_options = {
            winblend = 0,
          },
        },
        progress = {
          max_width = 0.9,
          min_width = { 40, 0.4 },
          width = nil,
          max_height = { 10, 0.9 },
          min_height = { 5, 0.1 },
          height = nil,
          border = 'single',
          minimized_border = 'none',
          win_options = {
            winblend = 0,
          },
        },
        keymaps = {
          ['<C-v>'] = { 'actions.select_vsplit', desc = 'Open in vertical split' },
          ['<C-s>'] = { 'actions.select_split', desc = 'Open in horizontal split' },
          ['<C-t>'] = { 'actions.select_tab', desc = 'Open in new tab' },
          ['<C-p>'] = { 'actions.preview', desc = 'Open preview' },
          ['<C-c>'] = { 'actions.close', desc = 'Close oil' },
          ['<C-r>'] = { 'actions.refresh', desc = 'Refresh' },
          ['-'] = { 'actions.parent', desc = 'Go to parent directory' },
          ['_'] = { 'actions.open_cwd', desc = 'Open current working directory' },
          ['`'] = { 'actions.cd', desc = 'Change directory' },
          ['~'] = { 'actions.tcd', desc = 'Change tab directory' },
          ['gs'] = { 'actions.change_sort', desc = 'Change sort order' },
          ['gx'] = { 'actions.open_external', desc = 'Open with system app' },
          ['g.'] = { 'actions.toggle_hidden', desc = 'Toggle hidden files' },
        },
      }

      -- Enhanced autocmd for opening oil on directories
      local oil_augroup = vim.api.nvim_create_augroup('oil-auto-open', { clear = true })

      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
        desc = 'Auto-open oil when navigating to directories',
        group = oil_augroup,
        callback = function(args)
          local bufname = vim.api.nvim_buf_get_name(args.buf)

          -- Skip if buffer is already oil
          if vim.bo[args.buf].filetype == 'oil' then
            return
          end

          -- Check if it's a directory
          if bufname ~= '' and vim.fn.isdirectory(bufname) == 1 then
            -- Avoid infinite loops and ensure buffer is valid
            if vim.api.nvim_buf_is_valid(args.buf) then
              vim.schedule(function()
                -- Only open oil if we're still in the same buffer
                if vim.api.nvim_get_current_buf() == args.buf then
                  require('oil').open(bufname)
                end
              end)
            end
          end
        end,
      })

      -- Handle directory arguments from command line
      vim.api.nvim_create_autocmd('VimEnter', {
        desc = 'Open oil if nvim started with directory argument',
        group = oil_augroup,
        callback = function()
          local argv = vim.v.argv
          if #argv >= 2 then
            local target = argv[#argv]
            if vim.fn.isdirectory(target) == 1 then
              vim.schedule(function()
                require('oil').open(target)
              end)
            end
          end
        end,
      })
    end,
  },

  -- bufstate.nvim - Tab-based workspace management
  {
    'syntaxpresso/bufstate.nvim',
    lazy = false,
    opts = {
      filter_by_tab = true,         -- Perfect for tab-local workflow
      autoload_last_session = true, -- Auto-restore on startup
      autosave = {
        enabled = true,
        on_exit = true,
        interval = 300000,          -- Save every 5 minutes (300000ms)
      },
    },
    keys = {
      { '<leader>ps', '<cmd>BufstateSave<cr>', desc = 'Save Workspace' },
      { '<leader>pr', '<cmd>BufstateLoad<cr>', desc = 'Load Workspace' },
    },
  },

  -- Which-key.nvim - Key mapping help
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    config = function()
      require('which-key').setup {
        preset = 'helix',
        icons = {
          rules = false,
          breadcrumb = '»',
          separator = '→',
          group = '+',
        },
        win = {
          border = 'single',
          padding = { 1, 1, 1, 1 },
        },
        spec = {
          -- Register which-key mappings
          { '<leader>w',  group = 'Window' },
          { '<leader>t',  group = 'Tab' },
          { '<leader>b',  group = 'Buffers' },
          { '<leader>g',  group = 'Git' },
          { '<leader>f',  group = 'Find' },
          { '<leader>s',  group = 'Search' },
          { '<leader>p',  group = 'Project' },
          { '<leader>pr', '<cmd>ProjectRoot<cr>', desc = 'Show Project Root' },
          { '<leader>pR', '<cmd>ProjectSetRoot<cr>', desc = 'Set Tab Root' },
          { '<leader>r',  group = 'Run' },
          { '<leader>q',  group = 'Quit' },
          { '<leader>d',  group = 'Debug' },
          { '<leader>c',  group = 'LSP' },
          { '<leader>l',  group = 'Code' },
          { '<leader>o',  group = 'Open' },
          { '<leader>h',  group = 'Help' },
        },
      }
    end,
  },

  -- LuaSnip - Snippet engine
  {
    'L3MON4D3/LuaSnip',
    version = 'v2.*',
    build = 'make install_jsregexp',
    event = 'InsertEnter',
    dependencies = {
      'rafamadriz/friendly-snippets',
    },
    config = function()
      require('snippets')
    end,
  },

  -- Treesitter - Complete syntax and code understanding
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
      "nvim-treesitter/nvim-treesitter-refactor",
      "JoosepAlviste/nvim-ts-context-commentstring",
      "windwp/nvim-ts-autotag",
    },
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua", "vim", "vimdoc", "javascript", "typescript", "tsx",
          "python", "go", "rust", "java", "c", "cpp",
          "html", "css", "json", "yaml", "toml", "markdown",
          "astro", "angular", "scss", "dart", "swift"
        },
        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
          -- Disable for very large files to prevent slowdown
          disable = function(lang, buf)
            local max_filesize = 100 * 1024 -- 100 KB
            local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
            if ok and stats and stats.size > max_filesize then
              return true
            end
          end,
        },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "gnn",
            node_incremental = "gni",
            scope_incremental = "gns",
            node_decremental = "gnd",
          },
        },
        indent = {
          enable = true,
        },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              -- Functions and methods
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["am"] = "@method.outer",
              ["im"] = "@method.inner",

              -- Classes and types
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              ["at"] = "@type.outer",
              ["it"] = "@type.inner",

              -- Blocks and scopes
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",
              ["as"] = "@scope",

              -- Control structures
              ["ai"] = "@conditional.outer",
              ["ii"] = "@conditional.inner",
              ["al"] = "@loop.outer",
              ["il"] = "@loop.inner",

              -- Code constructs
              ["a="] = "@assignment.outer",
              ["i="] = "@assignment.inner",
              ["ap"] = "@parameter.outer",
              ["ip"] = "@parameter.inner",
              ["ar"] = "@return.outer",
              ["ir"] = "@return.inner",
              ["aC"] = "@call.outer",
              ["iC"] = "@call.inner",

              -- Documentation
              ["ao"] = "@comment.outer",
              ["io"] = "@comment.inner",

              -- Language-specific
              ["aI"] = "@import",
              ["aS"] = "@statement.outer",
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]m"] = "@method.outer",
              ["]c"] = "@class.outer",
              ["]b"] = "@block.outer",
              ["]l"] = "@loop.outer",
              ["]i"] = "@conditional.outer",
              ["]p"] = "@parameter.outer",
              ["]C"] = "@call.outer",
              ["]o"] = "@comment.outer",
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]M"] = "@method.outer",
              ["]C"] = "@class.outer",
              ["]B"] = "@block.outer",
              ["]L"] = "@loop.outer",
              ["]I"] = "@conditional.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[m"] = "@method.outer",
              ["[c"] = "@class.outer",
              ["[b"] = "@block.outer",
              ["[l"] = "@loop.outer",
              ["[i"] = "@conditional.outer",
              ["[p"] = "@parameter.outer",
              ["[C"] = "@call.outer",
              ["[o"] = "@comment.outer",
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[M"] = "@method.outer",
              ["[C"] = "@class.outer",
              ["[B"] = "@block.outer",
              ["[L"] = "@loop.outer",
              ["[I"] = "@conditional.outer",
            },
          },
          swap = {
            enable = true,
            swap_next = {
              ["<leader>a"] = "@parameter.inner",
              ["<leader>f"] = "@function.outer",
            },
            swap_previous = {
              ["<leader>A"] = "@parameter.inner",
              ["<leader>F"] = "@function.outer",
            },
          },
          lsp_interop = {
            enable = true,
            border = 'single',
            floating_preview_opts = {},
            peek_definition_code = {
              ["<leader>df"] = "@function.outer",
              ["<leader>dc"] = "@class.outer",
            },
          },
        },
        refactor = {
          highlight_definitions = { enable = true },
          highlight_current_scope = { enable = false },
          smart_rename = {
            enable = true,
            keymaps = {
              smart_rename = "grr",
            },
          },
        },
        -- Enable folding
        fold = {
          enable = true,
          disable = {},
        },
        -- Autotag for HTML/JSX
        autotag = {
          enable = true,
          enable_rename = true,
          enable_close = true,
          enable_close_on_slash = true,
          filetypes = {
            'html', 'javascript', 'typescript', 'javascriptreact',
            'typescriptreact', 'svelte', 'vue', 'tsx', 'jsx',
            'rescript', 'xml', 'php', 'markdown', 'astro', 'glimmer',
            'handlebars', 'hbs'
          },
        },
      })

      -- Setup context commentstring for JSX and other embedded languages
      require('ts_context_commentstring').setup({
        enable = true,
        enable_autocmd = false,
      })

      -- Integrate with Neovim's built-in commenting (0.10+)
      local get_option = vim.filetype.get_option
      vim.filetype.get_option = function(filetype, option)
        return option == "commentstring"
          and require("ts_context_commentstring.internal").calculate_commentstring()
          or get_option(filetype, option)
      end
    end,
  },

  -- Treesitter context - Show current function context
  {
    "nvim-treesitter/nvim-treesitter-context",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      enable = true,
      max_lines = 3,
      min_window_height = 0,
      line_numbers = true,
      multiline_threshold = 20,
      trim_scope = 'outer',
      mode = 'cursor',
      separator = nil,
    },
  },

  -- nvim-treeclimber - Structural editing (Combobulate alternative)
  {
    "Dkendal/nvim-treeclimber",
    lazy = false,
    config = function()
      require('nvim-treeclimber').setup({
        keymaps = {
          show_tree = "T",  -- Show syntax tree
          goto_parent = "H",
          goto_child = "L",
          goto_next = "]n",
          goto_prev = "[n",
          select_node = "vn",
          swap_prev = "<leader>cs",
          swap_next = "<leader>cS",
        },
      })

      -- Enhanced structural navigation commands
      vim.api.nvim_create_user_command('TreeClimberShowTree',
        function() require('nvim-treeclimber').show_tree() end,
        { desc = 'Show Syntax Tree Structure' })

      vim.api.nvim_create_user_command('TreeClimberSelectParent',
        function()
          require('nvim-treeclimber').goto_parent()
          require('nvim-treeclimber').select_node()
        end,
        { desc = 'Select Parent Node' })

      vim.api.nvim_create_user_command('TreeClimberExpandSelection',
        function()
          vim.cmd('normal! v')
          require('nvim-treeclimber').goto_parent()
          require('nvim-treeclimber').select_node()
        end,
        { desc = 'Expand Selection to Parent' })
    end,
    keys = {
      { "H",          "<cmd>lua require('nvim-treeclimber').goto_parent()<cr>", desc = "Go to parent node" },
      { "L",          "<cmd>lua require('nvim-treeclimber').goto_child()<cr>",  desc = "Go to child node" },
      { "]n",         "<cmd>lua require('nvim-treeclimber').goto_next()<cr>",   desc = "Go to next node" },
      { "[n",         "<cmd>lua require('nvim-treeclimber').goto_prev()<cr>",   desc = "Go to previous node" },
      { "<leader>cs", "<cmd>lua require('nvim-treeclimber').swap_prev()<cr>",   desc = "Swap with previous" },
      { "<leader>cS", "<cmd>lua require('nvim-treeclimber').swap_next()<cr>",   desc = "Swap with next" },
      { "vn",         "<cmd>lua require('nvim-treeclimber').select_node()<cr>", desc = "Select current node" },
      { "T",          "<cmd>TreeClimberShowTree<cr>",                           desc = "Show syntax tree" },
      { "vp",         "<cmd>TreeClimberSelectParent<cr>",                       desc = "Select parent node" },
      { "vx",         "<cmd>TreeClimberExpandSelection<cr>",                    desc = "Expand selection" },
    },
  },

  -- tree-pairs - Treesitter-based pair manipulation
  {
    "yorickpeterse/nvim-tree-pairs",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("tree-pairs").setup()
    end,
  },

  -- Mini.bracketed - Unimpaired bracketed pairs
  {
    "echasnovski/mini.bracketed",
    version = false,
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("mini.bracketed").setup({
        buffer = { suffix = 'b', options = {} },
        comment = { suffix = 'c', options = {} },
        diagnostic = { suffix = 'd', options = {} },
        file = { suffix = 'f', options = {} },
        jump = { suffix = 'j', options = {} },
        quickfix = { suffix = 'q', options = {} },
        location = { suffix = 'l', options = {} },
        treesitter = { suffix = 't', options = {} },
        window = { suffix = 'w', options = {} },
      })

      -- Additional convenience mappings
      local keymap = vim.keymap.set
      keymap("n", "]e", ":move .+1<CR>==", { desc = "Move line down" })
      keymap("n", "[e", ":move .-2<CR>==", { desc = "Move line up" })
      keymap("v", "]e", ":move '>+1<CR>gv=gv", { desc = "Move selection down" })
      keymap("v", "[e", ":move '<-2<CR>gv=gv", { desc = "Move selection up" })
    end,
  },


  -- inc-rename - Enhanced LSP rename with live preview
  {
    "smjonas/inc-rename.nvim",
    cmd = "IncRename",
    keys = {
      {
        "<leader>cr",
        function()
          return ":IncRename " .. vim.fn.expand("<cword>")
        end,
        desc = "LSP Rename (inc-rename)",
        expr = true,
      },
    },
    opts = {
      input_buffer_type = "snacks",   -- Use Snacks input system for optimal integration
      show_message = true,            -- Show rename status messages
      preview_empty_name = false,     -- Don't preview empty names
      save_in_cmdline = false,        -- Don't save in command history
    },
  },

  -- Surround - Smart surrounding operations
  {
    "kylechui/nvim-surround",
    version = "*",
    keys = {
      { "ys",  mode = "n" },
      { "yss", mode = "n" },
      { "ds",  mode = "n" },
      { "cs",  mode = "n" },
      { "S",   mode = { "x", "o" } },
    },
    config = function()
      require("nvim-surround").setup({})
    end,
  },

  -- Autopairs - Auto-close brackets/quotes
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup({
        check_ts = true,
        ts_config = {
          lua = { "string" },
          javascript = { "template_string" },
        },
      })
    end,
  },

  -- Flash - Quick navigation
  {
    "folke/flash.nvim",
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end,       desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    },
    opts = {
      highlight = {
        backdrop = 0,
        groups = {
          match = "FlashMatch",
          current = "FlashCurrent",
          label = "FlashLabel",
        },
      },
      label = {
        uppercase = true,
        rainbow = {
          enabled = false,
        },
      },
      mode = "normal",
    },
  },

  -- vim-visual-multi - Multi-cursor editing (Helix-inspired)
  {
    "mg979/vim-visual-multi",
    event = "VeryLazy",
    init = function()
      -- Configure vim-visual-multi with non-conflicting keybindings
      -- Preserves: C-d/C-u (scroll), C-k (snippets/windows), C-p (preview)
      vim.g.VM_maps = {
        ["Find Under"] = '<C-n>',           -- Add cursor at next occurrence (VS Code style)
        ["Find Subword Under"] = '<C-n>',   -- Add cursor at next occurrence (subword)
        ["Skip Region"] = '<C-x>',          -- Skip current and find next
        ["Remove Region"] = '<C-\\>',       -- Remove current cursor
        ["Undo"] = '<C-z>',                 -- Undo in multi-cursor mode
        ["Redo"] = '<C-r>',                 -- Redo in multi-cursor mode
      }

      -- Additional settings for better integration
      vim.g.VM_theme = 'iceblue'
      vim.g.VM_highlight_matches = 'underline'
      vim.g.VM_silent_exit = 1
      vim.g.VM_show_warnings = 0

      -- Customize colors to match theme
      vim.api.nvim_create_autocmd('ColorScheme', {
        callback = function()
          vim.cmd [[
            highlight VM_Cursor ctermbg=blue guibg=#FFFCF0 ctermfg=black guifg=#100F0F
            highlight VM_Extend ctermbg=blue guibg=#333333 ctermfg=white guifg=#FFFCF0
            highlight VM_Insert ctermbg=green guibg=#404040 ctermfg=white guifg=#FFFCF0
          ]]
        end,
      })
    end,
    config = function()
      -- Commands for command palette
      vim.api.nvim_create_user_command('VMStart',
        function() vim.cmd('call vm#commands#add_cursor_down(0, v:count1)') end,
        { desc = 'Start Multi-cursor Mode' })

      vim.api.nvim_create_user_command('VMSelectAll',
        function() vim.cmd('call vm#commands#find_all(0, 1)') end,
        { desc = 'Select All Occurrences of Word' })

      vim.api.nvim_create_user_command('VMSelectAllMatches',
        function() vim.cmd('call vm#commands#find_all(0, 0)') end,
        { desc = 'Select All Pattern Matches' })
    end,
  },

  -- Neogit - Git operations with Snacks integration
  {
    'NeogitOrg/neogit',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'sindrets/diffview.nvim',
    },
    cmd = 'Neogit',
    keys = {
      { '<leader>gg', '<cmd>Neogit<cr>',                desc = 'Neogit Status' },
      { '<leader>gc', '<cmd>Neogit commit<cr>',         desc = 'Neogit Commit' },
      { '<leader>gp', '<cmd>Neogit push<cr>',           desc = 'Neogit Push' },
      { '<leader>gl', '<cmd>Neogit pull<cr>',           desc = 'Neogit Pull' },
      { '<leader>gb', '<cmd>Neogit branch<cr>',         desc = 'Neogit Branch' },
      { '<leader>gd', '<cmd>DiffviewOpen<cr>',          desc = 'Diff View' },
      { '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', desc = 'File History' },
    },
    opts = {
      kind = 'vsplit',
      use_default_keymaps = true,
      disable_builtin_notifications = true,
      integrations = {
        diffview = true,
        snacks = true,
        snacks_picker = true,
        builtin_diffs = true,
      },
      commit_popup = {
        kind = 'split',
        border = 'single',
      },
      popup = {
        kind = 'split',
        border = 'single',
      },
      commit_view = {
        kind = 'split',
        verify_commit = true,
      },
      commit_editor = {
        kind = 'split',
        border = 'single',
        show_staged_diff = false,
      },
      console_timeout = 5000,
      auto_show_console = false,
      -- Prevent opening in new tabs
      disable_tab_fallback = true,
      remember_settings = false,
    },
  },

  -- Diffview - Git diff viewer
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
    opts = {},
  },

  -- Scope.nvim - Tabbed buffer management
  {
    'tiagovla/scope.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('scope').setup({
        restore_state = true,
      })
    end,
  },

  -- Diagflow.nvim - Diagnostic flow display
  {
    'dgagn/diagflow.nvim',
    event = 'LspAttach',
    config = function()
      require('diagflow').setup({
        placement = 'top',
        scope = 'cursor',
        enable = true,
        show_sign = false,
        update_event = { 'CursorHold', 'CursorHoldI' },  -- Changed from CursorMoved for performance
        severity_colors = {
          error = 'DiagnosticError',
          warning = 'DiagnosticWarn',
          info = 'DiagnosticInfo',
          hint = 'DiagnosticHint',
        },
        format = function(diagnostic)
          local source = diagnostic.source and ('[' .. diagnostic.source .. '] ') or ''
          return source .. diagnostic.message
        end,
        gap_size = 1,
        padding_top = 0,
        padding_right = 0,
        show_border = false,
      })
    end,
  },

  -- Git conflict resolution
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    event = "BufReadPost",
    config = function()
      require("git-conflict").setup({
        default_mappings = true,
        default_commands = true,
        disable_diagnostics = false,
        list_opener = function()
          Snacks.picker.qflist()
        end,
        highlights = {
          incoming = "DiffAdd",
          current = "DiffText",
        },
      })
      vim.keymap.set("n", "<leader>gco", "<cmd>GitConflictChooseOurs<cr>", { desc = "Choose Ours" })
      vim.keymap.set("n", "<leader>gct", "<cmd>GitConflictChooseTheirs<cr>", { desc = "Choose Theirs" })
      vim.keymap.set("n", "<leader>gcb", "<cmd>GitConflictChooseBoth<cr>", { desc = "Choose Both" })
      vim.keymap.set("n", "<leader>gc0", "<cmd>GitConflictChooseNone<cr>", { desc = "Choose None" })
      vim.keymap.set("n", "<leader>gcl", "<cmd>GitConflictListQf<cr>", { desc = "List Conflicts" })
      vim.keymap.set("n", "]x", "<cmd>GitConflictNextConflict<cr>", { desc = "Next Conflict" })
      vim.keymap.set("n", "[x", "<cmd>GitConflictPrevConflict<cr>", { desc = "Prev Conflict" })
    end,
  },

  -- render-markdown.nvim - Real-time markdown rendering
  {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    ft = 'markdown',
    opts = {
      heading = {
        enabled = true,
        sign = false,
        icons = { '# ', '## ', '### ', '#### ', '##### ', '###### ' },
      },
      code = {
        enabled = true,
        sign = false,
        style = 'normal',
        border = 'thin',
      },
      bullet = {
        enabled = true,
        icons = { '●', '○', '◆', '◇' },
      },
      checkbox = {
        enabled = true,
        checked = { icon = '✓ ' },
        unchecked = { icon = '○ ' },
      },
    },
  },

  -- DAP - Debug Adapter Protocol
  {
    'mfussenegger/nvim-dap',
    lazy = true,
    keys = {
      { '<leader>db', function() require('dap').toggle_breakpoint() end,                                     desc = 'Toggle Breakpoint' },
      { '<leader>dB', function() require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) end,  desc = 'Conditional Breakpoint' },
      { '<leader>dL', function() require('dap').set_breakpoint(nil, nil, vim.fn.input('Log message: ')) end, desc = 'Log Point' },
      { '<leader>dc', function() require('dap').continue() end,                                              desc = 'Continue' },
      { '<leader>di', function() require('dap').step_into() end,                                             desc = 'Step Into' },
      { '<leader>do', function() require('dap').step_over() end,                                             desc = 'Step Over' },
      { '<leader>dO', function() require('dap').step_out() end,                                              desc = 'Step Out' },
      { '<leader>dj', function() require('dap').down() end,                                                  desc = 'Down Stack Frame' },
      { '<leader>dk', function() require('dap').up() end,                                                    desc = 'Up Stack Frame' },
      { '<leader>dR', function() require('dap').run_to_cursor() end,                                         desc = 'Run to Cursor' },
      { '<leader>dr', function() require('dap').repl.toggle() end,                                           desc = 'Toggle REPL' },
      { '<leader>dt', function() require('dapui').toggle() end,                                              desc = 'Toggle DAP UI' },
      { '<leader>de', function() require('dapui').eval() end,                                                desc = 'Eval Expression',       mode = { 'n', 'v' } },
    },
  },

  -- DAP UI - Debug UI
  {
    'rcarriga/nvim-dap-ui',
    dependencies = { 'mfussenegger/nvim-dap', 'nvim-neotest/nvim-nio' },
    lazy = true,
    keys = {
      { '<leader>dt', function() require('dapui').toggle() end, desc = 'Toggle DAP UI' },
      { '<leader>de', function() require('dapui').eval() end,   desc = 'Eval Expression', mode = { 'n', 'v' } },
    },
    config = function()
      local dap, dapui = require('dap'), require('dapui')

      dapui.setup({
        icons = { expanded = '▾', collapsed = '▸', current_frame = '▸' },
        mappings = {
          expand = { '<CR>', '<2-LeftMouse>' },
          open = 'o',
          remove = 'd',
          edit = 'e',
          repl = 'r',
          toggle = 't',
        },
        layouts = {
          {
            elements = {
              { id = 'scopes',      size = 0.25 },
              { id = 'breakpoints', size = 0.25 },
              { id = 'stacks',      size = 0.25 },
              { id = 'watches',     size = 0.25 },
            },
            size = 40,
            position = 'left',
          },
          {
            elements = {
              { id = 'repl',    size = 0.5 },
              { id = 'console', size = 0.5 },
            },
            size = 10,
            position = 'bottom',
          },
        },
        floating = {
          max_height = nil,
          max_width = nil,
          border = 'single',
          mappings = {
            close = { 'q', '<Esc>' },
          },
        },
      })

      dap.listeners.after.event_initialized['dapui_config'] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated['dapui_config'] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited['dapui_config'] = function()
        dapui.close()
      end

      vim.fn.sign_define('DapBreakpoint', { text = '●', texthl = 'DapBreakpoint', linehl = '', numhl = '' })
      vim.fn.sign_define('DapBreakpointCondition',
        { text = '◆', texthl = 'DapBreakpointCondition', linehl = '', numhl = '' })
      vim.fn.sign_define('DapLogPoint', { text = '◉', texthl = 'DapLogPoint', linehl = '', numhl = '' })
      vim.fn.sign_define('DapStopped', { text = '▶', texthl = 'DapStopped', linehl = 'DapStoppedLine', numhl = '' })
      vim.fn.sign_define('DapBreakpointRejected',
        { text = '✘', texthl = 'DapBreakpointRejected', linehl = '', numhl = '' })
    end,
  },

  -- Conform - Formatting
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>cf',
        function()
          require('conform').format({ async = true, lsp_fallback = true })
        end,
        desc = 'Format',
      },
    },
    config = function()
      require('conform').setup({
        format_on_save = function(bufnr)
          if vim.fn.getfsize(vim.api.nvim_buf_get_name(bufnr)) > 100000 then
            return
          end
          return { timeout_ms = 1000, lsp_fallback = true }
        end,
      })
    end,
  },

  -- Lint - Linting
  {
    'mfussenegger/nvim-lint',
    event = { 'BufReadPost', 'BufWritePost', 'BufNewFile' },
    keys = {
      {
        '<leader>cl',
        function()
          require('lint').try_lint()
        end,
        desc = 'Lint File',
      },
    },
    config = function()
      local lint = require('lint')

      vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
        group = vim.api.nvim_create_augroup('nvim_lint', { clear = true }),
        callback = function()
          require('lint').try_lint()
        end,
      })
    end,
  },

  -- Direnv support
  {
    "direnv/direnv.vim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.direnv_auto = 1
      vim.g.direnv_silent_load = 1
      -- Export direnv on startup and directory change
      vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
        callback = function()
          if vim.fn.executable('direnv') == 1 then
            vim.cmd("DirenvExport")
          end
        end,
      })
    end,
  },

  -- EditorConfig support
  {
    "editorconfig/editorconfig-vim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      vim.g.EditorConfig_exclude_patterns = { 'fugitive://.*', 'scp://.*' }
      vim.g.EditorConfig_max_line_indicator = "line"
    end,
  },

  -- Troublesum - Diagnostic summary
  {
    "ivanjermakov/troublesum.nvim",
    event = "LspAttach",
    opts = {
      enabled = true,
      severity_format = { "E", "W", "I", "H" },
      severity_highlight = {
        "DiagnosticError",
        "DiagnosticWarn",
        "DiagnosticInfo",
        "DiagnosticHint",
      },
    },
  },

}, {
  -- Performance optimizations
  defaults = {
    lazy = true,
  },
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = true,
    rtp = {
      reset = true,
      disabled_plugins = disabled_plugins,
    },
  },
  change_detection = {
    enabled = false,
    notify = false,
  },
  install = {
    colorscheme = { 'habamax', 'custom-monochrome' },
  },
})

-- Web development utilities autocmd
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "html", "css", "scss", "javascript", "typescript", "jsx", "tsx" },
  callback = function()
    vim.keymap.set("n", "<leader>cm", function()
      vim.ui.select({
        "Open in browser",
        "Toggle CSS colors",
      }, {
        prompt = "Web Development:",
        format_item = function(item)
          return item
        end
      }, function(choice)
        if choice == "Open in browser" then
          local file = vim.api.nvim_buf_get_name(0)
          local url = "file://" .. file
          vim.fn.system("open " .. url)
        elseif choice == "Toggle CSS colors" then
          vim.g.css_color = not vim.g.css_color
          vim.notify("CSS colors " .. (vim.g.css_color and "enabled" or "disabled"))
        end
      end)
    end, { buffer = true, desc = "Web development menu" })
  end,
})

-- Command to show current project root
vim.api.nvim_create_user_command("ProjectRoot", function()
  local root = require('tasks').get_project_root() or vim.fn.getcwd()
  vim.notify("Project root: " .. root, vim.log.levels.INFO)
end, {})

-- Auto-update tab working directory when entering buffers in new projects
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    local buftype = vim.api.nvim_buf_get_option(0, 'buftype')
    if buftype == '' or buftype == 'acwrite' then
      local current_file = vim.fn.expand('%:p')
      if current_file ~= '' and vim.fn.filereadable(current_file) == 1 then
        local root = require('tasks').get_project_root(vim.fn.expand('%:p:h'))
        local current_tcd = vim.fn.getcwd(0, 0)
        if root and root ~= current_tcd and vim.fn.isdirectory(root) == 1 then
          vim.cmd('tcd ' .. vim.fn.fnameescape(root))
          vim.notify('Tab root updated: ' .. vim.fn.fnamemodify(root, ':~'), vim.log.levels.INFO)
        end
      end
    end
  end,
})

-- Command to manually set tab root to current project
vim.api.nvim_create_user_command("ProjectSetRoot", function()
  local root = require('tasks').get_project_root()
  if root and vim.fn.isdirectory(root) == 1 then
    vim.cmd('tcd ' .. vim.fn.fnameescape(root))
    vim.notify('Tab root set to: ' .. root, vim.log.levels.INFO)
  else
    vim.notify('Could not detect project root', vim.log.levels.WARN)
  end
end, { desc = 'Set tab root to current project' })

-- Update tab directory when switching projects via picker
local original_projects_action = nil
vim.api.nvim_create_autocmd("User", {
  pattern = "SnacksPickerDone",
  callback = function(event)
    if event.data and event.data.picker and event.data.picker.opts and event.data.picker.opts.source == "projects" then
      if event.data.items and #event.data.items > 0 then
        local selected = event.data.items[1]
        if selected and selected.file then
          local project_root = vim.fn.fnamemodify(selected.file, ':h')
          if project_root and vim.fn.isdirectory(project_root) == 1 then
            vim.schedule(function()
              vim.cmd('tcd ' .. vim.fn.fnameescape(project_root))
              vim.notify('Project root: ' .. project_root, vim.log.levels.INFO)
            end)
          end
        end
      end
    end
  end,
})

-- Enhanced cleanup for all jobs and terminals on exit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    -- Kill all running jobs
    local jobs = vim.fn.jobwait({}, 0) -- Get all job IDs with 0 timeout (non-blocking)
    if jobs and type(jobs) == 'table' then
      for _, job_id in ipairs(jobs) do
        if job_id > 0 then
          vim.fn.jobstop(job_id)
        end
      end
    end

    -- Force close all terminal buffers and their processes
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
        if buftype == 'terminal' then
          -- Get the terminal job ID and stop it
          local term_job_id = vim.api.nvim_buf_get_var(buf, 'terminal_job_id')
          if term_job_id then
            vim.fn.jobstop(term_job_id)
          end
          -- Force delete the buffer
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end

    -- Clean up any remaining background processes started by tasks
    vim.cmd('silent! !pkill -P ' .. vim.fn.getpid())
  end,
})

-- Also cleanup on unexpected exits
vim.api.nvim_create_autocmd("VimLeave", {
  callback = function()
    -- Final cleanup of any remaining processes
    vim.cmd('silent! !pkill -P ' .. vim.fn.getpid())
  end,
})


