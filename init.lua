-- Minimal IDE-style Neovim Configuration
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
vim.opt.laststatus = 3 -- Global statusline for fully collapsible views

-- Native completion settings
vim.opt.completeopt = { "menu", "menuone", "noselect" }
vim.opt.pumheight = 15
vim.opt.pumblend = 10

-- IDE-style keymaps
local function map(mode, lhs, rhs, opts)
  local options = { noremap = true, silent = true }
  if opts then
    options = vim.tbl_extend('force', options, opts)
  end
  vim.keymap.set(mode, lhs, rhs, options)
end

-- Window management (from nvim.main with IDE optimizations)
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

-- Tab navigation (IDE-style)
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

-- Enable vim.loader for performance (2025 best practice)
vim.loader.enable()

-- Load LSP configuration before lazy.nvim (needed for ftplugins)
require('lsp')


-- Helper function for tab picker (needs to be defined before lazy.nvim setup)
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

-- Lazy.nvim bootstrap with performance optimization
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

-- Plugin setup with performance-optimized lazy loading
require('lazy').setup({

  -- Oil.nvim - Modern file explorer (lazy load on command)
  {
    'stevearc/oil.nvim',
    cmd = 'Oil',
    keys = { { '<leader>fj', '<cmd>Oil<CR>', desc = 'File Explorer' } },
    config = function()
      require('oil').setup {
        view_options = {
          show_hidden = true,
        },
        keymaps = {
          ['<C-v>'] = { 'actions.select_vsplit', desc = 'Open in vertical split' },
          ['<C-s>'] = { 'actions.select_split', desc = 'Open in horizontal split' },
          ['<C-t>'] = { 'actions.select_tab', desc = 'Open in new tab' },
        },
      }
    end,
  },

  -- Which-key.nvim - Key mapping help (lazy load on VeryLazy event)
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
          { '<leader>b',  group = 'Buffers' }, -- Buffer operations
          { '<leader>bb', function() require('snacks').picker.buffers() end, desc = 'Buffer List' },
          { '<leader>bt', show_tab_picker,                                   desc = 'Tab List' },
          { '<leader>h',  group = 'Harpoon' }, -- Fast file navigation
          { '<leader>g',  group = 'Git' },     -- Git operations
          { '<leader>f',  group = 'Find' },
          { '<leader>s',  group = 'Search' },
          { '<leader>p',  group = 'Project' }, -- Project operations
          { '<leader>pr', '<cmd>ProjectRoot<cr>',                            desc = 'Show Project Root' },
          { '<leader>r',  group = 'Run' },     -- Run operations
          { '<leader>rr', '<cmd>OverseerRun<cr>',                            desc = 'Run Task' },
          { '<leader>ro', '<cmd>OverseerToggle<cr>',                         desc = 'Toggle Overseer' },
          { '<leader>rb', '<cmd>OverseerBuild<cr>',                          desc = 'Build Task' },
          { '<leader>rq', '<cmd>OverseerQuickAction<cr>',                    desc = 'Quick Action' },
          { '<leader>ra', '<cmd>OverseerTaskAction<cr>',                     desc = 'Task Action' },
          { "<leader>sg", function()
            local root = vim.g.project_root or vim.fn.getcwd()
            require("snacks").picker.grep({ cwd = root })
          end, desc = "Grep" },
          { "<leader>sw", function() require("snacks").picker.grep_word() end, desc = "Search Word" },
          { "<leader>s*", function()
            local word = vim.fn.expand("<cword>")
            local root = vim.g.project_root or vim.fn.getcwd()
            require("snacks").picker.grep({ search = word, cwd = root })
          end, desc = "Grep Word Under Cursor" },
          { '<leader>q',  group = 'Quit' },
          { '<leader>d',  group = 'Debug' }, -- Debug operations
          { '<leader>a',  group = 'AI' },    -- AI operations (Avante)
          { '<leader>c',  group = 'LSP' },   -- LSP operations
          { '<leader>l',  group = 'Code' },  -- Code actions (format, rename)
        },
      }
    end,
  },

  -- Snacks.nvim - Performance and essential features
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      -- Essential features for minimal IDE
      bigfile = { enabled = true, size = 1.5 * 1024 * 1024 }, -- Performance for large files
      quickfile = { enabled = true },                         -- Faster file opening
      input = {
        enabled = true,
        win = {
          wo = {
            winblend = 0,
            winhighlight = 'Normal:SnacksInput,FloatBorder:SnacksInputBorder,FloatTitle:SnacksInputTitle',
          },
        },
      },
      words = { enabled = true, debounce = 200 }, -- Word completion
      rename = { enabled = true },                -- LSP rename
      quickfix = { enabled = true },              -- Quickfix enhancement

      -- Terminal management
      terminal = {
        enabled = true,
        win = {
          position = 'bottom',
          height = 0.3,
          style = 'terminal',
        },
      },

      -- Fuzzy finder (vscode-style layout)
      picker = {
        enabled = true,
        ui_select = true, -- Replace vim.ui.select with snacks picker
        layout = 'vscode',
        preview = { enabled = false },
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
          fuzzy = true,     -- Enable fuzzy matching
          smartcase = true, -- Use smartcase matching
          ignorecase = true -- Use ignorecase matching
        },
      },

      -- Essential UI features
      dim = { enabled = true }, -- Dim inactive windows

      -- Disabled features for minimal setup
      scope = { enabled = false }, -- Using separate scope.nvim
      notifier = { enabled = false },
      dashboard = { enabled = false },
      zen = { enabled = false },
      scratch = { enabled = false },
    },
    config = function(_, opts)
      require("snacks").setup(opts)
      -- Force global replacement of vim.ui.select if not already done
      if vim.ui.select ~= require("snacks").picker.select then
        vim.ui.select = require("snacks").picker.select
      end
    end,
    keys = {
      -- File finding (using project root)
      { '<leader><leader>', function() require('snacks').picker.files({ cwd = vim.g.project_root or vim.fn.getcwd() }) end,     desc = 'Find Files' },
      { '<leader>ff',       function() require('snacks').picker.files({ cwd = vim.g.project_root or vim.fn.getcwd() }) end,     desc = 'Find Files' },
      { '<leader>fr',       function() require('snacks').picker.recent() end,                                                   desc = 'Recent Files' },
      { '<leader>fb',       function() require('snacks').picker.buffers() end,                                                  desc = 'Find Buffers' },

      -- Search functionality (using project root)
      { '<leader>sg',       function() require('snacks').picker.grep({ cwd = vim.g.project_root or vim.fn.getcwd() }) end,      desc = 'Grep' },
      { '<leader>sw',       function() require('snacks').picker.grep_word({ cwd = vim.g.project_root or vim.fn.getcwd() }) end, desc = 'Search Word' },
      { '<leader>ss',       function() require('snacks').picker.lines() end,                                                    desc = 'Search Lines' },
      { '<leader>si',       function() require('snacks').picker.lsp_symbols() end,                                              desc = 'Search Symbols' },
      { '<leader>sd',       function() require('snacks').picker.diagnostics() end,                                              desc = 'Diagnostics' },

      -- Help and utilities
      { '<leader>hh',       function() require('snacks').picker.help() end,                                                     desc = 'Help Tags' },
      { '<leader>oc',       function() require('snacks').picker.commands() end,                                                 desc = 'Command Palette' },

      -- Terminal
      { '<C-/>',            function() require('snacks').terminal.toggle() end,                                                 desc = 'Toggle Terminal',    mode = { 'n', 't' } },
      { '<leader>ot',       function() require('snacks').terminal.toggle() end,                                                 desc = 'Toggle Terminal' },

      -- Quick buffer operations
      { '<leader>bt',       show_tab_picker,                                                                                    desc = 'Tab List' },
      { '<leader>bd',       '<cmd>bdelete<cr>',                                                                                 desc = 'Delete Buffer' },
      { '<leader>bD',       '<cmd>bdelete!<cr>',                                                                                desc = 'Force Delete Buffer' },

      -- Quit
      { '<leader>qq',       '<cmd>qa<cr>',                                                                                      desc = 'Quit All' },
      { '<leader>qr',       function() vim.cmd('source ' .. vim.fn.stdpath('config') .. '/init.lua') vim.notify('Config reloaded', vim.log.levels.INFO) end, desc = 'Reload Config' },

      -- LSP rename
      { '<leader>cr',       function() require('snacks').rename() end,                                                          desc = 'Rename' },

      -- Dim toggle
      { '<leader>td',       function() require('snacks').dim.toggle() end,                                                      desc = 'Toggle Dim' },
      {
        "<leader>pt",
        function()
          local cmd = vim.fn.input("Command: ")
          if cmd ~= "" then
            vim.g.last_terminal_command = cmd
            local cwd = vim.g.project_root or vim.fn.getcwd(0)
            vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
            vim.cmd("terminal " .. cmd)
            vim.cmd("startinsert")
          end
        end,
        desc = "Open Command in Terminal"
      }
    },
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

  -- Blink.cmp - Performant completion plugin
  {
    'saghen/blink.cmp',
    version = '0.*',
    event = 'InsertEnter',
    dependencies = {
      'L3MON4D3/LuaSnip',
      'rafamadriz/friendly-snippets',
    },
    opts = {
      keymap = {
        preset = 'default',
        ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
        ['<C-e>'] = { 'hide' },
        ['<CR>'] = { 'accept', 'fallback' },
        ['<Tab>'] = { 'select_next', 'snippet_forward', 'fallback' },
        ['<S-Tab>'] = { 'select_prev', 'snippet_backward', 'fallback' },
        ['<C-n>'] = { 'select_next', 'fallback' },
        ['<C-p>'] = { 'select_prev', 'fallback' },
        ['<C-u>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-d>'] = { 'scroll_documentation_down', 'fallback' },
      },
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = 'mono',
      },
      snippets = {
        preset = 'luasnip',
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
      completion = {
        menu = {
          border = 'single',
          winblend = 0,
          draw = {
            columns = {
              { 'label', 'label_description', gap = 1 },
              { 'kind_icon', 'kind' }
            },
          },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 500,
          window = {
            border = 'single',
            winblend = 0,
          },
        },
        ghost_text = {
          enabled = true,
        },
      },
      signature = {
        enabled = true,
        window = {
          border = 'single',
        },
      },
    },
  },

  -- Treesitter - Complete syntax and code understanding setup
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
      "nvim-treesitter/nvim-treesitter-refactor",
      "MeanderingProgrammer/treesitter-modules.nvim",
      "mawkler/jsx-element.nvim",
    },
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua", "vim", "vimdoc", "javascript", "typescript", "tsx",
          "python", "go", "rust", "java", "c", "cpp",
          "html", "css", "json", "yaml", "toml", "markdown",
          "astro", "angular", "scss", "dart"
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
      })
      require("jsx-element").setup()
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

  -- Mini.bracketed - Unimpaired bracketed pairs
  {
    "echasnovski/mini.bracketed",
    version = false,
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("mini.bracketed").setup({
        buffer = { suffix = 'b', options = { list_opener = function() require('snacks').picker.buffers() end } },
        comment = { suffix = 'c', options = {} },
        diagnostic = { suffix = 'd', options = {} },
        file = { suffix = 'f', options = {} },
        jump = { suffix = 'j', options = {} },
        quickfix = { suffix = 'q', options = { list_opener = function() require('snacks').picker.qflist() end } },
        location = { suffix = 'l', options = { list_opener = function() require('snacks').picker.loclist() end } },
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

  -- Harpoon-core - Fast file navigation
  {
    "MeanderingProgrammer/harpoon-core.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ha", function() require("harpoon-core").add_file() end,    desc = "Harpoon Add" },
      { "<leader>hh", function() require("harpoon-core").toggle_menu() end, desc = "Harpoon Menu" },
      { "<leader>hn", function() require("harpoon-core").nav_next() end,    desc = "Harpoon Next" },
      { "<leader>hp", function() require("harpoon-core").nav_prev() end,    desc = "Harpoon Previous" },
      { "<leader>h1", function() require("harpoon-core").nav_file(1) end,   desc = "Harpoon File 1" },
      { "<leader>h2", function() require("harpoon-core").nav_file(2) end,   desc = "Harpoon File 2" },
      { "<leader>h3", function() require("harpoon-core").nav_file(3) end,   desc = "Harpoon File 3" },
      { "<leader>h4", function() require("harpoon-core").nav_file(4) end,   desc = "Harpoon File 4" },
    },
    config = function()
      require("harpoon-core").setup({
        menu = {
          width = math.floor(vim.fn.winwidth(0) * 0.8),
          height = 10,
        },
      })
    end,
  },

  -- Markview - Enhanced mark visualization with Avante support
  {
    "OXY2DEV/markview.nvim",
    enabled = true,
    lazy = false,
    ft = { "markdown", "norg", "rmd", "org", "vimwiki", "Avante" },
    keys = {
      { "m",  mode = { "n", "v", "o", "s" } }, -- All mark modes
      { "dm", mode = "n" },                    -- Delete mark
      { "m'", mode = "n" },                    -- Jump to mark
    },
    config = function()
      require("markview").setup({
        preview = {
          filetypes = { "markdown", "norg", "rmd", "org", "vimwiki", "Avante" },
          ignore_buftypes = {},
        },
        max_length = 99999,
        highlight_groups = {
          Markview = { bg = "#b7b3ff", fg = "#000000" },
          MarkviewPrimary = { bg = "#ff79c6", fg = "#000000" },
          MarkviewSecondary = { bg = "#8be9fd", fg = "#000000" },
          MarkviewSign = { fg = "#ff79c6" },
        },
        signs = {
          current_mark = true,
          other_marks = true,
        },
        events = {
          show_on_autocmd = "CursorMoved",
          hide_on_autocmd = "BufLeave",
        },
      })
    end,
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
          { "match",   "FlashMatch",   { bg = "#F0F0F0", fg = "#0D0D0D" } },
          { "current", "FlashCurrent", { bg = "#FFFFFF", fg = "#0D0D0D" } },
          { "label",   "FlashLabel",   { bg = "#646464", fg = "#FFFFFF", bold = true } },
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

  -- Neogit - Git operations
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
      integrations = {
        diffview = true,
        snacks = true,
        snacks_picker = true,
        builtin_diffs = true,
        commit_editor = 'snacks_picker',
        select_view = 'snacks_picker',
        rebase_editor = 'snacks_picker',
        commit_select_view = 'snacks_picker',
        status_view = 'snacks_picker',
        log_view = 'snacks_picker',
        rebase_status_view = 'snacks_picker',
        reflog_view = 'snacks_picker',
        staging_view = 'snacks_picker',
        stash_view = 'snacks_picker',
        help_view = 'snacks_picker',
        config_view = 'snacks_picker',
      },
      commit_popup = {
        kind = 'split',
        wrap = false,
        border = 'single',
        title_pos = 'left',
        highlight = 'DiffDelete',
        padding = { 1, 1, 1, 1 },
        timeout = 2000,
        no_commit_message = false,
        staged = false,
        unstaged = false,
        untracked = false,
        whitespace = false,
      },
    },
    config = function(opts)
      require('neogit').setup(opts)
    end,
  },

  -- Diffview - Git diff viewer
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
    keys = {
      { '<leader>gd', '<cmd>DiffviewOpen<cr>',          desc = 'Diff View' },
      { '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', desc = 'File History' },
    },
    opts = {},
    config = function()
      require('diffview').setup({})
    end,
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
          require("snacks").picker.qflist()
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

  -- Avante - AI-powered coding assistant with LM Studio and ACP support
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    build = 'make',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'MeanderingProgrammer/render-markdown.nvim',
    },
    keys = {
      { '<leader>aa', function() require('avante.api').ask() end,     desc = 'Avante Ask',    mode = { 'n', 'v' } },
      { '<leader>ar', function() require('avante.api').refresh() end, desc = 'Avante Refresh' },
      { '<leader>ae', function() require('avante.api').edit() end,    desc = 'Avante Edit',   mode = 'v' },
      { '<leader>at', '<cmd>AvanteToggle<cr>',                        desc = 'Avante Toggle' },
      {
        '<leader>ap',
        function()
          vim.ui.select({ 'claude-code', 'opencode', 'goose', 'lmstudio' }, {
            prompt = 'Select Provider:',
          }, function(choice)
            if choice then
              vim.cmd('AvanteSwitchProvider ' .. choice)
            end
          end)
        end,
        desc = 'Switch Provider'
      },
    },
    opts = {
      provider = 'lmstudio',
      providers = {
        lmstudio = {
          __inherited_from = 'openai',
          endpoint = 'http://localhost:1234/v1',
          -- model = 'kat-dev-mlx',
          model = 'qwen/qwen3-vl-30b',
          timeout = 30000,
          api_key_name = 'LM_API_KEY',
          extra_request_body = {
            temperature = 0.7,
            max_tokens = 24000,
          },
        },
      },
      acp_providers = {
        ["claude-code"] = {
          command = "npx",
          args = { "@zed-industries/claude-code-acp" },
          env = {
            NODE_NO_WARNINGS = "1",
            ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY"),
          },
        },
        opencode = {
          command = 'opencode',
          args = { "acp" },
          env = {},
        },
        goose = {
          command = 'goose',
          args = { 'acp' },
          env = {},
        },
      },
      behaviour = {
        auto_suggestions = false,
        auto_set_highlight_group = true,
        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = true,
      },
      mappings = {
        ask = '<leader>aa',
        edit = '<leader>ae',
        refresh = '<leader>ar',
        diff = {
          ours = 'co',
          theirs = 'ct',
          both = 'cb',
          next = ']x',
          prev = '[x',
        },
        jump = {
          next = ']]',
          prev = '[[',
        },
        submit = {
          normal = '<CR>',
          insert = '<C-s>',
        },
      },
      windows = {
        wrap = true,
        width = 30,
        sidebar_header = {
          align = 'center',
          rounded = true,
        },
      },
      highlights = {
        diff = {
          current = 'DiffText',
          incoming = 'DiffAdd',
        },
      },
      diff = {
        debug = false,
        autojump = true,
      },
    },
    config = function(_, opts)
      require('avante').setup(opts)
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

  -- Overseer - Task runner
  {
    "stevearc/overseer.nvim",
    cmd = { "OverseerRun", "OverseerToggle", "OverseerBuild", "OverseerQuickAction", "OverseerTaskAction" },
    opts = {
      task_list = {
        direction = "bottom",
        min_height = 10,
        max_height = 20,
        default_detail = 1,
      },
    },
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

  -- Trouble.nvim - Diagnostics viewer
  {
    "ivanjermakov/troublesum.nvim",
    event = "LSPAttach",
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
    lazy = true, -- Load all plugins lazily by default
  },
  performance = {
    cache = {
      enabled = true,      -- Enable plugin cache
    },
    reset_packpath = true, -- Reset packpath for faster startup
    rtp = {
      reset = true,        -- Reset runtime path
      disabled_plugins = disabled_plugins,
    },
  },
  change_detection = {
    enabled = false, -- Disable automatic change detection for performance
    notify = false,
  },
  install = {
    colorscheme = { 'habamax', 'custom-monochrome' }, -- Fallback + custom monochrome
  },
})

-- Web development utilities autocmd
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "html", "css", "scss", "javascript", "typescript", "jsx", "tsx" },
  callback = function()
    vim.keymap.set("n", "<leader>cm", function()
      vim.ui.select({
        "Emmet expand",
        "Open in browser",
        "Toggle CSS colors",
        "Format with Emmet"
      }, {
        prompt = "Web Development:",
        format_item = function(item)
          return item
        end
      }, function(choice)
        if choice == "Emmet expand" then
          if vim.fn.exists("*emmet#expandAbbr") == 1 then
            vim.cmd("Emmet")
          else
            vim.lsp.buf.completion()
          end
        elseif choice == "Open in browser" then
          local file = vim.api.nvim_buf_get_name(0)
          local url = "file://" .. file
          vim.fn.system("open " .. url)
        elseif choice == "Toggle CSS colors" then
          vim.g.css_color = not vim.g.css_color
          vim.notify("CSS colors " .. (vim.g.css_color and "enabled" or "disabled"))
        elseif choice == "Format with Emmet" then
          if vim.fn.exists("*emmet#expandAbbr") == 1 then
            vim.cmd("Emmet")
          end
        end
      end)
    end, { buffer = true, desc = "Web development menu" })
  end,
})

-- Custom project root detection with Git worktree support
local function get_project_root(path)
  path = path or vim.fn.expand('%:p:h')
  if path == '' then
    path = vim.fn.getcwd()
  end

  -- Strategy 1: Git worktree support
  local git_dir_cmd = 'cd ' .. vim.fn.shellescape(path) .. " && git rev-parse --git-dir 2>/dev/null"
  local git_dir = vim.fn.system(git_dir_cmd):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")

  if git_dir ~= "" then
    -- Check if we're in a worktree
    if git_dir:match("/worktrees/") then
      -- Extract main git directory from worktree path
      local main_git_dir = git_dir:gsub("/worktrees/.*$", "")
      if vim.fn.isdirectory(main_git_dir) == 1 then
        -- Get worktree root
        local worktree_root = vim.fn.system('cd ' ..
              vim.fn.shellescape(path) .. " && git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", ""):gsub("^%s+", "")
            :gsub("%s+$", "")
        if worktree_root ~= "" and vim.fn.isdirectory(worktree_root) == 1 then
          vim.g.is_worktree = true
          vim.g.worktree_name = git_dir:match("/worktrees/([^/]+)$") or "unknown"
          return worktree_root
        end
      end
    else
      -- Regular git repository
      local git_root = vim.fn.system('cd ' .. vim.fn.shellescape(path) .. " && git rev-parse --show-toplevel 2>/dev/null")
          :gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
        vim.g.is_worktree = false
        return git_root
      end
    end
  end

  -- Strategy 2: Look for project markers
  local markers = {
    '.git', '.svn', '.hg',
    '.envrc', 'flake.nix', 'shell.nix',
    'docker-compose.yml', 'docker-compose.yaml',
    'package.json', 'Cargo.toml', 'go.mod', 'pom.xml',
    'build.gradle', 'CMakeLists.txt', 'Makefile',
    'setup.py', 'pyproject.toml', 'tsconfig.json',
    'composer.json', '.project', '.vscode', '.idea',
    'mix.exs', 'pubspec.yaml'
  }

  -- Search upwards for markers
  local current = path
  local found_mix_exs = nil

  while current ~= '/' do
    for _, marker in ipairs(markers) do
      local marker_path = current .. '/' .. marker
      if vim.fn.isdirectory(marker_path) == 1 or vim.fn.filereadable(marker_path) == 1 then
        -- Special handling for Elixir umbrella projects
        if marker == 'mix.exs' then
          -- Check if this is an umbrella project
          local mix_content = vim.fn.readfile(marker_path)
          for _, line in ipairs(mix_content) do
            if line:match('apps_path:%s*"apps"') or line:match("apps_path:%s*'apps'") then
              -- This is an umbrella root, use it
              return current
            end
          end
          -- Not an umbrella, but remember the first mix.exs we found
          if not found_mix_exs then
            found_mix_exs = current
          end
          -- Continue searching upward for umbrella
        else
          return current
        end
      end
    end
    local parent = vim.fn.fnamemodify(current, ':h')
    if parent == current then
      break
    end
    current = parent
  end

  -- If we found a mix.exs but no umbrella, use it
  if found_mix_exs then
    return found_mix_exs
  end

  -- Strategy 3: Check if we're in a bare repository
  local is_bare = vim.fn.system('cd ' .. vim.fn.shellescape(path) .. " && git rev-parse --is-bare-repository 2>/dev/null")
      :gsub("\n", "") == "true"
  if is_bare then
    local git_dir = vim.fn.system('cd ' .. vim.fn.shellescape(path) .. " && git rev-parse --git-dir 2>/dev/null"):gsub(
      "\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if git_dir ~= "" then
      return vim.fn.fnamemodify(git_dir, ":h")
    end
  end

  -- Fallback to current working directory
  return vim.fn.getcwd()
end

-- Auto-setup project root on startup and directory changes
vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "BufEnter" }, {
  callback = function()
    local current_path = vim.fn.expand("%:p:h")
    if current_path == "" then current_path = vim.fn.getcwd() end

    -- Update project root
    local project_root = get_project_root(current_path)
    vim.g.project_root = project_root

    -- Auto-change directory to project root
    if project_root and vim.fn.isdirectory(project_root) == 1 then
      if vim.fn.getcwd() ~= project_root then
        vim.cmd('cd ' .. vim.fn.fnameescape(project_root))
      end
    end
  end,
})

-- Command to show current project root
vim.api.nvim_create_user_command("ProjectRoot", function()
  local root = vim.g.project_root or vim.fn.getcwd()
  local info = "Project root: " .. root
  if vim.g.is_worktree then
    info = info .. " (worktree: " .. (vim.g.worktree_name or "unknown") .. ")"
  end
  vim.notify(info, vim.log.levels.INFO)
end, {})
