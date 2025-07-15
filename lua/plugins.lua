return {
  -- Which-key for keybinding help (Helix-style)
  {
    "folke/which-key.nvim",
    keys = { "<leader>", "[", "]", "g" },
    opts = {
      preset = "helix",
      delay = 200,
      expand = 1,
      notify = false,
      replace = {
        ["<space>"] = "SPC",
        ["<cr>"] = "RET",
        ["<tab>"] = "TAB",
      },
      spec = {
        { "<leader>f",  group = "find" },
        { "<leader>p",  group = "project" },
        { "<leader>s",  group = "search" },
        { "<leader>g",  group = "git" },
        { "<leader>d",  group = "debug" },
        { "<leader>c",  group = "code" },
        { "<leader>cr", group = "refactor" },
        { "<leader>w",  group = "window" },
        { "<leader>b",  group = "buffer" },
        { "<leader>bw", group = "window/tab" },
        { "<leader>t",  group = "toggle" },
        { "<leader>v",  group = "view" },
        { "<leader>o",  group = "open" },
        { "<leader>q",  group = "quit" },
        { "<leader>h",  group = "help" },
        { "<leader>r",  group = "run" },
        { "<leader>a",  group = "ai" },
      },
    },
  },

  -- Enhanced unimpaired functionality
  {
    "echasnovski/mini.bracketed",
    version = false,
    keys = { "[", "]" },
    config = function()
      require("mini.bracketed").setup({
        -- First-level elements are tables describing behavior of a target:
        --
        -- Keys of these tables are single characters used in mappings.
        -- Values are tables with the following structure:
        -- - <suffix> (string) - single character used in suffix of mappings.
        -- - <options> (table) - options for mappings.
        -- - <forward> (function) - function for forward movement.
        -- - <backward> (function) - function for backward movement.

        buffer = { suffix = 'b', options = {} },
        comment = { suffix = 'c', options = {} },
        conflict = { suffix = 'x', options = {} },
        diagnostic = { suffix = 'd', options = {} },
        file = { suffix = 'f', options = {} },
        indent = { suffix = 'i', options = {} },
        jump = { suffix = 'j', options = {} },
        location = { suffix = 'l', options = {} },
        oldfile = { suffix = 'o', options = {} },
        quickfix = { suffix = 'q', options = {} },
        treesitter = { suffix = 't', options = {} },
        undo = { suffix = 'u', options = {} },
        window = { suffix = 'w', options = {} },
        yank = { suffix = 'y', options = {} },
      })

      -- Add custom unimpaired-style mappings
      local keymap = vim.keymap.set

      -- Line manipulation
      keymap("n", "]<Space>", "o<Esc>", { desc = "Add blank line below" })
      keymap("n", "[<Space>", "O<Esc>", { desc = "Add blank line above" })
      keymap("n", "]e", ":move .+1<CR>==", { desc = "Move line down" })
      keymap("n", "[e", ":move .-2<CR>==", { desc = "Move line up" })
      keymap("v", "]e", ":move '>+1<CR>gv=gv", { desc = "Move selection down" })
      keymap("v", "[e", ":move '<-2<CR>gv=gv", { desc = "Move selection up" })

      -- Duplicate lines
      keymap("n", "]d", "yyp", { desc = "Duplicate line down" })
      keymap("n", "[d", "yyP", { desc = "Duplicate line up" })
      keymap("v", "]d", "y`>p", { desc = "Duplicate selection down" })
      keymap("v", "[d", "y`<P", { desc = "Duplicate selection up" })

      -- Option toggles
      keymap("n", "]on", function() vim.opt.number = true end, { desc = "Enable line numbers" })
      keymap("n", "[on", function() vim.opt.number = false end, { desc = "Disable line numbers" })
      keymap("n", "]or", function() vim.opt.relativenumber = true end, { desc = "Enable relative numbers" })
      keymap("n", "[or", function() vim.opt.relativenumber = false end, { desc = "Disable relative numbers" })
      keymap("n", "]ow", function() vim.opt.wrap = true end, { desc = "Enable word wrap" })
      keymap("n", "[ow", function() vim.opt.wrap = false end, { desc = "Disable word wrap" })
      keymap("n", "]os", function() vim.opt.spell = true end, { desc = "Enable spell check" })
      keymap("n", "[os", function() vim.opt.spell = false end, { desc = "Disable spell check" })
      keymap("n", "]oh", function() vim.opt.hlsearch = true end, { desc = "Enable search highlight" })
      keymap("n", "[oh", function() vim.opt.hlsearch = false end, { desc = "Disable search highlight" })
      keymap("n", "]oc", function() vim.opt.cursorline = true end, { desc = "Enable cursor line" })
      keymap("n", "[oc", function() vim.opt.cursorline = false end, { desc = "Disable cursor line" })

      -- Paste settings
      keymap("n", "]op", function() vim.opt.paste = true end, { desc = "Enable paste mode" })
      keymap("n", "[op", function() vim.opt.paste = false end, { desc = "Disable paste mode" })

      -- Folding
      keymap("n", "]z", "zj", { desc = "Next fold" })
      keymap("n", "[z", "zk", { desc = "Previous fold" })
    end,
  },

  -- Modern surround plugin
  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup({})
    end,
  },

  -- Enhanced text objects (Helix-style)
  {
    "echasnovski/mini.ai",
    version = false,
    keys = {
      { "a", mode = { "x", "o" } },
      { "i", mode = { "x", "o" } },
    },
    config = function()
      require("mini.ai").setup({
        custom_textobjects = {
          -- Entire buffer
          e = function()
            local from = { line = 1, col = 1 }
            local to = {
              line = vim.fn.line('$'),
              col = math.max(vim.fn.getline('$'):len(), 1)
            }
            return { from = from, to = to }
          end,
          -- Function call
          F = function()
            return require("mini.ai").gen_spec.treesitter({ a = "@call.outer", i = "@call.inner" })
          end,
          -- Arguments
          A = function()
            return require("mini.ai").gen_spec.treesitter({ a = "@parameter.outer", i = "@parameter.inner" })
          end,
          -- Conditional
          C = function()
            return require("mini.ai").gen_spec.treesitter({ a = "@conditional.outer", i = "@conditional.inner" })
          end,
          -- Loop
          L = function()
            return require("mini.ai").gen_spec.treesitter({ a = "@loop.outer", i = "@loop.inner" })
          end,
        },
      })
    end,
  },

  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      require("nvim-treesitter.configs").setup({
        auto_install = true,
        highlight = { enable = true },
        indent = { enable = true },
        fold = { enable = true },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              -- Functions
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              -- Classes
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              -- Blocks
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",
              -- Loops
              ["al"] = "@loop.outer",
              ["il"] = "@loop.inner",
              -- Parameters/Arguments
              ["aa"] = "@parameter.outer",
              ["ia"] = "@parameter.inner",
              -- Conditionals
              ["ai"] = "@conditional.outer",
              ["ii"] = "@conditional.inner",
              -- Calls
              ["aF"] = "@call.outer",
              ["iF"] = "@call.inner",
              -- Comments
              ["aC"] = "@comment.outer",
              ["iC"] = "@comment.inner",
              -- Assignments
              ["a="] = "@assignment.outer",
              ["i="] = "@assignment.inner",
              -- Returns
              ["ar"] = "@return.outer",
              ["ir"] = "@return.inner",
              -- Statements
              ["as"] = "@statement.outer",
              ["is"] = "@statement.inner",
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
              ["]a"] = "@parameter.outer",
              ["]r"] = "@return.outer",
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
              ["]B"] = "@block.outer",
              ["]L"] = "@loop.outer",
              ["]I"] = "@conditional.outer",
              ["]A"] = "@parameter.outer",
              ["]R"] = "@return.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[b"] = "@block.outer",
              ["[l"] = "@loop.outer",
              ["[i"] = "@conditional.outer",
              ["[a"] = "@parameter.outer",
              ["[r"] = "@return.outer",
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
              ["[B"] = "@block.outer",
              ["[L"] = "@loop.outer",
              ["[I"] = "@conditional.outer",
              ["[A"] = "@parameter.outer",
              ["[R"] = "@return.outer",
            },
          },
          swap = {
            enable = true,
            swap_next = {
              ["]a"] = "@parameter.inner",
              ["]f"] = "@function.outer",
            },
            swap_previous = {
              ["[a"] = "@parameter.inner",
              ["[f"] = "@function.outer",
            },
          },
          lsp_interop = {
            enable = true,
            border = "none",
            peek_definition_code = {
              ["<leader>vf"] = "@function.outer",
              ["<leader>vF"] = "@class.outer",
            },
          },
        },
      })

      -- Set up treesitter folding
      vim.opt.foldmethod = "expr"
      vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
      vim.opt.foldenable = false
    end,
  },

  -- Leap motion
  {
    "ggandor/leap.nvim",
    keys = {
      { "s",  mode = { "n", "x", "o" }, desc = "Leap forward to" },
      { "S",  mode = { "n", "x", "o" }, desc = "Leap backward to" },
      { "gs", mode = { "n", "x", "o" }, desc = "Leap from windows" },
    },
    config = function(_, opts)
      local leap = require("leap")
      for k, v in pairs(opts) do
        leap.opts[k] = v
      end
      leap.add_default_mappings(true)
      vim.keymap.del({ "x", "o" }, "x")
      vim.keymap.del({ "x", "o" }, "X")
    end,
  },


  -- Multi-cursors
  {
    "mg979/vim-visual-multi",
    keys = {
      { "<C-n>", mode = { "n", "v" } },
      { "<C-Up>", mode = { "n", "v" } },
      { "<C-Down>", mode = { "n", "v" } },
    },
  },

  -- Supermaven AI completion
  {
    "supermaven-inc/supermaven-nvim",
    event = "InsertEnter",
    cond = function()
      return vim.fn.getfsize(vim.fn.expand("%")) < 100000 -- Disable for files > 100KB
    end,
    config = function()
      require("supermaven-nvim").setup({
        keymaps = {
          accept_suggestion = "<Tab>",
          clear_suggestion = "<C-]>",
          accept_word = "<C-j>",
        },
        ignore_filetypes = {
          cpp = true,
        },
        color = {
          suggestion_color = "#ffffff",
          cterm = 244,
        },
        log_level = "info",
        disable_inline_completion = false,
        disable_keymaps = false,
      })
    end,
  },

  -- LuaSnip for snippets
  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
    build = "make install_jsregexp",
    event = "InsertEnter",
    opts = {
      history = false,
      update_events = "TextChanged,TextChangedI",
    },
    dependencies = {
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local luasnip = require("luasnip")

      -- Load snippets
      require("luasnip.loaders.from_vscode").lazy_load()

      -- Keymaps
      vim.keymap.set({ "i", "s" }, "<C-k>", function()
        if luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        end
      end, { desc = "Expand or jump snippet" })

      vim.keymap.set({ "i", "s" }, "<C-j>", function()
        if luasnip.jumpable(-1) then
          luasnip.jump(-1)
        end
      end, { desc = "Jump back in snippet" })

      vim.keymap.set({ "i", "s" }, "<C-l>", function()
        if luasnip.choice_active() then
          luasnip.change_choice(1)
        end
      end, { desc = "Select choice in snippet" })
    end,
  },

  -- Enhanced LSP rename with live preview
  {
    "smjonas/inc-rename.nvim",
    cmd = "IncRename",
    config = function()
      require("inc_rename").setup({
        preview_empty_name = false,
      })
    end,
  },

  -- Formatting
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    ft = { "lua", "python", "javascript", "typescript", "typescriptreact", "javascriptreact", "json", "html", "css", "markdown", "dart" },
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true }) end, desc = "Format" },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        javascriptreact = { "prettier" },
        json = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        markdown = { "prettier" },
        dart = { "dart_format" },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_fallback = true,
      },
    },
  },

  -- Linting
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile" },
    ft = { "python", "javascript", "typescript", "typescriptreact", "javascriptreact", "dart" },
    config = function()
      local lint = require("lint")

      -- Custom Dart linter using dart analyze command
      lint.linters.dart_analyze = {
        cmd = "dart",
        stdin = false,
        args = { "analyze", "--fatal-infos", "--fatal-warnings", "." },
        stream = "stderr",
        ignore_exitcode = true,
        parser = function(output, bufnr)
          local diagnostics = {}

          -- Parse dart analyze output format
          for line in output:gmatch("[^\r\n]+") do
            -- Try to match different dart analyze output formats
            -- Format: "severity • message • file:line:col • rule_name"
            local severity, message, location, rule = line:match("^%s*(%w+)%s*•%s*(.-)%s*•%s*(.-)%s*•%s*(.-)%s*$")

            if severity and message and location then
              local line_str, col_str = location:match(":(%d+):(%d+)")

              if line_str and col_str then
                local line_num = tonumber(line_str) - 1 -- Convert to 0-based indexing
                local col_num = tonumber(col_str) - 1

                -- Map severity levels
                local diagnostic_severity = vim.diagnostic.severity.INFO
                if severity == "error" then
                  diagnostic_severity = vim.diagnostic.severity.ERROR
                elseif severity == "warning" then
                  diagnostic_severity = vim.diagnostic.severity.WARN
                elseif severity == "info" then
                  diagnostic_severity = vim.diagnostic.severity.INFO
                end

                table.insert(diagnostics, {
                  lnum = line_num,
                  col = col_num,
                  message = message,
                  severity = diagnostic_severity,
                  source = "dart_analyze",
                  code = rule or "dart_analyze",
                })
              end
            end
          end

          return diagnostics
        end,
      }

      lint.linters_by_ft = {
        python = { "ruff" },
        javascript = { "eslint" },
        typescript = { "eslint" },
        typescriptreact = { "eslint" },
        javascriptreact = { "eslint" },
        dart = { "dart_analyze" },
      }

      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },

  -- Diagflow for Helix-style diagnostic display
  {
    "dgagn/diagflow.nvim",
    event = "LspAttach",
    ft = { "lua", "typescript", "javascript", "python", "dart", "rust", "go" },
    opts = {
      placement = "top",
      scope = "cursor",
      severity_colors = {
        error = "DiagnosticError",
        warning = "DiagnosticWarn",
        info = "DiagnosticInfo",
        hint = "DiagnosticHint",
      },
      format = function(diagnostic)
        return "[" .. diagnostic.source .. "] " .. diagnostic.message
      end,
    },
  },

  -- Oil.nvim file explorer
  {
    "stevearc/oil.nvim",
    lazy = true,
    cmd = "Oil",
    opts = {
      default_file_explorer = true,
      columns = {
        "icon",
        "permissions",
        "size",
        "mtime",
      },
      buf_options = {
        buflisted = false,
        bufhidden = "hide",
      },
      win_options = {
        wrap = false,
        signcolumn = "no",
        cursorcolumn = false,
        foldcolumn = "0",
        spell = false,
        list = false,
        conceallevel = 3,
        concealcursor = "nvic",
      },
      delete_to_trash = true,
      skip_confirm_for_simple_edits = false,
      prompt_save_on_select_new_entry = true,
      cleanup_delay_ms = 2000,
      lsp_file_methods = {
        timeout_ms = 1000,
        autosave_changes = false,
      },
      constrain_cursor = "editable",
      experimental_watch_for_changes = false,
      keymaps = {
        ["g?"] = "actions.show_help",
        ["<CR>"] = "actions.select",
        ["<C-s>"] = "actions.select_vsplit",
        ["<C-h>"] = "actions.select_split",
        ["<C-t>"] = "actions.select_tab",
        ["<C-p>"] = "actions.preview",
        ["<C-c>"] = "actions.close",
        ["<C-l>"] = "actions.refresh",
        ["-"] = "actions.parent",
        ["_"] = "actions.open_cwd",
        ["`"] = "actions.cd",
        ["~"] = "actions.tcd",
        ["gs"] = "actions.change_sort",
        ["gx"] = "actions.open_external",
        ["g."] = "actions.toggle_hidden",
        ["g\\"] = "actions.toggle_trash",
      },
      use_default_keymaps = true,
      view_options = {
        show_hidden = false,
        is_hidden_file = function(name, bufnr)
          return vim.startswith(name, ".")
        end,
        is_always_hidden = function(name, bufnr)
          return false
        end,
        sort = {
          { "type", "asc" },
          { "name", "asc" },
        },
      },
    },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>-", "<cmd>Oil<cr>", desc = "Open Oil" },
    },
  },

  -- Snacks.nvim with VSCode theme and enhanced pickers
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = true,
    event = "VeryLazy",
    opts = {
      picker = {
        enabled = true,
        layout = {
          preset = "vscode",
        },
      },
      terminal = { enabled = true },
    },
    keys = {
      -- Find operations
      { "<leader>ff",  function() require("snacks").picker.files() end,          desc = "Find Files" },
      { "<leader>fr",  function() require("snacks").picker.recent() end,         desc = "Recent Files" },
      { "<leader>fg",  function() require("snacks").picker.grep() end,           desc = "Grep Files" },
      { "<leader>fb",  function() require("snacks").picker.buffers() end,        desc = "Find Buffers" },
      { "<leader>fh",  function() require("snacks").picker.help() end,           desc = "Find Help" },
      { "<leader>fk",  function() require("snacks").picker.keymaps() end,        desc = "Find Keymaps" },
      { "<leader>fc",  function() require("snacks").picker.commands() end,       desc = "Find Commands" },

      -- Project operations
      { "<leader>pf",  function() require("snacks").picker.files() end,          desc = "Find Files in Project" },
      { "<leader>pr",  function() require("snacks").picker.recent() end,         desc = "Recent Files in Project" },
      { "<leader>pg",  function() require("snacks").picker.grep() end,           desc = "Grep in Project" },
      { "<leader>ps",  function() require("snacks").picker.lsp_symbols() end,    desc = "Project Symbols" },

      -- Search operations
      { "<leader>ss",  function() require("snacks").picker.grep_word() end,      desc = "Search Word" },
      { "<leader>sg",  function() require("snacks").picker.grep() end,           desc = "Grep Search" },
      { "<leader>sl",  function() require("snacks").picker.lines() end,          desc = "Search Lines" },
      { "<leader>sr",  function() require("snacks").picker.lsp_references() end, desc = "Search References" },
      { "<leader>si",  function() require("snacks").picker.lsp_symbols() end,    desc = "Search Symbols" },

      -- Buffer operations
      { "<leader>bb",  function() require("snacks").picker.buffers() end,        desc = "Buffer List" },
      { "<leader>bd",  "<cmd>bdelete<cr>",                                       desc = "Delete Buffer" },
      { "<leader>bwn", "<cmd>tabnew<cr>",                                        desc = "New Tab" },
      { "<leader>bwc", "<cmd>tabclose<cr>",                                      desc = "Close Tab" },
      { "<leader>bwo", "<cmd>tabonly<cr>",                                       desc = "Close Other Tabs" },
      { "<leader>bwh", "<cmd>tabprevious<cr>",                                   desc = "Previous Tab" },
      { "<leader>bwl", "<cmd>tabnext<cr>",                                       desc = "Next Tab" },

      -- Window operations (Doom Emacs style)
      { "<leader>ww",  "<C-w>w",                                                 desc = "Switch Window" },
      { "<leader>wd",  "<C-w>c",                                                 desc = "Delete Window" },
      { "<leader>w-",  "<C-w>s",                                                 desc = "Split Below" },
      { "<leader>w|",  "<C-w>v",                                                 desc = "Split Right" },
      { "<leader>wh",  "<C-w>h",                                                 desc = "Window Left" },
      { "<leader>wj",  "<C-w>j",                                                 desc = "Window Down" },
      { "<leader>wk",  "<C-w>k",                                                 desc = "Window Up" },
      { "<leader>wl",  "<C-w>l",                                                 desc = "Window Right" },
      { "<leader>w=",  "<C-w>=",                                                 desc = "Balance Windows" },
      { "<leader>w_",  "<C-w>_",                                                 desc = "Maximize Height" },

      -- Help operations
      { "<leader>hh",  function() require("snacks").picker.help() end,           desc = "Help Tags" },
      { "<leader>hm",  function() require("snacks").picker.man() end,            desc = "Man Pages" },
      { "<leader>hk",  function() require("snacks").picker.keymaps() end,        desc = "Keymaps" },

      -- Terminal operations
      { "<leader>tt",  function() require("snacks").terminal.toggle() end,       desc = "Toggle Terminal" },
      {
        "<leader>tc",
        function()
          local cmd = vim.fn.input("Command: ")
          if cmd ~= "" then
            vim.g.last_terminal_command = cmd
            require("snacks").terminal.open(cmd, { win = { position = "right" } })
          end
        end,
        desc = "Run Custom Command"
      },
      {
        "<leader>tr",
        function()
          if vim.g.last_terminal_command then
            require("snacks").terminal.open(vim.g.last_terminal_command)
          else
            vim.notify("No previous command to restart", vim.log.levels.WARN)
          end
        end,
        desc = "Restart Last Command"
      },
      { "<leader>gg", function() require("snacks").terminal.open("lazygit", { win = { position = "right" } }) end, desc = "Lazygit" },
    },
  },

  -- Simple monotone theme (white on black)
  {
    "theme",
    dir = vim.fn.stdpath("config") .. "/lua",
    priority = 1000,
    lazy = false,
    config = function()
      require("theme").setup()
    end,
  },
  -- Avante.nvim AI assistant
  {
    "yetone/avante.nvim",
    lazy = true,
    cmd = {"AvanteAsk", "AvanteChat", "AvanteEdit", "AvanteRefresh"},
    version = false,
    opts = {
      provider = "lm_studio",
      providers = {
        lm_studio = {
          __inherited_from = "openai",
          endpoint = "http://localhost:1234/v1",
          model = "devstral-small-2507_gguf",
          -- model = "nextcoder-32b-mlx",
          api_key_name = "",
          timeout = 30000,
          context_window = 16000,
          extra_request_body = {
            temperature = 0,
            max_tokens = 4096,
          },
        },
      },
      behaviour = {
        auto_suggestions = false,
        auto_set_highlight_group = true,
        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = false,
      },
      mappings = {
        ask = "<leader>aa",
        edit = "<leader>ae",
        refresh = "<leader>ar",
        diff = {
          ours = "co",
          theirs = "ct",
          none = "c0",
          both = "cb",
          next = "]x",
          prev = "[x",
        },
        jump = {
          next = "]]",
          prev = "[[",
        },
        submit = {
          normal = "<CR>",
          insert = "<C-s>",
        },
        sidebar = {
          switch_windows = "<Tab>",
          reverse_switch_windows = "<S-Tab>",
        },
      },
      hints = { enabled = true },
      windows = {
        wrap = true,
        width = 30,
        sidebar_header = {
          align = "center",
          rounded = true,
        },
      },
      highlights = {
        diff = {
          current = "DiffText",
          incoming = "DiffAdd",
        },
      },
    },
    build = "make",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
      "zbirenbaum/copilot.lua",
      {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            use_absolute_path = true,
          },
        },
      },
      {
        "MeanderingProgrammer/render-markdown.nvim",
        lazy = true,
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },

  -- CodeCompanion.nvim AI chat
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "folke/snacks.nvim",
    },
    config = function()
      require("codecompanion").setup({
        strategies = {
          chat = {
            adapter = "lm_studio",
          },
          inline = {
            adapter = "lm_studio",
          },
          agent = {
            adapter = "lm_studio",
          },
        },
        adapters = {
          lm_studio = function()
            return require("codecompanion.adapters").extend("openai", {
              env = {
                api_key = "lm-studio",
              },
              url = "http://localhost:1234/v1/chat/completions",
              model = "devstral-small-2507_gguf",
            })
          end,
        },
        opts = {
          log_level = "ERROR",
        },
      })
    end,
    keys = {
      { "<leader>ac", "<cmd>CodeCompanionChat<cr>",        desc = "CodeCompanion Chat" },
      { "<leader>ai", "<cmd>CodeCompanionActions<cr>",     desc = "CodeCompanion Actions" },
      { "<leader>at", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle CodeCompanion Chat" },
      { "<leader>ap", "<cmd>CodeCompanionActions<cr>",     mode = "v",                        desc = "CodeCompanion Actions" },
    },
  },

  -- Mini.hipatterns for highlighting patterns
  {
    "echasnovski/mini.hipatterns",
    version = false,
    event = "BufReadPost",
    ft = { "lua", "typescript", "javascript", "python", "dart", "rust", "go" },
    config = function()
      require("mini.hipatterns").setup({
        highlighters = {
          -- Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
          fixme = { pattern = '%f[%w]()FIXME()%f[%W]', group = 'MiniHipatternsFixme' },
          hack  = { pattern = '%f[%w]()HACK()%f[%W]',  group = 'MiniHipatternsHack' },
          todo  = { pattern = '%f[%w]()TODO()%f[%W]',  group = 'MiniHipatternsTodo' },
          note  = { pattern = '%f[%w]()NOTE()%f[%W]',  group = 'MiniHipatternsNote' },

          -- Highlight hex color in '#rrggbb' format
          hex_color = require('mini.hipatterns').gen_highlighter.hex_color(),
        },
      })
    end,
  },

  -- Vim repeat for better dot command support
  {
    "tpope/vim-repeat",
    event = "VeryLazy",
  },

  -- Neorg for note-taking and task management
  {
    "nvim-neorg/neorg",
    dependencies = { "nvim-lua/plenary.nvim" },
    ft = "norg",
    cmd = "Neorg",
    lazy = true,
    config = function()
      require("neorg").setup {
        load = {
          ["core.defaults"] = {},
          ["core.concealer"] = {
            config = {
              icon_preset = "basic"
            }
          },
          ["core.dirman"] = {
            config = {
              workspaces = {
                notes = "~/notes",
                work = "~/work",
              },
              default_workspace = "notes",
            },
          },
          ["core.qol.todo_items"] = {
            config = {
              order = { "undone", "pending", "done", "cancelled" }
            }
          },
          ["core.keybinds"] = {
            config = {
              default_keybinds = true,
              neorg_leader = "<LocalLeader>",
            }
          },
        },
      }
      
      -- Set up the t mapping after neorg loads
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "norg",
        callback = function()
          vim.keymap.set("n", "t", "<Plug>(neorg.qol.todo-items.todo.task-cycle)", { buffer = true, desc = "Toggle Todo" })
        end,
      })
    end,
    keys = {
      { "<leader>otn", "<cmd>Neorg workspace notes<cr>", desc = "Open Notes" },
      { "<leader>otw", "<cmd>Neorg workspace work<cr>", desc = "Open Work" },
      { "<leader>ott", "<cmd>Neorg return<cr>", desc = "Return to Index" },
    },
  },

  -- Overseer.nvim is now configured as a dependency in dap.lua

  -- Xcodebuild.nvim for iOS/macOS development
  {
    "wojciech-kulik/xcodebuild.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-treesitter/nvim-treesitter",
      "folke/snacks.nvim",
    },
    config = function()
      require("xcodebuild").setup({
        -- Restore options on startup
        restore_on_start = true,
        -- Auto save before running actions
        auto_save = true,
        -- Show build progress
        show_build_progress_bar = true,
        -- Logs settings
        logs = {
          auto_open_on_success_tests = false,
          auto_open_on_failed_tests = false,
          auto_open_on_success_build = false,
          auto_open_on_failed_build = true,
          auto_focus = true,
          auto_close_on_app_launch = false,
          auto_close_on_success = false,
          only_summary = false,
          notify = function(message, severity)
            vim.notify(message, severity)
          end,
        },
        -- Marks settings
        marks = {
          show_signs = true,
          success_sign = "✓",
          failure_sign = "✗",
          show_test_duration = true,
          show_diagnostics = true,
          file_pattern = "*.swift",
        },
        -- Quickfix settings
        quickfix = {
          show_errors_on_quickfixlist = true,
          show_warnings_on_quickfixlist = true,
        },
        -- Test explorer settings
        test_explorer = {
          enabled = true,
          auto_open = true,
          auto_focus = false,
        },
        -- Code coverage settings
        code_coverage = {
          enabled = true,
          file_pattern = "*.swift",
        },
      })
    end,
    keys = {
      -- Main xcodebuild picker
      { "<leader>cx",  "<cmd>XcodebuildPicker<cr>",                 desc = "Xcodebuild Actions" },

      -- Build and run
      { "<leader>cxb", "<cmd>XcodebuildBuild<cr>",                  desc = "Build Project" },
      { "<leader>cxr", "<cmd>XcodebuildBuildRun<cr>",               desc = "Build & Run" },

      -- Testing
      { "<leader>cxt", "<cmd>XcodebuildTest<cr>",                   desc = "Run Tests" },
      { "<leader>cxT", "<cmd>XcodebuildTestClass<cr>",              desc = "Run Class Tests" },
      { "<leader>cxe", "<cmd>XcodebuildTestExplorer<cr>",           desc = "Toggle Test Explorer" },

      -- Device/scheme/configuration selection
      { "<leader>cxd", "<cmd>XcodebuildSelectDevice<cr>",           desc = "Select Device" },
      { "<leader>cxs", "<cmd>XcodebuildSelectScheme<cr>",           desc = "Select Scheme" },
      { "<leader>cxc", "<cmd>XcodebuildSelectTestPlan<cr>",         desc = "Select Test Plan" },

      -- Logs and debugging
      { "<leader>cxl", "<cmd>XcodebuildToggleLogs<cr>",             desc = "Toggle Build Logs" },
      { "<leader>cxX", "<cmd>XcodebuildCleanBuild<cr>",             desc = "Clean Build Folder" },

      -- Code coverage
      { "<leader>cxv", "<cmd>XcodebuildToggleCodeCoverage<cr>",     desc = "Toggle Code Coverage" },
      { "<leader>cxC", "<cmd>XcodebuildShowCodeCoverageReport<cr>", desc = "Show Coverage Report" },
    },
  },

  -- LSP configuration
  { import = "lsp" },

  -- DAP configuration
  { import = "dap" },


}
