-- Editor plugins: LSP, formatting, and linting configuration

return {
  -- EditorConfig support
  {
    "gpanders/editorconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
  },

  -- Code formatting (primary engine)
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
        desc = "Format buffer",
      },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        vue = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        less = { "prettier" },
        html = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        yml = { "prettier" },
        markdown = { "prettier" },
        dart = { "dart_format" },
        elixir = { "mix" },
        rust = { "rustfmt" },
        c = { "clang_format" },
        cpp = { "clang_format" },
        r = { "styler" },
        rmd = { "styler" },
        quarto = { "injected" },
        astro = { "prettier" },
        go = { "goimports", "gofumpt" },
        dockerfile = { "prettier" },
        ["yaml.docker-compose"] = { "prettier" },
        ruby = { "rubocop" },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_format = "fallback", -- Use LSP only when conform formatter unavailable
      },
      formatters = {
        -- Respect EditorConfig settings
        prettier = {
          prepend_args = { "--config-precedence", "file-override" },
        },
        stylua = {
          prepend_args = function()
            return { "--respect-ignores" }
          end,
        },
      },
    },
  },

  -- Linting (ESLint focused)
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local lint = require("lint")

      lint.linters_by_ft = {
        python = { "ruff" },
        javascript = { "eslint" },
        typescript = { "eslint" },
        javascriptreact = { "eslint" },
        typescriptreact = { "eslint" },
        vue = { "eslint" },
        dart = { "dart_analyze" },
        elixir = { "credo" },
        rust = { "clippy" },
        c = { "cppcheck" },
        cpp = { "cppcheck" },
        go = { "golangcilint" },
        yaml = { "yamllint" },
        dockerfile = { "hadolint" },
        html = { "htmlhint" },
        css = { "stylelint" },
        scss = { "stylelint" },
        less = { "stylelint" },
        ruby = { "rubocop" },
      }

      -- Configure eslint to use project config
      lint.linters.eslint.cmd = "npx"
      lint.linters.eslint.args = {
        "eslint",
        "--format",
        "json",
        "--stdin",
        "--stdin-filename",
        function()
          return vim.api.nvim_buf_get_name(0)
        end,
      }

      -- Configure dart_analyze for proper project detection
      lint.linters.dart_analyze = {
        cmd = "dart",
        stdin = true,
        args = {
          "analyze",
          "--fatal-infos",
          "--fatal-warnings",
        },
        stream = "stderr",
        ignore_exitcode = true,
        parser = function(output, bufnr)
          local diagnostics = {}
          local lines = vim.split(output, "\n")

          for _, line in ipairs(lines) do
            local level, msg, file, lnum, col = line:match("^%s*(%w+)%s*•%s*(.-)%s*•%s*(.-)%s*:(%d+):(%d+)")
            if level and msg and lnum and col then
              local severity = vim.diagnostic.severity.INFO
              if level == "error" then
                severity = vim.diagnostic.severity.ERROR
              elseif level == "warning" then
                severity = vim.diagnostic.severity.WARN
              elseif level == "info" then
                severity = vim.diagnostic.severity.INFO
              end

              table.insert(diagnostics, {
                lnum = tonumber(lnum) - 1,
                col = tonumber(col) - 1,
                message = msg,
                severity = severity,
                source = "dart_analyze",
              })
            end
          end

          return diagnostics
        end,
      }

      -- Auto-lint on save and text change
      local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function()
          -- Only lint JS/TS files or files where we have specific linters
          local ft = vim.bo.filetype
          if lint.linters_by_ft[ft] then
            lint.try_lint()
          end
        end,
      })

      -- Also lint when entering a buffer
      vim.api.nvim_create_autocmd("BufReadPost", {
        group = lint_augroup,
        callback = function()
          vim.defer_fn(function()
            local ft = vim.bo.filetype
            if lint.linters_by_ft[ft] then
              lint.try_lint()
            end
          end, 100)
        end,
      })
    end,
    keys = {
      {
        "<leader>cl",
        function()
          require("lint").try_lint()
        end,
        desc = "Run linter",
      },
    },
  },

  -- Unified AI Assistant Interface - Avante (Chat-style AI)
  {
    "yetone/avante.nvim",
    cmd = { "AvanteAsk", "AvanteChat", "AvanteToggle" },
    version = false,
    build = "make",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "echasnovski/mini.icons",
      "ravitemer/mcphub.nvim", -- MCP integration
    },
    opts = {
      provider = "claude",
      auto_suggestions_provider = "copilot",
      providers = {
        claude = {
          endpoint = "https://api.anthropic.com/v1/messages",
          model = "claude-3-5-sonnet-20241022",
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
      -- MCP integration
      system_prompt = function()
        local ok, hub = pcall(function()
          return require("mcphub").get_hub_instance()
        end)
        if ok and hub then
          return hub:get_active_servers_prompt()
        end
        return ""
      end,
      custom_tools = function()
        local ok, mcphub_extension = pcall(require, "mcphub.extensions.avante")
        if ok then
          return {
            mcphub_extension.mcp_tool(),
          }
        end
        return {}
      end,
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
        submit = {
          normal = "<CR>",
          insert = "<C-s>",
        },
        sidebar = {
          switch_windows = "<Tab>",
          reverse_switch_windows = "<S-Tab>",
        },
      },
    },
    config = function(_, opts)
      require("avante").setup(opts)
    end,
    keys = {
      {
        "<leader>ac",
        function()
          require("avante.api").ask()
        end,
        desc = "Avante Chat",
        mode = { "n", "v" },
      },
      {
        "<leader>ae",
        function()
          require("avante.api").edit()
        end,
        desc = "Avante Edit",
        mode = "v",
      },
      {
        "<leader>ar",
        function()
          require("avante.api").refresh()
        end,
        desc = "Avante Refresh",
      },
      {
        "<leader>at",
        function()
          require("avante.api").toggle()
        end,
        desc = "Avante Toggle",
      },
    },
  },

  -- Import cost analysis
  {
    "barrett-ruth/import-cost.nvim",
    build = function()
      -- Check if npm is available before attempting install
      if vim.fn.executable("npm") == 1 then
        vim.fn.system("cd " .. vim.fn.stdpath("data") .. "/lazy/import-cost.nvim && sh install.sh npm")
      else
        vim.notify("npm not found. Skipping import-cost.nvim installation.", vim.log.levels.WARN)
      end
    end,
    ft = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
    cmd = { "ImportCost", "ImportCostToggle" },
    cond = function()
      -- Only load if npm is available
      return vim.fn.executable("npm") == 1
    end,
    config = function()
      -- Check if the required script exists before setting up
      local script_path = vim.fn.stdpath("data") .. "/lazy/import-cost.nvim/import-cost/index.js"
      if vim.fn.filereadable(script_path) == 1 then
        require("import-cost").setup({
          filetypes = {
            "javascript",
            "typescript",
            "javascriptreact",
            "typescriptreact",
          },
          format = {
            virtual_text = "%s • %s",
          },
        })
      else
        vim.notify("import-cost.nvim script not found. Run :Lazy build import-cost.nvim", vim.log.levels.WARN)
      end
    end,
    keys = {
      {
        "<leader>ic",
        function()
          local script_path = vim.fn.stdpath("data") .. "/lazy/import-cost.nvim/import-cost/index.js"
          if vim.fn.filereadable(script_path) == 1 then
            vim.cmd("ImportCost")
          else
            vim.notify("import-cost.nvim not properly installed. Run :Lazy build import-cost.nvim", vim.log.levels.ERROR)
          end
        end,
        desc = "Import Cost",
        ft = { "javascript", "typescript", "javascriptreact", "typescriptreact" }
      },
      {
        "<leader>it",
        function()
          local script_path = vim.fn.stdpath("data") .. "/lazy/import-cost.nvim/import-cost/index.js"
          if vim.fn.filereadable(script_path) == 1 then
            vim.cmd("ImportCostToggle")
          else
            vim.notify("import-cost.nvim not properly installed. Run :Lazy build import-cost.nvim", vim.log.levels.ERROR)
          end
        end,
        desc = "Toggle Import Cost",
        ft = { "javascript", "typescript", "javascriptreact", "typescriptreact" }
      },
    },
  },

  -- Symbol usage and unused imports detection
  {
    "Wansmer/symbol-usage.nvim",
    event = "BufReadPre",
    config = function()
      require("symbol-usage").setup({
        ---@type table<string, any> `nvim_set_hl`-like options for highlight group
        hl = { fg = "#bb9af7" },             -- Purple to match theme
        ---@type lsp.SymbolKind[] Symbol kinds what need to be count (see `lsp.SymbolKind`)
        kinds = { 1, 6, 12, 14, 16, 5, 13 }, -- Function, Method, Variable, Property, Field, Class, Interface
        ---@type 'above'|'end_of_line'|'textwidth'|'signcolumn' `above` by default
        vt_position = "end_of_line",
        ---Text to display when request is pending. If `false`, extmark will not be
        ---created until the request is finished. Recommended to use with `above`
        ---vt_position to avoid "jumping lines".
        ---@type string|false
        request_pending_text = false,
        ---Text to display when there are no references. If `false`, extmark will not be created.
        ---@type string|false
        references_text = false,
        ---Text to display when there are no definitions. If `false`, extmark will not be created.
        ---@type string|false
        definition_text = false,
        ---Text to display when there are no implementations. If `false`, extmark will not be created.
        ---@type string|false
        implementation_text = false,
        ---@type function|false Function to filter symbols by their names. Filters out by default:
        ---`__*` - symbols with double underscore prefix
        ---`_*` - symbols with underscore prefix in Python
        symbols_filter = function(symbol)
          return not string.match(symbol.name, "^__")
        end,
        ---Additional filter for references count. References count lower this value will be ignored.
        ---@type integer
        references_threshold = 0,
        ---@type function(): string|false Text to display as suffix. If `false`, no suffix is displayed.
        text_format = function(symbol)
          local fragments = {}

          -- Add reference count with parentheses
          if symbol.references and symbol.references > 0 then
            local usage = symbol.references == 1 and "ref" or "refs"
            table.insert(fragments, ("%d %s"):format(symbol.references, usage))
          end

          -- Add definition indicator
          if symbol.definition then
            table.insert(fragments, "def")
          end

          -- Add implementation indicator
          if symbol.implementation then
            table.insert(fragments, "impl")
          end

          return #fragments > 0 and ("(%s)"):format(table.concat(fragments, ", ")) or ""
        end,
      })
    end,
    keys = {
      { "<leader>su", "<cmd>SymbolUsageToggle<cr>",  desc = "Toggle Symbol Usage" },
      { "<leader>sr", "<cmd>SymbolUsageRefresh<cr>", desc = "Refresh Symbol Usage" },
    },
  },

  -- Virtual line diagnostics disabled in favor of diagflow.nvim
  -- {
  --   "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
  --   event = "LspAttach",
  --   config = function()
  --     require("lsp_lines").setup()
  --
  --     -- Disable virtual text (we'll use lsp_lines instead)
  --     vim.diagnostic.config({
  --       virtual_text = false,
  --       virtual_lines = { only_current_line = true },
  --     })
  --
  --     -- Auto-toggle: show diagnostics only for current line
  --     local group = vim.api.nvim_create_augroup("lsp_lines_current_line", { clear = true })
  --
  --     vim.api.nvim_create_autocmd("CursorMoved", {
  --       group = group,
  --       callback = function()
  --         -- Hide all virtual lines first
  --         vim.diagnostic.config({ virtual_lines = false })
  --
  --         -- Show virtual lines only for current line if it has diagnostics
  --         local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  --         local diagnostics = vim.diagnostic.get(0, { lnum = line })
  --
  --         if #diagnostics > 0 then
  --           vim.diagnostic.config({ virtual_lines = { only_current_line = true } })
  --         end
  --       end,
  --     })
  --
  --     -- Also show on CursorHold for a bit more stability
  --     vim.api.nvim_create_autocmd("CursorHold", {
  --       group = group,
  --       callback = function()
  --         local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  --         local diagnostics = vim.diagnostic.get(0, { lnum = line })
  --
  --         if #diagnostics > 0 then
  --           vim.diagnostic.config({ virtual_lines = { only_current_line = true } })
  --         else
  --           vim.diagnostic.config({ virtual_lines = false })
  --         end
  --       end,
  --     })
  --   end,
  --   keys = {
  --     {
  --       "<leader>dl",
  --       function()
  --         local config = vim.diagnostic.config() or {}
  --         if config.virtual_lines then
  --           vim.diagnostic.config({ virtual_lines = false })
  --         else
  --           vim.diagnostic.config({ virtual_lines = { only_current_line = true } })
  --         end
  --       end,
  --       desc = "Toggle LSP lines",
  --     },
  --   },
  -- },

  -- Flutter tools integration
  {
    "akinsho/flutter-tools.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "stevearc/dressing.nvim",
    },
    ft = "dart",
    opts = {
      ui = {
        border = "single",
        notification_style = "native",
      },
      decorations = {
        statusline = {
          app_version = false,
          device = true,
          project_config = false,
        },
      },
      debugger = {
        enabled = true,
        run_via_dap = true,
        exception_breakpoints = {},
        evaluate_to_string_in_debug_views = true,
      },
      fvm = false,
      flutter_lookup_cmd = "asdf where flutter",
      widget_guides = {
        enabled = true,
      },
      closing_tags = {
        highlight = "Comment",
        prefix = " // ",
        enabled = true
      },
      dev_log = {
        enabled = true,
        notify_errors = false,
        open_cmd = "tabedit",
      },
      dev_tools = {
        autostart = false,
        auto_open_browser = false,
      },
      outline = {
        open_cmd = "30vnew",
        auto_open = false,
      },
      lsp = {
        color = {
          enabled = false,
          background = false,
          background_color = nil,
          foreground = false,
          virtual_text = true,
          virtual_text_str = "■",
        },
        capabilities = function(config)
          config.textDocument.codeAction = {
            dynamicRegistration = true,
            codeActionLiteralSupport = {
              codeActionKind = {
                valueSet = {
                  "source.organizeImports.dart",
                  "source.fixAll.dart",
                  "quickfix.dart",
                  "refactor.dart",
                }
              }
            }
          }
          return config
        end,
        settings = {
          showTodos = true,
          completeFunctionCalls = true,
          analysisExcludedFolders = {
            vim.fn.expand("~/.pub-cache"),
            vim.fn.expand("~/fvm/versions"),
            vim.fn.expand("/opt/homebrew"),
            vim.fn.expand("$HOME/AppData/Local/Pub/Cache"),
            vim.fn.expand("$HOME/.pub-cache"),
            vim.fn.expand("/Applications/Flutter"),
          },
          renameFilesWithClasses = "prompt",
          enableSnippets = true,
          updateImportsOnRename = true,
        }
      }
    },
    keys = {
      { "<leader>ofr", "<cmd>FlutterRun<cr>",           desc = "Flutter Run" },
      { "<leader>ofR", "<cmd>FlutterRestart<cr>",       desc = "Flutter Restart" },
      { "<leader>ofq", "<cmd>FlutterQuit<cr>",          desc = "Flutter Quit" },
      { "<leader>ofh", "<cmd>FlutterReload<cr>",        desc = "Flutter Hot Reload" },
      { "<leader>ofH", "<cmd>FlutterRestart<cr>",       desc = "Flutter Hot Restart" },
      { "<leader>ofd", "<cmd>FlutterDevices<cr>",       desc = "Flutter Devices" },
      { "<leader>ofe", "<cmd>FlutterEmulators<cr>",     desc = "Flutter Emulators" },
      { "<leader>ofo", "<cmd>FlutterOutlineToggle<cr>", desc = "Flutter Outline" },
      { "<leader>ofD", "<cmd>FlutterDevTools<cr>",      desc = "Flutter DevTools" },
      { "<leader>ofL", "<cmd>FlutterLogClear<cr>",      desc = "Flutter Log Clear" },
      { "<leader>ofs", "<cmd>FlutterSuper<cr>",         desc = "Flutter Super" },
      { "<leader>ofg", "<cmd>FlutterPubGet<cr>",        desc = "Flutter Pub Get" },
      { "<leader>ofG", "<cmd>FlutterPubUpgrade<cr>",    desc = "Flutter Pub Upgrade" },
      { "<leader>ofc", "<cmd>FlutterClean<cr>",         desc = "Flutter Clean" },
      { "<leader>oft", "<cmd>FlutterTest<cr>",          desc = "Flutter Test" },
      { "<leader>ofT", "<cmd>FlutterTestAll<cr>",       desc = "Flutter Test All" },
      { "<leader>ofv", "<cmd>FlutterVersion<cr>",       desc = "Flutter Version" },
      { "<leader>ofp", "<cmd>FlutterPubDeps<cr>",       desc = "Flutter Pub Deps" },
      { "<leader>ofn", "<cmd>FlutterRename<cr>",        desc = "Flutter Rename" },
      { "<leader>ofi", "<cmd>FlutterScreenshot<cr>",    desc = "Flutter Screenshot" },
    },
    config = function(_, opts)
      require("flutter-tools").setup(opts)

      -- Enhanced which-key integration for Flutter
      local ok, wk = pcall(require, "which-key")
      if ok then
        wk.add({
          { "<leader>of",  group = "flutter",    ft = "dart" },
          { "<leader>ofr", desc = "run",         ft = "dart" },
          { "<leader>ofR", desc = "restart",     ft = "dart" },
          { "<leader>ofq", desc = "quit",        ft = "dart" },
          { "<leader>ofh", desc = "hot reload",  ft = "dart" },
          { "<leader>ofH", desc = "hot restart", ft = "dart" },
          { "<leader>ofd", desc = "devices",     ft = "dart" },
          { "<leader>ofe", desc = "emulators",   ft = "dart" },
          { "<leader>ofo", desc = "outline",     ft = "dart" },
          { "<leader>ofD", desc = "devtools",    ft = "dart" },
          { "<leader>ofL", desc = "log clear",   ft = "dart" },
          { "<leader>ofs", desc = "super",       ft = "dart" },
          { "<leader>ofg", desc = "pub get",     ft = "dart" },
          { "<leader>ofG", desc = "pub upgrade", ft = "dart" },
          { "<leader>ofc", desc = "clean",       ft = "dart" },
          { "<leader>oft", desc = "test",        ft = "dart" },
          { "<leader>ofT", desc = "test all",    ft = "dart" },
          { "<leader>ofv", desc = "version",     ft = "dart" },
          { "<leader>ofp", desc = "pub deps",    ft = "dart" },
          { "<leader>ofn", desc = "rename",      ft = "dart" },
          { "<leader>ofi", desc = "screenshot",  ft = "dart" },
        })
      end
    end,
  },

  -- Debug Adapter Protocol
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "theHamsta/nvim-dap-virtual-text",
      "nvim-neotest/nvim-nio",
      {
        "miroshQa/debugmaster.nvim",
        config = function()
          local dm = require("debugmaster")
          -- Enable Neovim Lua debugging integration
          dm.plugins.osv_integration.enabled = true
        end,
      },
    },
    keys = {
      { "<leader>db", function() require("dap").toggle_breakpoint() end,                                    desc = "Toggle Breakpoint" },
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "Conditional Breakpoint" },
      { "<leader>dc", function() require("dap").continue() end,                                             desc = "Continue" },
      { "<leader>da", function() require("dap").continue({ before = get_args }) end,                        desc = "Run with Args" },
      { "<leader>dC", function() require("dap").run_to_cursor() end,                                        desc = "Run to Cursor" },
      { "<leader>dg", function() require("dap").goto_() end,                                                desc = "Go to Line (No Execute)" },
      { "<leader>di", function() require("dap").step_into() end,                                            desc = "Step Into" },
      { "<leader>dj", function() require("dap").down() end,                                                 desc = "Down" },
      { "<leader>dk", function() require("dap").up() end,                                                   desc = "Up" },
      { "<leader>dl", function() require("dap").run_last() end,                                             desc = "Run Last" },
      { "<leader>do", function() require("dap").step_out() end,                                             desc = "Step Out" },
      { "<leader>dO", function() require("dap").step_over() end,                                            desc = "Step Over" },
      { "<leader>dp", function() require("dap").pause() end,                                                desc = "Pause" },
      { "<leader>dr", function() require("dap").repl.toggle() end,                                          desc = "Toggle REPL" },
      { "<leader>ds", function() require("dap").session() end,                                              desc = "Session" },
      { "<leader>dt", function() require("dap").terminate() end,                                            desc = "Terminate" },
      { "<leader>dd", function() require("debugmaster").mode.toggle() end,                                desc = "Debug Mode" },
    },
    config = function()
      local dap = require("dap")

      -- Configure signs with theme-matching colors
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◐", texthl = "DapBreakpointCondition" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DapBreakpointRejected" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapStoppedLine" })
      
      -- Custom DAP highlight groups that match your minimal theme
      vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#ff5555", bold = true })           -- Error red
      vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = "#bb9af7", bold = true })  -- Accent purple
      vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = "#666666" })                -- Gray
      vim.api.nvim_set_hl(0, "DapStopped", { fg = "#bb9af7", bold = true })              -- Accent purple
      vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = "#222222" })                       -- Selection background

      -- DAP Virtual Text with theme-matching colors
      require("nvim-dap-virtual-text").setup({
        enabled = true,
        enabled_commands = true,
        highlight_changed_variables = true,
        highlight_new_as_changed = false,
        show_stop_reason = true,
        commented = false,
        only_first_definition = true,
        all_references = false,
        filter_references_pattern = '<module',
        virt_text_pos = 'eol',
        all_frames = false,
        virt_lines = false,
        virt_text_win_col = nil,
      })
      
      -- Custom virtual text highlight groups
      vim.api.nvim_set_hl(0, "NvimDapVirtualText", { fg = "#666666", italic = true })
      vim.api.nvim_set_hl(0, "NvimDapVirtualTextChanged", { fg = "#bb9af7", italic = true })
      vim.api.nvim_set_hl(0, "NvimDapVirtualTextError", { fg = "#ff5555", italic = true })
      
      -- DAP View winbar highlights (purple theme) - using actual highlight groups
      vim.api.nvim_set_hl(0, "WinBar", { fg = "#bb9af7", bg = "#444444", bold = true })
      vim.api.nvim_set_hl(0, "WinBarNC", { fg = "#666666", bg = "#444444" })
      vim.api.nvim_set_hl(0, "FloatTitle", { fg = "#bb9af7", bold = true })
      vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#bb9af7" })
      
      -- Also try dap-view specific groups if they exist
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          vim.api.nvim_set_hl(0, "WinBar", { fg = "#bb9af7", bg = "#444444", bold = true })
          vim.api.nvim_set_hl(0, "WinBarNC", { fg = "#666666", bg = "#444444" })
          vim.api.nvim_set_hl(0, "FloatTitle", { fg = "#bb9af7", bold = true })
          vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#bb9af7" })
        end,
      })

      -- Language-specific configurations

      -- Node.js/TypeScript
      dap.adapters.node2 = {
        type = 'executable',
        command = 'node',
        args = { vim.fn.exepath('js-debug-adapter') },
      }

      dap.configurations.javascript = {
        {
          name = 'Launch',
          type = 'node2',
          request = 'launch',
          program = '${file}',
          cwd = vim.fn.getcwd(),
          sourceMaps = true,
          protocol = 'inspector',
          console = 'integratedTerminal',
        },
        {
          name = 'Attach to process',
          type = 'node2',
          request = 'attach',
          processId = require 'dap.utils'.pick_process,
        },
      }

      dap.configurations.typescript = dap.configurations.javascript

      -- Python
      dap.adapters.python = function(cb, config)
        if config.request == 'attach' then
          local port = (config.connect or config).port
          local host = (config.connect or config).host or '127.0.0.1'
          cb({
            type = 'server',
            port = assert(port, '`connect.port` is required for a python `attach` configuration'),
            host = host,
            options = {
              source_filetype = 'python',
            },
          })
        else
          cb({
            type = 'executable',
            command = 'python',
            args = { '-m', 'debugpy.adapter' },
            options = {
              source_filetype = 'python',
            },
          })
        end
      end

      dap.configurations.python = {
        {
          type = 'python',
          request = 'launch',
          name = 'Launch file',
          program = '${file}',
          pythonPath = function()
            return '/usr/bin/python3'
          end,
        },
      }

      -- Rust (via CodeLLDB)
      dap.adapters.codelldb = {
        type = 'server',
        port = '${port}',
        executable = {
          command = 'codelldb',
          args = { '--port', '${port}' },
        }
      }

      dap.configurations.rust = {
        {
          name = 'Launch file',
          type = 'codelldb',
          request = 'launch',
          program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
        },
      }

      -- C/C++
      dap.configurations.c = dap.configurations.rust
      dap.configurations.cpp = dap.configurations.rust

      -- Ruby (debug gem)
      dap.adapters.ruby = function(callback, config)
        callback {
          type = "server",
          host = "127.0.0.1",
          port = "${port}",
          executable = {
            command = "bundle",
            args = { "exec", "rdbg", "-n", "--open", "--port", "${port}", "-c", "--", "ruby", config.program }
          },
        }
      end

      dap.configurations.ruby = {
        {
          type = "ruby",
          name = "debug current file",
          request = "attach",
          localfs = true,
          program = "${file}",
        },
        {
          type = "ruby",
          name = "run current spec file",
          request = "attach", 
          localfs = true,
          program = "bundle",
          args = { "exec", "rspec", "${file}" },
        },
      }

      -- Dart/Flutter (enhanced by flutter-tools.nvim)
      dap.adapters.dart = {
        type = "executable",
        command = "dart",
        args = { "debug_adapter" },
      }

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
        }
      }
    end,
  },

  -- Database management
  {
    "tpope/vim-dadbod",
    cmd = "DB",
  },
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      "tpope/vim-dadbod",
      { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
    },
    cmd = {
      "DBUI",
      "DBUIToggle",
      "DBUIAddConnection",
      "DBUIFindBuffer",
    },
    keys = {
      { "<leader>od", "<cmd>DBUIToggle<cr>",        desc = "Database UI" },
      { "<leader>of", "<cmd>DBUIFindBuffer<cr>",    desc = "Find DB Buffer" },
      { "<leader>or", "<cmd>DBUIRenameBuffer<cr>",  desc = "Rename DB Buffer" },
      { "<leader>oq", "<cmd>DBUILastQueryInfo<cr>", desc = "Last Query Info" },
    },
    init = function()
      -- Database UI configuration
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_force_echo_notifications = 1
      vim.g.db_ui_win_position = "left"
      vim.g.db_ui_winwidth = 40

      -- Auto-execute table queries
      vim.g.db_ui_auto_execute_table_helpers = 1

      -- Save location for queries
      vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"

      -- Icons (minimal, matching theme)
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
        new_query = "📝",
        tables = "📋",
        buffers = "📚",
        add_connection = "📡",
        connection_ok = "✅",
        connection_error = "❌",
      }

      -- Drawer behavior
      vim.g.db_ui_tmp_query_location = vim.fn.stdpath("data") .. "/db_ui/tmp"

      -- Execute current query on <leader><CR>
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function()
          vim.keymap.set("n", "<leader><CR>", "<cmd>DBUIExecute<cr>", { buffer = true, desc = "Execute Query" })
          vim.keymap.set("v", "<leader><CR>", "<cmd>DBUIExecute<cr>", { buffer = true, desc = "Execute Query" })
        end,
      })
    end,
    config = function()
      -- Setup completion for SQL files
      require("cmp").setup.filetype({ "sql", "mysql", "plsql" }, {
        sources = {
          { name = "vim-dadbod-completion" },
          { name = "buffer" },
          { name = "snippets" },
        },
      })
    end,
  },

  -- MCPhub for MCP server management
  {
    "ravitemer/mcphub.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",               -- Required for Job and HTTP requests
    },
    cmd = "MCPHub",                          -- Lazily start the hub when MCPHub is called
    build = "npm install -g mcp-hub@latest", -- Installs required mcp-hub npm module
    config = function()
      require("mcphub").setup({
        -- Required options
        port = 3000,                                 -- Port for MCP Hub server
        config = vim.fn.expand("~/mcpservers.json"), -- Absolute path to config file

        -- Optional options
        on_ready = function(hub)
          vim.notify("MCP Hub is ready", vim.log.levels.INFO)
        end,
        on_error = function(err)
          vim.notify("MCP Hub error: " .. tostring(err), vim.log.levels.ERROR)
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
    end,
    keys = {
      { "<leader>mh", "<cmd>MCPHub<cr>", desc = "Start MCP Hub" },
    },
  },

  -- AI Code Companion (Local models via LM Studio + MCP integration)
  {
    "olimorris/codecompanion.nvim",
    cmd = {
      "CodeCompanion",
      "CodeCompanionActions",
      "CodeCompanionChat",
      "CodeCompanionCmd",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "ravitemer/mcphub.nvim", -- MCP integration
    },
    config = function(_, opts)
      require("codecompanion").setup(opts)
    end,
    keys = {
      {
        "<leader>aa",
        "<cmd>CodeCompanionActions<cr>",
        mode = { "n", "v" },
        desc = "CodeCompanion Actions"
      },
      {
        "<leader>ai",
        "<cmd>CodeCompanion<cr>",
        mode = { "n", "v" },
        desc = "CodeCompanion Inline"
      },
      {
        "<leader>am",
        "<cmd>CodeCompanionCmd<cr>",
        desc = "CodeCompanion Command"
      },
      {
        "<leader>al",
        "<cmd>CodeCompanionChat Toggle<cr>",
        mode = { "n", "v" },
        desc = "CodeCompanion Chat"
      },
    },
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
              url = "http://127.0.0.1:1234",     -- LM Studio default URL
              chat_url = "/v1/chat/completions", -- API endpoint
              models_endpoint = "/v1/models",    -- Models endpoint
            },
            schema = {
              model = {
                -- default = "qwen3-32b-mlx" -- Default model (change as needed)
                default = "uigen-t3-14b-preview"
              },
              temperature = {
                order = 2,
                mapping = "parameters",
                type = "number",
                optional = true,
                default = 0.8,
                desc = "Sampling temperature between 0 and 2",
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
                desc = "Upper bound for tokens that can be generated",
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
                desc = "Stop sequences for text generation",
                validate = function(s)
                  return s:len() > 0, "Cannot be an empty string"
                end,
              },
            },
          })
        end,
      },
    },
  },

  -- Otter.nvim for embedded code in Quarto/R Markdown/Jupyter
  {
    "jmbuhr/otter.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      {
        "quarto-dev/quarto-nvim",
        opts = {
          lspFeatures = {
            enabled = true,
            languages = { "r", "python", "julia", "bash", "html" },
          },
          codeRunner = {
            enabled = true,
            default_method = "molten",
          },
        }
      },
    },
    ft = { "quarto", "rmd", "markdown", "ipynb" },
    opts = {
      lsp = {
        hover = {
          border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
        },
      },
      buffers = {
        set_filetype = true,
        write_to_disk = false,
      },
      handle_leading_whitespace = true,
    },
    keys = {
      { "<leader>oa", function() require("otter").activate() end,   desc = "Activate Otter" },
      { "<leader>od", function() require("otter").deactivate() end, desc = "Deactivate Otter" },
      { "<leader>oo", function() require("otter").toggle() end,     desc = "Toggle Otter" },
      {
        "<leader>oi",
        function()
          require("otter").activate({ "r", "python", "julia", "bash" })
          vim.notify("Otter activated for R, Python, Julia, and Bash", vim.log.levels.INFO)
        end,
        desc = "Activate Otter (multi-lang)"
      },
    },
    config = function(_, opts)
      require("otter").setup(opts)

      -- Auto-activate otter for supported filetypes (only if code blocks are detected)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "quarto", "rmd", "markdown" },
        callback = function()
          -- Delay activation to ensure buffer is fully loaded
          vim.defer_fn(function()
            -- Check if buffer has code blocks before activating
            local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            local has_code_blocks = false

            for _, line in ipairs(lines) do
              if line:match("^```[%w_]*$") then -- Detect code block fences
                has_code_blocks = true
                break
              end
            end

            if has_code_blocks then
              local ok, err = pcall(function()
                require("otter").activate({ "r", "python", "julia", "bash" })
              end)
              if not ok and not err:match("No explicit query provided") then
                vim.notify("Otter activation failed: " .. err, vim.log.levels.WARN)
              end
            end
          end, 200)
        end,
      })
    end,
  },

  -- Molten for Jupyter notebook support
  {
    "benlubas/molten-nvim",
    version = "^1.0.0", -- use version <2.0.0 to avoid breaking changes
    dependencies = { "3rd/image.nvim" },
    build = ":UpdateRemotePlugins",
    init = function()
      -- Setup molten configuration
      vim.g.molten_output_win_max_height = 20
      vim.g.molten_auto_open_output = false
      vim.g.molten_wrap_output = true
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
    end,
    keys = {
      { "<leader>oji", ":MoltenInit<CR>",                  desc = "Initialize Molten" },
      { "<leader>oje", ":MoltenEvaluateOperator<CR>",      desc = "Evaluate operator",         mode = "n" },
      { "<leader>oje", ":<C-u>MoltenEvaluateVisual<CR>gv", desc = "Evaluate visual selection", mode = "v" },
      { "<leader>ojr", ":MoltenReevaluateCell<CR>",        desc = "Re-evaluate cell" },
      { "<leader>ojd", ":MoltenDelete<CR>",                desc = "Delete Molten cell" },
      { "<leader>ojo", ":MoltenShowOutput<CR>",            desc = "Show output" },
      { "<leader>ojh", ":MoltenHideOutput<CR>",            desc = "Hide output" },
      { "<leader>ojj", ":MoltenNext<CR>",                  desc = "Next cell" },
      { "<leader>ojk", ":MoltenPrev<CR>",                  desc = "Previous cell" },
    },
  },

  -- Image.nvim for displaying images in terminal
  {
    "3rd/image.nvim",
    opts = {
      backend = "kitty",
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
          only_render_image_at_cursor = false,
          filetypes = { "markdown", "vimwiki", "quarto" },
        },
        neorg = {
          enabled = true,
          filetypes = { "norg" },
        },
      },
      max_width = nil,
      max_height = nil,
      max_width_window_percentage = nil,
      max_height_window_percentage = 50,
      window_overlap_clear_enabled = false,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
      editor_only_render_when_focused = false,
      tmux_show_only_in_active_window = false,
      hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
    },
  },

  -- Jupytext for Jupyter notebook conversion
  {
    "GCBallesteros/jupytext.nvim",
    opts = {
      style = "light",
      output_extension = "auto",
      force_ft = nil,
      custom_language_formatting = {
        python = {
          extension = "qmd",
          style = "quarto",
          force_ft = "quarto",
        },
        r = {
          extension = "qmd",
          style = "quarto",
          force_ft = "quarto",
        },
        julia = {
          extension = "qmd",
          style = "quarto",
          force_ft = "quarto",
        },
      },
    },
    keys = {
      { "<leader>ojc", ":JupytextConvert<CR>", desc = "Convert Jupyter notebook" },
      { "<leader>ojs", ":JupytextSync<CR>",    desc = "Sync Jupyter notebook" },
      
      -- Quarto-specific commands (using <leader>oq* to avoid conflicts)
      { "<leader>oqp", ":QuartoPreview<CR>",    desc = "Quarto preview",     ft = { "quarto", "qmd" } },
      { "<leader>oqc", ":QuartoClosePreview<CR>", desc = "Quarto close preview", ft = { "quarto", "qmd" } },
      { "<leader>oqr", function() 
          if vim.bo.filetype == "quarto" or vim.bo.filetype == "qmd" then
            vim.cmd("QuartoSendAbove")
          else
            vim.notify("Quarto commands only available in .qmd files", vim.log.levels.WARN)
          end
        end, desc = "Quarto run to cursor" },
      { "<leader>oqa", function()
          if vim.bo.filetype == "quarto" or vim.bo.filetype == "qmd" then
            vim.cmd("QuartoSendAll")
          else
            vim.notify("Quarto commands only available in .qmd files", vim.log.levels.WARN)
          end
        end, desc = "Quarto run all" },
    },
  },

  -- Robust project root detection with git priority
  {
    dir = vim.fn.stdpath("config") .. "/lua",
    name = "project-rooter",
    config = function()
      local M = {}

      -- Project root patterns (ordered by priority)
      local root_patterns = {
        -- Git takes highest priority
        ".git",
        -- Package managers and build systems
        "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
        "Cargo.toml", "Cargo.lock",
        "go.mod", "go.sum",
        "pyproject.toml", "setup.py", "requirements.txt", "Pipfile", "poetry.lock", "setup.cfg",
        "composer.json", "composer.lock",
        "Gemfile", "Gemfile.lock",
        "mix.exs", "rebar.config", "rebar3.config",
        "CMakeLists.txt", "Makefile", "makefile",
        "pubspec.yaml", "pubspec.yml",
        "deno.json", "deno.jsonc",
        -- IDE and editor configs
        ".vscode", ".idea",
        ".envrc", ".env",
        -- R and data science
        ".Rprofile", "DESCRIPTION", "renv.lock",
        -- Web frameworks
        "astro.config.mjs", "astro.config.js", "astro.config.ts",
        "nuxt.config.js", "nuxt.config.ts",
        "next.config.js", "next.config.ts",
        "svelte.config.js", "vite.config.js", "vite.config.ts",
        "webpack.config.js", "rollup.config.js",
        -- Documentation
        "README.md", "readme.md", "README.rst",
      }

      -- Find git root based on current file location (not nvim cwd)
      function M.find_git_root(start_path)
        -- Always prioritize the current file's directory over nvim's cwd
        if not start_path then
          local current_file = vim.fn.expand('%:p')
          if current_file and current_file ~= '' then
            start_path = vim.fn.fnamemodify(current_file, ':h')
          else
            start_path = vim.fn.getcwd()
          end
        end

        -- Try the most reliable method first: git rev-parse from the file's directory
        local cmd = string.format("cd %s && git rev-parse --show-toplevel 2>/dev/null", vim.fn.shellescape(start_path))
        local result = vim.fn.system(cmd):gsub("\n", "")

        if vim.v.shell_error == 0 and result ~= "" and vim.fn.isdirectory(result) == 1 then
          return result
        end

        -- Fallback: walk up directories looking for .git
        local current = start_path
        while current ~= "/" and current ~= "" do
          local git_dir = current .. "/.git"
          if vim.fn.isdirectory(git_dir) == 1 or vim.fn.filereadable(git_dir) == 1 then
            return current
          end
          local parent = vim.fn.fnamemodify(current, ":h")
          if parent == current then break end
          current = parent
        end

        return nil
      end

      -- Find project root starting from given directory
      function M.find_root(start_path)
        start_path = start_path or vim.fn.expand('%:p:h')

        -- If no file buffer, use current working directory
        if start_path == '' or start_path == '.' then
          start_path = vim.fn.getcwd()
        end

        -- Try git root first (most reliable for git projects)
        local git_root = M.find_git_root(start_path)
        if git_root then
          return git_root
        end

        -- Fall back to pattern matching for non-git projects
        local current_dir = start_path

        -- Walk up the directory tree
        while current_dir ~= "/" and current_dir ~= "" do
          for _, pattern in ipairs(root_patterns) do
            local path = current_dir .. "/" .. pattern
            if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
              return current_dir
            end
          end

          -- Go up one level
          local parent = vim.fn.fnamemodify(current_dir, ":h")
          if parent == current_dir then
            break -- Reached filesystem root
          end
          current_dir = parent
        end

        -- No root found, return the starting directory
        return start_path
      end

      -- Get current project root
      function M.get_current_root()
        return M.find_root()
      end

      -- Change to project root
      function M.change_to_root(silent)
        local root = M.find_root()
        local current_cwd = vim.fn.getcwd()

        if root and root ~= current_cwd then
          vim.cmd("cd " .. vim.fn.fnameescape(root))
          if not silent then
            vim.notify("📁 Project root: " .. root, vim.log.levels.INFO)
          end
          return true
        end

        if not silent then
          vim.notify("Already at project root: " .. current_cwd, vim.log.levels.INFO)
        end
        return false
      end

      -- Show project info
      function M.show_info()
        local cwd = vim.fn.getcwd()
        local root = M.find_root()
        local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")

        local info = { "📂 Project Information:", "" }
        table.insert(info, "Current directory: " .. cwd)
        table.insert(info, "Detected root: " .. root)

        if vim.v.shell_error == 0 and git_root ~= "" then
          table.insert(info, "Git repository: " .. git_root)
          if git_root ~= root then
            table.insert(info, "⚠️  Root mismatch detected")
          end
        else
          table.insert(info, "Git repository: Not a git repo")
        end

        -- Check for project markers
        local markers_found = {}
        for _, pattern in ipairs(root_patterns) do
          local path = root .. "/" .. pattern
          if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
            table.insert(markers_found, pattern)
          end
        end

        if #markers_found > 0 then
          table.insert(info, "")
          table.insert(info, "Project markers found:")
          for _, marker in ipairs(markers_found) do
            table.insert(info, "  • " .. marker)
          end
        end

        vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
      end

      -- Setup autocommands for automatic root detection
      function M.setup_auto_root()
        local group = vim.api.nvim_create_augroup("project_rooter", { clear = true })

        -- Change to project root when opening files
        vim.api.nvim_create_autocmd({ "BufEnter", "BufNewFile" }, {
          group = group,
          callback = function(ev)
            -- Don't change root for special buffers
            local buftype = vim.bo[ev.buf].buftype
            if buftype ~= "" and buftype ~= "acwrite" then
              return
            end

            -- Don't change root for certain filetypes
            local filetype = vim.bo[ev.buf].filetype
            local ignore_fts = { "help", "qf", "fugitive", "gitcommit", "gitrebase" }
            for _, ft in ipairs(ignore_fts) do
              if filetype == ft then
                return
              end
            end

            vim.schedule(function()
              M.change_to_root(true) -- Silent mode for auto-changes
            end)
          end,
        })

        -- Also run when Vim starts
        vim.api.nvim_create_autocmd("VimEnter", {
          group = group,
          callback = function()
            vim.schedule(function()
              M.change_to_root(true)
            end)
          end,
        })
      end

      -- Global access
      _G.ProjectRooter = M

      -- Setup auto root detection
      M.setup_auto_root()

      -- Create user commands
      vim.api.nvim_create_user_command("ProjectRoot", function()
        M.change_to_root()
      end, { desc = "Change to project root" })

      vim.api.nvim_create_user_command("ProjectInfo", function()
        M.show_info()
      end, { desc = "Show project information" })

      vim.api.nvim_create_user_command("ProjectFind", function()
        local root = M.find_root()
        vim.notify("Project root would be: " .. root, vim.log.levels.INFO)
      end, { desc = "Find project root without changing" })
    end,
    keys = {
      {
        "<leader>fP",
        function()
          _G.ProjectRooter.change_to_root()
        end,
        desc = "Go to project root"
      },
      {
        "<leader>fI",
        function()
          _G.ProjectRooter.show_info()
        end,
        desc = "Project info"
      },
      {
        "<leader>fR",
        function()
          local root = _G.ProjectRooter.find_root()
          vim.notify("Project root: " .. root, vim.log.levels.INFO)
        end,
        desc = "Show project root"
      },
    },
  },

  -- Workspaces (Doom Emacs style)
  {
    "natecraddock/workspaces.nvim",
    cmd = { "WorkspacesAdd", "WorkspacesOpen", "WorkspacesRemove", "WorkspacesList" },
    event = "VeryLazy",
    opts = {
      hooks = {
        open = function()
          -- Auto-detect project root when opening workspace
          vim.schedule(function()
            if _G.ProjectRooter then
              _G.ProjectRooter.change_to_root(true)
            end
          end)
        end,
      },
      sort = true,
      mru_sort = true,
      notify_info = true,
      auto_open = true,
      auto_dir = true,
      cd_type = "global",
      path = vim.fn.stdpath("data") .. "/workspaces",
    },
    config = function(_, opts)
      require("workspaces").setup(opts)

      -- Auto-save workspace when changing directories
      vim.api.nvim_create_autocmd("DirChanged", {
        group = vim.api.nvim_create_augroup("workspaces_auto", { clear = true }),
        callback = function()
          local cwd = vim.fn.getcwd()
          local workspace_name = vim.fn.fnamemodify(cwd, ":t")

          -- Only auto-add if it looks like a project directory
          local project_markers = { ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" }
          for _, marker in ipairs(project_markers) do
            if vim.fn.isdirectory(cwd .. "/" .. marker) == 1 or vim.fn.filereadable(cwd .. "/" .. marker) == 1 then
              local workspaces = require("workspaces").get()
              local exists = false
              for _, ws in ipairs(workspaces) do
                if ws.path == cwd then
                  exists = true
                  break
                end
              end

              if not exists then
                require("workspaces").add(cwd, workspace_name)
                vim.notify("Added workspace: " .. workspace_name, vim.log.levels.INFO)
              end
              break
            end
          end
        end,
      })
    end,
    keys = {
      {
        "<leader>fws",
        function()
          -- Custom workspace picker using Snacks
          local workspaces = require("workspaces").get()

          if #workspaces == 0 then
            vim.notify("No workspaces found", vim.log.levels.WARN)
            return
          end

          local items = {}
          for _, workspace in ipairs(workspaces) do
            table.insert(items, {
              text = workspace.name,
              path = workspace.path,
              display = workspace.name .. " (" .. workspace.path .. ")",
            })
          end

          Snacks.picker.pick({
            items = items,
            format = function(item)
              return item.display
            end,
            confirm = function(item)
              require("workspaces").open(item.name)
              vim.notify("Opened workspace: " .. item.text, vim.log.levels.INFO)
            end,
            layout = { preset = "vscode" },
            title = "Workspaces",
          })
        end,
        desc = "Switch Workspace"
      },
      {
        "<leader>fwa",
        function()
          local cwd = vim.fn.getcwd()
          local default_name = vim.fn.fnamemodify(cwd, ":t")

          vim.ui.input({
            prompt = "Workspace name: ",
            default = default_name,
          }, function(name)
            if name and name ~= "" then
              require("workspaces").add(cwd, name)
              vim.notify("Added workspace: " .. name, vim.log.levels.INFO)
            end
          end)
        end,
        desc = "Add Workspace"
      },
      {
        "<leader>fwd",
        function()
          local workspaces = require("workspaces").get()

          if #workspaces == 0 then
            vim.notify("No workspaces to remove", vim.log.levels.WARN)
            return
          end

          local items = {}
          for _, workspace in ipairs(workspaces) do
            table.insert(items, {
              text = workspace.name,
              path = workspace.path,
              display = workspace.name .. " (" .. workspace.path .. ")",
            })
          end

          Snacks.picker.pick({
            items = items,
            format = function(item)
              return item.display
            end,
            confirm = function(item)
              require("workspaces").remove(item.name)
              vim.notify("Removed workspace: " .. item.text, vim.log.levels.INFO)
            end,
            layout = { preset = "vscode" },
            title = "Remove Workspace",
          })
        end,
        desc = "Remove Workspace"
      },
      {
        "<leader>fwl",
        "<cmd>WorkspacesList<cr>",
        desc = "List Workspaces"
      },
    },
  },

  -- Multiple cursors (reliable and battle-tested)
  {
    "mg979/vim-visual-multi",
    event = "VeryLazy",
    init = function()
      -- Disable default mappings to avoid conflicts
      vim.g.VM_default_mappings = 0
      vim.g.VM_maps = {
        ["Find Under"] = "",
        ["Find Subword Under"] = "",
      }

      -- Custom highlighting to match theme
      vim.g.VM_Cursor_hl = "MultiCursor"
      vim.g.VM_Extend_hl = "MultiCursorExtend"
      vim.g.VM_Mono_hl = "MultiCursorMono"
      vim.g.VM_Insert_hl = "MultiCursorInsert"
    end,
    config = function()
      -- Set custom highlight groups
      vim.api.nvim_set_hl(0, "MultiCursor", { fg = "#ffffff", bg = "#bb9af7", bold = true })
      vim.api.nvim_set_hl(0, "MultiCursorExtend", { fg = "#ffffff", bg = "#666666" })
      vim.api.nvim_set_hl(0, "MultiCursorMono", { fg = "#bb9af7", bg = "#222222" })
      vim.api.nvim_set_hl(0, "MultiCursorInsert", { fg = "#000000", bg = "#bb9af7" })
    end,
    keys = {
      -- Doom Emacs gz prefix keybindings
      {
        "gzm",
        "<Plug>(VM-Find-Under)",
        mode = { "n", "v" },
        desc = "Find word under cursor"
      },
      {
        "gzM",
        "<Plug>(VM-Find-Subword-Under)",
        mode = { "n", "v" },
        desc = "Find subword under cursor"
      },
      {
        "gzn",
        "<Plug>(VM-Add-Cursor-Down)",
        mode = { "n", "v" },
        desc = "Add cursor down"
      },
      {
        "gzp",
        "<Plug>(VM-Add-Cursor-Up)",
        mode = { "n", "v" },
        desc = "Add cursor up"
      },
      {
        "gza",
        "<Plug>(VM-Select-All)",
        mode = { "n", "v" },
        desc = "Select all occurrences"
      },
      {
        "gzs",
        "<Plug>(VM-Skip-Region)",
        mode = { "n", "v" },
        desc = "Skip current and find next"
      },
      {
        "gzr",
        "<Plug>(VM-Remove-Region)",
        mode = { "n", "v" },
        desc = "Remove current region"
      },
      {
        "gzc",
        "<Plug>(VM-Exit)",
        mode = { "n", "v" },
        desc = "Exit multicursor mode"
      },
      -- Visual mode selections
      {
        "gzv",
        "<Plug>(VM-Visual-Cursors)",
        mode = "v",
        desc = "Create cursors from visual"
      },
      {
        "gzA",
        "<Plug>(VM-Visual-All)",
        mode = "v",
        desc = "Select all in visual"
      },
      {
        "gzf",
        "<Plug>(VM-Visual-Find)",
        mode = "v",
        desc = "Find in visual selection"
      },
      -- Alternative quick access (common patterns)
      {
        "<C-n>",
        "<Plug>(VM-Find-Under)",
        mode = { "n", "v" },
        desc = "Find word under cursor"
      },
      {
        "<C-Down>",
        "<Plug>(VM-Add-Cursor-Down)",
        mode = { "n", "v" },
        desc = "Add cursor down"
      },
      {
        "<C-Up>",
        "<Plug>(VM-Add-Cursor-Up)",
        mode = { "n", "v" },
        desc = "Add cursor up"
      },
    },
  },

  -- Fleet-like inline code actions with preview
  {
    "aznhe21/actions-preview.nvim",
    event = "LspAttach",
    config = function()
      require("actions-preview").setup({
        highlight_command = {
          require("actions-preview.highlight").delta(),
        },
        backend = { "snacks" },
        snacks = {
          enabled = true,
          layout = { preset = "vscode", preview = "main" },
        },
      })
    end,
    keys = {
      {
        "<leader>ca",
        function()
          require("actions-preview").code_actions()
        end,
        mode = { "n", "v" },
        desc = "Code actions with preview"
      },
    },
  },

  -- Assistant editor (related file switching)
  {
    "rgroli/other.nvim",
    cmd = { "Other", "OtherTabNew", "OtherSplit", "OtherVSplit" },
    config = function()
      require("other-nvim").setup({
        mappings = {
          -- TypeScript/JavaScript
          "livescript",
          "angular",
          "react",
          {
            pattern = "(.*).ts$",
            target = "%1.spec.ts",
            context = "test"
          },
          {
            pattern = "(.*).tsx$",
            target = "%1.spec.tsx",
            context = "test"
          },
          {
            pattern = "(.*).js$",
            target = "%1.spec.js",
            context = "test"
          },
          {
            pattern = "(.*).jsx$",
            target = "%1.spec.jsx",
            context = "test"
          },
          -- C/C++
          {
            pattern = "(.*).c$",
            target = "%1.h",
            context = "header"
          },
          {
            pattern = "(.*).cpp$",
            target = "%1.h",
            context = "header"
          },
          {
            pattern = "(.*).h$",
            target = {
              { target = "%1.c",   context = "implementation" },
              { target = "%1.cpp", context = "implementation" },
              { target = "%1.m",   context = "implementation" },
            }
          },
          -- Python
          {
            pattern = "(.*).py$",
            target = "test_%1.py",
            context = "test"
          },
          {
            pattern = "test_(.*).py$",
            target = "%1.py",
            context = "implementation"
          },
          -- Dart/Flutter
          {
            pattern = "(.*).dart$",
            target = "%1_test.dart",
            context = "test"
          },
          {
            pattern = "(.*)_test.dart$",
            target = "%1.dart",
            context = "implementation"
          },
        },
        transformers = {
          camelToKebab = function(inputString)
            return inputString:gsub("%f[^%l]%u", "-%1"):lower()
          end
        },
        style = {
          border = "solid",
          seperator = "|",
        }
      })
    end,
    keys = {
      {
        "<leader>oa",
        "<cmd>Other<cr>",
        desc = "Open related file"
      },
      {
        "<leader>oA",
        "<cmd>OtherVSplit<cr>",
        desc = "Open related file (vsplit)"
      },
    },
  },

  -- Better visual feedback (smooth scrolling)
  {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    config = function()
      require("neoscroll").setup({
        mappings = { "<C-u>", "<C-d>", "<C-b>", "<C-f>", "<C-y>", "<C-e>", "zt", "zz", "zb" },
        hide_cursor = true,
        stop_eof = true,
        respect_scrolloff = false,
        cursor_scrolls_alone = true,
        easing_function = "sine",
        pre_hook = nil,
        post_hook = nil,
      })
    end,
  },

  -- Timber for smart log insertions
  {
    "Goose97/timber.nvim",
    version = "*",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("timber").setup({
        log_templates = {
          -- Default template
          default = {
            javascript = [[console.log("%identifier %log_target:", %log_target)]],
            typescript = [[console.log("%identifier %log_target:", %log_target)]],
            javascriptreact = [[console.log("%identifier %log_target:", %log_target)]],
            typescriptreact = [[console.log("%identifier %log_target:", %log_target)]],
            lua = [[print("%identifier %log_target:", vim.inspect(%log_target))]],
            python = [[print(f"%identifier %log_target: {%log_target}")]],
            go = [[fmt.Printf("%identifier %log_target: %+v\n", %log_target)]],
            rust = [[println!("%identifier %log_target: {:?}", %log_target);]],
            c = [[printf("%identifier %log_target: %s\n", %log_target);]],
            cpp = [[std::cout << "%identifier %log_target: " << %log_target << std::endl;]],
            elixir = [[IO.inspect(%log_target, label: "%identifier %log_target")]],
            dart = [[print("%identifier %log_target: ${%log_target}");]],
            r = [[cat("%identifier %log_target:", %log_target, "\n")]],
            astro = [[console.log("%identifier %log_target:", %log_target)]],
            yaml = [[# %identifier %log_target: %log_target]],
            dockerfile = [[# %identifier %log_target: %log_target]],
          },
          -- Plain template (no variable inspection)
          plain = {
            javascript = [[console.log("%log_target")]],
            typescript = [[console.log("%log_target")]],
            lua = [[print("%log_target")]],
            python = [[print("%log_target")]],
            go = [[fmt.Println("%log_target")]],
            rust = [[println!("%log_target");]],
          },
        },
        -- Keymaps
        keymaps = {
          -- Insert log statement for word under cursor
          insert_log_below = "<leader>ljj",
          insert_log_above = "<leader>ljk",
          -- Insert log statement for visual selection
          insert_log_below_visual = "<leader>ljj",
          insert_log_above_visual = "<leader>ljk",
          -- Add plain log statement
          add_log_targets_to_template = "<leader>lja",
          -- Insert batch logs
          insert_batch_log = "<leader>ljb",
        },
        -- Log marker for easy navigation
        log_marker = "🪵",
        -- Auto-generate unique identifiers
        auto_add_identifier = true,
      })

      -- Enhanced which-key integration for timber
      local wk = require("which-key")
      wk.add({
        { "<leader>lj",  group = "timber logs" },
        { "<leader>ljj", desc = "log below" },
        { "<leader>ljk", desc = "log above" },
        { "<leader>lja", desc = "add to template" },
        { "<leader>ljb", desc = "batch log" },
        { "<leader>ljd", desc = "delete all logs" },
        { "<leader>ljg", desc = "goto next log" },
        { "<leader>ljG", desc = "goto prev log" },
      })
    end,
    keys = {
      -- Timber logging keybindings
      { "<leader>ljj", desc = "Insert log below" },
      { "<leader>ljk", desc = "Insert log above" },
      { "<leader>lja", desc = "Add log targets" },
      { "<leader>ljb", desc = "Insert batch log" },
      { "<leader>ljj", mode = "v",               desc = "Insert log below (visual)" },
      { "<leader>ljk", mode = "v",               desc = "Insert log above (visual)" },
      -- Additional timber commands
      {
        "<leader>ljd",
        function()
          -- Delete all timber logs in current buffer
          vim.cmd([[g/🪵.*console\.log\|🪵.*print\|🪵.*fmt\./d]])
        end,
        desc = "Delete all logs"
      },
      {
        "<leader>ljg",
        function()
          -- Go to next log statement
          vim.cmd([[/🪵]])
        end,
        desc = "Goto next log"
      },
      {
        "<leader>ljG",
        function()
          -- Go to previous log statement
          vim.cmd([[?🪵]])
        end,
        desc = "Goto prev log"
      },
    },
  },

  -- Auto-import support for multiple languages
  {
    "stevanmilic/nvim-lspimport",
    ft = { "typescript", "typescriptreact", "javascript", "javascriptreact", "python", "go", "rust" },
    config = function()
      local map = vim.keymap.set
      map("n", "<leader>ci", function() require("lspimport").import() end, { desc = "Import symbol under cursor" })

      -- Enhanced which-key integration
      local ok, wk = pcall(require, "which-key")
      if ok then
        wk.add({
          { "<leader>ci", desc = "import symbol" },
        })
      end
    end,
  },

  -- Python import management and refactoring
  {
    "alexpasmantier/pymple.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    build = ":PympleBuild",
    ft = "python",
    keys = {
      { "<leader>ci", function() require('pymple.api').resolve_import_under_cursor() end, desc = "Resolve import under cursor" },
      { "<leader>cio", function() require('pymple.api').optimize_imports() end, desc = "Optimize imports" },
      { "<leader>ciu", function() require('pymple.api').remove_unused_imports() end, desc = "Remove unused imports" },
    },
    config = function()
      require('pymple').setup({
        keymaps = {
          resolve_import_under_cursor = {
            desc = "Resolve import under cursor",
            keys = "<leader>ci",
          },
        },
        python = {
          analysis = {
            auto_update_imports_on_move = true, -- Works with oil.nvim
            update_imports_on_folder_move = true, -- Useful for refactoring
          },
        },
        -- Integration with existing tools
        integrations = {
          ruff = true, -- Uses your existing ruff formatter/linter
        },
        -- File explorer integration
        file_explorer = {
          enabled = true,
          oil = true, -- Integrates with your oil.nvim setup
        },
      })
    end,
  },

  -- Python debugging (enhanced for direnv)
  {
    "mfussenegger/nvim-dap-python",
    ft = "python",
    dependencies = {
      "mfussenegger/nvim-dap",
    },
    config = function()
      -- Use direnv to detect Python path, fallback to system python
      local python_path = vim.env.VIRTUAL_ENV and (vim.env.VIRTUAL_ENV .. "/bin/python") or "python3"
      require("dap-python").setup(python_path)

      -- Enhanced Python debugging keybindings
      local map = vim.keymap.set
      map("n", "<leader>cpm", function() require("dap-python").test_method() end, { desc = "Python Test Method" })
      map("n", "<leader>cpc", function() require("dap-python").test_class() end, { desc = "Python Test Class" })
      map("n", "<leader>cps", function() require("dap-python").debug_selection() end,
        { desc = "Python Debug Selection", mode = { "n", "v" } })

      -- Enhanced which-key integration
      local ok, wk = pcall(require, "which-key")
      if ok then
        wk.add({
          { "<leader>cp",  group = "python",         ft = "python" },
          { "<leader>cpm", desc = "test method",     ft = "python" },
          { "<leader>cpc", desc = "test class",      ft = "python" },
          { "<leader>cps", desc = "debug selection", ft = "python" },
        })
      end
    end,
  },

  -- Auto brackets/pairs insertion
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      local autopairs = require("nvim-autopairs")
      local Rule = require("nvim-autopairs.rule")
      local cond = require("nvim-autopairs.conds")

      autopairs.setup({
        check_ts = true, -- Enable treesitter integration
        ts_config = {
          lua = { "string", "source" },
          javascript = { "string", "template_string" },
          typescript = { "string", "template_string" },
          javascriptreact = { "string", "template_string", "jsx_attribute", "jsx_expression" },
          typescriptreact = { "string", "template_string", "jsx_attribute", "jsx_expression" },
          java = false, -- Don't add pairs in java
        },
        disable_filetype = { "TelescopePrompt", "spectre_panel" },
        disable_in_macro = true,
        disable_in_visualblock = false,
        disable_in_replace_mode = true,
        ignored_next_char = [=[[%w%%%'%[%"%.%`%$]]=],
        enable_moveright = true,
        enable_afterquote = true,
        enable_check_bracket_line = false,
        enable_bracket_in_quote = true,
        enable_abbr = false,
        break_undo = true,
        check_comma = true,
        map_cr = true,
        map_bs = true,
        map_c_h = false,
        map_c_w = false,
      })

      -- Custom rules for different languages

      -- JSX/TSX custom rules
      autopairs.add_rules({
        -- JSX tag completion
        Rule("<", ">", { "javascriptreact", "typescriptreact" })
            :with_pair(cond.before_regex("%a+"))
            :with_move(function(opts) return opts.char == ">" end),

        -- JSX self-closing tag
        Rule("<", " />", { "javascriptreact", "typescriptreact" })
            :with_pair(cond.before_regex("%a+"))
            :with_move(function(opts) return opts.char == ">" end),

        -- Template literals
        Rule("`", "`", { "javascript", "typescript", "javascriptreact", "typescriptreact" }),

        -- JSX expression braces
        Rule("{", "}", { "javascriptreact", "typescriptreact" })
            :with_pair(cond.not_inside_quote()),
      })

      -- XML/HTML rules
      autopairs.add_rules({
        Rule("<", ">", { "html", "xml", "astro", "vue", "svelte" })
            :with_pair(cond.before_regex("%a+"))
            :with_move(function(opts) return opts.char == ">" end),
      })

      -- Markdown rules
      autopairs.add_rules({
        Rule("*", "*", "markdown"),
        Rule("**", "**", "markdown"),
        Rule("***", "***", "markdown"),
        Rule("`", "`", "markdown"),
        Rule("```", "```", "markdown"),
      })

      -- Language-specific bracket rules
      autopairs.add_rules({
        -- Rust
        Rule("|", "|", "rust")
            :with_pair(cond.before_regex("%w+"))
            :with_move(function(opts) return opts.char == "|" end),

        -- Go
        Rule("interface{", "}", "go"),
        Rule("struct{", "}", "go"),

        -- Python f-strings
        Rule("f\"", "\"", "python"),
        Rule("f'", "'", "python"),

        -- Lua string literals
        Rule("[[", "]]", "lua"),

        -- CSS/SCSS
        Rule("${", "}", { "css", "scss", "sass" }),
      })

      -- Integrate with blink.cmp
      local ok, blink_cmp = pcall(require, "blink.cmp")
      if ok and blink_cmp and blink_cmp.event then
        local cmp_autopairs = require("nvim-autopairs.completion.cmp")
        blink_cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
      end
    end,
  },

  -- Advanced refactoring tools
  {
    "smjonas/inc-rename.nvim",
    cmd = "IncRename",
    config = function()
      require("inc_rename").setup({
        input_buffer_type = "dressing",
        preview_empty_name = false,
      })
    end,
    keys = {
      {
        "<leader>crn",
        function()
          return ":IncRename " .. vim.fn.expand("<cword>")
        end,
        desc = "Incremental rename",
        expr = true,
      },
    },
  },

  -- Enhanced search and replace (snacks-integrated)
  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    opts = {
      headerMaxWidth = 80,
      transient = false,
      windowCreationCommand = "tabnew %",
      staticTitle = "Find and Replace",
      engines = {
        ripgrep = {
          placeholders = {
            enabled = true,
            search = "ex: foo   foo([a-z0-9]*)   fun\\(",
            replacement = "ex: bar   ${1}_bar   zig\\(",
            filesFilter = "ex: *.lua   *.{css,js}   **/docs/**",
            flags = "ex: --help --ignore-case (-i) --replace= (empty replace) --multiline (-U)",
          },
        },
      },
    },
    config = function(_, opts)
      require("grug-far").setup(opts)

      -- Integrate with snacks picker for better file selection
      local grug_far = require("grug-far")
      local original_get_current_files = grug_far.get_current_files

      -- Override file selection to use snacks picker
      grug_far.get_current_files = function()
        return Snacks.picker.files({
          layout = { preset = "vscode", preview = "main" },
          title = "Select files for search",
          multi = true,
        })
      end
    end,
    keys = {
      {
        "<leader>sr",
        function()
          local grug = require("grug-far")
          local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
          grug.open({
            transient = true,
            prefills = {
              filesFilter = ext and ext ~= "" and "*." .. ext or nil,
            },
          })
        end,
        mode = { "n", "v" },
        desc = "Search and Replace",
      },
      {
        "<leader>sw",
        function()
          local grug = require("grug-far")
          local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
          grug.open({
            transient = true,
            prefills = {
              search = vim.fn.expand("<cword>"),
              filesFilter = ext and ext ~= "" and "*." .. ext or nil,
            },
          })
        end,
        desc = "Search and Replace Word",
      },
      -- Enhanced search using snacks picker first
      {
        "<leader>sR",
        function()
          -- Use snacks to find and select, then open grug-far with results
          Snacks.picker.grep({
            layout = { preset = "vscode", preview = "main" },
            title = "Search to replace",
          }, function(items)
            if items and #items > 0 then
              local first_result = items[1]
              local search_term = first_result.text and first_result.text:match("([^:]+)") or ""
              require("grug-far").open({
                transient = true,
                prefills = {
                  search = search_term,
                  filesFilter = first_result.filename and ("*" .. vim.fn.fnamemodify(first_result.filename, ":e")) or nil,
                },
              })
            end
          end)
        end,
        desc = "Search with Snacks then Replace",
      },
    },
  },

  -- Code generation with LuaSnip enhancement
  {
    "L3MON4D3/LuaSnip",
    dependencies = {
      "rafamadriz/friendly-snippets",
      "saadparwaiz1/cmp_luasnip",
    },
    event = "InsertEnter",
    config = function()
      local luasnip = require("luasnip")

      -- Load snippets from friendly-snippets
      require("luasnip.loaders.from_vscode").lazy_load()

      -- Custom snippets for common patterns
      local s = luasnip.snippet
      local t = luasnip.text_node
      local i = luasnip.insert_node
      local f = luasnip.function_node

      luasnip.add_snippets("all", {
        s("todo", {
          t("// TODO: "),
          i(1, "description"),
        }),
        s("fixme", {
          t("// FIXME: "),
          i(1, "description"),
        }),
      })

      -- Language-specific snippets
      luasnip.add_snippets("typescript", {
        s("comp", {
          t({ "export const " }), i(1, "Component"), t({ " = () => {", "  return (", "    <div>" }),
          i(2, "content"), t({ "</div>", "  )", "}" }),
        }),
        s("func", {
          t("const "), i(1, "name"), t(" = ("), i(2, "params"), t("): "), i(3, "ReturnType"), t({ " => {", "  " }),
          i(4, "// implementation"), t({ "", "}" }),
        }),
      })

      luasnip.add_snippets("python", {
        s("def", {
          t("def "), i(1, "function_name"), t("("), i(2, "params"), t(") -> "), i(3, "ReturnType"), t({ ":", "    " }),
          i(4, '"""Docstring."""'), t({ "", "    " }), i(5, "pass"),
        }),
        s("class", {
          t("class "), i(1, "ClassName"), t("("), i(2, "BaseClass"), t({ "):", "    " }),
          i(3, '"""Class docstring."""'), t({ "", "", "    def __init__(self" }),
          i(4, ", args"), t({ "):", "        " }), i(5, "pass"),
        }),
      })

      luasnip.add_snippets("dart", {
        s("class", {
          t("class "), i(1, "ClassName"), t({ " {", "  " }), i(2, "// implementation"), t({ "", "}" }),
        }),
        s("widget", {
          t({ "class " }), i(1, "WidgetName"), t({ " extends StatelessWidget {", "  const " }),
          f(function(args) return args[1][1] end, { 1 }), t({ "({super.key});", "", "  @override",
          "  Widget build(BuildContext context) {", "    return " }),
          i(2, "Container()"), t({ ";", "  }", "}" }),
        }),
      })

      -- Enhanced which-key integration
      local ok, wk = pcall(require, "which-key")
      if ok then
        wk.add({
          { "<leader>cs",  group = "snippets" },
          { "<leader>cse", function() require("luasnip.loaders").edit_snippet_files() end, desc = "edit snippets" },
          { "<leader>csr", function() require("luasnip").unlink_current() end,             desc = "unlink snippet" },
        })
      end
    end,
    keys = {
      {
        "<Tab>",
        function()
          local luasnip = require("luasnip")
          if luasnip.locally_jumpable(1) then
            luasnip.jump(1)
          else
            return "<Tab>"
          end
        end,
        expr = true,
        silent = true,
        mode = "i",
        desc = "Jump to next snippet node",
      },
      {
        "<S-Tab>",
        function()
          local luasnip = require("luasnip")
          if luasnip.locally_jumpable(-1) then
            luasnip.jump(-1)
          else
            return "<S-Tab>"
          end
        end,
        expr = true,
        silent = true,
        mode = "i",
        desc = "Jump to previous snippet node",
      },
    },
  },

  -- Async task runner
  {
    "stevearc/overseer.nvim",
    cmd = {
      "OverseerOpen",
      "OverseerClose",
      "OverseerToggle",
      "OverseerSaveBundle",
      "OverseerLoadBundle",
      "OverseerDeleteBundle",
      "OverseerRunCmd",
      "OverseerRun",
      "OverseerInfo",
      "OverseerBuild",
      "OverseerQuickAction",
      "OverseerTaskAction",
      "OverseerClearCache",
    },
    opts = {
      strategy = {
        "toggleterm",
        direction = "horizontal",
        autos_croll = true,
        quit_on_exit = "success"
      },
      templates = { "builtin", "user.dart_tasks", "user.node_tasks", "user.python_tasks" },
      auto_scroll = true,
      open_on_start = false,
      task_list = {
        direction = "bottom",
        min_height = 15,
        max_height = 20,
        default_detail = 1,
        bindings = {
          ["?"] = "ShowHelp",
          ["g?"] = "ShowHelp",
          ["<CR>"] = "RunAction",
          ["<C-e>"] = "Edit",
          ["o"] = "Open",
          ["<C-v>"] = "OpenVsplit",
          ["<C-s>"] = "OpenSplit",
          ["<C-f>"] = "OpenFloat",
          ["<C-q>"] = "OpenQuickFix",
          ["p"] = "TogglePreview",
          ["<C-l>"] = "IncreaseDetail",
          ["<C-h>"] = "DecreaseDetail",
          ["L"] = "IncreaseAllDetail",
          ["H"] = "DecreaseAllDetail",
          ["["] = "DecreaseWidth",
          ["]"] = "IncreaseWidth",
          ["{"] = "PrevTask",
          ["}"] = "NextTask",
          ["<C-k>"] = "ScrollOutputUp",
          ["<C-j>"] = "ScrollOutputDown",
          ["q"] = "Close",
        },
      },
      form = {
        border = "single",
        win_opts = {
          winblend = 0,
        },
      },
      confirm = {
        border = "single",
        win_opts = {
          winblend = 0,
        },
      },
      task_win = {
        border = "single",
        win_opts = {
          winblend = 0,
        },
      },
    },
    config = function(_, opts)
      require("overseer").setup(opts)

      -- Create custom task templates
      local overseer = require("overseer")

      -- Flutter/Dart tasks
      overseer.register_template({
        name = "flutter run",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "run" },
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

      -- Node.js tasks
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
          filetype = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
        },
      })

      -- Python tasks
      overseer.register_template({
        name = "python run",
        builder = function()
          return {
            cmd = { "python" },
            args = { vim.fn.expand("%") },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "python" },
        },
      })

      -- Enhanced which-key integration
      local ok, wk = pcall(require, "which-key")
      if ok then
        wk.add({
          { "<leader>r",  group = "run" },
          { "<leader>rr", desc = "run task" },
          { "<leader>rt", desc = "toggle task list" },
          { "<leader>ro", desc = "open task list" },
          { "<leader>rc", desc = "close task list" },
          { "<leader>rq", desc = "quick action" },
          { "<leader>ri", desc = "task info" },
        })
      end
    end,
    keys = {
      { "<leader>rr", "<cmd>OverseerRun<cr>",         desc = "Run task" },
      { "<leader>rt", "<cmd>OverseerToggle<cr>",      desc = "Toggle task list" },
      { "<leader>ro", "<cmd>OverseerOpen<cr>",        desc = "Open task list" },
      { "<leader>rc", "<cmd>OverseerClose<cr>",       desc = "Close task list" },
      { "<leader>rq", "<cmd>OverseerQuickAction<cr>", desc = "Quick action" },
      { "<leader>ri", "<cmd>OverseerInfo<cr>",        desc = "Task info" },
      {
        "<leader>!!",
        function()
          vim.ui.input({ prompt = "Command: " }, function(cmd)
            if cmd and cmd ~= "" then
              require("overseer").new_task({
                cmd = vim.split(cmd, " "),
                components = { "default" },
              }):start()
            end
          end)
        end,
        desc = "Run shell command"
      },
    },
  },

  -- Modern folding with nvim-origami (serious nesting only)
  {
    "chrisgrieser/nvim-origami",
    event = "BufReadPost",
    opts = {
      keepFoldsAcrossSessions = true,
      pauseFoldsOnSearch = true,
      setupFoldKeymaps = true,
      -- Only create folds for serious nesting (4+ levels deep)
      foldlevelstart = 4,
      h = {
        auto_close = false, -- Don't auto-close, let user decide
        auto_open = true,
      },
    },
    config = function(_, opts)
      require("origami").setup(opts)

      -- Set folding method and levels for serious nesting only
      vim.opt.foldmethod = "indent"
      vim.opt.foldlevel = 3      -- Start folding at level 4 (0-indexed)
      vim.opt.foldlevelstart = 3 -- Open files with folds up to level 3
      vim.opt.foldnestmax = 10   -- Maximum fold nesting
      vim.opt.foldminlines = 4   -- Minimum lines needed to create a fold

      -- Language-specific fold settings for serious nesting
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("origami_filetype", { clear = true }),
        callback = function()
          local ft = vim.bo.filetype

          -- For code files, use treesitter folding with higher threshold
          if ft == "lua" or ft == "python" or ft == "javascript" or ft == "typescript"
              or ft == "jsx" or ft == "tsx" or ft == "rust" or ft == "go"
              or ft == "c" or ft == "cpp" or ft == "java" or ft == "dart" then
            vim.opt_local.foldmethod = "expr"
            vim.opt_local.foldexpr = "nvim_treesitter#foldexpr()"
            vim.opt_local.foldlevel = 4    -- Even more conservative for code
            vim.opt_local.foldminlines = 6 -- Need at least 6 lines to fold

            -- For markup files, be more conservative
          elseif ft == "markdown" or ft == "rst" or ft == "asciidoc" then
            vim.opt_local.foldmethod = "expr"
            vim.opt_local.foldexpr = "nvim_treesitter#foldexpr()"
            vim.opt_local.foldlevel = 2    -- Only fold deep sections
            vim.opt_local.foldminlines = 8 -- Need substantial content

            -- For config files, minimal folding
          elseif ft == "yaml" or ft == "json" or ft == "toml" or ft == "xml" then
            vim.opt_local.foldlevel = 5     -- Very deep nesting only
            vim.opt_local.foldminlines = 10 -- Large blocks only
          end
        end,
      })

      -- Enhanced folding keybindings (z-prefixed)
      local map = vim.keymap.set

      -- Core fold navigation (enhance existing z motions)
      map("n", "zj", "zj", { desc = "Next fold start" })
      map("n", "zk", "zk", { desc = "Previous fold start" })
      map("n", "zJ", function()
        vim.cmd("normal! zj")
        vim.cmd("normal! zo")
      end, { desc = "Next fold and open" })
      map("n", "zK", function()
        vim.cmd("normal! zk")
        vim.cmd("normal! zo")
      end, { desc = "Previous fold and open" })

      -- Enhanced fold management (z-prefixed)
      map("n", "zO", "zR", { desc = "Open all folds" })
      map("n", "zC", "zM", { desc = "Close all folds" })
      map("n", "zt", "za", { desc = "Toggle fold" })
      map("n", "zr", "zr", { desc = "Reduce fold level" })
      map("n", "zm", "zm", { desc = "More fold level" })

      -- Fold creation and deletion (z-prefixed)
      map("n", "zf", "zf", { desc = "Create fold" })
      map("v", "zf", "zf", { desc = "Create fold" })
      map("n", "zd", "zd", { desc = "Delete fold" })
      map("n", "zD", "zD", { desc = "Delete fold recursively" })
      map("n", "zE", "zE", { desc = "Eliminate all folds" })

      -- Advanced fold operations (z-prefixed)
      map("n", "zn", "zN", { desc = "Fold none (disable folding)" })
      map("n", "zi", "zi", { desc = "Invert fold enable" })
      map("n", "zx", "zx", { desc = "Update folds" })
      map("n", "zX", "zX", { desc = "Undo manual folds" })

      -- Fold level jumps (z-prefixed)
      map("n", "z1", function() vim.opt.foldlevel = 1 end, { desc = "Set fold level 1" })
      map("n", "z2", function() vim.opt.foldlevel = 2 end, { desc = "Set fold level 2" })
      map("n", "z3", function() vim.opt.foldlevel = 3 end, { desc = "Set fold level 3" })
      map("n", "z4", function() vim.opt.foldlevel = 4 end, { desc = "Set fold level 4" })
      map("n", "z5", function() vim.opt.foldlevel = 5 end, { desc = "Set fold level 5" })
      map("n", "z0", function() vim.opt.foldlevel = 0 end, { desc = "Set fold level 0 (close all)" })

      -- Enhanced which-key integration
      local ok, wk = pcall(require, "which-key")
      if ok then
        wk.add({
          { "z",  group = "fold" },
          -- Core fold operations
          { "za", desc = "toggle fold" },
          { "zo", desc = "open fold" },
          { "zc", desc = "close fold" },
          { "zt", desc = "toggle fold" },
          -- Navigation
          { "zj", desc = "next fold start" },
          { "zk", desc = "previous fold start" },
          { "zJ", desc = "next fold and open" },
          { "zK", desc = "previous fold and open" },
          -- Global operations
          { "zO", desc = "open all folds (zR)" },
          { "zC", desc = "close all folds (zM)" },
          { "zr", desc = "reduce fold level" },
          { "zm", desc = "more fold level" },
          -- Creation/deletion
          { "zf", desc = "create fold" },
          { "zd", desc = "delete fold" },
          { "zD", desc = "delete fold recursively" },
          { "zE", desc = "eliminate all folds" },
          -- Advanced
          { "zn", desc = "fold none (disable)" },
          { "zi", desc = "invert fold enable" },
          { "zx", desc = "update folds" },
          { "zX", desc = "undo manual folds" },
          -- Level shortcuts
          { "z0", desc = "fold level 0 (close all)" },
          { "z1", desc = "fold level 1" },
          { "z2", desc = "fold level 2" },
          { "z3", desc = "fold level 3" },
          { "z4", desc = "fold level 4" },
          { "z5", desc = "fold level 5" },
        })
      end
    end,
  },


  -- Color highlighting (colorizer)
  {
    "norcalli/nvim-colorizer.lua",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("colorizer").setup({
        filetypes = {
          "*", -- Highlight colors in all files
          css = { rgb_fn = true },
          scss = { rgb_fn = true },
          sass = { rgb_fn = true },
          html = { names = false },
          javascript = { RGB = true, RRGGBB = true },
          typescript = { RGB = true, RRGGBB = true },
          lua = { names = false },
        },
        user_default_options = {
          RGB = true,          -- #RGB hex codes
          RRGGBB = true,       -- #RRGGBB hex codes
          names = true,        -- "Name" codes like Blue or red
          RRGGBBAA = false,    -- #RRGGBBAA hex codes
          AARRGGBB = false,    -- 0xAARRGGBB hex codes
          rgb_fn = false,      -- CSS rgb() and rgba() functions
          hsl_fn = false,      -- CSS hsl() and hsla() functions
          css = false,         -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
          css_fn = false,      -- Enable all CSS *functions*: rgb_fn, hsl_fn
          -- Available modes for `mode`: foreground, background,  virtualtext
          mode = "background", -- Set the display mode
          -- Available methods are false / true / "normal" / "lsp" / "both"
          -- True is same as normal
          tailwind = false,                              -- Enable tailwind colors
          -- parsers can contain values used in |user_default_options|
          sass = { enable = true, parsers = { "css" } }, -- Enable sass colors
          virtualtext = "■",
          -- update color values even if buffer is not focused
          always_update = false
        },
        -- all the sub-options of filetypes apply to buftypes
        buftypes = {},
      })
    end,
    keys = {
      {
        "<leader>tc",
        "<cmd>ColorizerToggle<cr>",
        desc = "Toggle colorizer"
      },
      {
        "<leader>tC",
        "<cmd>ColorizerReloadAllBuffers<cr>",
        desc = "Reload colorizer"
      },
    },
  },

  -- iOS/macOS development with xcodebuild integration
  {
    "wojciech-kulik/xcodebuild.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "folke/snacks.nvim",
    },
    ft = { "swift", "objc", "objcpp" },
    config = function()
      require("xcodebuild").setup({
        restore_on_start = true,
        auto_save = true,
        -- Use snacks.nvim instead of telescope
        picker = {
          name = "snacks",
          commands = {
            select_device = function()
              local devices = require("xcodebuild.core.config").devices
              local items = {}
              for _, device in ipairs(devices or {}) do
                table.insert(items, {
                  text = device.name .. " (" .. device.platform .. ")",
                  value = device,
                })
              end
              
              Snacks.picker.pick({
                items = items,
                format = function(item) return item.text end,
                confirm = function(item)
                  require("xcodebuild.actions").select_device(item.value)
                end,
                title = "Select Device",
              })
            end,
            select_scheme = function()
              local schemes = require("xcodebuild.core.config").schemes
              local items = {}
              for _, scheme in ipairs(schemes or {}) do
                table.insert(items, {
                  text = scheme,
                  value = scheme,
                })
              end
              
              Snacks.picker.pick({
                items = items,
                format = function(item) return item.text end,
                confirm = function(item)
                  require("xcodebuild.actions").select_scheme(item.value)
                end,
                title = "Select Scheme",
              })
            end,
            select_config = function()
              local configs = { "Debug", "Release" }
              local items = {}
              for _, config in ipairs(configs) do
                table.insert(items, {
                  text = config,
                  value = config,
                })
              end
              
              Snacks.picker.pick({
                items = items,
                format = function(item) return item.text end,
                confirm = function(item)
                  require("xcodebuild.actions").select_config(item.value)
                end,
                title = "Select Configuration",
              })
            end,
          },
        },
        test_search = {
          file_matching = "filename_lsp",
          target_matching = true,
          lsp_client = "sourcekit",
          lsp_timeout = 200,
        },
        commands = {
          cache_devices = true,
        },
        logs = {
          auto_open_on_success_tests = false,
          auto_open_on_failed_tests = false,
          auto_open_on_success_build = false,
          auto_open_on_failed_build = true,
          auto_close_on_app_launch = false,
          auto_close_on_success_build = false,
          auto_focus = true,
          filetype = "objc",
          open_command = "silent botright 20split {path}",
          logs_formatter = {
            mark_progress = true,
            mark_succeeded_tests = true,
            mark_failed_tests = true,
            show_warnings = true,
            show_errors = true,
            show_build_warnings = true,
            show_build_errors = true,
            show_filepath_in_logs = false,
            show_xcodebuild_warnings = true,
          },
        },
        marks = {
          show_signs = true,
          success_sign = "✓",
          failure_sign = "✗",
          show_test_duration = true,
          show_diagnostics = true,
          file_pattern = "*Tests.swift",
        },
        quickfix = {
          show_errors_on_quickfixlist = true,
          show_warnings_on_quickfixlist = true,
        },
        test_explorer = {
          enabled = true,
          auto_open = true,
          auto_focus = false,
          open_command = "botright 42vsplit Test Explorer",
          open_expanded = true,
          success_sign = "✓",
          failure_sign = "✗",
          progress_sign = "…",
          disabled_sign = "⏸",
          partial_execution_sign = "‐",
          not_executed_sign = "",
          show_disabled_tests = false,
          animate_status = true,
          cursor_follows_tests = true,
        },
        code_coverage = {
          enabled = false,
          file_pattern = "*.swift",
          covered_sign = "",
          partially_covered_sign = "┃",
          not_covered_sign = "┃",
          not_executable_sign = "",
        },
        integrations = {
          oil_nvim = {
            enabled = true,
            should_update_project = function(path)
              return true
            end,
          },
        },
      })
    end,
    keys = {
      -- Build commands under cx prefix (xcodebuild)
      { "<leader>cxl", "<cmd>XcodebuildToggleLogs<cr>", desc = "Toggle Xcode logs" },
      { "<leader>cxb", "<cmd>XcodebuildBuild<cr>", desc = "Build project" },
      { "<leader>cxr", "<cmd>XcodebuildBuildRun<cr>", desc = "Build & Run project" },
      { "<leader>cxt", "<cmd>XcodebuildTest<cr>", desc = "Run tests" },
      { "<leader>cxT", "<cmd>XcodebuildTestClass<cr>", desc = "Run class tests" },
      { "<leader>cx.", "<cmd>XcodebuildTestSelected<cr>", desc = "Run selected tests", mode = "v" },
      
      -- Project management
      { "<leader>cxd", "<cmd>XcodebuildSelectDevice<cr>", desc = "Select device" },
      { "<leader>cxp", "<cmd>XcodebuildSelectTestPlan<cr>", desc = "Select test plan" },
      { "<leader>cxs", "<cmd>XcodebuildSelectScheme<cr>", desc = "Select scheme" },
      { "<leader>cxc", "<cmd>XcodebuildSelectConfig<cr>", desc = "Select config" },
      { "<leader>cxq", "<cmd>XcodebuildQuickfixLine<cr>", desc = "Quickfix line" },
      { "<leader>cxa", "<cmd>XcodebuildCodeActions<cr>", desc = "Show code actions" },
      
      -- Test Explorer
      { "<leader>cxe", "<cmd>XcodebuildTestExplorerToggle<cr>", desc = "Toggle Test Explorer" },
      { "<leader>cxi", "<cmd>XcodebuildTestExplorerRunSelectedTests<cr>", desc = "Run selected tests" },
      { "<leader>cxf", "<cmd>XcodebuildFailingSnapshots<cr>", desc = "Show failing snapshots" },
      
      -- Utilities
      { "<leader>cxX", "<cmd>XcodebuildCleanBuild<cr>", desc = "Clean build folder" },
      { "<leader>cxC", "<cmd>XcodebuildToggleCodeCoverage<cr>", desc = "Toggle code coverage" },
      { "<leader>cxS", "<cmd>XcodebuildFailingSnapshots<cr>", desc = "Show failing snapshots" },
      { "<leader>cxD", "<cmd>XcodebuildSelectDeveloperDir<cr>", desc = "Select Xcode version" },
    },
  },
}
