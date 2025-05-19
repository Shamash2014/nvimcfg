local set = vim.keymap.set

return {

   {
      "alexxGmZ/e-ink.nvim",
      priority = 1000,
      config = function()
         require("e-ink").setup()
         vim.cmd.colorscheme "e-ink"

         -- choose light mode or dark mode
         -- vim.opt.background = "dark"
         -- vim.opt.background = "light"
         --
         -- or do
         -- :set background=dark
         -- :set background=light
         --
         --
         vim.o.background = "light"
         vim.cmd [[ set guicursor=n-v-c:block-Cursor,i-ci-ve:ver25-Cursor,r-cr-o:hor20-Cursor ]]
      end
   },
   {
      "kylechui/nvim-surround",
      version = "*", -- Use for stability; omit to use `main` branch for the latest features
      event = "VeryLazy",
      config = function()
         require("nvim-surround").setup({
            -- Configuration here, or leave empty to use defaults
         })
      end
   },
   -- normal autocommands events (`:help autocmd-events`).
   --
   -- Then, because we use the `opts` key (recommended), the configuration runs
   -- after the plugin has been loaded as `require(MODULE).setup(opts)`.

   {                      -- Useful plugin to show you pending keybinds.
      'folke/which-key.nvim',
      event = 'VimEnter', -- Sets the loading event to 'VimEnter'
      opts = {
         -- delay between pressing a key and opening which-key (milliseconds)
         -- this setting is independent of vim.opt.timeoutlen
         delay = 0,
         -- Document existing key chains
         spec = {
            { '<leader>c', group = '[C]ode',    mode = { 'n', 'x' } },
            { '<leader>d', group = '[D]ocument' },
            { '<leader>r', group = '[R]ename' },
            { '<leader>f', group = '[F]iles' },
            { '<leader>s', group = '[S]earch' },
            { '<leader>w', group = '[W]indows' },
            { '<leader>t', group = '[T]oggle' },
            { '<leader>o', group = '[O]pen' },
         },
      },
   },

   { -- Highlight, edit, and navigate code
      'nvim-treesitter/nvim-treesitter',
      dependencies = {

         "nvim-treesitter/nvim-treesitter-textobjects"

      },
      build = ':TSUpdate',
      main = 'nvim-treesitter.configs', -- Sets main module to use for opts
      -- [[ Configure Treesitter ]] See `:help nvim-treesitter`
      opts = {
         ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
         -- Autoinstall languages that are not installed
         auto_install = true,
         highlight = {
            enable = true,
            -- Some languages depend on vim's regex highlighting system (such as Ruby) for indent rules.
            --  If you are experiencing weird indenting issues, add the language to
            --  the list of additional_vim_regex_highlighting and disabled languages for indent.
            additional_vim_regex_highlighting = { 'ruby' },
         },
         indent = { enable = true, disable = { 'ruby' } },
         textobjects = {
            select = {
               enable = true,

               -- Automatically jump forward to textobj, similar to targets.vim
               lookahead = true,

               keymaps = {
                  -- You can use the capture groups defined in textobjects.scm
                  ["af"] = "@function.outer",
                  ["if"] = "@function.inner",
                  ["ac"] = "@class.outer",
                  -- You can optionally set descriptions to the mappings (used in the desc parameter of
                  -- nvim_buf_set_keymap) which plugins like which-key display
                  ["ic"] = { query = "@class.inner", desc = "Select inner part of a class region" },
                  -- You can also use captures from other query groups like `locals.scm`
                  ["as"] = { query = "@local.scope", query_group = "locals", desc = "Select language scope" },
               },
               -- You can choose the select mode (default is charwise 'v')
               --
               -- Can also be a function which gets passed a table with the keys
               -- * query_string: eg '@function.inner'
               -- * method: eg 'v' or 'o'
               -- and should return the mode ('v', 'V', or '<c-v>') or a table
               -- mapping query_strings to modes.
               selection_modes = {
                  ['@parameter.outer'] = 'v', -- charwise
                  ['@function.outer'] = 'V',  -- linewise
                  ['@class.outer'] = '<c-v>', -- blockwise
               },
               -- If you set this to `true` (default is `false`) then any textobject is
               -- extended to include preceding or succeeding whitespace. Succeeding
               -- whitespace has priority in order to act similarly to eg the built-in
               -- `ap`.
               --
               -- Can also be a function which gets passed a table with the keys
               -- * query_string: eg '@function.inner'
               -- * selection_mode: eg 'v'
               -- and should return true or false
               include_surrounding_whitespace = true,
            },
         },
      },
      -- There are additional nvim-treesitter modules that you can use to interact
      -- with nvim-treesitter. You should go explore a few and see what interests you:
      --
      --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
      --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
      --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
   },
   {
      'echasnovski/mini.nvim',
      version = false,
      config = function()
         require('mini.pairs').setup()
         require('mini.splitjoin').setup()
         require('mini.move').setup()
         require('mini.bracketed').setup()
         require('mini.extra').setup({})
         require('mini.pick').setup({
            mappings = {
               move_down  = '<C-j>',
               move_start = '<C-g>',
               move_up    = '<C-k>',
            }
         })

         set('n', '<leader>ff', function()
            -- MiniPick.builtin.files({ tool = 'rg' })
            Snacks.picker.files({ layout = { preset = "vscode", preview = "main" } })
         end)
         set('n', '<leader>sg', function()
            -- MiniPick.builtin.grep_live({ tool = "rg" })
            Snacks.picker.grep({ layout = { preset = "vscode", preview = "main" } })
         end)

         set('n', '<leader>bb', function()
            -- MiniPick.builtin.buffers()
            Snacks.picker.buffers({ layout = { preset = "vscode" }, preview = "main" })
         end)

         set('n', '<leader>bm', function()
            -- MiniPick.builtin.buffers()
            Snacks.picker.marks({ layout = { preset = "vscode" }, preview = "main" })
         end)

         set('n', '<leader><leader>', function()
            -- MiniPick.builtin.buffers()
            Snacks.picker.smart({ layout = { preset = "vscode" }, preview = "main" })
         end)

         set('n', '<leader>bd', function()
            vim.api.nvim_buf_delete(MiniPick.get_picker_matches().current.bufnr, {})
         end)

         set('n', '<leader>fr', function()
            -- MiniPick.builtin.resume()
            Snacks.picker.recent({ layout = { preset = "vscode" }, preview = "main" })
         end)


         set('n', '<leader>s*', function()
            -- MiniPick.builtin.resume()
            Snacks.picker.grep_word({ layout = { preset = "vscode" }, preview = "main" })
         end)


         set('n', '<leader>fb', function()
            -- MiniPick.builtin.resume()
            Snacks.picker.resume({ layout = { preset = "vscode" } })
         end)

         set('n', '<leader>cd', function()
            Snacks.picker.diagnostics({ layout = { preset = "vscode", preview = "main" } })
         end)

         set('n', '<leader>cs', function()
            -- MiniExtra.pickers.lsp({ scope = 'document_symbol' })
            Snacks.picker.lsp_symbols({ layout = { preset = "vscode", preview = "main" } })
         end)

         set('n', '<leader>cw', function()
            -- MiniExtra.pickers.lsp({ scope = 'document_symbol' })
            Snacks.picker.lsp_workspace_symbols({ layout = { preset = "vscode", preview = "main" } })
         end)

         set('n', '<leader>td', function()
            -- MiniExtra.pickers.lsp({ scope = 'document_symbol' })
            Snacks.dim()
         end)
      end
   },
   {
      "ggandor/leap.nvim",
      dependencies = {
         {
            "ggandor/flit.nvim",
            config = function()
               require('flit').setup {}
            end
         }
      },
      config = function()
         require('leap').opts.equivalence_classes = { ' \t\r\n', '([{', ')]}', '\'"`' }
         set('n', 's', '<Plug>(leap)')
         set('n', 'S', '<Plug>(leap-from-window)')
         set({ 'x', 'o' }, 's', '<Plug>(leap-forward)')
         set({ 'x', 'o' }, 'S', '<Plug>(leap-backward)')
         set({ 'n', 'x', 'o' }, 'ga', function()
            require('leap.treesitter').select()
         end)
         set({ 'n', 'o' }, 'gs', function()
            require('leap.remote').action()
         end)
      end
   },

   {
      "NeogitOrg/neogit",
      dependencies = {
         "nvim-lua/plenary.nvim",  -- required
         "sindrets/diffview.nvim", -- optional - Diff integration

         -- Only one of these is needed.
         -- "nvim-telescope/telescope.nvim", -- optional
         -- "ibhagwan/fzf-lua",              -- optional
         "echasnovski/mini.pick", -- optional
      },
      config = function()
         require("neogit").setup {}

         set('n', '<leader>gg', function()
            local neogit = require("neogit")
            neogit.open({ kind = "vsplit" })
         end)
      end
   },
   {
      'akinsho/git-conflict.nvim',
      version = "*",
      config = function()
         require('git-conflict').setup()
      end
   },
   {
      "chrisgrieser/nvim-spider",
      lazy = true,
      keys = {
         { "w", "<cmd>lua require('spider').motion('w')<CR>", mode = { "n", "o", "x" } },
         { "e", "<cmd>lua require('spider').motion('e')<CR>", mode = { "n", "o", "x" } },
         { "b", "<cmd>lua require('spider').motion('b')<CR>", mode = { "n", "o", "x" } },
      },
   },
   {
      'stevearc/oil.nvim',
      ---@module 'oil'
      ---@type oil.SetupOpts
      opts = {},
      -- Optional dependencies
      dependencies = { { "echasnovski/mini.icons", opts = {} } },
      -- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if prefer nvim-web-devicons
      config = function()
         require("oil").setup()
         set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
      end
   },
   { 'Abstract-IDE/penvim', config = true },
   {
      'stevearc/quicker.nvim',
      -- event = "FileType qf",
      ---@module "quicker"
      ---@type quicker.SetupOptions
      opts = {},
      config = function()
         require("quicker").setup()
         set("n", "<leader>oq", function()
            require("quicker").toggle()
         end, {
            desc = "Toggle quickfix",
         })

         set("n", "<leader>ol", function()
            require("quicker").toggle({ loclist = true })
         end, {
            desc = "Toggle loclist",
         })
      end

   },
   {
      "RRethy/vim-illuminate",
   },
   {
      "gpanders/editorconfig.nvim"
   },
   {
      'saghen/blink.cmp',
      -- optional: provides snippets for the snippet source
      dependencies = {
         'rafamadriz/friendly-snippets',
         {
            'saghen/blink.compat',
            -- use the latest release, via version = '*', if you also use the latest release for blink.cmp
            version = '*',
            -- lazy.nvim will automatically load the plugin when it's required by blink.cmp
            lazy = true,
            -- make sure to set opts so that lazy.nvim calls blink.compat's setup
            opts = {},
         },

         {
            "giuxtaposition/blink-cmp-copilot",
            dependencies = {
               {
                  "zbirenbaum/copilot.lua",
                  cmd = "Copilot",
                  event = "InsertEnter",
                  config = function()
                     require("copilot").setup({
                        suggestion = { enabled = false },
                        panel = { enabled = false },
                     })
                  end,
               }
            }
         },
         "mikavilpas/blink-ripgrep.nvim",
         {
            "supermaven-inc/supermaven-nvim",
            config = function()
               require("supermaven-nvim").setup({})
            end,
         },

         { "tzachar/cmp-tabnine", build = "./install.sh" },

      },
      -- use a release tag to download pre-built binaries
      version = '*',
      -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
      -- build = 'cargo build --release',
      -- If you use nix, you can build from source using latest nightly rust with:
      -- build = 'nix run .#build-plugin',

      ---@module 'blink.cmp'
      ---@type blink.cmp.Config
      opts = {
         -- 'default' for mappings similar to built-in completion
         -- 'super-tab' for mappings similar to vscode (tab to accept, arrow keys to navigate)
         -- 'enter' for mappings similar to 'super-tab' but with 'enter' to accept
         -- See the full "keymap" documentation for information on defining your own keymap.
         keymap = {
            preset = 'default',

            ['<C-k>'] = { 'select_prev', 'fallback' },
            ['<C-j>'] = { 'select_next', 'fallback' },
         },
         completion = {
            ghost_text = { enabled = true },
            menu = {
               draw = {
                  components = {
                     kind_icon = {
                        ellipsis = false,
                        text = function(ctx)
                           local kind_icon, _, _ = require('mini.icons').get('lsp', ctx.kind)
                           return kind_icon
                        end,
                        -- Optionally, you may also use the highlights from mini.icons
                        highlight = function(ctx)
                           local _, hl, _ = require('mini.icons').get('lsp', ctx.kind)
                           return hl
                        end,
                     }
                  }
               }
            }
         },
         appearance = {
            -- Sets the fallback highlight groups to nvim-cmp's highlight groups
            -- Useful for when your theme doesn't support blink.cmp
            -- Will be removed in a future release
            use_nvim_cmp_as_default = true,
            -- Set to 'mono' for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
            -- Adjusts spacing to ensure icons are aligned
            nerd_font_variant = 'mono'
         },

         -- Default list of enabled providers defined so that you can extend it
         -- elsewhere in your config, without redefining it, due to `opts_extend`
         sources = {
            default = { 'supermaven', 'cmp_tabnine', 'copilot', 'lsp', 'path', 'snippets', 'buffer', 'ripgrep',
               "dadbod",
               "avante_commands",
               "avante_mentions",
               "avante_files",
            },
            providers = {
               cmp_tabnine = {
                  name = "cmp_tabnine", -- IMPORTANT: use the same name as you would for nvim-cmp
                  module = "blink.compat.source",

                  -- all blink.cmp source config options work as normal:
                  score_offset = -3,

                  -- this table is passed directly to the proxied completion source
                  -- as the `option` field in nvim-cmp's source config
                  --
                  -- this is NOT the same as the opts in a plugin's lazy.nvim spec
                  opts = {
                     -- this is an option from cmp-digraphs
                  },
               },
               dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" },
               supermaven = {
                  name = "supermaven", -- IMPORTANT: use the same name as you would for nvim-cmp
                  module = "blink.compat.source",

                  -- all blink.cmp source config options work as normal:
                  score_offset = -3,

                  -- this table is passed directly to the proxied completion source
                  -- as the `option` field in nvim-cmp's source config
                  --
                  -- this is NOT the same as the opts in a plugin's lazy.nvim spec
                  opts = {
                     -- this is an option from cmp-digraphs
                  },
               },
               copilot = {
                  name = "copilot",
                  module = "blink-cmp-copilot",
                  score_offset = 100,
                  async = true,
               },
               avante_commands = {
                  name = "avante_commands",
                  module = "blink.compat.source",
                  score_offset = 90, -- show at a higher priority than lsp
                  opts = {},
               },
               avante_files = {
                  name = "avante_commands",
                  module = "blink.compat.source",
                  score_offset = 100, -- show at a higher priority than lsp
                  opts = {},
               },
               avante_mentions = {
                  name = "avante_mentions",
                  module = "blink.compat.source",
                  score_offset = 1000, -- show at a higher priority than lsp
                  opts = {},
               },
               ripgrep = {
                  module = "blink-ripgrep",
                  name = "Ripgrep",
                  -- the options below are optional, some default values are shown
                  ---@module "blink-ripgrep"
                  ---@type blink-ripgrep.Options
                  opts = {
                     -- For many options, see `rg --help` for an exact description of
                     -- the values that ripgrep expects.

                     -- the minimum length of the current word to start searching
                     -- (if the word is shorter than this, the search will not start)
                     prefix_min_len = 3,

                     -- The number of lines to show around each match in the preview
                     -- (documentation) window. For example, 5 means to show 5 lines
                     -- before, then the match, and another 5 lines after the match.
                     context_size = 5,

                     -- The maximum file size of a file that ripgrep should include in
                     -- its search. Useful when your project contains large files that
                     -- might cause performance issues.
                     -- Examples:
                     -- "1024" (bytes by default), "200K", "1M", "1G", which will
                     -- exclude files larger than that size.
                     max_filesize = "1M",

                     -- Specifies how to find the root of the project where the ripgrep
                     -- search will start from. Accepts the same options as the marker
                     -- given to `:h vim.fs.root()` which offers many possibilities for
                     -- configuration. If none can be found, defaults to Neovim's cwd.
                     --
                     -- Examples:
                     -- - ".git" (default)
                     -- - { ".git", "package.json", ".root" }
                     project_root_marker = ".git",

                     -- The casing to use for the search in a format that ripgrep
                     -- accepts. Defaults to "--ignore-case". See `rg --help` for all the
                     -- available options ripgrep supports, but you can try
                     -- "--case-sensitive" or "--smart-case".
                     search_casing = "--ignore-case",

                     -- (advanced) Any additional options you want to give to ripgrep.
                     -- See `rg -h` for a list of all available options. Might be
                     -- helpful in adjusting performance in specific situations.
                     -- If you have an idea for a default, please open an issue!
                     --
                     -- Not everything will work (obviously).
                     additional_rg_options = {},

                     -- When a result is found for a file whose filetype does not have a
                     -- treesitter parser installed, fall back to regex based highlighting
                     -- that is bundled in Neovim.
                     fallback_to_regex_highlighting = true,

                     -- Show debug information in `:messages` that can help in
                     -- diagnosing issues with the plugin.
                     debug = false,
                  },
                  transform_items = function(_, items)
                     for _, item in ipairs(items) do
                        -- example: append a description to easily distinguish rg results
                        item.labelDetails = {
                           description = "(rg)",
                        }
                     end
                     return items
                  end,
               }
            }
         },
      },
      opts_extend = { "sources.default" }
   },
   {
      "mfussenegger/nvim-dap",
      dependencies = {
         "nvim-neotest/nvim-nio",
         {
            "mfussenegger/nvim-dap-python",
            config = function()
               require("dap-python").setup("uv")
            end
         },
         { "rcarriga/nvim-dap-ui",            config = true },
         { "theHamsta/nvim-dap-virtual-text", config = true },
      },
      config = function()
         local dap, dapui = require("dap"), require("dapui")


         dap.listeners.before.attach.dapui_config = function()
            dapui.open()
         end
         dap.listeners.before.launch.dapui_config = function()
            dapui.open()
         end
         dap.listeners.before.event_terminated.dapui_config = function()
            dapui.close()
         end
         dap.listeners.before.event_exited.dapui_config = function()
            dapui.close()
         end

         set('n', '<leader>old', function() require('dap').continue() end, { desc = 'Continue (dap)' })
         set('n', '<leader>ols', function() require('dap').step_over() end, { desc = 'Step over (dap)' })
         set('n', '<leader>oli', function() require('dap').step_into() end, { desc = 'Step into (dap)' })
         set('n', '<leader>olo', function() require('dap').step_out() end, { desc = 'Step out (dap)' })
         set('n', '<Leader>olb', function() require('dap').toggle_breakpoint() end, { desc = 'Toggle breakpoint (dap)' })
         set('n', '<Leader>olB', function() require('dap').set_breakpoint() end, { desc = 'Set breakpoint (dap)' })
         set('n', '<Leader>oll',
            function() require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end, { desc = 'Set breakpoint (dap)' })
         set('n', '<Leader>olr', function() require('dap').repl.open() end, { desc = 'Open REPL (dap)' })
         set('n', '<Leader>olq', function() require('dap').run_last() end, { desc = 'Run last (dap)' })
         set({ 'n', 'v' }, '<Leader>olh', function()
            require('dap.ui.widgets').hover()
         end, { desc = 'Hover (dap)' })
         set({ 'n', 'v' }, '<Leader>olp', function()
            require('dap.ui.widgets').preview()
         end, { desc = 'Preview (dap)' })
         set('n', '<Leader>olf', function()
            local widgets = require('dap.ui.widgets')
            widgets.centered_float(widgets.frames)
         end, { desc = 'Frames (dap)' })
         set('n', '<Leader>olu', function()
            local widgets = require('dap.ui.widgets')
            widgets.centered_float(widgets.scopes)
         end,  { desc = 'Scopes (dap)' })

         -- Configs
         --
         dap.adapters.mix_task = {
           type = 'executable',
           command = '/Users/shamash/.tools/elixir-ls/debug_adapter.sh', -- debug_adapter.bat for windows
           args = {}
         }
         dap.configurations.elixir = {
            {
               type = "mix_task",
               name = "mix test",
               task = 'test',
               taskArgs = { "--trace" },
               request = "launch",
               startApps = true, -- for Phoenix projects
               projectDir = "${workspaceFolder}",
               requireFiles = {
                  "test/**/test_helper.exs",
                  "test/**/*_test.exs"
               }
            },
            {
               type = "mix_task",
               name = "mix server",
               task = 'phx.server',
               request = "attach",
               remoteNode = "remote@127.0.0.1",
               projectDir = "${workspaceFolder}",
               debugAutoInterpretAllModules = false,
               debugInterpretModulesPatterns = { "Justfin.*", "JustfinCore.*" },
               env = {
                  ELS_ELIXIR_OPTS = "--sname elixir_ls_dap --cookie secret"
               }
            }
         }
      end
   },
   {
      -- Main LSP Configuration
      'neovim/nvim-lspconfig',
      event = { "BufReadPre", "BufNewFile" },

      opts = {
         inlay_hints = {
            enabled = false,
         },
         diagnostics = { virtual_text = { prefix = "icons" } },
         capabilities = {
            textDocument = {
               foldingRange = {
                  dynamicRegistration = false,
                  lineFoldingOnly = true,
               },
               completion = {
                  completionItem = {
                     snippetSupport = true,
                  },
               },
            },
         },
         showMessage = {
            messageActionItem = {
               additionalPropertiesSupport = true,
            },
         },
         flags = {
            debounce_text_changes = 150,
         },
      },
      dependencies = {
         -- {
         --  "hedyhli/outline.nvim",
         --  lazy = true,
         --  cmd = { "Outline", "OutlineOpen" },
         --  keys = { -- Example mapping to toggle outline
         --   { "<leader>os", "<cmd>Outline<CR>", desc = "Toggle outline" },
         --  },
         --  opts = {
         --   -- Your setup opts here
         --   keymaps = {
         --    up_and_jump = '<C-j>',
         --    down_and_jump = '<C-k>',
         --   }
         --  },
         -- },
         {
            'nvim-flutter/flutter-tools.nvim',
            lazy = false,
            ft = "dart",
            dependencies = {
               'nvim-lua/plenary.nvim',
               'stevearc/dressing.nvim', -- optional for vim.ui.select
            },
            keys = {
               { "<leader>cbR", "<cmd>FlutterRestart<CR>", desc = "Flutter run" },
               { "<leader>cbr", "<cmd>FlutterReload<CR>",  desc = "Flutter run" },
               { "<leader>cbf", "<cmd>FlutterRun<CR>",     desc = "Flutter run" },
               { "<leader>cbD", "<cmd>FlutterDebug<CR>",   desc = "Flutter run" },
            },
            opts = {
               lsp = {
                  color = { -- show the derived colours for dart variables
                     background = false,
                     foreground = true,
                     virtual_text = true,
                     virtual_text_str = "■",
                  },
                  settings = {
                     showTodos = true,
                     completeFunctionCalls = true,
                     renameFilesWithClasses = "prompt", -- "always"
                     updateImportsOnRename = true,      --
                     enableSnippets = true,
                     analysisExcludedFolders = {
                        vim.fn.expand '$HOME/.pub-cache',
                        vim.fn.expand '$HOME/fvm/',
                     },
                     lineLength = 200,
                  },
               },
               debugger = { -- integrate with nvim dap + install dart code debugger
                  enabled = true,
                  -- if empty dap will not stop on any exceptions, otherwise it will stop on those specified
                  -- see |:help dap.set_exception_breakpoints()| for more info
                  exception_breakpoints = {},
                  -- Whether to call toString() on objects in debug views like hovers and the
                  -- variables list.
                  -- Invoking toString() has a performance cost and may introduce side-effects,
                  -- although users may expected this functionality. null is treated like false.
                  evaluate_to_string_in_debug_views = true,
                  -- You can use the `debugger.register_configurations` to register custom runner configuration (for example for different targets or flavor). Plugin automatically registers the default configuration, but you can override it or add new ones.
                  -- register_configurations = function(paths)
                  --   require("dap").configurations.dart = {
                  --     -- your custom configuration
                  --   }
                  -- end,
               },
               flutter_lookup_cmd = "asdf where flutter",
               widget_guides = {
                  enabled = false,
               },
               closing_tags = {
                  highlight = "ErrorMsg", -- highlight for the closing tag
                  prefix = ">",           -- character to use for close tag e.g. > Widget
                  priority = 10,          -- priority of virtual text in current line
                  -- consider to configure this when there is a possibility of multiple virtual text items in one line
                  -- see `priority` option in |:help nvim_buf_set_extmark| for more info
                  enabled = true -- set to false to disable
               },
            },
         },
         {
            'Wansmer/symbol-usage.nvim',
            event = 'BufReadPre', -- need run before LspAttach if you use nvim 0.9. On 0.10 use 'LspAttach'
            config = function()
               require('symbol-usage').setup()
            end
         },
         {

            'vxpm/ferris.nvim',
            ft = "rust",
            opts = {
               create_commands = false,
               -- your options here
            },
            keys = {
               {
                  "<leader>cmw",
                  function()
                     require("ferris.methods.reload_workspace")
                  end,
                  desc = "Reload workspace"
               },
               {
                  "<leader>cml",
                  function()
                     require("ferris.methods.view_memory_layout")
                  end,
                  desc = "Memory layoyt"
               },

               {
                  "<leader>cmm",
                  function()
                     require("ferris.methods.expand_macro")
                  end,
                  desc = "expand macro"
               },

            }
         },

         {
            "olexsmir/gopher.nvim",
            ft = "go",
            -- branch = "develop", -- if you want develop branch
            -- keep in mind, it might break everything
            dependencies = {
               "nvim-lua/plenary.nvim",
               "nvim-treesitter/nvim-treesitter",
               {
                  "maxandron/goplements.nvim",
                  ft = "go",
                  opts = {
                     -- your configuration comes here
                     -- or leave it empty to use the default settings
                     -- refer to the configuration section below
                  },
               },
            },
            -- (optional) will update plugin's deps on every update
            -- build = function()
            -- vim.cmd.GoInstallDeps()
            -- end,
            ---@type gopher.Config
            opts = {},
            keys = {
               {
                  -- Customize or remove this keymap to your liking
                  "<leader>cmt",
                  function()
                     require("gopher").test.add()
                  end,
                  mode = "n",
                  desc = "GO add test",
               },
               {
                  -- Customize or remove this keymap to your liking
                  "<leader>cmi",
                  function()
                     require("gopher").iferr()
                  end,
                  mode = "n",
                  desc = "GO if else",
               },

               {
                  -- Customize or remove this keymap to your liking
                  "<leader>cma",
                  function()
                     require("gopher").test.all()
                  end,
                  mode = "n",
                  desc = "GO add all test",
               },


            }

         },

         {
            "actionshrimp/direnv.nvim",
            opts = {
               async = true,
               on_direnv_finished = function()
                  -- You may also want to pair this with `autostart = false` in any `lspconfig` calls
                  -- See the 'LSP config examples' section further down.
                  vim.cmd("LspStart")
               end
            }
         },
         { 'saghen/blink.cmp' },
         {
            'dgagn/diagflow.nvim',
            -- event = 'LspAttach', This is what I use personnally and it works great
            opts = {},
            config = true
         },
         "b0o/schemastore.nvim",
         "yioneko/nvim-vtsls",
         -- Useful status updates for LSP.
         -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
         { 'j-hui/fidget.nvim', opts = {} },

      },
      config = function()
         local lspconfig = require("lspconfig")
         -- Brief aside: **What is LSP?**
         --
         -- LSP is an initialism you've probably heard, but might not understand what it is.
         --
         -- LSP stands for Language Server Protocol. It's a protocol that helps editors
         -- and language tooling communicate in a standardized fashion.
         --
         -- In general, you have a "server" which is some tool built to understand a particular
         -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
         -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
         -- processes that communicate with some "client" - in this case, Neovim!
         --
         -- LSP provides Neovim with features like:
         --  - Go to definition
         --  - Find references
         --  - Autocompletion
         --  - Symbol Search
         --  - and more!
         --
         -- Thus, Language Servers are external tools that must be installed separately from
         -- Neovim. This is where `mason` and related plugins come into play.
         --
         -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
         -- and elegantly composed help section, `:help lsp-vs-treesitter`

         --  This function gets run when an LSP attaches to a particular buffer.
         --    That is to say, every time a new file is opened that is associated with
         --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
         --    function will be executed to configure the current buffer
         vim.api.nvim_create_autocmd('LspAttach', {
            group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
            callback = function(event)
               -- NOTE: Remember that Lua is a real programming language, and as such it is possible
               -- to define small helper and utility functions so you don't have to repeat yourself.
               --
               -- In this case, we create a function that lets us more easily define mappings specific
               -- for LSP related items. It sets the mode, buffer and description for us each time.
               local map = function(keys, func, desc, mode)
                  mode = mode or 'n'
                  vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
               end

               -- Jump to the definition of the word under your cursor.
               --  This is where a variable was first declared, or where a function is defined, etc.
               --  To jump back, press <C-t>.
               map('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')

               -- Find references for the word under your cursor.
               map('gr', vim.lsp.buf.references, '[G]oto [R]eferences')

               -- Jump to the implementation of the word under your cursor.
               --  Useful when your language has ways of declaring types without an actual implementation.
               map('gI', vim.lsp.buf.implementation, '[G]oto [I]mplementation')

               -- Jump to the type of the word under your cursor.
               --  Useful when you're not sure what type a variable is and you want to see
               --  the definition of its *type*, not where it was *defined*.
               map('<leader>cD', vim.lsp.buf.type_definition, 'Type [D]efinition')

               -- Fuzzy find all the symbols in your current document.
               --  Symbols are things like variables, functions, types, etc.
               -- map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')

               -- Fuzzy find all the symbols in your current workspace.
               --  Similar to document symbols, except searches over your entire project.
               -- map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

               -- Rename the variable under your cursor.
               --  Most Language Servers support renaming across files, etc.
               map('<leader>crn', vim.lsp.buf.rename, '[R]e[n]ame')

               -- Execute a code action, usually your cursor needs to be on top of an error
               -- or a suggestion from your LSP for this to activate.
               map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })

               -- WARN: This is not Goto Definition, this is Goto Declaration.
               --  For example, in C this would take you to the header.
               map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

               -- The following two autocommands are used to highlight references of the
               -- word under your cursor when your cursor rests there for a little while.
               --    See `:help CursorHold` for information about when this is executed
               --
               -- When you move your cursor, the highlights will be cleared (the second autocommand).
               local client = vim.lsp.get_client_by_id(event.data.client_id)
               if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
                  local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
                  vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                     buffer = event.buf,
                     group = highlight_augroup,
                     callback = vim.lsp.buf.document_highlight,
                  })

                  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                     buffer = event.buf,
                     group = highlight_augroup,
                     callback = vim.lsp.buf.clear_references,
                  })

                  vim.api.nvim_create_autocmd('LspDetach', {
                     group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
                     callback = function(event2)
                        vim.lsp.buf.clear_references()
                        vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
                     end,
                  })
               end

               -- The following code creates a keymap to toggle inlay hints in your
               -- code, if the language server you are using supports them
               --
               -- This may be unwanted, since they displace some of your code
               if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
                  map('<leader>th', function()
                     vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
                  end, '[T]oggle Inlay [H]ints')
               end
            end,
         })

         -- Change diagnostic symbols in the sign column (gutter)
         -- if vim.g.have_nerd_font then
         --   local signs = { ERROR = '', WARN = '', INFO = '', HINT = '' }
         --   local diagnostic_signs = {}
         --   for type, icon in pairs(signs) do
         --     diagnostic_signs[vim.diagnostic.severity[type]] = icon
         --   end
         --   vim.diagnostic.config { signs = { text = diagnostic_signs } }
         -- end

         -- LSP servers and clients are able to communicate to each other what features they support.
         --  By default, Neovim doesn't support everything that is in the LSP specification.
         --  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
         --  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
         -- Enable the following language servers
         --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
         --
         --  Add any additional override configuration in the following tables. Available keys are:
         --  - cmd (table): Override the default command used to start the server
         --  - filetypes (table): Override the default list of associated filetypes for the server
         --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
         --  - settings (table): Override the default settings passed when initializing the server.
         --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
         local util = require 'lspconfig.util'
         local servers = {

            clojure_lsp = {

            },
            volar = {
               init_options = {
                  vue = {
                     hybridMode = true,
                  },
               },
            },
            dockerls = {},
            gopls = {
               settings = {
                  gofumpt = true,
                  codelenses = {
                     gc_details = false,
                     generate = true,
                     regenerate_cgo = true,
                     run_govulncheck = true,
                     test = true,
                     tidy = true,
                     upgrade_dependency = true,
                     vendor = true,
                  },
                  hints = {
                     assignVariableTypes = true,
                     compositeLiteralFields = true,
                     compositeLiteralTypes = true,
                     constantValues = true,
                     functionTypeParameters = true,
                     parameterNames = true,
                     rangeVariableTypes = true,
                  },
                  analyses = {
                     fieldalignment = true,
                     nilness = true,
                     unusedparams = true,
                     unusedwrite = true,
                     useany = true,
                  },
                  usePlaceholders = true,
                  completeUnimported = true,
                  staticcheck = true,
                  directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
                  semanticTokens = true,
               },
            },
            rust_analyzer = {
               settings = {
                  ["rust-analyzer"] = {
                     procMacro = { enable = true },
                     cargo = { allFeatures = true },
                     checkOnSave = {
                        command = "clippy",
                        extraArgs = { "--no-deps" },
                     },
                  },
               },
            },
            terraformls = {},
            -- clangd = {},
            -- gopls = {},
            -- pyright = {},
            -- ... etc. See `:help lspconfig-all` for a list of all the pre-configured LSPs
            --
            -- Some languages (like typescript) have entire language plugins that can be useful:
            --    https://github.com/pmizio/typescript-tools.nvim
            --
            -- But for many setups, the LSP (`ts_ls`) will work just fine
            -- ts_ls = {},
            --
            vtsls = require("vtsls").lspconfig,
            jsonls = {
               capabilities = { textDocument = { completion = { completionItem = { snippetSupport = true } } } },
               settings = {
                  json = {
                     schemas = require('schemastore').json.schemas(),
                     validate = { enable = true },
                  },
               },
            },
            yamlls = {
               settings = {
                  yaml = {
                     schemaStore = {
                        -- Ycu must disable built-in schemaStore support if you want to use
                        -- this plugin and its advanced options like `ignore`.
                        enable = false,
                        -- Avoid TypeError: Cannot read properties of undefined (reading 'length')
                        url = "",
                     },
                     schemas = require('schemastore').yaml.schemas(),
                  },
               },
            },
            sourcekit = {
               capabilities = {
                  workspace = {
                     didChangeWatchedFiles = {
                        dynamicRegistration = true,
                     },
                  },
               },
            },
            astro = {},
            elixirls = {
               flags = {
                  debounce_text_changes = 150,
               },
               cmd = { "/Users/shamash/.tools/elixir-ls/language_server.sh" },
               elixirLS = {
                  dialyzerEnabled = false,
                  fetchDeps = false,
               }
            },
            csharp_ls = {
               root_dir = util.root_pattern('*.sln', '*.csproj', "*.git"),
            },
            lua_ls = {
               -- cmd = { ... },
               -- filetypes = { ... },
               -- capabilities = {},
               settings = {
                  Lua = {
                     completion = {
                        callSnippet = 'Replace',
                     },
                     -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
                     -- diagnostics = { disable = { 'missing-fields' } },
                  },
               },
            },
            basedpyright = {
               settings = {
                  basedpyright = {
                     analysis = {
                        diagnosticMode = "openFilesOnly",
                        autoImportCompletions = true,
                     }
                  }
               }

            }
         }
         for server, config in pairs(servers) do
            -- passing config.capabilities to blink.cmp merges with the capabilities in your
            -- `opts[server].capabilities, if you've defined it
            config.capabilities = require('blink.cmp').get_lsp_capabilities(config.capabilities)
            lspconfig[server].setup(config)
         end
         -- Ensure the servers and tools above are installed
         --
         -- To check the current status of installed tools and/or manually install
         -- other tools, you can run
         --    :Mason
         --
         -- You can press `g?` for help in this menu.
         --
         -- `mason` had to be setup earlier: to configure its options see the
         -- `dependencies` table for `nvim-lspconfig` above.
         --
         -- You can add other tools here that you want Mason to install
         -- for you, so that they are available from within Neovim.
         -- local ensure_installed = vim.tbl_keys(servers or {})
         -- vim.list_extend(ensure_installed, {
         --   'stylua', -- Used to format Lua code
         -- })
         -- require('mason-tool-installer').setup { ensure_installed = ensure_installed }

         -- require('mason-lspconfig').setup {
         --   handlers = {
         --     function(server_name)
         --       local server = servers[server_name] or {}
         --       -- This handles overriding only values explicitly passed
         --       -- by the server configuration above. Useful when disabling
         --       -- certain features of an LSP (for example, turning off formatting for ts_ls)
         --       server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
         --       require('lspconfig')[server_name].setup(server)
         --     end,
         --   },
         -- }
      end,
   },
   {
      "stevearc/conform.nvim",
      event = { "BufWritePre" },
      cmd = { "ConformInfo" },
      keys = {
         {
            -- Customize or remove this keymap to your liking
            "<leader>cf",
            function()
               require("conform").format({ async = true, fallback = true })
            end,
            mode = "",
            desc = "Format buffer",
         },
      },
      -- This will provide type hinting with LuaLS
      ---@module "conform"
      ---@type conform.setupOpts
      opts = {
         -- Define your formatters
         formatters_by_ft = {
            lua = { "stylua" },
            python = { "isort", "ruff_format" },
            terraform = { "terraform_fmt" },
            ["terraform-vars"] = { "terraform_fmt" },
            javascript = { "prettierd", "prettier", stop_after_first = true },
            typescript = { "prettierd", "prettier", stop_after_first = true },
            typescriptreact = { "prettierd", "prettier", stop_after_first = true },
            go = { "goimports", "gofmt" },
            swift = { "swiftformat" },
            rust = { "rustfmt" },
            ["typescript.tsx"] = { "prettierd", "prettier", stop_after_first = true },
         },
         -- Set default options
         default_format_opts = {
            lsp_format = "fallback",
         },
         -- Set up format-on-save
         format_on_save = { timeout_ms = 500 },
         -- Customize formatters
         formatters = {
            shfmt = {
               prepend_args = { "-i", "2" },
            },
         },
      },
      init = function()
         -- If you want the formatexpr, here is the place to set it
         vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
      end,
   },
   {
      "mfussenegger/nvim-lint",
      event = { "BufReadPost", "BufNewFile", "BufWritePre" },
      opts = {
         events = { "BufWritePost", "BufReadPost", "InsertLeave" },
         linters_by_ft = {
            cmake = { "cmakelint" },
            javascript = { "eslint" },
            rust = { "clippy" },
            terraform = { "tflint" },
            dockerfile = { "hadolint" },
            ["javascript.jsx"] = { "eslint" },
            javascriptreact = { "eslint" },
            lua = { "luacheck" },
            -- rst = { "rstlint" },
            -- sh = { "shellcheck" },
            typescript = { "eslint" },
            ["typescript.tsx"] = { "eslint" },
            typescriptreact = { "eslint" },
            -- vim = { "vint" },
            yaml = { "yamllint" },
            swift = { "swiftlint" },

            dockerfile = { "hadolint" },
            go = { "golangcilint" },

         }
      },
      config = function(_, opts)
         vim.api.nvim_create_autocmd({ "BufWritePost" }, {
            callback = function()
               -- try_lint without arguments runs the linters defined in `linters_by_ft`
               -- for the current filetype
               require("lint").try_lint()
            end,
         })
      end,
      keys = {

         {
            "<leader>cl",
            function()
               require("lint").try_lint()
            end
            ,
            desc = "Toggle csv view"
         },
      }

   },
   {

      -- Make sure to set this up properly if you have lazy=true
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
         file_types = { "markdown", "Avante" },
      },
      ft = { "markdown" },
      config = true
   },
   {
      "folke/snacks.nvim",
      lazy = false,
      ---@type snacks.Config
      opts = {
         -- your configuration comes here
         -- or leave it empty to use the default settings
         -- refer to the configuration section below
         bigfile = { enabled = true },
         pickers = { enabled = true },
         dashboard = { enabled = false },
         indent = { enabled = true },
         input = { enabled = true },
         notifier = { enabled = false },
         quickfile = { enabled = true },
         scroll = { enabled = true },
         statuscolumn = { enabled = true },
         words = { enabled = true },
      },
      keys = {
      }
   },
   {
      "Goose97/timber.nvim",
      version = "*", -- Use for stability; omit to use `main` branch for the latest features
      event = "VeryLazy",
      config = function()
         require("timber").setup({
            -- Configuration here, or leave empty to use defaults
         })
      end
   },
   {
      'hat0uma/csvview.nvim',
      config = function()
         require('csvview').setup()
      end,
      keys = {

         { "<leader>ot", "<cmd>CsvViewToggle<CR>", desc = "Toggle csv view" },
      }
   },
   {
      'jmbuhr/otter.nvim',
      dependencies = {
         'nvim-treesitter/nvim-treesitter',
         { 'quarto-dev/quarto-nvim', opts = {} },
      },
      opts = {},
      keys = {

         {
            "<leader>oo",
            function()
               local ottr = require("otter")
               ottr.activate()
            end,
            desc = "Otter activate"
         },
      }
   },
   {
      "GCBallesteros/jupytext.nvim",
      config = function()
         require("jupytext").setup({
            custom_language_formatting = {
               python = {
                  extension = "qmd",
                  style = "quarto",
                  force_ft = "quarto", -- you can set whatever filetype you want here
               },
            }
         })
      end,
      -- Depending on your nvim distro or config you may need to make the loading not lazy
      -- lazy=false,
   },
   {
      "wojciech-kulik/xcodebuild.nvim",
      dependencies = {
         "nvim-telescope/telescope.nvim",
         "MunifTanjim/nui.nvim",
         -- "nvim-tree/nvim-tree.lua", -- (optional) to manage project files
         -- "stevearc/oil.nvim", -- (optional) to manage project files
         -- "nvim-treesitter/nvim-treesitter", -- (optional) for Quick tests support (required Swift parser)
      },
      config = function()
         require("xcodebuild").setup({
            -- put some options here or leave it empty to use default settings
         })
      end,
      keys = {

         { "<leader>cbx", "<cmd>XcodebuildPicker<CR>", desc = "Xcodeild" },
      }


   },
   {
      'kristijanhusak/vim-dadbod-ui',
      dependencies = {
         { 'tpope/vim-dadbod',                     lazy = true },
         { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true }, -- Optional
      },
      cmd = {
         'DBUI',
         'DBUIToggle',
         'DBUIAddConnection',
         'DBUIFindBuffer',
      },
      init = function()
         -- Your DBUI configuration
         vim.g.db_ui_use_nerd_fonts = 1
      end,
      keys = {
         { "<leader>odu", "<cmd>DBUIToggle<CR>", desc = "DBUI" },
      }
   },
   'milch/vim-fastlane',

   {
      "ravitemer/mcphub.nvim",
      dependencies = {
         "nvim-lua/plenary.nvim", -- Required for Job and HTTP requests
      },
      -- cmd = "MCPHub", -- lazily start the hub when `MCPHub` is called
      build = "npm install -g mcp-hub@latest", -- Installs required mcp-hub npm module
      config = function()
         require("mcphub").setup({
            -- Required options
            port = 3000,                                 -- Port for MCP Hub server
            config = vim.fn.expand("~/mcpservers.json"), -- Absolute path to config file

            -- Optional options
            on_ready = function(hub)
               -- Called when hub is ready
            end,
            on_error = function(err)
               -- Called on errors
            end,
            shutdown_delay = 0, -- Wait 0ms before shutting down server after last client exits
            auto_approve = false,
            log = {
               level = vim.log.levels.WARN,
               to_file = false,
               file_path = nil,
               prefix = "MCPHub"
            },
         })
      end
   },
   {
      "yetone/avante.nvim",
      event = "VeryLazy",
      lazy = false,
      version = false,
      opts = {
         -- provider = "claude",
         -- provider = "ollama",

         behaviour = {
            --- ... existing behaviours
            enable_cursor_planning_mode = true, -- enable cursor planning mode!
            enable_claude_text_editor_tool_mode = true,
         },

         provider = 'lmstudio',
         vendors = {
            ---@type AvanteProvider
            lmstudio = {
               __inherited_from = 'openai',
               api_key_name = '',
               endpoint = 'http://127.0.0.1:1234/v1',
               -- model = 'gemma-3-12b-it',
               -- model = "qwq-32b",
               -- model = "qwq-deepseek-r1-skyt1-flash-lightest-32b-mlx"
               -- model = "qwen2.5-coder-32b-instruct-mlx"
               -- model = "fuseo1-deepseekr1-qwen2.5-instruct-32b-preview"
               -- model = "deepcoder-14b-preview"
               -- model = "deepcogito-cogito-v1-preview-qwen-32b"
               model = "qwen3-32b-mlxqwen3-32b-mlx"

               -- model =  "deepseek-r1-distill-qwen-14b",
            },
         },

         ollama = {
            __inherited_from = "openai",
            -- model = "deepseek-r1:14b",
            model = "gemma-3-27b-it",
            disable_tools = false
         },
         rag_service = {
            enabled = false,                        -- Enables the RAG service
            host_mount = os.getenv("HOME"),         -- Host mount path for the rag service
            provider = "openai",                    -- The provider to use for RAG service (e.g. openai or ollama)
            llm_model = "",                         -- The LLM model to use for RAG service
            embed_model = "",                       -- The embedding model to use for RAG service
            endpoint = "http://localhost:11434/v1", -- The API endpoint for RAG service
         },
         system_prompt = function()
            local hub = require("mcphub").get_hub_instance()
            return hub:get_active_servers_prompt()
         end,
         custom_tools = function()
            return {
               require("mcphub.extensions.avante").mcp_tool(),
            }
         end,
      },
      -- add any opts here
      -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
      build = "make",
      -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
      dependencies = {
         "stevearc/dressing.nvim",
         "nvim-lua/plenary.nvim",
         "MunifTanjim/nui.nvim",
         --- The below dependencies are optional,
         "echasnovski/mini.pick", -- for file_selector provider mini.pick
         -- "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
         -- "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
         -- "ibhagwan/fzf-lua", -- for file_selector provider fzf
         "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
         -- "zbirenbaum/copilot.lua", -- for providers='copilot'
         {
            -- support for image pasting
            "HakonHarnes/img-clip.nvim",
            event = "VeryLazy",
            opts = {
               -- recommended settings
               default = {
                  embed_image_as_base64 = false,
                  prompt_for_file_name = false,
                  drag_and_drop = {
                     insert_mode = true,
                  },
                  -- required for Windows users
                  use_absolute_path = true,
               },
            },
         },
         {
            -- Make sure to set this up properly if you have lazy=true
            'MeanderingProgrammer/render-markdown.nvim',
            opts = {
               file_types = { "markdown", "Avante" },
            },
            ft = { "markdown", "Avante" },
         },
      },
   },
   {
      'mistweaverco/kulala.nvim',
      opts = {},
      keys = {
         {
            "<leader>okr",
            function()
               require('kulala').run()
            end,
            desc = "Kulala"
         },
      },
   },


   {
      "olimorris/codecompanion.nvim",
      keys = {
         {
            "<leader>oc",
            "<cmd>CodeCompanionChat Toggle<CR>",
            desc = "CodeCompanion",
         },
         {
            "<leader>oa",
            "<cmd>CodeCompanionActions<CR>",
            desc = "CodeCompanion",
         }

      },
      config = true,
      opts = {
         display = {
            inline = {
               layout = "vertical", -- vertical|horizontal|buffer
            },
         },
         extensions = {
            mcphub = {
               callback = "mcphub.extensions.codecompanion",
               opts = {
                  show_result_in_chat = true, -- Show the mcp tool result in the chat buffer
                  make_vars = true,           -- make chat #variables from MCP server resources
                  make_slash_commands = true, -- make /slash_commands from MCP server prompts
               },
            }
         },
         strategies = {
            chat = {
               adapter = "lm_studio",
            },
            inline = {
               adapter = "lm_studio",
               keymaps = {
                  accept_change = {
                     modes = { n = "ga" },
                     description = "Accept the suggested change",
                  },
                  reject_change = {
                     modes = { n = "gr" },
                     description = "Reject the suggested change",
                  },
               },
            },
         },
         adapters = {
            lm_studio = function()
               return require("codecompanion.adapters").extend("openai_compatible", {
                  env = {
                     url = "http://127.0.0.1:1234",     -- optional: default value is ollama url http://127.0.0.1:11434
                     -- api_key = "dummy_api_key", -- optional: if your endpoint is authenticated
                     chat_url = "/v1/chat/completions", -- optional: default value, override if different
                     models_endpoint = "/v1/models",    -- optional: attaches to the end of the URL to form the endpoint to retrieve models
                  },
                  schema = {
                     model = {
                        -- default = "deepseek-r1-distill-qwen-14b",  -- define llm model to be used
                        -- default = "gemma-3-12b-it",  -- define llm model to be used
                        -- default = "qwq-deepseek-r1-skyt1-flash-lightest-32b-mlx"
                        -- default = "qwen2.5-coder-32b-instruct-mlx"
                        -- default = "fuseo1-deepseekr1-qwen2.5-instruct-32b-preview"
                        -- default = "deepcogito-cogito-v1-preview-qwen-32b"
                        default = "qwen3-32b-mlxqwen3-32b-mlx"
                     },
                     temperature = {
                        order = 2,
                        mapping = "parameters",
                        type = "number",
                        optional = true,
                        default = 0.8,
                        desc =
                        "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
                        validate = function(n)
                           return n >= 0 and n <= 2, "Must be between 0 and 2"
                        end,
                     },
                     max_completion_tokens = {
                        order = 3,
                        mapping = "parameters",
                        type = "integer",
                        optional = true,
                        default = nil,
                        desc = "An upper bound for the number of tokens that can be generated for a completion.",
                        validate = function(n)
                           return n > 0, "Must be greater than 0"
                        end,
                     },
                     stop = {
                        order = 4,
                        mapping = "parameters",
                        type = "string",
                        optional = true,
                        default = nil,
                        desc =
                        "Sets the stop sequences to use. When this pattern is encountered the LLM will stop generating text and return. Multiple stop patterns may be set by specifying multiple separate stop parameters in a modelfile.",
                        validate = function(s)
                           return s:len() > 0, "Cannot be an empty string"
                        end,
                     },
                     logit_bias = {
                        order = 5,
                        mapping = "parameters",
                        type = "map",
                        optional = true,
                        default = nil,
                        desc =
                        "Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID) to an associated bias value from -100 to 100. Use https://platform.openai.com/tokenizer to find token IDs.",
                        subtype_key = {
                           type = "integer",
                        },
                        subtype = {
                           type = "integer",
                           validate = function(n)
                              return n >= -100 and n <= 100, "Must be between -100 and 100"
                           end,
                        },
                     },
                  },
               })
            end,
         },
      },
      dependencies = {
         "nvim-lua/plenary.nvim",
         "nvim-treesitter/nvim-treesitter",
      },
   },

{
  "azorng/goose.nvim",
  config = function()
    require("goose").setup({
 default_global_keymaps = false,      
keymap = {
    global = {
      toggle = '<leader>ogg',                 -- Open goose. Close if opened 
      open_input = '<leader>ogi',             -- Opens and focuses on input window on insert mode
      open_input_new_session = '<leader>ogI', -- Opens and focuses on input window on insert mode. Creates a new session
      open_output = '<leader>ogo',            -- Opens and focuses on output window 
      toggle_focus = '<leader>ogt',           -- Toggle focus between goose and last window
      close = '<leader>ogq',                  -- Close UI windows
      toggle_fullscreen = '<leader>ogf',      -- Toggle between normal and fullscreen mode
      select_session = '<leader>ogs',         -- Select and load a goose session
      goose_mode_chat = '<leader>ogmc',       -- Set goose mode to `chat`. (Tool calling disabled. No editor context besides selections)
      goose_mode_auto = '<leader>ogma',       -- Set goose mode to `auto`. (Default mode with full agent capabilities)
      configure_provider = '<leader>ogp',     -- Quick provider and model switch from predefined list
      diff_open = '<leader>ogd',              -- Opens a diff tab of a modified file since the last goose prompt
      diff_next = '<leader>og]',              -- Navigate to next file diff
      diff_prev = '<leader>og[',              -- Navigate to previous file diff
      diff_close = '<leader>ogc',             -- Close diff view tab and return to normal editing
      diff_revert_all = '<leader>ogra',       -- Revert all file changes since the last goose prompt
      diff_revert_this = '<leader>ogrt',      -- Revert current file changes since the last goose prompt
    },
         }

         })
  end,
  dependencies = {
    "nvim-lua/plenary.nvim",
    {
      "MeanderingProgrammer/render-markdown.nvim",
      opts = {
        anti_conceal = { enabled = false },
      },
    }
  },
}
}
