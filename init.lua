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
vim.opt.foldmethod = "marker"
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

-- Tab navigation
map('n', '<leader>tt', '<cmd>tabnew<cr>', { desc = "New tab" })
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
        win = {
          position = 'bottom',
          height = 0.3,
          style = 'terminal',
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
      dim = { enabled = true },

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
      { '<C-/>',       function() require('snacks').terminal.toggle() end,      desc = 'Toggle Terminal',    mode = { 'n', 't' } },
      { '<leader>ot',  function() require('snacks').terminal.toggle() end,      desc = 'Toggle Terminal' },

      -- Buffer operations
      { '<leader>bb',  function() Snacks.picker.buffers() end,                  desc = 'All Buffers' },
      { '<leader>br',  function() require('tasks').show_terminal_buffers() end, desc = 'Terminal Buffers' },
      { '<leader>bt',  show_tab_picker,                                         desc = 'Tab List' },
      { '<leader>bd',  '<cmd>bdelete<cr>',                                      desc = 'Delete Buffer' },
      { '<leader>bD',  '<cmd>bdelete!<cr>',                                     desc = 'Force Delete Buffer' },

      -- Task runner
      { '<leader>rr',  function() require('tasks').show_task_picker() end,      desc = 'Run Task' },
      { '<leader>rl',  function() require('tasks').run_last_command() end,      desc = 'Run Last Command' },
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

      -- Quit
      { '<leader>qq', '<cmd>qa<cr>',                               desc = 'Quit All' },
      {
        '<leader>qr',
        function()
          vim.cmd('source ' .. vim.fn.stdpath('config') .. '/init.lua')
          vim.notify('Config reloaded', vim.log.levels.INFO)
        end,
        desc = 'Reload Config'
      },


      -- Dim toggle
      { '<leader>td', function() Snacks.toggle.dim():toggle() end, desc = 'Toggle Dim' },

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
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",
              ["a="] = "@assignment.outer",
              ["i="] = "@assignment.inner",
              ["ar"] = "@return.outer",
              ["ir"] = "@return.inner",
              ["ao"] = "@comment.outer",
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]b"] = "@block.outer",
              ["]l"] = "@loop.outer",
              ["]i"] = "@conditional.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[b"] = "@block.outer",
              ["[l"] = "@loop.outer",
              ["[i"] = "@conditional.outer",
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

      -- Setup context commentstring for JSX
      require('ts_context_commentstring').setup({
        enable = true,
        enable_autocmd = false,
      })

      -- Integrate with Comment.nvim if needed
      vim.g.skip_ts_context_commentstring_module = true
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
    opts = {},
    keys = {
      { "H",          "<cmd>lua require('nvim-treeclimber').goto_parent()<cr>", desc = "Go to parent node" },
      { "L",          "<cmd>lua require('nvim-treeclimber').goto_child()<cr>",  desc = "Go to child node" },
      { "J",          "<cmd>lua require('nvim-treeclimber').goto_next()<cr>",   desc = "Go to next node" },
      { "K",          "<cmd>lua require('nvim-treeclimber').goto_prev()<cr>",   desc = "Go to previous node" },
      { "<leader>cs", "<cmd>lua require('nvim-treeclimber').swap_prev()<cr>",   desc = "Swap with previous" },
      { "<leader>cS", "<cmd>lua require('nvim-treeclimber').swap_next()<cr>",   desc = "Swap with next" },
      { "vn",         "<cmd>lua require('nvim-treeclimber').select_node()<cr>", desc = "Select current node" },
    },
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
      console_timeout = 5000,
      auto_show_console = false,
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
        update_event = { 'CursorMoved', 'CursorMovedI' },
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


