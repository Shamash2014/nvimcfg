return {
  {
    "stevearc/oil.nvim",
    lazy = true,
    opts = {
      default_file_explorer = true,
      view_options = {
        show_hidden = true,
      },
      keymaps = {
        ["g?"] = "actions.show_help",
        ["<CR>"] = "actions.select",
        ["<C-v>"] = "actions.select_vsplit",
        ["<C-h>"] = "actions.select_split",
        ["<C-t>"] = "actions.select_tab",
        ["<C-p>"] = "actions.preview",
        ["<C-c>"] = "actions.close",
        ["<C-r>"] = "actions.refresh",
        ["-"] = "actions.parent",
        ["_"] = "actions.open_cwd",
        ["`"] = "actions.cd",
        ["~"] = "actions.tcd",
        ["gs"] = "actions.change_sort",
        ["gx"] = "actions.open_external",
        ["g."] = "actions.toggle_hidden",
      },
    },
    keys = {
      { "<leader>-", "<cmd>Oil<cr>", desc = "Open file explorer" },
    },
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      win = {
        border = "single",
        padding = { 1, 2 },
      },
      spec = {
        { "<leader>a",  group = "AI / Avante" },
        { "<leader>b",  group = "Buffers" },
        { "<leader>c",  group = "Code / LSP" },
        { "<leader>f",  group = "Files" },
        { "<leader>g",  group = "Git" },
        { "<leader>gc", group = "Git Conflicts" },
        { "<leader>m",  group = "Marks" },
        { "<leader>p",  group = "Projects / Workspaces" },
        { "<leader>r",  group = "Runner / Overseer" },
        { "<leader>s",  group = "Search" },
        { "<leader>t",  group = "Terminal / Toggle" },
        { "<leader>w",  group = "Windows" },
      },
    },
  },
  {
    "ggandor/leap.nvim",
    lazy = true,
    keys = { "s", "S", "gs" },
    config = function()
      require("leap").add_default_mappings()
    end,
  },
  {
    "kylechui/nvim-surround",
    version = "*",
    lazy = true,
    keys = { "ys", "ds", "cs" },
    config = function()
      require("nvim-surround").setup({})
    end,
  },
  {
    "echasnovski/mini.bracketed",
    version = "*",
    lazy = true,
    keys = { "]", "[" },
    config = function()
      require("mini.bracketed").setup({
        buffer     = { suffix = "b", options = {} },
        comment    = { suffix = "c", options = {} },
        conflict   = { suffix = "x", options = {} },
        diagnostic = { suffix = "d", options = {} },
        file       = { suffix = "f", options = {} },
        indent     = { suffix = "i", options = {} },
        jump       = { suffix = "j", options = {} },
        location   = { suffix = "l", options = {} },
        oldfile    = { suffix = "o", options = {} },
        quickfix   = { suffix = "q", options = {} },
        treesitter = { suffix = "t", options = {} },
        undo       = { suffix = "u", options = {} },
        window     = { suffix = "w", options = {} },
        yank       = { suffix = "y", options = {} },
      })
    end,
  },
  {
    "echasnovski/mini.pairs",
    version = "*",
    lazy = true,
    event = "InsertEnter",
    config = function()
      require("mini.pairs").setup()
    end,
  },
  {
    "tjdevries/colorbuddy.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      local colorbuddy = require("colorbuddy")
      local Color = colorbuddy.Color
      local colors = colorbuddy.colors
      local Group = colorbuddy.Group
      local groups = colorbuddy.groups
      local styles = colorbuddy.styles

      -- Define monotone palette
      Color.new("bg", "#1a1a1a")
      Color.new("fg", "#ffffff")
      Color.new("comment", "#777777")
      Color.new("linenr", "#555555")
      Color.new("error", "#ff6b6b")
      Color.new("ui", "#333333")

      -- Base groups
      Group.new("Normal", colors.fg, colors.bg)
      Group.new("Comment", colors.comment, colors.none, styles.italic)
      Group.new("Error", colors.error, colors.none)
      Group.new("ErrorMsg", colors.error, colors.none)

      -- UI elements
      Group.new("LineNr", colors.linenr, colors.none)
      Group.new("CursorLineNr", colors.fg, colors.none)
      Group.new("StatusLine", colors.fg, colors.ui)
      Group.new("StatusLineNC", colors.comment, colors.ui)
      Group.new("WinSeparator", colors.ui, colors.none)
      Group.new("Visual", colors.none, colors.ui)
      Group.new("Search", colors.bg, colors.fg)

      -- All syntax groups to white (monotone)
      local syntax_groups = {
        "String", "Number", "Boolean", "Float", "Identifier", "Function",
        "Statement", "Conditional", "Repeat", "Label", "Operator", "Keyword",
        "Exception", "PreProc", "Include", "Define", "Macro", "PreCondit",
        "Type", "StorageClass", "Structure", "Typedef", "Special", "SpecialChar",
        "Tag", "Delimiter", "Debug", "Constant", "Variable"
      }

      for _, group in ipairs(syntax_groups) do
        Group.new(group, colors.fg, colors.none)
      end

      -- Oil.nvim specific groups to keep monotone
      Group.new("OilDir", colors.fg, colors.none)
      Group.new("OilFile", colors.fg, colors.none)
      Group.new("OilLink", colors.fg, colors.none)
      Group.new("OilSocket", colors.fg, colors.none)
      Group.new("OilCreate", colors.fg, colors.none)
      Group.new("OilDelete", colors.fg, colors.none)
      Group.new("OilMove", colors.fg, colors.none)
      Group.new("OilCopy", colors.fg, colors.none)
      Group.new("OilChange", colors.fg, colors.none)
    end,
  },
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ async = true })
        end,
        mode = "",
        desc = "Format buffer"
      }
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        rust = { "rustfmt" },
        go = { "goimports", "gofumpt" },
      },
      format_on_save = {
        timeout_ms = 1000,
        lsp_format = "fallback"
      },
    }
  },
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local lint = require("lint")

      lint.linters_by_ft = {
        javascript = { "eslint_d" },
        typescript = { "eslint_d" },
        python = { "ruff" },
        lua = { "luacheck" },
        go = { "golangcilint" },
        rust = { "clippy" },
      }

      local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufWritePost" }, {
        group = lint_augroup,
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = {
        enabled = true,
        size = 500 * 1024, -- 500KB threshold
        setup = function(ctx)
          vim.b.minianimate_disable = true
          vim.schedule(function()
            vim.bo[ctx.buf].syntax = ""
            vim.bo[ctx.buf].foldmethod = "manual"
          end)
        end,
      },
      notifier = { enabled = true },
      quickfile = { enabled = true },
      statuscolumn = { enabled = true },
      words = { enabled = true },
      picker = {
        layout = {
          preset = "bottom",
        },
        win = {
          input = {
            border = "rounded",
          },
          list = {
            border = "rounded",
            height = 12,
          },
          preview = {
            enabled = false,
          },
        },
      },
      terminal = {
        win = {
          style = "terminal",
          position = "bottom",
          height = 0.4,
          width = 1.0,
          border = "rounded",
        },
        bo = {
          buflisted = false,
        },
      },
    },
    keys = {
      {
        "<leader>tt",
        function()
          Snacks.terminal()
        end,
        desc = "Toggle Terminal",
      },
      {
        "<leader>tf",
        function()
          Snacks.terminal(nil, { cwd = vim.fn.expand("%:p:h") })
        end,
        desc = "Terminal (current file dir)",
      },
      {
        "<leader>gg",
        function()
          Snacks.terminal("lazygit", { win = { position = "right", width = 0.5 } })
        end,
        desc = "Lazygit",
      },
      {
        "<leader>tc",
        function()
          vim.ui.input({ prompt = "Command: " }, function(cmd)
            if cmd and cmd ~= "" then
              vim.g.last_terminal_command = cmd
              Snacks.terminal(cmd, { win = { position = "bottom", height = 0.3 } })
            end
          end)
        end,
        desc = "Run command in terminal (hsplit)",
      },
      {
        "<leader>tv",
        function()
          vim.ui.input({ prompt = "Command: " }, function(cmd)
            if cmd and cmd ~= "" then
              vim.g.last_terminal_command = cmd
              Snacks.terminal(cmd, { win = { position = "right", width = 0.5 } })
            end
          end)
        end,
        desc = "Run command in terminal (vsplit)",
      },
      {
        "<leader>bt",
        function()
          local all_bufs = vim.api.nvim_list_bufs()
          local items = {}

          for _, buf in ipairs(all_bufs) do
            if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
              local name = vim.api.nvim_buf_get_name(buf)
              local display_name = name:match("term://.*:(.*)") or "Terminal"
              local is_visible = vim.fn.bufwinnr(buf) ~= -1

              table.insert(items, {
                text = display_name .. (is_visible and " (visible)" or " (hidden)"),
                buf = buf,
                visible = is_visible
              })
            end
          end

          if #items == 0 then
            print("No terminals found")
            return
          end

          Snacks.picker.pick({
            items = items,
            prompt = "Select terminal:",
            preview = { enabled = false },
            layout = "vscode",
            on_select = function(choice)
              if choice then
                if choice.visible then
                  vim.api.nvim_set_current_win(vim.fn.bufwinnr(choice.buf))
                else
                  vim.cmd("vsplit")
                  vim.api.nvim_set_current_buf(choice.buf)
                  vim.cmd("startinsert")
                end
              end
            end
          })
        end,
        desc = "Pick terminal",
      },
      {
        "<leader>ca",
        vim.lsp.buf.code_action,
        desc = "Code action",
      },
      {
        "<leader>tr",
        function()
          local last_cmd = vim.g.last_terminal_command
          if last_cmd and last_cmd ~= "" then
            Snacks.terminal(last_cmd)
          else
            vim.notify("No previous terminal command found")
          end
        end,
        desc = "Rerun last terminal command",
      },
      {
        "<leader>th",
        function()
          local current_buf = vim.api.nvim_get_current_buf()
          if vim.bo[current_buf].buftype == "terminal" then
            vim.api.nvim_win_hide(vim.api.nvim_get_current_win())
          else
            print("Not in a terminal buffer")
          end
        end,
        desc = "Hide current terminal",
      },
      {
        "<leader>ff",
        function()
          Snacks.picker.files({ preview = { enabled = false }, layout = "vscode" })
        end,
        desc = "Find Files",
      },
      {
        "<leader>sg",
        function()
          Snacks.picker.grep({ tool = "ast-grep", preview = { enabled = false }, layout = "vscode" })
        end,
        desc = "AST Grep",
      },
      {
        "<leader>s*",
        function()
          local word = vim.fn.expand("<cword>")
          Snacks.picker.grep({ search = word, preview = { enabled = false }, layout = "vscode" })
        end,
        desc = "Grep word under cursor",
      },
      {
        "<leader>bb",
        function()
          Snacks.picker.buffers({ preview = { enabled = false }, layout = "vscode" })
        end,
        desc = "Buffers",
      },
      {
        "<leader>fr",
        function()
          Snacks.picker.recent({ preview = { enabled = false }, layout = "vscode" })
        end,
        desc = "Recent Files",
      },
      {
        "<leader>sa",
        function()
          Snacks.picker.lsp_symbols({ preview = { enabled = false }, layout = "vscode", workspace = true })
        end,
        desc = "Workspace Symbols",
      },
      {
        "<leader>ss",
        function()
          Snacks.picker.lsp_symbols({ preview = { enabled = false }, buf = 0, layout = "vscode" })
        end,
        desc = "Buffer Symbols",
      },
    },
  },
  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
    lazy = true,
    event = "InsertEnter",
    build = "make install_jsregexp",
    dependencies = {
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local luasnip = require("luasnip")
      
      -- Load snippets from friendly-snippets
      require("luasnip.loaders.from_vscode").lazy_load()
      
      -- Load custom snippets
      require("luasnip.loaders.from_lua").lazy_load({ paths = { vim.fn.stdpath("config") .. "/snippets" } })
      
      luasnip.config.setup({
        region_check_events = "InsertEnter",
        delete_check_events = "InsertLeave",
        enable_autosnippets = false,
        store_selection_keys = "<Tab>",
        update_events = { "TextChanged", "TextChangedI" },
        history = true,
        ext_opts = {
          [require("luasnip.util.types").choiceNode] = {
            active = {
              virt_text = { { "●", "Special" } },
            },
          },
        },
      })
      
      -- Keybindings for snippet expansion and navigation
      vim.keymap.set({ "i", "s" }, "<C-l>", function()
        if luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        end
      end, { desc = "Expand or jump to next snippet placeholder" })
      
      vim.keymap.set({ "i", "s" }, "<C-h>", function()
        if luasnip.jumpable(-1) then
          luasnip.jump(-1)
        end
      end, { desc = "Jump to previous snippet placeholder" })
      
      vim.keymap.set({ "i", "s" }, "<C-e>", function()
        if luasnip.choice_active() then
          luasnip.change_choice(1)
        end
      end, { desc = "Change snippet choice" })
    end,
  },
  {
    "supermaven-inc/supermaven-nvim",
    lazy = true,
    event = "InsertEnter",
    config = function()
      require("supermaven-nvim").setup({
        keymaps = {
          accept_suggestion = "<Tab>",
          clear_suggestion = "<C-]>",
          accept_word = "<C-j>",
        },
        ignore_filetypes = { 
          "TelescopePrompt", "oil", "netrw", "help", "qf", "quickfix", "alpha", 
          "dashboard", "neo-tree", "Trouble", "trouble", "lazy", "mason", "notify",
          "toggleterm", "floaterm", "lazyterm", "terminal", "prompt", "noice",
          "NvimTree", "fzf", "fzf-lua", "snacks_picker", "snacks_terminal",
          "snacks_notifier", "snacks_lazygit", "dap-repl", "dapui_breakpoints",
          "dapui_console", "dapui_scopes", "dapui_stacks", "dapui_watches",
          "overseer", "gitcommit", "git", "fugitive", "fugitiveblame",
          "startuptime", "checkhealth", "man", "lspinfo", "null-ls-info",
          "conform", "lint", "copilot", "copilot-chat", "avante", "avante-chat"
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
  {
    "stevearc/overseer.nvim",
    lazy = true,
    cmd = {
      "OverseerOpen",
      "OverseerClose",
      "OverseerToggle",
      "OverseerRunCmd",
      "OverseerRun",
      "OverseerInfo",
      "OverseerBuild",
      "OverseerQuickAction",
      "OverseerTaskAction",
      "OverseerClearCache",
    },
    opts = {
      strategy = "jobstart",
      task_list = {
        direction = "bottom",
        min_height = 25,
        max_height = 25,
        default_detail = 1,
        bindings = {
          ["<C-h>"] = false,
          ["<C-j>"] = false,
          ["<C-k>"] = false,
          ["<C-l>"] = false,
        },
      },
      form = {
        border = "rounded",
        win_opts = {
          winblend = 0,
        },
      },
      confirm = {
        border = "rounded",
        win_opts = {
          winblend = 0,
        },
      },
      task_win = {
        border = "rounded",
        win_opts = {
          winblend = 0,
        },
      },
      component_aliases = {
        default = {
          "display_duration",
          "on_output_summarize",
          "on_exit_set_status",
          "on_complete_notify",
        },
      },
      -- Add error handling for window management
      auto_scroll = true,
      auto_detect_success_color = true,
    },
    config = function(_, opts)
      require("overseer").setup(opts)
      -- Load custom templates
      require("overseer-templates")
    end,
    keys = {
      { "<leader>rt", "<cmd>OverseerToggle<cr>",      desc = "Toggle task list" },
      {
        "<leader>rr",
        function()
          require("overseer-snacks").run_task_picker()
        end,
        desc = "Run task (snacks picker)"
      },
      {
        "<leader>ra",
        function()
          vim.cmd("OverseerTaskAction")
        end,
        desc = "Task action"
      },
      { "<leader>ri", "<cmd>OverseerInfo<cr>",        desc = "Overseer info" },
      { "<leader>rb", "<cmd>OverseerBuild<cr>",       desc = "Build task" },
      { "<leader>rq", "<cmd>OverseerQuickAction<cr>", desc = "Quick action" },
      {
        "<leader>rx",
        function()
          -- Simple approach - let user use overseer's built-in task management
          vim.cmd("OverseerToggle")
          vim.notify("Use 'd' to delete tasks in the overseer window")
        end,
        desc = "Delete task"
      },
      { "<leader>rc", "<cmd>OverseerClearCache<cr>", desc = "Clear cache" },
      {
        "<leader>rh",
        function()
          vim.cmd("OverseerToggle")
          vim.notify("Task history available in overseer window")
        end,
        desc = "Task history"
      },
      {
        "<leader>rC",
        function()
          vim.ui.input({ prompt = "Command: " }, function(cmd)
            if cmd and cmd ~= "" then
              require("overseer").run_template({
                name = "terminal command",
                params = { cmd = cmd }
              })
            end
          end)
        end,
        desc = "Run custom command"
      },
      {
        "<leader>rs",
        function()
          vim.ui.input({ prompt = "Script path: " }, function(script)
            if script and script ~= "" then
              require("overseer").run_template({
                name = "shell script",
                params = { script = script }
              })
            end
          end)
        end,
        desc = "Run script"
      },
      {
        "<leader>rd",
        function()
          local templates = {
            "docker compose up",
            "docker compose down",
            "docker compose build",
            "docker compose logs",
            "docker compose exec",
            "docker run",
            "docker build",
            "docker exec",
            "docker logs"
          }

          Snacks.picker.pick({
            items = templates,
            prompt = "Docker command:",
            preview = { enabled = false },
            layout = "vscode",
            on_select = function(choice)
              if choice then
                require("overseer").run_template({ name = choice })
              end
            end
          })
        end,
        desc = "Docker commands"
      },
    },
  },
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = true,
    version = false,
    opts = {
      provider = "lmstudio",
      auto_suggestions_provider = "lmstudio",
      providers = {
        lmstudio = {
          __inherited_from = "openai",
          api_key_name = "",
          endpoint = "http://127.0.0.1:1234/v1",
          model = "mistralai/devstral-small-2505",
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
        diff = {
          ours = "co",
          theirs = "ct",
          all_theirs = "ca",
          both = "cb",
          cursor = "cc",
          next = "]x",
          prev = "[x",
        },
        suggestion = {
          accept = "<M-l>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
        jump = {
          next = "]]",
          prev = "[[",
        },
      },
      hints = { enabled = true },
      windows = {
        position = "right",
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
      "nvim-treesitter/nvim-treesitter",
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
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
    keys = {
      {
        "<leader>aa",
        function()
          require("avante.api").ask()
        end,
        desc = "Avante: Ask",
        mode = { "n", "v" },
      },
      {
        "<leader>ar",
        function()
          require("avante.api").refresh()
        end,
        desc = "Avante: Refresh",
      },
      {
        "<leader>ae",
        function()
          require("avante.api").edit()
        end,
        desc = "Avante: Edit",
        mode = "v",
      },
    },
  },
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    lazy = true,
    event = "BufRead",
    config = function()
      require("git-conflict").setup({
        default_mappings = true,
        default_commands = true,
        disable_diagnostics = false,
        list_opener = "copen",
        highlights = {
          incoming = "DiffAdd",
          current = "DiffText",
        },
      })
    end,
    keys = {
      {
        "<leader>gco",
        "<cmd>GitConflictChooseOurs<cr>",
        desc = "Choose ours (current branch)",
      },
      {
        "<leader>gct",
        "<cmd>GitConflictChooseTheirs<cr>",
        desc = "Choose theirs (incoming branch)",
      },
      {
        "<leader>gcb",
        "<cmd>GitConflictChooseBoth<cr>",
        desc = "Choose both",
      },
      {
        "<leader>gc0",
        "<cmd>GitConflictChooseNone<cr>",
        desc = "Choose none",
      },
      {
        "<leader>gcn",
        "<cmd>GitConflictNextConflict<cr>",
        desc = "Next conflict",
      },
      {
        "<leader>gcp",
        "<cmd>GitConflictPrevConflict<cr>",
        desc = "Previous conflict",
      },
      {
        "<leader>gcq",
        "<cmd>GitConflictListQf<cr>",
        desc = "List conflicts in quickfix",
      },
    },
  },
  {
    "natecraddock/workspaces.nvim",
    lazy = true,
    cmd = { "WorkspacesAdd", "WorkspacesRemove", "WorkspacesOpen" },
    config = function()
      require("workspaces").setup({
        hooks = {
          open = function()
            require("snacks").picker.files()
          end,
        },
      })
    end,
    keys = {
      {
        "<leader>pa",
        function()
          require("workspaces").add()
        end,
        desc = "Add workspace",
      },
      {
        "<leader>pr",
        function()
          require("workspaces").remove()
        end,
        desc = "Remove workspace",
      },
      {
        "<leader>pp",
        function()
          local workspaces = require("workspaces")
          local ws_list = workspaces.get()
          if #ws_list == 0 then
            vim.notify("No workspaces configured")
            return
          end

          Snacks.picker.pick("workspace", {
            items = ws_list,
            format = function(item)
              return item.name .. " (" .. item.path .. ")"
            end,
            on_select = function(choice)
              workspaces.open(choice.name)
            end
          })
        end,
        desc = "Switch workspace",
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = true,
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua", "vim", "vimdoc", "query", "markdown", "markdown_inline",
          "javascript", "typescript", "python", "rust", "go", "swift"
        },
        auto_install = true,
        highlight = {
          enable = true,
          disable = function(_, buf)
            local max_filesize = 500 * 1024 -- 500KB
            local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
            if ok and stats and stats.size > max_filesize then
              return true
            end
          end,
        },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "<C-space>",
            node_incremental = "<C-space>",
            scope_incremental = "<C-s>",
            node_decremental = "<M-space>",
          },
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
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]b"] = "@block.outer",
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
              ["]B"] = "@block.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[b"] = "@block.outer",
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
              ["[B"] = "@block.outer",
            },
          },
        },
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    dependencies = "nvim-treesitter/nvim-treesitter",
    event = "VeryLazy",
  },
}
