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

  -- AI Code Assistant (Chat Interface)
  {
    "yetone/avante.nvim",
    cmd = { "AvanteAsk", "AvanteChat", "AvanteToggle" },
    keys = {
      { "<leader>aa", mode = { "n", "v" } },
      { "<leader>ar", mode = "n" },
      { "<leader>ae", mode = "v" },
    },
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
    keys = {
      {
        "<leader>aa",
        function()
          require("avante.api").ask()
        end,
        desc = "avante: ask",
        mode = { "n", "v" },
      },
      {
        "<leader>ar",
        function()
          require("avante.api").refresh()
        end,
        desc = "avante: refresh",
      },
      {
        "<leader>ae",
        function()
          require("avante.api").edit()
        end,
        desc = "avante: edit",
        mode = "v",
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

  -- Virtual line diagnostics (current line only)
  {
    "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
    event = "LspAttach",
    config = function()
      require("lsp_lines").setup()

      -- Disable virtual text (we'll use lsp_lines instead)
      vim.diagnostic.config({
        virtual_text = false,
        virtual_lines = { only_current_line = true },
      })

      -- Auto-toggle: show diagnostics only for current line
      local group = vim.api.nvim_create_augroup("lsp_lines_current_line", { clear = true })

      vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        callback = function()
          -- Hide all virtual lines first
          vim.diagnostic.config({ virtual_lines = false })

          -- Show virtual lines only for current line if it has diagnostics
          local line = vim.api.nvim_win_get_cursor(0)[1] - 1
          local diagnostics = vim.diagnostic.get(0, { lnum = line })

          if #diagnostics > 0 then
            vim.diagnostic.config({ virtual_lines = { only_current_line = true } })
          end
        end,
      })

      -- Also show on CursorHold for a bit more stability
      vim.api.nvim_create_autocmd("CursorHold", {
        group = group,
        callback = function()
          local line = vim.api.nvim_win_get_cursor(0)[1] - 1
          local diagnostics = vim.diagnostic.get(0, { lnum = line })

          if #diagnostics > 0 then
            vim.diagnostic.config({ virtual_lines = { only_current_line = true } })
          else
            vim.diagnostic.config({ virtual_lines = false })
          end
        end,
      })
    end,
    keys = {
      {
        "<leader>dl",
        function()
          local config = vim.diagnostic.config() or {}
          if config.virtual_lines then
            vim.diagnostic.config({ virtual_lines = false })
          else
            vim.diagnostic.config({ virtual_lines = { only_current_line = true } })
          end
        end,
        desc = "Toggle LSP lines",
      },
    },
  },

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
      { "<leader>cfr", "<cmd>FlutterRun<cr>",           desc = "Flutter Run" },
      { "<leader>cfR", "<cmd>FlutterRestart<cr>",       desc = "Flutter Restart" },
      { "<leader>cfq", "<cmd>FlutterQuit<cr>",          desc = "Flutter Quit" },
      { "<leader>cfh", "<cmd>FlutterReload<cr>",        desc = "Flutter Hot Reload" },
      { "<leader>cfH", "<cmd>FlutterRestart<cr>",       desc = "Flutter Hot Restart" },
      { "<leader>cfd", "<cmd>FlutterDevices<cr>",       desc = "Flutter Devices" },
      { "<leader>cfe", "<cmd>FlutterEmulators<cr>",     desc = "Flutter Emulators" },
      { "<leader>cfo", "<cmd>FlutterOutlineToggle<cr>", desc = "Flutter Outline" },
      { "<leader>cfD", "<cmd>FlutterDevTools<cr>",      desc = "Flutter DevTools" },
      { "<leader>cfL", "<cmd>FlutterLogClear<cr>",      desc = "Flutter Log Clear" },
      { "<leader>cfs", "<cmd>FlutterSuper<cr>",         desc = "Flutter Super" },
      { "<leader>cfg", "<cmd>FlutterPubGet<cr>",        desc = "Flutter Pub Get" },
      { "<leader>cfG", "<cmd>FlutterPubUpgrade<cr>",    desc = "Flutter Pub Upgrade" },
      { "<leader>cfc", "<cmd>FlutterClean<cr>",         desc = "Flutter Clean" },
      { "<leader>cft", "<cmd>FlutterTest<cr>",          desc = "Flutter Test" },
      { "<leader>cfT", "<cmd>FlutterTestAll<cr>",       desc = "Flutter Test All" },
      { "<leader>cfv", "<cmd>FlutterVersion<cr>",       desc = "Flutter Version" },
      { "<leader>cfp", "<cmd>FlutterPubDeps<cr>",       desc = "Flutter Pub Deps" },
      { "<leader>cfn", "<cmd>FlutterRename<cr>",        desc = "Flutter Rename" },
      { "<leader>cfi", "<cmd>FlutterScreenshot<cr>",    desc = "Flutter Screenshot" },
    },
    config = function(_, opts)
      require("flutter-tools").setup(opts)

      -- Enhanced which-key integration for Flutter
      local ok, wk = pcall(require, "which-key")
      if ok then
        wk.add({
          { "<leader>cf",  group = "flutter",    ft = "dart" },
          { "<leader>cfr", desc = "run",         ft = "dart" },
          { "<leader>cfR", desc = "restart",     ft = "dart" },
          { "<leader>cfq", desc = "quit",        ft = "dart" },
          { "<leader>cfh", desc = "hot reload",  ft = "dart" },
          { "<leader>cfH", desc = "hot restart", ft = "dart" },
          { "<leader>cfd", desc = "devices",     ft = "dart" },
          { "<leader>cfe", desc = "emulators",   ft = "dart" },
          { "<leader>cfo", desc = "outline",     ft = "dart" },
          { "<leader>cfD", desc = "devtools",    ft = "dart" },
          { "<leader>cfL", desc = "log clear",   ft = "dart" },
          { "<leader>cfs", desc = "super",       ft = "dart" },
          { "<leader>cfg", desc = "pub get",     ft = "dart" },
          { "<leader>cfG", desc = "pub upgrade", ft = "dart" },
          { "<leader>cfc", desc = "clean",       ft = "dart" },
          { "<leader>cft", desc = "test",        ft = "dart" },
          { "<leader>cfT", desc = "test all",    ft = "dart" },
          { "<leader>cfv", desc = "version",     ft = "dart" },
          { "<leader>cfp", desc = "pub deps",    ft = "dart" },
          { "<leader>cfn", desc = "rename",      ft = "dart" },
          { "<leader>cfi", desc = "screenshot",  ft = "dart" },
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
        "igorlfs/nvim-dap-view",
        config = function()
          require("dap-view").setup({
            windows = {
              height = 12,
              position = "below",
              terminal = {
                position = "right",
                width = 0.5,
                -- List of debug adapters for which the terminal should be ALWAYS hidden
                hide = {},
                -- Hide the terminal when starting a new session
                start_hidden = false,
              },
            },
          })
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
      { "<leader>dw", function() require("dap.ui.widgets").hover() end,                                     desc = "Widgets" },
      { "<leader>dv", function() require("dap-view").toggle() end,                                          desc = "DAP View" },
    },
    config = function()
      local dap = require("dap")

      -- Configure signs
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◐", texthl = "DiagnosticWarn" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticInfo" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DiagnosticWarn", linehl = "Visual" })

      -- DAP Virtual Text
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
    keys = {
      { "<leader>oc", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "CodeCompanion Chat" },
      { "<leader>oa", "<cmd>CodeCompanionActions<cr>",     mode = { "n", "v" }, desc = "CodeCompanion Actions" },
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
                default = "qwen3-32b-mlx" -- Default model (change as needed)
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

      -- Auto-activate otter for supported filetypes
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "quarto", "rmd", "markdown" },
        callback = function()
          -- Delay activation to ensure buffer is fully loaded
          vim.defer_fn(function()
            require("otter").activate({ "r", "python", "julia", "bash" })
          end, 100)
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
    },
  },

  -- Modern project root detection (2024/2025)
  {
    "ygm2/rooter.nvim",
    event = "VeryLazy",
    config = function()
      -- Simple setup - this plugin might not need complex configuration
      local ok = pcall(require, "rooter")
      if not ok then
        vim.notify("Failed to load rooter.nvim", vim.log.levels.ERROR)
        return
      end

      -- Set up patterns and behavior through vim variables (common pattern for rooter plugins)
      vim.g.rooter_patterns = {
        ".git",
        "package.json",
        "Cargo.toml",
        "go.mod",
        "pyproject.toml",
        "setup.py",
        "requirements.txt",
        "Pipfile",
        "poetry.lock",
        "composer.json",
        "mix.exs",
        "rebar.config",
        "Makefile",
        "astro.config.mjs",
        "astro.config.js",
        "astro.config.ts",
        "deno.json",
        "deno.jsonc",
        ".Rprofile",
        "DESCRIPTION",
        "pubspec.yaml",
      }

      vim.g.rooter_silent_chdir = 1
      vim.g.rooter_change_directory_for_non_project_files = 'current'
      vim.g.rooter_resolve_links = 1

      -- Add manual commands
      vim.api.nvim_create_user_command("ProjectRoot", function()
        -- Use vim's built-in rooter function or implement simple logic
        local patterns = vim.g.rooter_patterns
        local current_dir = vim.fn.expand('%:p:h')
        local root_dir = current_dir

        -- Simple root detection logic
        for _, pattern in ipairs(patterns) do
          local found = vim.fn.finddir(pattern, current_dir .. ';')
          if found ~= '' then
            root_dir = vim.fn.fnamemodify(found, ':h')
            break
          end

          local found_file = vim.fn.findfile(pattern, current_dir .. ';')
          if found_file ~= '' then
            root_dir = vim.fn.fnamemodify(found_file, ':h')
            break
          end
        end

        if root_dir ~= current_dir then
          vim.cmd('cd ' .. root_dir)
          vim.notify("Project root: " .. root_dir, vim.log.levels.INFO)
        else
          vim.notify("No project root found", vim.log.levels.WARN)
        end
      end, { desc = "Set project root manually" })

      -- Show current project root info
      vim.api.nvim_create_user_command("ProjectInfo", function()
        local cwd = vim.fn.getcwd()
        local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")

        if vim.v.shell_error == 0 and git_root ~= "" then
          vim.notify(string.format("Current: %s\nGit root: %s", cwd, git_root), vim.log.levels.INFO)
        else
          vim.notify("Current: " .. cwd, vim.log.levels.INFO)
        end
      end, { desc = "Show current project info" })

      -- Auto-change to project root on file open
      vim.api.nvim_create_autocmd({ "BufRead", "BufWinEnter", "BufNewFile" }, {
        group = vim.api.nvim_create_augroup("rooter_auto", { clear = true }),
        callback = function()
          vim.schedule(function()
            vim.cmd("ProjectRoot")
          end)
        end,
      })
    end,
    keys = {
      {
        "<leader>fP",
        "<cmd>ProjectRoot<cr>",
        desc = "Set Project Root"
      },
      {
        "<leader>fI",
        "<cmd>ProjectInfo<cr>",
        desc = "Project Info"
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
            vim.cmd("ProjectRoot")
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

  -- Multiple cursors (Doom Emacs gz style)
  {
    "zaucy/mcos.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      delay = 500,
      show_numbers = true,
      max_cursors = 50,
      wrap_around = true,
      vim_command_hooks = {
        before = {},
        after = {},
      },
    },
    config = function(_, opts)
      require("mcos").setup(opts)

      -- Custom highlight groups to match theme
      vim.api.nvim_set_hl(0, "McosCursor", { fg = "#ffffff", bg = "#bb9af7" })
      vim.api.nvim_set_hl(0, "McosVisual", { fg = "#000000", bg = "#666666" })
      vim.api.nvim_set_hl(0, "McosNumber", { fg = "#bb9af7", bold = true })
    end,
    keys = {
      -- Doom Emacs gz prefix keybindings
      {
        "gzm",
        function()
          require("mcos").find_next()
        end,
        mode = { "n", "v" },
        desc = "Add cursor at next match"
      },
      {
        "gzM",
        function()
          require("mcos").find_prev()
        end,
        mode = { "n", "v" },
        desc = "Add cursor at previous match"
      },
      {
        "gzs",
        function()
          require("mcos").skip_next()
        end,
        mode = { "n", "v" },
        desc = "Skip next match"
      },
      {
        "gzS",
        function()
          require("mcos").skip_prev()
        end,
        mode = { "n", "v" },
        desc = "Skip previous match"
      },
      {
        "gza",
        function()
          require("mcos").find_all()
        end,
        mode = { "n", "v" },
        desc = "Add cursors at all matches"
      },
      {
        "gzc",
        function()
          require("mcos").clear()
        end,
        mode = { "n", "v" },
        desc = "Clear all cursors"
      },
      {
        "gzj",
        function()
          require("mcos").add_cursor_down()
        end,
        mode = { "n", "v" },
        desc = "Add cursor below"
      },
      {
        "gzk",
        function()
          require("mcos").add_cursor_up()
        end,
        mode = { "n", "v" },
        desc = "Add cursor above"
      },
      -- Alternative quick access (keeping some common patterns)
      {
        "<C-n>",
        function()
          require("mcos").find_next()
        end,
        mode = { "n", "v" },
        desc = "Add cursor at next match"
      },
      {
        "<Esc>",
        function()
          require("mcos").clear()
        end,
        mode = { "n", "v" },
        desc = "Clear all cursors"
      },
    },
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
}

