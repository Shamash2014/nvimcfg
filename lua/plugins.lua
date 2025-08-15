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
        { "<leader>s",  group = "search" },
        { "<leader>g",  group = "git" },
        { "<leader>gw", group = "worktree" },
        { "<leader>d",  group = "debug" },
        { "<leader>c",  group = "code" },
        { "<leader>cr", group = "refactor" },
        { "<leader>w",  group = "window" },
        { "<leader>b",  group = "buffer" },
        { "<leader>bw", group = "window/tab" },
        { "<leader>t",  group = "tabs/workspaces" },
        { "<leader>v",  group = "view" },
        { "<leader>o",  group = "open/toggle" },
        { "<leader>op", group = "project" },
        { "<leader>od", group = "database" },
        { "<leader>ot", group = "terminal" },
        { "<leader>on", group = "notes" },
        { "<leader>q",  group = "quit" },
        { "<leader>h",  group = "help" },
        { "<leader>r",  group = "run" },
        { "<leader>i",  group = "repl" },
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
    keys = {
      { "ys", mode = "n", desc = "Add surround" },
      { "yS", mode = "n", desc = "Add surround (line)" },
      { "ds", mode = "n", desc = "Delete surround" },
      { "cs", mode = "n", desc = "Change surround" },
      { "cS", mode = "n", desc = "Change surround (line)" },
      { "S", mode = "v", desc = "Add surround" },
      { "gS", mode = "v", desc = "Add surround (line)" },
    },
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
      { "nvim-treesitter/nvim-treesitter-textobjects", lazy = true },
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

  -- LuaSnip for snippets with native vim.snippet integration
  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
    build = "make install_jsregexp",
    event = "InsertEnter",
    opts = {
      history = false,
      update_events = "TextChanged,TextChangedI",
      enable_autosnippets = true,
      store_selection_keys = "<Tab>",
    },
    dependencies = {
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local luasnip = require("luasnip")

      -- Load snippets
      require("luasnip.loaders.from_vscode").lazy_load()
      
      -- Setup native vim.snippet expansion with LuaSnip
      vim.snippet.expand = function(input)
        -- Use LuaSnip for expansion when available
        if luasnip then
          local snippet = luasnip.snippet_from_nodes(nil, luasnip.parser.parse_snippet("", input))
          luasnip.snip_expand(snippet)
        else
          -- Fallback to native expansion
          local ok, parsed = pcall(vim.snippet.parse, input)
          if ok then
            vim.snippet.expand(parsed)
          end
        end
      end

      -- Unified keymaps for both LuaSnip and native snippets
      vim.keymap.set({ "i", "s" }, "<C-k>", function()
        -- Try LuaSnip first
        if luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        -- Then try native snippet
        elseif vim.snippet.active({ direction = 1 }) then
          vim.snippet.jump(1)
        end
      end, { desc = "Expand or jump forward in snippet" })

      vim.keymap.set({ "i", "s" }, "<C-j>", function()
        -- Try LuaSnip first
        if luasnip.jumpable(-1) then
          luasnip.jump(-1)
        -- Then try native snippet
        elseif vim.snippet.active({ direction = -1 }) then
          vim.snippet.jump(-1)
        end
      end, { desc = "Jump back in snippet" })

      vim.keymap.set({ "i", "s" }, "<C-l>", function()
        -- Try LuaSnip choices first
        if luasnip.choice_active() then
          luasnip.change_choice(1)
        -- Then stop native snippet
        elseif vim.snippet.active() then
          vim.snippet.stop()
        end
      end, { desc = "Select choice or stop snippet" })
    end,
  },


  -- Formatting
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    ft = { "lua", "python", "javascript", "typescript", "typescriptreact", "javascriptreact", "json", "html", "css", "markdown", "dart" },
    keys = {
      { "<leader>cf", function() 
        -- Wrap in pcall to handle LSP sync errors
        local ok, err = pcall(function()
          require("conform").format({ 
            async = true,
            lsp_fallback = true,
            timeout_ms = 1000,
          })
        end)
        if not ok then
          vim.notify("Format failed: " .. tostring(err), vim.log.levels.WARN)
        end
      end, desc = "Format" },
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
      format_on_save = function(bufnr)
        -- Disable autoformat on certain filetypes or large files
        local ignore_filetypes = { "sql", "java" }
        if vim.tbl_contains(ignore_filetypes, vim.bo[bufnr].filetype) then
          return
        end
        
        -- Disable for large files
        if vim.fn.getfsize(vim.api.nvim_buf_get_name(bufnr)) > 100000 then
          return
        end
        
        -- Return format options
        return {
          timeout_ms = 1000,
          lsp_fallback = true,
          quiet = true, -- Don't show error notifications on save
        }
      end,
      -- Log level for notifications
      log_level = vim.log.levels.WARN,
      -- Notify on format errors
      notify_on_error = false,
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

  -- Neogit for Magit-like git interface (with bare repo support)
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "folke/snacks.nvim",
    },
    cmd = "Neogit",
    keys = {
      { "<leader>gg", "<cmd>Neogit<cr>", desc = "Neogit Status" },
      { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Neogit Commit" },
      { "<leader>gp", "<cmd>Neogit push<cr>", desc = "Neogit Push" },
      { "<leader>gl", "<cmd>Neogit pull<cr>", desc = "Neogit Pull" },
      { "<leader>gb", "<cmd>Neogit branch<cr>", desc = "Neogit Branch" },
      -- Worktree commands
      { "<leader>gww", function() require("neogit").open({ "worktree" }) end, desc = "Git worktree" },
      { "<leader>gwa", function() require("neogit").open({ "worktree", "create" }) end, desc = "Add worktree" },
      { "<leader>gws", function() require("neogit").open({ "worktree", "switch" }) end, desc = "Switch worktree" },
      { "<leader>gwd", function() require("neogit").open({ "worktree", "delete" }) end, desc = "Delete worktree" },
      { "<leader>gwl", function() require("neogit").open({ "worktree", "list" }) end, desc = "List worktrees" },
    },
    opts = {
      kind = "vsplit", -- Open in vertical split on the right
      disable_hint = false,
      disable_context_highlighting = false,
      disable_signs = false,
      disable_insert_on_commit = true,
      signs = {
        section = { ">", "v" },
        item = { ">", "v" },
        hunk = { "", "" },
      },
      integrations = {
        diffview = true,
        snacks = true
      },
      -- Use default section configuration
      mappings = {
        status = {
          ["q"] = "Close",
          ["<esc>"] = "Close",
          ["1"] = "Depth1",
          ["2"] = "Depth2",
          ["3"] = "Depth3",
          ["4"] = "Depth4",
          ["<tab>"] = "Toggle",
          ["x"] = "Discard",
          ["s"] = "Stage",
          ["S"] = "StageUnstaged",
          ["<c-s>"] = "StageAll",
          ["u"] = "Unstage",
          ["U"] = "UnstageStaged",
          ["$"] = "CommandHistory",
          ["Y"] = "YankSelected",
          ["<c-r>"] = "RefreshBuffer",
          ["<enter>"] = "GoToFile",
          ["<c-v>"] = "VSplitOpen",
          ["<c-x>"] = "SplitOpen",
          ["<c-t>"] = "TabOpen",
          ["i"] = "InitRepo",
          -- Popup commands are handled differently in newer versions
          -- Remove invalid popup mappings
        },
      },
    },
    config = function(_, opts)
      require("neogit").setup(opts)
      
      -- Additional git keybindings
      vim.keymap.set("n", "<leader>gB", function()
        require("neogit").open({ "branch" })
      end, { desc = "Git branches" })
      
      vim.keymap.set("n", "<leader>gl", function()
        require("neogit").open({ "log" })
      end, { desc = "Git log" })
      
      vim.keymap.set("n", "<leader>gd", function()
        require("neogit").open({ "diff" })
      end, { desc = "Git diff" })
    end,
  },

  -- Diffview for better diff visualization
  {
    "sindrets/diffview.nvim",
    dependencies = "nvim-lua/plenary.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    keys = {
      { "<leader>gdo", "<cmd>DiffviewOpen<cr>", desc = "Open Diffview" },
      { "<leader>gdc", "<cmd>DiffviewClose<cr>", desc = "Close Diffview" },
      { "<leader>gdh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
      { "<leader>gdH", "<cmd>DiffviewFileHistory<cr>", desc = "Branch History" },
    },
    opts = {
      enhanced_diff_hl = true,
      view = {
        default = {
          layout = "diff2_horizontal",
          winbar_info = true,
        },
        merge_tool = {
          layout = "diff3_mixed",
          disable_diagnostics = true,
          winbar_info = true,
        },
      },
      file_panel = {
        listing_style = "tree",
        tree_options = {
          flatten_dirs = true,
          folder_statuses = "only_folded",
        },
      },
      keymaps = {
        view = {
          ["<tab>"] = false,
          ["<s-tab>"] = false,
          ["<leader>e"] = false,
          ["<leader>b"] = false,
        },
      },
    },
  },

  -- Git conflict resolver
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("git-conflict").setup({
        default_mappings = true, -- disable the default mappings, refer to the table below
        default_commands = true, -- disable commands created by this plugin
        disable_diagnostics = false, -- disable diagnostics in conflicted files
        list_opener = "copen", -- command or function to open the conflicts list
        highlights = { -- They must have background color, otherwise the default color will be used
          incoming = "DiffAdd",
          current = "DiffText",
        },
      })
      
      -- Additional custom keymaps for git conflict resolution
      vim.keymap.set("n", "<leader>gco", "<cmd>GitConflictChooseOurs<cr>", { desc = "Choose our changes" })
      vim.keymap.set("n", "<leader>gct", "<cmd>GitConflictChooseTheirs<cr>", { desc = "Choose their changes" })
      vim.keymap.set("n", "<leader>gcb", "<cmd>GitConflictChooseBoth<cr>", { desc = "Choose both changes" })
      vim.keymap.set("n", "<leader>gc0", "<cmd>GitConflictChooseNone<cr>", { desc = "Choose none" })
      vim.keymap.set("n", "<leader>gcl", "<cmd>GitConflictListQf<cr>", { desc = "List conflicts" })
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
    lazy = false,
    config = function()
      require("oil").setup({
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
        autosave_changes = true,
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
        }
      })
    end,
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
      terminal = { 
        enabled = true,
        win = {
          position = "bottom",
          height = 0.3,
        },
      },
      -- Dim inactive code (replaces twilight.nvim)
      dim = {
        enabled = false, -- Toggle with keybind
        animate = {
          enabled = false, -- Better performance
        },
      },
      -- Word highlighting (like vim-illuminate)
      words = {
        enabled = true,
        debounce = 200,
      },
      -- LSP rename with preview (replaces inc-rename.nvim)
      rename = {
        enabled = true,
      },
      -- Better quickfix (replaces quicker.nvim)
      quickfix = {
        enabled = true,
      },
    },
    keys = {
      -- Find operations (with proper root detection for bare repos and worktrees)
      { "<leader>ff",  function() 
        local root = vim.g.git_root or vim.fn.getcwd()
        require("snacks").picker.files({ cwd = root }) 
      end, desc = "Find Files" },
      { "<leader>fr",  function() require("snacks").picker.recent() end,         desc = "Recent Files" },
      { "<leader>fg",  function() 
        local root = vim.g.git_root or vim.fn.getcwd()
        require("snacks").picker.grep({ cwd = root }) 
      end, desc = "Grep Files" },
      { "<leader>fb",  function() require("snacks").picker.buffers() end,        desc = "Find Buffers" },
      { "<leader>fh",  function() require("snacks").picker.help() end,           desc = "Find Help" },
      { "<leader>fk",  function() require("snacks").picker.keymaps() end,        desc = "Find Keymaps" },
      { "<leader>fc",  function() require("snacks").picker.commands() end,       desc = "Find Commands" },

      -- Project operations (with proper root detection)
      { "<leader>opf",  function() 
        local root = vim.g.git_root or vim.fn.getcwd()
        require("snacks").picker.files({ cwd = root }) 
      end, desc = "Find Files in Project" },
      { "<leader>opr",  function() require("snacks").picker.recent() end,         desc = "Recent Files in Project" },
      { "<leader>opg",  function() 
        local root = vim.g.git_root or vim.fn.getcwd()
        require("snacks").picker.grep({ cwd = root }) 
      end, desc = "Grep in Project" },
      { "<leader>ops",  function() require("snacks").picker.lsp_symbols() end,    desc = "Project Symbols" },

      -- Search operations
      { "<leader>ss",  function() require("snacks").picker.grep_word() end,      desc = "Search Word" },
      { "<leader>sg",  function() require("snacks").picker.grep() end,           desc = "Grep Search" },
      { "<leader>sl",  function() require("snacks").picker.lines() end,          desc = "Search Lines" },
      { "<leader>sr",  function() require("snacks").picker.lsp_references() end, desc = "Search References" },
      { "<leader>si",  function() require("snacks").picker.lsp_symbols() end,    desc = "Search Symbols" },
      { "<leader>sI",  function() require("snacks").picker.lsp_workspace_symbols() end, desc = "Search All Symbols (Zed-like)" },

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
      { "<leader>ott", function() require("snacks").terminal.toggle() end,       desc = "Toggle Terminal (All)" },
      { "<leader>otd", function() require("snacks").terminal.toggle(nil, { cwd = vim.fn.getcwd() }) end, desc = "Toggle Terminal (Current Dir)" },
      { "<leader>od",  function() require("snacks").dim.toggle() end,            desc = "Toggle Dim (Twilight)" },
      { "<leader>cr",  function() require("snacks").rename() end,                desc = "Rename Symbol" },
      {
        "<leader>otc",
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
        "<leader>otr",
        function()
          if vim.g.last_terminal_command then
            require("snacks").terminal.open(vim.g.last_terminal_command)
          else
            vim.notify("No previous command to restart", vim.log.levels.WARN)
          end
        end,
        desc = "Rerun Last Command"
      },
      { "<leader>gg", "<cmd>Neogit<cr>", desc = "Neogit" },
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
          model = "gpt-oss-20b-mlx",
          api_key_name = "",
          timeout = 30000,
          context_window = 32768,  -- Increased for larger model
          extra_request_body = {
            temperature = 0,
            max_tokens = 8192,  -- Increased for larger model
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
        cmd = "PasteImage",
        keys = {
          { "<leader>pi", "<cmd>PasteImage<cr>", desc = "Paste Image" },
        },
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
      { "<leader>ao", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle CodeCompanion Chat" },
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
    keys = { "." },
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
      { "<leader>onn", "<cmd>Neorg workspace notes<cr>", desc = "Open Notes" },
      { "<leader>onw", "<cmd>Neorg workspace work<cr>", desc = "Open Work" },
      { "<leader>oni", "<cmd>Neorg return<cr>", desc = "Return to Index" },
    },
  },

  -- Overseer task runner
  {
    "stevearc/overseer.nvim",
    opts = {
      task_list = {
        direction = "bottom",
        min_height = 10,
        max_height = 20,
        default_detail = 1,
      },
      dap = true,  -- Enable DAP integration
      strategy = "terminal",
      templates = { "builtin" },
      component_aliases = {
        default = {
          { "display_duration", detail_level = 2 },
          "on_output_summarize",
          "on_exit_set_status",
          "on_complete_notify",
          { "on_complete_dispose", require_view = { "SUCCESS", "FAILURE" } },
        },
      },
    },
    config = function(_, opts)
      require("overseer").setup(opts)
      
      -- Simple tab-based task isolation using scope.nvim approach
      -- Just let each tab have its own working directory
      -- Tasks naturally isolate per directory
      
      -- Register overseer task templates after setup
      local overseer = require("overseer")
      
      -- Flutter/Dart task templates
      overseer.register_template({
        name = "flutter run",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "run", "--debug" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter build",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "build", "apk", "--debug" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter test",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "test" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter pub get",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "pub", "get" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("pubspec.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "flutter clean",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "clean" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      -- Docker Compose task templates
      overseer.register_template({
        name = "docker-compose up",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "up", "--watch" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose up -d",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "up", "-d" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose up --force-recreate",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "up", "-d", "--force-recreate" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose down",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "down" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose stop",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "stop" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose build",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "build", "--no-cache" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose exec",
        builder = function()
          local service = vim.fn.input("Service name: ")
          local command = vim.fn.input("Command: ", "/bin/bash")
          return {
            cmd = { "docker-compose" },
            args = { "exec", service, command },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose run --rm",
        builder = function()
          local service = vim.fn.input("Service name: ")
          local command = vim.fn.input("Command: ", "/bin/bash")
          return {
            cmd = { "docker-compose" },
            args = { "run", "--rm", service, command },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "aider --watch-files",
        builder = function()
          return {
            cmd = { "aider" },
            args = { "--watch-files" },
            components = { "default" },
          }
        end,
      })

      -- npm task templates
      overseer.register_template({
        name = "npm install",
        builder = function()
          return {
            cmd = { "npm" },
            args = { "install" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "npm run build",
        builder = function()
          return {
            cmd = { "npm" },
            args = { "run", "build" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "npm run start",
        builder = function()
          return {
            cmd = { "npm" },
            args = { "run", "start" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "npm run dev",
        builder = function()
          return {
            cmd = { "npm" },
            args = { "run", "dev" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "npm test",
        builder = function()
          return {
            cmd = { "npm" },
            args = { "test" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })

      -- iOS CocoaPods task templates
      overseer.register_template({
        name = "pod install",
        builder = function()
          return {
            cmd = { "pod" },
            args = { "install" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("Podfile") == 1 or vim.fn.filereadable("ios/Podfile") == 1
          end,
        },
      })

      overseer.register_template({
        name = "pod update",
        builder = function()
          return {
            cmd = { "pod" },
            args = { "update" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("Podfile") == 1 or vim.fn.filereadable("ios/Podfile") == 1
          end,
        },
      })

      -- DAP debugging task templates
      overseer.register_template({
        name = "Build and Debug (Python)",
        builder = function()
          return {
            cmd = { "python3", "-m", "py_compile" },
            args = { vim.fn.expand("%") },
            components = {
              "default",
              {
                "on_complete_callback",
                on_complete = function(task, status, result)
                  if status == "SUCCESS" then
                    vim.cmd("DapContinue")
                  end
                end,
              },
            },
          }
        end,
        condition = {
          filetype = { "python" },
        },
      })

      overseer.register_template({
        name = "Build and Debug (Flutter)",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "build", "apk", "--debug" },
            components = {
              "default",
              {
                "on_complete_callback",
                on_complete = function(task, status, result)
                  if status == "SUCCESS" then
                    vim.notify("Build complete. Ready to debug.", vim.log.levels.INFO)
                    -- You can trigger DAP here if needed
                  end
                end,
              },
            },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      -- Template for running tests before debugging
      overseer.register_template({
        name = "Test and Debug (Python)",
        builder = function()
          return {
            cmd = { "python3", "-m", "pytest" },
            args = { vim.fn.expand("%"), "-v" },
            components = {
              "default",
              {
                "on_complete_callback",
                on_complete = function(task, status, result)
                  if status == "SUCCESS" then
                    vim.notify("Tests passed. Starting debugger.", vim.log.levels.INFO)
                    vim.cmd("DapContinue")
                  else
                    vim.notify("Tests failed. Fix issues before debugging.", vim.log.levels.WARN)
                  end
                end,
              },
            },
          }
        end,
        condition = {
          filetype = { "python" },
          callback = function()
            return vim.fn.expand("%:t"):match("test_") ~= nil
          end,
        },
      })

      -- Neotest integration templates
      overseer.register_template({
        name = "Run tests (neotest)",
        builder = function()
          return {
            cmd = { vim.cmd.NeotestOverseer },
            components = { "default" },
          }
        end,
        desc = "Run tests using neotest with overseer backend",
      })
      
      -- Generic test templates
      overseer.register_template({
        name = "pytest",
        builder = function()
          return {
            cmd = { "pytest" },
            args = { "-v", vim.fn.expand("%") },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "python" },
        },
      })
      
      overseer.register_template({
        name = "jest",
        builder = function()
          return {
            cmd = { "npm", "test", "--", vim.fn.expand("%") },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })
      
      overseer.register_template({
        name = "cargo test",
        builder = function()
          return {
            cmd = { "cargo", "test" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "rust" },
          callback = function()
            return vim.fn.filereadable("Cargo.toml") == 1
          end,
        },
      })
      
      overseer.register_template({
        name = "go test",
        builder = function()
          return {
            cmd = { "go", "test", "./..." },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "go" },
          callback = function()
            return vim.fn.filereadable("go.mod") == 1
          end,
        },
      })
      
      overseer.register_template({
        name = "flutter test",
        builder = function()
          return {
            cmd = { "flutter", "test" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
          callback = function()
            return vim.fn.filereadable("pubspec.yaml") == 1
          end,
        },
      })

      -- Terminal mode exit mapping
      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "*",
        callback = function()
          vim.keymap.set("t", "jk", "<C-\\><C-n>", { buffer = true, desc = "Exit terminal mode" })
        end,
      })
    end,
    keys = {
      { "<leader>rr", "<cmd>OverseerRun<cr>",         desc = "Run Task" },
      { "<leader>ro", "<cmd>OverseerToggle<cr>",      desc = "Toggle Overseer" },
      { "<leader>rb", "<cmd>OverseerBuild<cr>",       desc = "Build Task" },
      { "<leader>rq", "<cmd>OverseerQuickAction<cr>", desc = "Quick Action" },
      { "<leader>ra", "<cmd>OverseerTaskAction<cr>",  desc = "Task Action" },
      { "<leader>rv", "<cmd>OverseerRun<cr>", desc = "Run Task" },
      { "<leader>rl", "<cmd>OverseerLoadBundle<cr>",  desc = "Load Task Bundle" },
      { "<leader>rs", "<cmd>OverseerSaveBundle<cr>",  desc = "Save Task Bundle" },
    },
  },

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

  -- DAP (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "theHamsta/nvim-dap-virtual-text",
      "nvim-neotest/nvim-nio",
      {
        "microsoft/vscode-js-debug",
        lazy = true,
        build = "npm install --legacy-peer-deps && npx gulp vsDebugServerBundle && rm -rf out && mv dist out",
        version = "v1.x",
      },
      {
        "mxsdev/nvim-dap-vscode-js",
        dependencies = { 
          "mfussenegger/nvim-dap",
          "microsoft/vscode-js-debug"
        },
        config = function()
          -- Check if the debug server exists
          local debugger_path = vim.fn.stdpath("data") .. "/lazy/vscode-js-debug"
          local server_path = debugger_path .. "/out/src/vsDebugServer.js"
          
          if vim.fn.filereadable(server_path) == 0 then
            vim.notify("vscode-js-debug not found. Run :Lazy build vscode-js-debug", vim.log.levels.ERROR)
            return
          end
          
          require("dap-vscode-js").setup({
            -- Node executable path (uses system node by default)
            node_path = "node",
            -- Path to vscode-js-debug installation
            debugger_path = debugger_path,
            -- Command to use (optional, overrides node_path and debugger_path)
            -- debugger_cmd = { "node", server_path },
            -- Which adapters to register in nvim-dap
            adapters = { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' },
            -- Log file settings
            log_file_path = false,
            log_file_level = false,
            log_console_level = vim.log.levels.ERROR,
          })
        end,
      },
      {
        "miroshQa/debugmaster.nvim",
        dependencies = { 
          "mfussenegger/nvim-dap",
          "jbyuki/one-small-step-for-vimkind"  -- For Lua debugging
        },
        config = function()
          local dm = require("debugmaster")
          
          -- Enable Neovim Lua debugging integration
          dm.plugins.osv_integration.enabled = true
          
          -- Auto-enable debug mode when DAP starts
          local dap = require("dap")
          
          -- Track debug mode state
          local debug_mode_active = false
          
          -- Use DAP listeners to auto-toggle debug mode
          dap.listeners.after.event_initialized["debugmaster"] = function()
            if not debug_mode_active then
              dm.mode.toggle()  -- Enter debug mode
              debug_mode_active = true
            end
          end
          
          -- Auto-disable debug mode when DAP session ends
          dap.listeners.after.event_terminated["debugmaster"] = function()
            if debug_mode_active then
              dm.mode.toggle()  -- Exit debug mode
              debug_mode_active = false
            end
          end
          
          dap.listeners.after.event_exited["debugmaster"] = function()
            if debug_mode_active then
              dm.mode.toggle()  -- Exit debug mode
              debug_mode_active = false
            end
          end
          
          -- Set debug mode cursor color
          vim.api.nvim_set_hl(0, "dCursor", { bg = "#FF2C2C" })
        end,
      },
    },
    keys = {
      { "<leader>dm", function() require("debugmaster").mode.toggle() end,                                         desc = "Toggle Debug Mode" },
      { "<leader>dd", "<cmd>DapContinue<cr>",                                                                      desc = "Start/Continue Debug" },
      { "<leader>do", "<cmd>DapStepOver<cr>",                                                                      desc = "Step Over" },
      { "<leader>di", "<cmd>DapStepInto<cr>",                                                                      desc = "Step Into" },
      { "<leader>du", "<cmd>DapStepOut<cr>",                                                                       desc = "Step Out" },
      { "<leader>db", "<cmd>DapToggleBreakpoint<cr>",                                                              desc = "Toggle Breakpoint" },
      { "<leader>dB", function() require("dap").set_breakpoint() end,                                              desc = "Set Breakpoint" },
      { "<leader>dl", function() require("dap").set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end, desc = "Log Point" },
      { "<leader>dr", "<cmd>DapToggleRepl<cr>",                                                                    desc = "Open REPL" },
      { "<leader>dL", function() require("dap").run_last() end,                                                    desc = "Run Last" },
    },
    config = function()
      local dap = require("dap")

      -- Ensure adapters and configurations tables exist
      dap.adapters = dap.adapters or {}
      dap.configurations = dap.configurations or {}
      
      -- nvim-dap-vscode-js plugin should already be configured via its config function
      
      -- Load VS Code launch.json if it exists
      require('dap.ext.vscode').load_launchjs(nil, {
        ["pwa-node"] = { "javascript", "typescript" },
        ["node"] = { "javascript", "typescript" },
        ["chrome"] = { "javascript", "typescript" },
        ["python"] = { "python" },
        ["dart"] = { "dart" },
        ["flutter"] = { "dart" },
      })

      -- Node.js adapters are now configured by nvim-dap-vscode-js plugin above

      -- Alternative: node-debug2 adapter (install with: npm install -g node-inspect)
      dap.adapters.node2 = {
        type = "executable",
        command = "node",
        args = {
          vim.fn.expand("~/.local/share/nvim/debug-adapters/vscode-node-debug2/out/src/nodeDebug.js"),
        },
      }

      -- Node adapter for attach configurations
      -- This adapter connects through Chrome DevTools Protocol
      dap.adapters.node = {
        type = "server",
        host = "localhost",
        port = 9229,  -- Default port, will be overridden by configuration
        options = {
          max_retries = 10,
          delay_ms = 100,
        },
      }
      
      -- Check if pwa-node works, provide diagnostic
      vim.api.nvim_create_user_command("DapCheckNode", function()
        local vscode_js_path = vim.fn.stdpath("data") .. "/lazy/vscode-js-debug"
        local server_path = vscode_js_path .. "/out/src/vsDebugServer.js"
        
        if vim.fn.filereadable(server_path) == 1 then
          vim.notify("✓ vscode-js-debug found at: " .. server_path, vim.log.levels.INFO)
        else
          vim.notify("✗ vscode-js-debug not found. Run :Lazy build vscode-js-debug", vim.log.levels.ERROR)
        end
        
        -- Check if pwa-node adapter is registered
        if dap.adapters["pwa-node"] then
          vim.notify("✓ pwa-node adapter is registered", vim.log.levels.INFO)
        else
          vim.notify("✗ pwa-node adapter not registered", vim.log.levels.ERROR)
        end
        
        -- Check node executable
        if vim.fn.executable("node") == 1 then
          local node_version = vim.fn.system("node --version"):gsub("\n", "")
          vim.notify("✓ Node.js " .. node_version .. " found", vim.log.levels.INFO)
        else
          vim.notify("✗ Node.js not found in PATH", vim.log.levels.ERROR)
        end
      end, { desc = "Check DAP Node.js setup" })

      -- Generalized Node.js configurations (JS/TS)
      -- Using both pwa-node (feature-rich) and node (fallback) adapters
      local node_configs = {
        {
          type = "pwa-node",
          request = "launch",
          name = "Launch Current File",
          program = "${file}",
          cwd = "${workspaceFolder}",
          sourceMaps = true,
          skipFiles = { "<node_internals>/**", "node_modules/**" },
          resolveSourceMapLocations = {
            "${workspaceFolder}/**",
            "!**/node_modules/**",
          },
        },
        {
          type = "node",
          request = "launch", 
          name = "Launch File (Simple)",
          program = "${file}",
          cwd = "${workspaceFolder}",
          runtimeArgs = { "--inspect-brk" },
          port = 9229,
          sourceMaps = true,
          skipFiles = { "<node_internals>/**", "node_modules/**" },
        },
        {
          type = "pwa-node",
          request = "launch",
          name = "Run Script",
          runtimeExecutable = function()
            if vim.fn.filereadable("yarn.lock") == 1 then return "yarn"
            elseif vim.fn.filereadable("pnpm-lock.yaml") == 1 then return "pnpm"
            else return "npm" end
          end,
          runtimeArgs = function()
            return vim.split(vim.fn.input("Script: ", "run start"), " ")
          end,
          cwd = "${workspaceFolder}",
          console = "integratedTerminal",
          sourceMaps = true,
        },
        {
          type = "pwa-node",
          request = "launch",
          name = "NPM Debug Script",
          runtimeExecutable = "npm",
          runtimeArgs = { "run", "debug" },
          cwd = "${workspaceFolder}",
          attachSimplePort = 9229,
          sourceMaps = true,
          protocol = "inspector",
          skipFiles = { "<node_internals>/**", "node_modules/**" },
        },
        {
          type = "pwa-node",
          request = "attach",
          name = "Attach to Process",
          processId = require("dap.utils").pick_process,
          cwd = "${workspaceFolder}",
          sourceMaps = true,
        },
        {
          type = "pwa-node",
          request = "attach",
          name = "Attach to Port (pwa-node)",
          port = function()
            return tonumber(vim.fn.input("Port: ", "9229"))
          end,
          address = "localhost",
          restart = true,
          sourceMaps = true,
          protocol = "inspector",
          cwd = "${workspaceFolder}",
          resolveSourceMapLocations = {
            "${workspaceFolder}/**",
            "!**/node_modules/**",
          },
          skipFiles = { "<node_internals>/**", "node_modules/**" },
          continueOnAttach = true,
        },
        {
          type = "pwa-node",
          request = "attach",
          name = "Attach to Remote (Docker)",
          address = function()
            return vim.fn.input("Address (localhost for Docker): ", "localhost")
          end,
          port = function()
            return tonumber(vim.fn.input("Port: ", "9229"))
          end,
          localRoot = "${workspaceFolder}",
          remoteRoot = function()
            local remote = vim.fn.input("Remote root (e.g., /app for Docker, leave empty for local): ", "")
            if remote == "" then
              return "${workspaceFolder}"
            end
            return remote
          end,
          sourceMaps = true,
          protocol = "inspector",
          continueOnAttach = true,
          resolveSourceMapLocations = {
            "${workspaceFolder}/**",
            "!**/node_modules/**",
          },
          sourceMapPathOverrides = {
            ["/app/*"] = "${workspaceFolder}/*",
            ["/usr/src/app/*"] = "${workspaceFolder}/*",
            ["webpack:///./~/*"] = "${workspaceFolder}/node_modules/*",
            ["webpack://?:*/*"] = "${workspaceFolder}/*",
          },
          skipFiles = { "<node_internals>/**", "node_modules/**" },
          smartStep = true,
        },
        {
          type = "pwa-node",
          request = "launch",
          name = "Test File",
          program = function()
            if vim.fn.filereadable("node_modules/.bin/vitest") == 1 then
              return "${workspaceFolder}/node_modules/.bin/vitest"
            elseif vim.fn.filereadable("node_modules/.bin/jest") == 1 then
              return "${workspaceFolder}/node_modules/.bin/jest"
            else
              return "${file}"
            end
          end,
          args = { "${file}" },
          cwd = "${workspaceFolder}",
          console = "integratedTerminal",
        },
      }

      dap.configurations.javascript = vim.deepcopy(node_configs)
      dap.configurations.typescript = vim.deepcopy(node_configs)
      
      -- TypeScript-specific: Direct execution
      table.insert(dap.configurations.typescript, 1, {
        type = "pwa-node",
        request = "launch",
        name = "Run TypeScript",
        runtimeExecutable = function()
          if vim.fn.executable("tsx") == 1 then return "tsx"
          elseif vim.fn.executable("ts-node") == 1 then return "ts-node"
          elseif vim.fn.executable("bun") == 1 then return "bun"
          else return "node" end
        end,
        program = "${file}",
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        resolveSourceMapLocations = {
          "${workspaceFolder}/**",
          "!**/node_modules/**",
        },
      })
      
      -- Apply to React files
      dap.configurations.javascriptreact = dap.configurations.javascript
      dap.configurations.typescriptreact = dap.configurations.typescript

      -- DAP Dart/Flutter adapters configuration
      dap.adapters.dart = {
        type = 'executable',
        command = 'dart',
        args = { 'debug_adapter' },
        options = { 
          detached = false,
        }
      }
      
      dap.adapters.flutter = {
        type = 'executable',
        command = 'flutter',
        args = { 'debug_adapter' },
        options = { 
          detached = false,
        }
      }

      -- DAP Elixir adapter configuration
      -- Using the same path as ElixirLS LSP server
      local elixir_debugger_path = vim.fn.expand('~/.tools/elixir-ls/debug_adapter.sh')
      if vim.fn.filereadable(elixir_debugger_path) == 1 then
        dap.adapters.mix_task = {
          type = 'executable',
          command = elixir_debugger_path,
          args = {},
        }
      else
        -- Try alternative path
        elixir_debugger_path = vim.fn.expand('~/.tools/elixir-ls/debugger.sh')
        if vim.fn.filereadable(elixir_debugger_path) == 1 then
          dap.adapters.mix_task = {
            type = 'executable',
            command = elixir_debugger_path,
            args = {},
          }
        else
          vim.notify("ElixirLS debugger not found at ~/.tools/elixir-ls/", vim.log.levels.WARN)
        end
      end

      -- DAP Python configuration
      dap.adapters.python = {
        type = "executable",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      }

      dap.configurations.python = {
        {
          type = "python",
          request = "launch",
          name = "Launch file",
          program = "${file}",
          pythonPath = function()
            return "/usr/bin/python3"
          end,
        },
        {
          type = "python",
          request = "launch",
          name = "Launch with Build",
          program = "${file}",
          preLaunchTask = "Build and Debug (Python)",
          pythonPath = function()
            return "/usr/bin/python3"
          end,
        },
        {
          type = "python",
          request = "launch",
          name = "Test and Debug",
          program = "${file}",
          preLaunchTask = "Test and Debug (Python)",
          pythonPath = function()
            return "/usr/bin/python3"
          end,
        },
      }

      -- DAP Dart configuration
      dap.configurations.dart = {
        {
          type = "dart",
          request = "launch",
          name = "Launch Dart",
          dartSdkPath = function()
            local flutter_root = vim.env.FLUTTER_ROOT
            if flutter_root then
              return flutter_root .. "/bin/cache/dart-sdk"
            end
            return "dart"
          end,
          program = "${file}",
          cwd = "${workspaceFolder}",
        },
        {
          type = "dart",
          request = "launch",
          name = "Launch Flutter",
          flutterSdkPath = function()
            local flutter_root = vim.env.FLUTTER_ROOT
            if flutter_root then
              return flutter_root
            end
            local fvm_local = vim.fn.getcwd() .. "/.fvm/flutter_sdk"
            if vim.fn.isdirectory(fvm_local) == 1 then
              return fvm_local
            end
            return "flutter"
          end,
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
        },
        {
          type = "dart",
          request = "launch",
          name = "Launch Flutter with Build",
          preLaunchTask = "Build and Debug (Flutter)",
          flutterSdkPath = function()
            local flutter_root = vim.env.FLUTTER_ROOT
            if flutter_root then
              return flutter_root
            end
            local fvm_local = vim.fn.getcwd() .. "/.fvm/flutter_sdk"
            if vim.fn.isdirectory(fvm_local) == 1 then
              return fvm_local
            end
            return "flutter"
          end,
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
        }
      }

      -- DAP Elixir configuration
      dap.configurations.elixir = {
        {
          type = "mix_task",
          name = "mix test",
          task = 'test',
          taskArgs = {"--trace"},
          request = "launch",
          startApps = true, -- for Phoenix projects
          projectDir = "${workspaceFolder}",
          requireFiles = {
            "test/**/test_helper.exs",
            "test/**/*_test.exs"
          }
        },
      }

      -- Configure signs with proper symbols
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◐", texthl = "DapBreakpointCondition" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DapBreakpointRejected" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapStoppedLine" })

      -- Setup virtual text
      require("nvim-dap-virtual-text").setup({
        enabled = true,
        enabled_commands = true,
        highlight_changed_variables = true,
        highlight_new_as_changed = false,
        show_stop_reason = true,
        commented = false,
        only_first_definition = true,
        all_references = false,
        clear_on_continue = false,
        display_callback = function(variable, buf, stackframe, node, options)
          if options.virt_text_pos == 'inline' then
            return ' = ' .. variable.value
          else
            return variable.name .. ' = ' .. variable.value
          end
        end,
        virt_text_pos = vim.fn.has 'nvim-0.10' == 1 and 'inline' or 'eol',
        all_frames = false,
        virt_lines = false,
        virt_text_win_col = nil
      })
    end,
  },

  -- Scope.nvim for tab-based buffer isolation (workspace per tab)
  {
    "tiagovla/scope.nvim",
    event = "VeryLazy",
    config = function()
      require("scope").setup({
        hooks = {
          pre_tab_enter = nil,
          post_tab_enter = nil,
          pre_tab_leave = nil,
          post_tab_leave = nil,
          pre_tab_close = nil,
          post_tab_close = nil,
        },
        -- Restore cursor position when switching tabs
        restore_state = true,
      })
      
      -- Override default buffer keymaps to use scope with snacks.nvim
      vim.keymap.set("n", "<leader>bb", function()
        -- Since scope.nvim already filters buffers per tab, just use the regular buffer picker
        -- It will only show buffers from the current tab thanks to scope
        Snacks.picker.buffers()
      end, { desc = "Buffers (current tab)" })
      
      vim.keymap.set("n", "<leader>bB", function()
        -- To show all buffers, we need to temporarily get all buffers across tabs
        -- This is a workaround since scope filters them by default
        local all_bufs = {}
        local current_tab = vim.api.nvim_get_current_tabpage()
        
        -- Iterate through all tabs to collect buffers
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
          vim.api.nvim_set_current_tabpage(tab)
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
              all_bufs[buf] = true
            end
          end
        end
        
        -- Restore current tab
        vim.api.nvim_set_current_tabpage(current_tab)
        
        -- Show all buffers
        Snacks.picker.buffers()
      end, { desc = "Buffers (all tabs)" })
      
      -- Tab management keymaps for workspaces
      vim.keymap.set("n", "<leader>tt", "<cmd>tabnew<cr>", { desc = "New tab/workspace" })
      vim.keymap.set("n", "<leader>tc", "<cmd>tabclose<cr>", { desc = "Close tab" })
      vim.keymap.set("n", "<leader>tj", "<cmd>tabnext<cr>", { desc = "Next tab" })
      vim.keymap.set("n", "<leader>tk", "<cmd>tabprevious<cr>", { desc = "Previous tab" })
      vim.keymap.set("n", "<leader>t1", "1gt", { desc = "Tab 1" })
      vim.keymap.set("n", "<leader>t2", "2gt", { desc = "Tab 2" })
      vim.keymap.set("n", "<leader>t3", "3gt", { desc = "Tab 3" })
      vim.keymap.set("n", "<leader>t4", "4gt", { desc = "Tab 4" })
      vim.keymap.set("n", "<leader>t5", "5gt", { desc = "Tab 5" })
    end,
  },
  
  -- LSP-based project switching
  {
    name = "lsp-projects",
    dir = vim.fn.stdpath("config"),
    event = "LspAttach",
    config = function()
      -- Project switching using LSP roots
      vim.keymap.set("n", "<leader>op", function()
        -- Collect unique LSP root directories from all clients
        local roots = {}
        local seen = {}
        for _, client in ipairs(vim.lsp.get_clients()) do
          if client.root_dir and not seen[client.root_dir] then
            seen[client.root_dir] = true
            table.insert(roots, client.root_dir)
          end
        end
        
        if #roots == 0 then
          vim.notify("No LSP projects found", vim.log.levels.WARN)
          return
        end
        
        -- Use snacks picker to select project
        Snacks.picker.select(roots, {
          prompt = "LSP Projects",
          format_item = function(item)
            return vim.fn.fnamemodify(item, ":~:.")
          end,
          confirm = function(item)
            vim.cmd("tabnew")
            vim.cmd("tcd " .. item)
            -- Try to open a file in the project
            local files = vim.fn.glob(item .. "/*.*", false, true)
            if #files > 0 then
              vim.cmd("edit " .. files[1])
            end
          end
        })
      end, { desc = "Open project (LSP)" })
      
      -- Show current project
      vim.keymap.set("n", "<leader>oP", function()
        local cwd = vim.g.git_root or vim.fn.getcwd()
        local project = vim.fn.fnamemodify(cwd, ":t")
        local in_worktree = vim.g.in_worktree and " (worktree)" or ""
        local in_bare = vim.g.bare_repo and " (bare repo)" or ""
        vim.notify("Current project: " .. project .. in_worktree .. in_bare .. "\n" .. cwd, vim.log.levels.INFO)
      end, { desc = "Show current project" })
    end,
  },

  -- Otter.nvim for embedded code support in markdown/quarto
  {
    "jmbuhr/otter.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    ft = { "markdown", "quarto", "rmd", "org", "norg" },
    config = function()
      local otter = require("otter")
      otter.setup({
        lsp = {
          diagnostic_update_events = { "BufWritePost", "InsertLeave", "TextChanged" },
          root_dir = function(_, bufnr)
            return vim.fs.root(bufnr or 0, {
              ".git",
              "_quarto.yml",
              "package.json",
            }) or vim.fn.getcwd()
          end,
        },
        buffers = {
          set_filetype = false,
          write_to_disk = false,
        },
        strip_wrapping_quote_characters = { "'", '"', "`" },
        handle_leading_whitespace = true,
      })
      
      -- Auto-activate otter for supported files
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        pattern = { "*.md", "*.qmd", "*.Rmd", "*.org", "*.norg" },
        callback = function(ev)
          local bufnr = ev.buf
          -- Check if file contains code blocks
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(100, vim.api.nvim_buf_line_count(bufnr)), false)
          local has_code_block = false
          for _, line in ipairs(lines) do
            if line:match("^```%w") or line:match("^~~~%w") then
              has_code_block = true
              break
            end
          end
          
          if has_code_block then
            otter.activate(
              { "python", "lua", "javascript", "typescript", "r", "rust", "go", "dart", "bash", "sh", "zsh", "elixir" },
              true,  -- Enable completion
              true,  -- Enable diagnostics
              nil    -- Use default for tsquery
            )
          end
        end,
      })
    end,
    keys = {
      {
        "<leader>lo",
        function()
          require("otter").activate()
          vim.notify("Otter activated for embedded code", vim.log.levels.INFO)
        end,
        desc = "Activate Otter for embedded code",
        ft = { "markdown", "quarto", "rmd", "org", "norg" },
      },
      {
        "<leader>lO",
        function()
          require("otter").deactivate()
          vim.notify("Otter deactivated", vim.log.levels.INFO)
        end,
        desc = "Deactivate Otter",
        ft = { "markdown", "quarto", "rmd", "org", "norg" },
      },
      {
        "<leader>lk",
        function()
          require("otter").ask_hover()
        end,
        desc = "Otter hover in code block",
        ft = { "markdown", "quarto", "rmd", "org", "norg" },
      },
      {
        "<leader>ld",
        function()
          require("otter").ask_definition()
        end,
        desc = "Otter go to definition",
        ft = { "markdown", "quarto", "rmd", "org", "norg" },
      },
    },
  },

  -- Iron.nvim for REPL support
  {
    "Vigemus/iron.nvim",
    keys = {
      { "<leader>ir", desc = "Toggle REPL" },
      { "<leader>il", desc = "Send line" },
      { "<leader>is", desc = "Send selection", mode = "v" },
      { "<leader>if", desc = "Send file" },
      { "<leader>ip", desc = "Send paragraph" },
      { "<leader>ib", desc = "Send code block" },
      { "<leader>in", desc = "Send block and move" },
      { "<leader>ic", desc = "Clear REPL" },
      { "<leader>iq", desc = "Close REPL" },
      { "<leader>i<cr>", desc = "Send line and move" },
      { "ctr", desc = "Send motion to REPL", mode = "n" },
      { "cp", desc = "Send paragraph", mode = "n" },
      { "cc", desc = "Send line", mode = "n" },
      { "ce", desc = "Eval to end of line", mode = "n" },
      { "cee", desc = "Eval current line", mode = "n" },
      { "cew", desc = "Eval word", mode = "n" },
      { "]b", desc = "Next code block", mode = "n" },
      { "[b", desc = "Previous code block", mode = "n" },
    },
    config = function()
      local iron = require("iron.core")
      local view = require("iron.view")

      iron.setup {
        config = {
          -- Whether a repl should be discarded or not
          scratch_repl = true,
          -- Your repl definitions come here
          repl_definition = {
            python = {
              command = function()
                -- Prefer ipython if available
                if vim.fn.executable("ipython") == 1 then
                  return { "ipython", "--no-autoindent" }
                else
                  return { "python3" }
                end
              end,
              format = require("iron.fts.common").bracketed_paste_python,
              block_dividers = { "# %%", "#%%" }  -- Jupyter-style code blocks
            },
            javascript = {
              command = { "node" },
              format = require("iron.fts.common").bracketed_paste,
            },
            typescript = {
              command = { "ts-node" },
              format = require("iron.fts.common").bracketed_paste,
            },
            lua = {
              command = { "lua" },
              format = require("iron.fts.common").bracketed_paste,
            },
            r = {
              command = function()
                -- Prefer radian if available
                if vim.fn.executable("radian") == 1 then
                  return { "radian" }
                else
                  return { "R", "--no-save", "--no-restore" }
                end
              end,
              format = require("iron.fts.common").bracketed_paste,
              block_dividers = { "# %%", "#%%" }  -- R markdown style blocks
            },
            dart = {
              command = function()
                -- Use interactive package for Dart REPL
                -- Requires: dart pub global activate interactive
                if vim.fn.executable("interactive") == 1 then
                  return { "interactive" }
                else
                  -- Fallback to basic dart if interactive not installed
                  vim.notify("Install 'interactive' for better REPL: dart pub global activate interactive", vim.log.levels.WARN)
                  return { "dart" }
                end
              end,
              format = require("iron.fts.common").bracketed_paste,
              block_dividers = { "// ---", "//---" }  -- Dart style code blocks
            },
            sh = {
              command = { "bash" },
              format = require("iron.fts.common").bracketed_paste,
            },
            rust = {
              command = { "evcxr" },  -- Requires cargo install evcxr_repl
              format = require("iron.fts.common").bracketed_paste,
            },
            go = {
              command = { "gore" },  -- Requires go install github.com/x-motemen/gore/cmd/gore@latest
              format = require("iron.fts.common").bracketed_paste,
            },
            julia = {
              command = { "julia" },
              format = require("iron.fts.common").bracketed_paste,
              block_dividers = { "##" }  -- Julia style blocks
            },
            clojure = {
              command = function()
                -- Check for different Clojure REPLs
                if vim.fn.filereadable("deps.edn") == 1 then
                  return { "clj" }  -- Clojure CLI tools
                elseif vim.fn.filereadable("project.clj") == 1 then
                  return { "lein", "repl" }  -- Leiningen
                else
                  return { "clj" }  -- Default to Clojure CLI
                end
              end,
              format = require("iron.fts.common").bracketed_paste,
            },
            elixir = {
              command = { "iex" },
              format = require("iron.fts.common").bracketed_paste,
            },
            racket = {
              command = { "racket" },
              format = require("iron.fts.common").bracketed_paste,
            },
            scheme = {
              command = { "mit-scheme" },
              format = require("iron.fts.common").bracketed_paste,
            },
          },
          -- How the repl window will be displayed
          repl_open_cmd = view.split.vertical.botright(80),
        },
        -- Iron doesn't set keymaps by default anymore.
        -- Set up operator-pending mode "ctr" style mappings for Clojure-like RDD
        keymaps = {
          send_motion = "ctr",  -- Operator-pending mode: ctr3j, ctrap, ctr}, ctri{, etc.
          visual_send = "<leader>is",
          send_file = "<leader>if",
          send_line = "<leader>il",
          send_paragraph = "<leader>ip",
          send_until_cursor = "<leader>iu",
          send_mark = "<leader>im",
          send_code_block = "<leader>ib",  -- Send code block between dividers
          send_code_block_and_move = "<leader>in",  -- Send and move to next block
          mark_motion = "<leader>imc",
          mark_visual = "<leader>imc",
          remove_mark = "<leader>imd",
          cr = "<leader>i<cr>",
          interrupt = "<leader>i<space>",
          exit = "<leader>iq",
          clear = "<leader>ic",
        },
        -- If the highlight is on, you can change how it looks
        -- For the available options, check nvim_set_hl
        highlight = {
          italic = true
        },
        ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
      }

      -- Custom keymaps for better integration
      vim.keymap.set("n", "<leader>ir", "<cmd>IronRepl<cr>", { desc = "Toggle REPL" })
      vim.keymap.set("n", "<leader>iR", "<cmd>IronRestart<cr>", { desc = "Restart REPL" })
      vim.keymap.set("n", "<leader>if", "<cmd>IronFocus<cr>", { desc = "Focus REPL" })
      vim.keymap.set("n", "<leader>ih", "<cmd>IronHide<cr>", { desc = "Hide REPL" })
      
      -- Additional operator-pending mappings for RDD workflow
      -- Send text object (works with any text object: w, W, }, {, ap, i{, etc.)
      vim.keymap.set("n", "cp", "ctrip", { remap = true, desc = "Send paragraph" })
      vim.keymap.set("n", "cc", "ctr_", { remap = true, desc = "Send current line" })
      vim.keymap.set("n", "c{", "ctr{j", { remap = true, desc = "Send to previous empty line" })
      vim.keymap.set("n", "c}", "ctr}k", { remap = true, desc = "Send to next empty line" })
      
      -- Send and move to next line (Clojure-style evaluation)
      vim.keymap.set("n", "<leader>i<cr>", function()
        require("iron.core").send_line()
        vim.cmd("normal! j")
      end, { desc = "Send line and move down" })
      
      -- Send paragraph and move to next
      vim.keymap.set("n", "<leader>ip", function()
        require("iron.core").send_paragraph()
        vim.cmd("normal! }j")
      end, { desc = "Send paragraph and move" })
      
      -- Send form/expression under cursor (useful for Lisp-like languages)
      vim.keymap.set("n", "caf", "ctraf", { remap = true, desc = "Send outer function" })
      vim.keymap.set("n", "cif", "ctrif", { remap = true, desc = "Send inner function" })
      vim.keymap.set("n", "ca{", "ctra{", { remap = true, desc = "Send outer block" })
      vim.keymap.set("n", "ci{", "ctri{", { remap = true, desc = "Send inner block" })
      
      -- Simple expression evaluation (Clojure-style)
      vim.keymap.set("n", "ce", "ctr$", { remap = true, desc = "Eval to end of line" })
      vim.keymap.set("n", "cee", "cc", { remap = true, desc = "Eval current line" })
      vim.keymap.set("n", "cew", "ctriw", { remap = true, desc = "Eval word" })
      
      -- Visual mode enhancements
      vim.keymap.set("v", "<leader>is", function()
        require("iron.core").visual_send()
        vim.cmd("normal! gv")  -- Reselect visual selection
      end, { desc = "Send selection and reselect" })
      
      -- Code block navigation and sending (multi-language support)
      vim.keymap.set("n", "]b", function()
        -- Navigate to next code block based on filetype
        local ft = vim.bo.filetype
        if ft == "python" or ft == "r" or ft == "rmd" or ft == "quarto" then
          vim.fn.search("^# %%\\|^#%%", "W")
        elseif ft == "julia" then
          vim.fn.search("^##", "W")
        elseif ft == "dart" then
          vim.fn.search("^// ---\\|^//---", "W")
        else
          -- Generic code block pattern
          vim.fn.search("^# %%\\|^#%%\\|^##\\|^// ---", "W")
        end
      end, { desc = "Next code block" })
      
      vim.keymap.set("n", "[b", function()
        -- Navigate to previous code block based on filetype
        local ft = vim.bo.filetype
        if ft == "python" or ft == "r" or ft == "rmd" or ft == "quarto" then
          vim.fn.search("^# %%\\|^#%%", "bW")
        elseif ft == "julia" then
          vim.fn.search("^##", "bW")
        elseif ft == "dart" then
          vim.fn.search("^// ---\\|^//---", "bW")
        else
          -- Generic code block pattern
          vim.fn.search("^# %%\\|^#%%\\|^##\\|^// ---", "bW")
        end
      end, { desc = "Previous code block" })
      
    end,
  },

  -- Database management with vim-dadbod
  {
    "tpope/vim-dadbod",
    dependencies = {
      {
        "kristijanhusak/vim-dadbod-ui",
        dependencies = {
          { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" }, lazy = true },
        },
        cmd = {
          "DBUI",
          "DBUIToggle",
          "DBUIAddConnection",
          "DBUIFindBuffer",
        },
        init = function()
          -- Your DBUI configuration
          vim.g.db_ui_use_nerd_fonts = 1
          vim.g.db_ui_show_database_icon = 1
          vim.g.db_ui_force_echo_notifications = 1
          vim.g.db_ui_win_position = "right"
          vim.g.db_ui_winwidth = 40
          vim.g.db_ui_default_query = "SELECT * FROM "
          vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
          vim.g.db_ui_tmp_query_location = vim.fn.stdpath("data") .. "/db_ui/tmp"
          
          -- Configure icons
          vim.g.db_ui_icons = {
            expanded = {
              db = "▾ ",
              buffers = "▾ ",
              saved_queries = "▾ ",
              schemas = "▾ ",
              schema = "▾ ",
              tables = "▾ ",
              table = "▾ ",
            },
            collapsed = {
              db = "▸ ",
              buffers = "▸ ",
              saved_queries = "▸ ",
              schemas = "▸ ",
              schema = "▸ ",
              tables = "▸ ",
              table = "▸ ",
            },
            saved_query = "",
            new_query = "󰘶",
            tables = "󰅩",
            buffers = "󰯉",
            add_connection = "",
            connection_ok = "✓",
            connection_error = "✗",
          }
          
          -- Auto-completion for SQL
          vim.api.nvim_create_autocmd("FileType", {
            pattern = { "sql", "mysql", "plsql" },
            callback = function()
              -- Setup buffer-local completion with vim-dadbod-completion
              vim.b.completion_chains = {
                {
                  complete_items = {
                    'vim-dadbod-completion'
                  }
                }
              }
              
              -- Enable SQL-specific settings
              vim.opt_local.expandtab = true
              vim.opt_local.shiftwidth = 2
              vim.opt_local.tabstop = 2
              vim.opt_local.softtabstop = 2
            end,
          })
        end,
        keys = {
          { "<leader>od", "<cmd>DBUIToggle<cr>", desc = "Toggle Database UI" },
          { "<leader>odf", "<cmd>DBUIFindBuffer<cr>", desc = "Find Database Buffer" },
          { "<leader>oda", "<cmd>DBUIAddConnection<cr>", desc = "Add Database Connection" },
          { "<leader>odr", "<cmd>DBUIRenameBuffer<cr>", desc = "Rename Database Buffer" },
          { "<leader>odq", "<cmd>DBUILastQueryInfo<cr>", desc = "Last Query Info" },
        },
      },
    },
    cmd = {
      "DB",
      "DBCompleteTables",
      "DBCompleteColumns",
    },
    config = function()
      -- Setup vim-dadbod
      vim.g.dadbod_manage_dbext = 1
      
      -- Add some common database URLs as examples (you can customize these)
      -- PostgreSQL: postgresql://user:password@localhost:5432/dbname
      -- MySQL: mysql://user:password@localhost:3306/dbname
      -- SQLite: sqlite:///path/to/database.db
      
      -- Optional: Set up some default connections
      -- vim.g.dbs = {
      --   dev = 'postgresql://user:password@localhost:5432/devdb',
      --   prod = 'postgresql://user:password@prod-server:5432/proddb',
      --   local = 'sqlite:' .. vim.fn.expand('~/databases/local.db'),
      -- }
      
      -- SQL specific keymaps
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function()
          vim.keymap.set("n", "<leader>ode", "<Plug>(DBUI_ExecuteQuery)", { buffer = true, desc = "Execute Query" })
          vim.keymap.set("v", "<leader>ode", "<Plug>(DBUI_ExecuteQuery)", { buffer = true, desc = "Execute Query" })
          vim.keymap.set("n", "<leader>odw", "<Plug>(DBUI_SaveQuery)", { buffer = true, desc = "Save Query" })
          vim.keymap.set("n", "<leader>odp", "<Plug>(DBUI_EditBindParameters)", { buffer = true, desc = "Edit Bind Parameters" })
          vim.keymap.set("n", "<leader>ods", "<Plug>(DBUI_ToggleResultLayout)", { buffer = true, desc = "Toggle Result Layout" })
        end,
      })
    end,
  },

  -- Neotest for testing
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      -- Test adapters
      "nvim-neotest/neotest-python",
      "nvim-neotest/neotest-jest",
      "nvim-neotest/neotest-go",
      "rouge8/neotest-rust",
      "sidlatau/neotest-dart",
      "jfpedroza/neotest-elixir",
      "olimorris/neotest-rspec",
    },
    keys = {
      { "<leader>ctn", function() require("neotest").run.run() end, desc = "Run Nearest Test" },
      { "<leader>ctf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run File Tests" },
      { "<leader>ctr", function() require("neotest").run.run({ strategy = "integrated" }) end, desc = "Run Test (Integrated)" },
      { "<leader>ctR", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run All File Tests" },
      { "<leader>ctd", function() require("neotest").run.run({strategy = "dap"}) end, desc = "Debug Nearest Test" },
      { "<leader>cts", function() require("neotest").run.stop() end, desc = "Stop Test" },
      { "<leader>cta", function() require("neotest").run.attach() end, desc = "Attach to Test" },
      { "<leader>cto", function() require("neotest").output.open({ enter = true }) end, desc = "Open Test Output" },
      { "<leader>ctO", function() require("neotest").output_panel.toggle() end, desc = "Toggle Output Panel" },
      { "<leader>ctw", function() require("neotest").watch.toggle(vim.fn.expand("%")) end, desc = "Watch File Tests" },
      { "<leader>ctW", function() require("neotest").watch.toggle() end, desc = "Watch All Tests" },
      { "<leader>ctt", function() require("neotest").summary.toggle() end, desc = "Toggle Test Summary" },
      { "[t", function() require("neotest").jump.prev({ status = "failed" }) end, desc = "Previous Failed Test" },
      { "]t", function() require("neotest").jump.next({ status = "failed" }) end, desc = "Next Failed Test" },
    },
    config = function()
      local neotest = require("neotest")
      
      neotest.setup({
        -- Integrate with Overseer to run tests as tasks
        consumers = {
          overseer = require("neotest.consumers.overseer"),
        },
        overseer = {
          enabled = true,
          force_default = false,  -- Use overseer only when explicitly requested
        },
        adapters = {
          require("neotest-python")({
            dap = { justMyCode = false },
            runner = "pytest",
            python = ".venv/bin/python",
            args = { "--tb=short", "-v" },
          }),
          require("neotest-jest")({
            jestCommand = "npm test --",
            jestConfigFile = "jest.config.js",
            env = { CI = true },
            cwd = function(path)
              return vim.fn.getcwd()
            end,
          }),
          require("neotest-go")({
            experimental = {
              test_table = true,
            },
            args = { "-count=1", "-timeout=60s" }
          }),
          require("neotest-rust")({
            args = { "--no-capture" },
            dap_adapter = "codelldb",
          }),
          require("neotest-dart")({
            command = "flutter",
            use_lsp = true,
          }),
          require("neotest-elixir"),
          require("neotest-rspec")({
            rspec_cmd = function()
              return vim.tbl_flatten({
                "bundle",
                "exec",
                "rspec",
              })
            end,
          }),
        },
        discovery = {
          enabled = true,
          concurrent = 2,
        },
        diagnostic = {
          enabled = true,
          severity = vim.diagnostic.severity.ERROR,
        },
        floating = {
          border = "rounded",
          max_height = 0.8,
          max_width = 0.8,
          options = {}
        },
        highlights = {
          adapter_name = "NeotestAdapterName",
          border = "NeotestBorder",
          dir = "NeotestDir",
          expand_marker = "NeotestExpandMarker",
          failed = "NeotestFailed",
          file = "NeotestFile",
          focused = "NeotestFocused",
          indent = "NeotestIndent",
          marked = "NeotestMarked",
          namespace = "NeotestNamespace",
          passed = "NeotestPassed",
          running = "NeotestRunning",
          select_win = "NeotestWinSelect",
          skipped = "NeotestSkipped",
          target = "NeotestTarget",
          test = "NeotestTest",
          unknown = "NeotestUnknown",
          watching = "NeotestWatching",
        },
        icons = {
          child_indent = "│",
          child_prefix = "├",
          collapsed = "─",
          expanded = "╮",
          failed = "✖",
          final_child_indent = " ",
          final_child_prefix = "╰",
          non_collapsible = "─",
          passed = "✔",
          running = "⟳",
          running_animated = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
          skipped = "○",
          unknown = "?",
          watching = "👁",
        },
        output = {
          enabled = true,
          open_on_run = false,
        },
        output_panel = {
          enabled = true,
          open = "botright split | resize 10"
        },
        quickfix = {
          enabled = true,
          open = false,
        },
        run = {
          enabled = true,
        },
        running = {
          concurrent = true,
        },
        state = {
          enabled = true,
        },
        status = {
          enabled = true,
          signs = true,
          virtual_text = false,
        },
        strategies = {
          integrated = {
            height = 40,
            width = 120,
          },
        },
        summary = {
          animated = true,
          enabled = true,
          expand_errors = true,
          follow = true,
          mappings = {
            attach = "a",
            clear_marked = "M",
            clear_target = "T",
            debug = "d",
            debug_marked = "D",
            expand = { "<CR>", "<2-LeftMouse>" },
            expand_all = "e",
            jumpto = "i",
            mark = "m",
            next_failed = "]F",
            output = "o",
            prev_failed = "[F",
            run = "r",
            run_marked = "R",
            short = "O",
            stop = "u",
            target = "t",
            watch = "w",
          },
          open = "botright vsplit | vertical resize 50"
        },
        watch = {
          enabled = true,
          symbol_queries = {
            python = [[
              ;query
              ;Captures imports
              (import_statement) @import
              (import_from_statement) @import
            ]],
            go = [[
              ;query
              ;Captures imports
              (import_declaration) @import
              (import_spec) @import
            ]],
          },
        },
      })
      
      -- Overseer integration is handled by the consumer above
      -- Use <leader>ctr to run tests with overseer
    end,
  },

  -- Load LSP configuration
  require("lsp"),
}
