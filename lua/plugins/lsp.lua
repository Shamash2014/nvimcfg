return {
  "neovim/nvim-lspconfig",
  event = "VeryLazy",
  config = function()
    local capabilities = require("blink.cmp").get_lsp_capabilities()

    local default_config = {
      capabilities = capabilities,
      flags = {
        debounce_text_changes = 150,
      },
    }

    vim.lsp.config("*", default_config)

    local original_schedule = vim.schedule
    local lsp_error_suppression_active = false

    vim.schedule = function(fn)
      return original_schedule(function()
        local ok, err = pcall(fn)
        if not ok then
          local err_str = tostring(err)
          if err_str:match("unhandled method") or err_str:match("code = 123") or err_str:match("code_name = unknown") then
            if not lsp_error_suppression_active then
              lsp_error_suppression_active = true
              original_schedule(function()
                vim.notify(
                  "LSP initialization error suppressed.\n" ..
                  "A language server failed to respond to the initialize method.\n" ..
                  "This is usually safe to ignore. Check :LspLog if needed.",
                  vim.log.levels.WARN
                )
                vim.defer_fn(function()
                  lsp_error_suppression_active = false
                end, 5000)
              end)
            end
            return
          end
          error(err)
        end
      end)
    end

    local function safe_enable(server_name)
      local ok, err = pcall(vim.lsp.enable, server_name)
      if not ok then
        vim.schedule(function()
          local error_msg = tostring(err)
          if error_msg:match("unhandled method") or error_msg:match("RPC") then
            vim.notify(
              string.format("LSP '%s' failed to initialize.\nError: %s\nCheck :LspInfo for details.", server_name, error_msg),
              vim.log.levels.ERROR
            )
          else
            vim.notify("Failed to enable " .. server_name .. ": " .. error_msg, vim.log.levels.WARN)
          end
        end)
        return false
      end
      return true
    end

    if vim.fn.executable("vtsls") == 1 then
      vim.lsp.config("vtsls", {
        filetypes = {
          "javascript",
          "javascriptreact",
          "javascript.jsx",
          "typescript",
          "typescriptreact",
          "typescript.tsx",
          "vue"
        },
        settings = {
          complete_function_calls = true,
          vtsls = {
            enableMoveToFileCodeAction = true,
            autoUseWorkspaceTsdk = true,
            experimental = {
              maxInlayHintLength = 30,
              completion = {
                enableServerSideFuzzyMatch = true,
              },
            },
          },
          typescript = {
            globalPlugins = {
              {
                name = "@angular/language-service",
                location = vim.fs.normalize("node_modules/@angular/language-service"),
                enableForWorkspaceTypeScriptVersions = false,
              },
            },
            updateImportsOnFileMove = { enabled = "always" },
            suggest = {
              completeFunctionCalls = true,
              autoImports = true,
              includeCompletionsForModuleExports = true,
            },
            preferences = {
              importModuleSpecifier = "relative",
              includePackageJsonAutoImports = "on",
            },
            inlayHints = {
              enumMemberValues = { enabled = true },
              functionLikeReturnTypes = { enabled = true },
              parameterNames = { enabled = "literals" },
              parameterTypes = { enabled = true },
              variableTypes = { enabled = false },
              propertyDeclarationTypes = { enabled = true }
            },
            format = {
              enable = true,
              semicolons = "insert",
              insertSpaceAfterOpeningAndBeforeClosingNonemptyBraces = true,
              insertSpaceAfterOpeningAndBeforeClosingTemplateStringBraces = false,
            },
            workspaceSymbols = {
              scope = "allOpenProjects",
            },
          },
          javascript = {
            updateImportsOnFileMove = { enabled = "always" },
            suggest = {
              completeFunctionCalls = true,
              autoImports = true,
              includeCompletionsForModuleExports = true,
            },
            preferences = {
              importModuleSpecifier = "relative",
              includePackageJsonAutoImports = "on",
            },
            inlayHints = {
              enumMemberValues = { enabled = true },
              functionLikeReturnTypes = { enabled = true },
              parameterNames = { enabled = "literals" },
              parameterTypes = { enabled = true },
              variableTypes = { enabled = false },
              propertyDeclarationTypes = { enabled = true }
            },
            format = {
              enable = true,
              semicolons = "insert",
              insertSpaceAfterOpeningAndBeforeClosingNonemptyBraces = true,
              insertSpaceAfterOpeningAndBeforeClosingTemplateStringBraces = false,
            },
          },
        },
      })
      safe_enable("vtsls")
    end

    if vim.fn.executable("basedpyright") == 1 or vim.fn.executable("basedpyright-langserver") == 1 then
      safe_enable("basedpyright")
    end

    if vim.fn.executable("rust-analyzer") == 1 then
      vim.lsp.config("rust_analyzer", {
      settings = {
        ["rust-analyzer"] = {
          imports = {
            granularity = {
              group = "module",
            },
            prefix = "self",
          },
          cargo = {
            buildScripts = {
              enable = true,
            },
          },
          procMacro = {
            enable = true,
          },
          diagnostics = {
            enable = true,
            experimental = {
              enable = true,
            },
          },
          checkOnSave = {
            command = "clippy",
            extraArgs = { "--no-deps" },
          },
          inlayHints = {
            bindingModeHints = {
              enable = false,
            },
            chainingHints = {
              enable = true,
            },
            closingBraceHints = {
              enable = true,
              minLines = 25,
            },
            closureReturnTypeHints = {
              enable = "never",
            },
            lifetimeElisionHints = {
              enable = "never",
              useParameterNames = false,
            },
            maxLength = 25,
            parameterHints = {
              enable = true,
            },
            reborrowHints = {
              enable = "never",
            },
            renderColons = true,
            typeHints = {
              enable = true,
              hideClosureInitialization = false,
              hideNamedConstructor = false,
            },
          },
          lens = {
            enable = true,
          },
          hover = {
            actions = {
              enable = true,
            },
          },
        },
      },
      })
      safe_enable("rust_analyzer")
    end

    if vim.fn.executable("dart") == 1 then
      vim.lsp.config("dartls", {
      cmd = { "dart", "language-server", "--protocol=lsp" },
      filetypes = { "dart" },
      root_markers = { "pubspec.yaml", ".git" },
      init_options = {
        onlyAnalyzeProjectsWithOpenFiles = false,
        suggestFromUnimportedLibraries = true,
        closingLabels = true,
        outline = true,
        flutterOutline = true,
      },
      settings = {
        dart = {
          completeFunctionCalls = true,
          showTodos = true,
          renameFilesWithClasses = "prompt",
          updateImportsOnRename = true,
          insertArgumentPlaceholders = true,
          analysisExcludedFolders = {
            vim.fn.expand("$HOME/AppData/Local/Pub/Cache"),
            vim.fn.expand("$HOME/.pub-cache"),
            vim.fn.expand("/opt/homebrew/"),
            vim.fn.expand("$HOME/tools/flutter/"),
            ".dart_tool",
            "build",
          },
          enableSdkFormatter = true,
          lineLength = 80,
          enableSnippets = true,
        },
      },
      on_attach = function(client, bufnr)
        vim.b[bufnr].flutter_outline = nil

        local namespace = vim.api.nvim_create_namespace("flutter_closing_labels")

        local handlers = client.handlers or {}

        handlers["dart/textDocument/publishFlutterOutline"] = function(err, result, ctx)
          if err then return end
          local uri = result.uri
          local buf = vim.uri_to_bufnr(uri)
          if result and result.outline and vim.api.nvim_buf_is_valid(buf) then
            vim.b[buf].flutter_outline = result.outline
          end
        end

        handlers["dart/textDocument/publishClosingLabels"] = function(err, result, ctx)
          local uri = result.uri
          local buf = vim.uri_to_bufnr(uri)

          if not vim.api.nvim_buf_is_valid(buf) then
            return
          end

          if err or not result or not result.labels then
            vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
            return
          end

          vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

          for _, label in ipairs(result.labels) do
            local line = label.range["end"].line
            if line then
              vim.api.nvim_buf_set_extmark(buf, namespace, line, 0, {
                virt_text = { { "  // " .. label.label, "Comment" } },
                virt_text_pos = "eol",
                hl_mode = "combine",
              })
            end
          end
        end

        client.handlers = handlers

        vim.keymap.set("n", "<localleader>r", ":FlutterReload<CR>", { buffer = bufnr, desc = "Flutter Hot Reload" })
        vim.keymap.set("n", "<localleader>R", ":FlutterRestart<CR>", { buffer = bufnr, desc = "Flutter Hot Restart" })
        vim.keymap.set("n", "<localleader>q", ":FlutterQuit<CR>", { buffer = bufnr, desc = "Flutter Quit" })
        vim.keymap.set("n", "<localleader>d", ":FlutterDevices<CR>", { buffer = bufnr, desc = "Flutter Devices" })
        vim.keymap.set("n", "<localleader>l", ":FlutterLog<CR>", { buffer = bufnr, desc = "Flutter Logs" })
        vim.keymap.set("n", "<localleader>c", ":FlutterLogClear<CR>", { buffer = bufnr, desc = "Clear Flutter Logs" })
        vim.keymap.set("n", "<localleader>p", ":FlutterPubGet<CR>", { buffer = bufnr, desc = "Flutter Pub Get" })
        vim.keymap.set("n", "<localleader>u", ":FlutterPubUpgrade<CR>", { buffer = bufnr, desc = "Flutter Pub Upgrade" })
        vim.keymap.set("n", "<localleader>o", ":FlutterOutline<CR>", { buffer = bufnr, desc = "Flutter Widget Outline" })

        local Job = require('plenary.job')

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterReload", function()
          vim.notify("Flutter Hot Reload triggered", vim.log.levels.INFO)
          Job:new({
            command = 'sh',
            args = { '-c', 'kill -USR1 $(pgrep -f flutter_runner)' },
            on_exit = function(j, return_val)
              vim.schedule(function()
                if return_val == 0 then
                  vim.notify("Hot reload signal sent", vim.log.levels.INFO)
                else
                  vim.notify("No Flutter process found", vim.log.levels.WARN)
                end
              end)
            end,
          }):start()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterRestart", function()
          vim.notify("Flutter Hot Restart triggered", vim.log.levels.INFO)
          Job:new({
            command = 'sh',
            args = { '-c', 'kill -USR2 $(pgrep -f flutter_runner)' },
            on_exit = function(j, return_val)
              vim.schedule(function()
                if return_val == 0 then
                  vim.notify("Hot restart signal sent", vim.log.levels.INFO)
                else
                  vim.notify("No Flutter process found", vim.log.levels.WARN)
                end
              end)
            end,
          }):start()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterQuit", function()
          vim.notify("Quitting Flutter app", vim.log.levels.INFO)
          Job:new({
            command = 'sh',
            args = { '-c', 'kill -QUIT $(pgrep -f flutter_runner)' },
            on_exit = function(j, return_val)
              vim.schedule(function()
                if return_val == 0 then
                  vim.notify("Flutter app quit", vim.log.levels.INFO)
                else
                  vim.notify("No Flutter process found", vim.log.levels.WARN)
                end
              end)
            end,
          }):start()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterDevices", function()
          Job:new({
            command = 'flutter',
            args = { 'devices' },
            on_exit = function(j, return_val)
              local output = table.concat(j:result(), '\n')
              vim.schedule(function()
                vim.notify(output, vim.log.levels.INFO)
              end)
            end,
          }):start()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterLog", function()
          require("snacks").terminal.open("flutter logs", {
            cwd = vim.fn.getcwd(),
            env = { PATH = vim.env.PATH },
            interactive = true,
            win = {
              position = "bottom",
              height = 0.3,
              border = "rounded",
            },
          })
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterLogClear", function()
          Job:new({
            command = 'flutter',
            args = { 'logs', '--clear' },
            on_exit = function(j, return_val)
              vim.schedule(function()
                if return_val == 0 then
                  vim.notify("Flutter logs cleared", vim.log.levels.INFO)
                else
                  vim.notify("Failed to clear Flutter logs", vim.log.levels.ERROR)
                end
              end)
            end,
          }):start()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterPubGet", function()
          vim.notify("Running flutter pub get...", vim.log.levels.INFO)
          Job:new({
            command = 'flutter',
            args = { 'pub', 'get' },
            on_exit = function(j, return_val)
              local output = table.concat(j:result(), '\n')
              vim.schedule(function()
                if return_val == 0 then
                  vim.notify("Dependencies installed successfully", vim.log.levels.INFO)
                else
                  vim.notify("Failed to install dependencies:\n" .. output, vim.log.levels.ERROR)
                end
              end)
            end,
          }):start()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterPubUpgrade", function()
          vim.notify("Running flutter pub upgrade...", vim.log.levels.INFO)
          Job:new({
            command = 'flutter',
            args = { 'pub', 'upgrade' },
            on_exit = function(j, return_val)
              local output = table.concat(j:result(), '\n')
              vim.schedule(function()
                if return_val == 0 then
                  vim.notify("Dependencies upgraded successfully", vim.log.levels.INFO)
                else
                  vim.notify("Failed to upgrade dependencies:\n" .. output, vim.log.levels.ERROR)
                end
              end)
            end,
          }):start()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "FlutterOutline", function()
          local outline = vim.b[bufnr].flutter_outline

          if not outline then
            vim.notify("No Flutter outline available. Make sure the file has been analyzed.", vim.log.levels.WARN)
            return
          end

          local items = {}
          local function traverse_outline(node, depth)
            depth = depth or 0
            local indent = string.rep("  ", depth)

            local kind = node.kind or "Widget"
            local className = node.className or node.label or "Unknown"
            local range = node.codeRange or node.range

            if range then
              table.insert(items, {
                text = string.format("%s%s: %s", indent, kind, className),
                line = range.start.line + 1,
                col = range.start.character + 1,
                node = node,
              })
            end

            if node.children then
              for _, child in ipairs(node.children) do
                traverse_outline(child, depth + 1)
              end
            end
          end

          traverse_outline(outline)

          if #items == 0 then
            vim.notify("Flutter outline is empty", vim.log.levels.WARN)
            return
          end

          require("snacks").picker({
            title = "Flutter Widget Outline",
            items = items,
            format = "text",
            layout = { preset = "vscode" },
            confirm = function(picker, item)
              picker:close()
              if item and item.line then
                vim.api.nvim_win_set_cursor(0, { item.line, item.col - 1 })
                vim.cmd("normal! zz")
              end
            end,
          })
        end, {})

        vim.keymap.set("v", "<localleader>w", function()
          local start_row, start_col = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
          local end_row, end_col = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))
          local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

          local indent = lines[1]:match("^%s*")
          vim.api.nvim_buf_set_lines(bufnr, start_row - 1, start_row - 1, false, { indent .. "Container(" })
          vim.api.nvim_buf_set_lines(bufnr, end_row + 1, end_row + 1, false, { indent .. "  child: " })
          vim.api.nvim_buf_set_lines(bufnr, end_row + 2, end_row + 2, false, { indent .. ")," })
        end, { buffer = bufnr, desc = "Wrap with Widget" })
      end,
      })
      safe_enable("dartls")
    end

    if vim.fn.executable("gopls") == 1 then
      vim.lsp.config("gopls", {
      cmd = { "gopls" },
      filetypes = { "go", "gomod", "gowork", "gotmpl" },
      root_markers = { "go.work", "go.mod", ".git" },
      settings = {
        gopls = {
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
            nilness = true,
            unusedparams = true,
            unusedwrite = true,
            useany = true,
            shadow = true,
            unusedvariable = true,
          },
          usePlaceholders = true,
          completeUnimported = true,
          staticcheck = true,
          directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
          semanticTokens = true,
          templateExtensions = { "tpl", "tmpl", "gotmpl" },
          buildFlags = { "-tags=integration" },
        },
      },
      on_attach = function(client, bufnr)
        if client.server_capabilities.inlayHintProvider then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end

        local opts = { buffer = bufnr, silent = true }

        vim.keymap.set("n", "<localleader>i", function()
          vim.lsp.buf.code_action({
            context = { only = { "source.organizeImports" }, diagnostics = {} },
            apply = true,
          })
        end, vim.tbl_extend("force", opts, { desc = "Organize Imports" }))

        vim.keymap.set("n", "<localleader>fs", function()
          vim.lsp.buf.code_action({
            context = { only = { "refactor.rewrite" }, diagnostics = {} },
            apply = true,
          })
        end, vim.tbl_extend("force", opts, { desc = "Fill struct" }))

        vim.keymap.set("n", "<localleader>gt", function()
          vim.lsp.buf.code_action({
            context = { only = { "source.generateTest" }, diagnostics = {} },
            apply = true,
          })
        end, vim.tbl_extend("force", opts, { desc = "Generate test" }))

        vim.keymap.set("n", "<localleader>m", function()
          vim.lsp.buf.code_action({
            context = { only = { "source.fixAll" }, diagnostics = {} },
            apply = true,
          })
          vim.notify("Running go mod tidy", vim.log.levels.INFO)
        end, vim.tbl_extend("force", opts, { desc = "Go mod tidy" }))

        vim.keymap.set("n", "<localleader>h", function()
          vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
        end, vim.tbl_extend("force", opts, { desc = "Toggle inlay hints" }))

        vim.keymap.set("n", "<localleader>t", function()
          local current_file = vim.fn.expand("%:p:h")
          require("snacks").terminal("go test -v ./...", {
            cwd = current_file,
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Run tests" }))

        vim.keymap.set("n", "<localleader>r", function()
          local current_file = vim.fn.expand("%")
          require("snacks").terminal("go run " .. current_file, {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Run current file" }))

        vim.keymap.set("n", "<localleader>b", function()
          require("snacks").terminal("go build", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Build project" }))
      end,
      })
      safe_enable("gopls")
    end

    if vim.fn.executable("ngserver") == 1 then
      vim.lsp.config("angularls", {
      cmd = { "ngserver", "--stdio", "--tsProbeLocations", "", "--ngProbeLocations", "" },
      filetypes = { "typescript", "html", "typescriptreact", "typescript.tsx", "htmlangular" },
      root_markers = { "angular.json", ".git" },
      on_attach = function(client, bufnr)
        local opts = { buffer = bufnr, silent = true }

        vim.keymap.set("n", "<localleader>gc", function()
          vim.lsp.buf.definition()
        end, vim.tbl_extend("force", opts, { desc = "Go to component" }))

        vim.keymap.set("n", "<localleader>gt", function()
          vim.cmd("edit %:r.html")
        end, vim.tbl_extend("force", opts, { desc = "Go to template" }))

        vim.keymap.set("n", "<localleader>gs", function()
          vim.cmd("edit %:r.scss")
        end, vim.tbl_extend("force", opts, { desc = "Go to styles" }))

        vim.keymap.set("n", "<localleader>gT", function()
          vim.cmd("edit %:r.spec.ts")
        end, vim.tbl_extend("force", opts, { desc = "Go to test" }))
      end,
      })
      safe_enable("angularls")
    end

    if vim.fn.executable("astro-ls") == 1 then
      vim.lsp.config("astro", {
      cmd = { "astro-ls", "--stdio" },
      filetypes = { "astro" },
      root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
      init_options = {
        typescript = {
          tsdk = vim.fs.normalize("node_modules/typescript/lib")
        },
      },
      settings = {
        astro = {
          updateImportsOnFileMove = {
            enabled = true
          },
        },
        typescript = {
          globalPlugins = {
            {
              name = "@astrojs/ts-plugin",
              location = vim.fs.normalize("node_modules/@astrojs/ts-plugin"),
              enableForWorkspaceTypeScriptVersions = true,
            },
          },
        },
      },
      on_attach = function(client, bufnr)
        local opts = { buffer = bufnr, silent = true }

        vim.keymap.set("n", "<localleader>f", function()
          vim.lsp.buf.format({ async = true })
        end, vim.tbl_extend("force", opts, { desc = "Format Astro file" }))

        vim.keymap.set("n", "<localleader>b", function()
          require("snacks").terminal("npm run build", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Build Astro project" }))

        vim.keymap.set("n", "<localleader>d", function()
          require("snacks").terminal("npm run dev", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Start dev server" }))
      end,
      })
      safe_enable("astro")
    end

    if vim.fn.executable("tailwindcss-language-server") == 1 then
      vim.lsp.config("tailwindcss", {
      cmd = { "tailwindcss-language-server", "--stdio" },
      filetypes = { "html", "css", "javascript", "javascriptreact", "typescript", "typescriptreact", "astro", "vue", "svelte" },
      root_markers = { "tailwind.config.js", "tailwind.config.cjs", "tailwind.config.mjs", "tailwind.config.ts", ".git" },
      settings = {
        tailwindCSS = {
          validate = true,
          classAttributes = { "class", "className", "class:list", "classList", "ngClass" },
          lint = {
            cssConflict = "warning",
            invalidApply = "error",
            invalidConfigPath = "error",
            invalidScreen = "error",
            invalidTailwindDirective = "error",
            invalidVariant = "error",
            recommendedVariantOrder = "warning",
          },
          experimental = {
            classRegex = {
              -- Support for clsx/cn functions
              { "clsx\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
              { "cn\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
              -- Angular class bindings
              { "\\[class\\]=\\\"([^\"]*)\\\"", "([^\"]*)" },
              { "\\[ngClass\\]=\\\"([^\"]*)\\\"", "([^\"]*)" },
            },
          },
        },
      },
      })
      safe_enable("tailwindcss")
    end

    if vim.fn.executable("vscode-html-language-server") == 1 then
      vim.lsp.config("html", {
      cmd = { "vscode-html-language-server", "--stdio" },
      filetypes = { "html", "htmlangular" },
      root_markers = { "package.json", ".git" },
      init_options = {
        configurationSection = { "html", "css", "javascript" },
        embeddedLanguages = {
          css = true,
          javascript = true,
        },
        provideFormatter = true,
      },
      settings = {
        html = {
          format = {
            enable = true,
            wrapLineLength = 120,
            unformatted = "",
            contentUnformatted = "pre,code,textarea",
            indentInnerHtml = false,
            preserveNewLines = true,
            maxPreserveNewLines = 2,
            indentHandlebars = false,
            endWithNewline = true,
            extraLiners = "",
            wrapAttributes = "auto",
          },
          validate = {
            scripts = true,
            styles = true,
          },
        },
      },
      })
      safe_enable("html")
    end

    if vim.fn.executable("vscode-css-language-server") == 1 then
      vim.lsp.config("cssls", {
      cmd = { "vscode-css-language-server", "--stdio" },
      filetypes = { "css", "scss", "less" },
      root_markers = { "package.json", ".git" },
      settings = {
        css = {
          validate = true,
          lint = {
            unknownAtRules = "ignore",
          },
        },
        scss = {
          validate = true,
          lint = {
            unknownAtRules = "ignore",
          },
        },
      },
      })
      safe_enable("cssls")
    end

    if vim.fn.executable("ls_emmet") == 1 then
      vim.lsp.config("ls_emmet", {
      cmd = { "ls_emmet", "--stdio" },
      filetypes = { "html", "css", "scss", "javascript", "typescript", "vue", "svelte" },
      root_markers = { "package.json", ".git" },
      settings = {
        html = {
          preferences = {
            -- Enable emmet abbreviation expansion
            expandAbbreviation = true,
          },
        },
      },
      })
      safe_enable("ls_emmet")
    end

    if vim.fn.executable('xcode-build-server') == 1 then
      vim.lsp.config("xcode_build_server", {
        cmd = { 'xcode-build-server' },
        filetypes = { 'swift', 'objective-c', 'objective-cpp' },
        root_markers = { '*.xcodeproj', '*.xcworkspace', 'Package.swift', '.git' },
        init_options = {
          preferences = {
            useBuildSystemSettings = true,
            enableIndexing = true,
          },
        },
      })
      safe_enable("xcode_build_server")
    end

    if vim.fn.executable("sourcekit-lsp") == 1 then
      vim.lsp.config("sourcekit", {
      cmd = { "sourcekit-lsp" },
      filetypes = { "swift", "objective-c", "objective-cpp" },
      root_markers = { "Package.swift", "Package.resolved", ".git", "*.xcodeproj", "*.xcworkspace" },
      capabilities = vim.tbl_deep_extend("force", capabilities, {
        workspace = {
          workspaceFolders = true,
        },
        textDocument = {
          completion = {
            completionItem = {
              snippetSupport = true,
              resolveSupport = {
                properties = { "documentation", "detail", "additionalTextEdits" },
              },
            },
          },
        },
      }),
      settings = {
        sourcekit = {
          trace = "verbose",
          enableBSP = vim.fn.executable('xcode-build-server') == 1,
        },
      },
      on_attach = function(client, bufnr)
        if client.server_capabilities.inlayHintProvider then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end

        local opts = { buffer = bufnr, silent = true }

        vim.keymap.set("n", "<localleader>b", function()
          require("snacks").terminal("xcede build", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Build with xcede" }))

        vim.keymap.set("n", "<localleader>br", function()
          require("snacks").terminal("xcede buildrun", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Build and run with xcede" }))

        vim.keymap.set("n", "<localleader>t", function()
          require("snacks").terminal("xcede test", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Test with xcede" }))

        vim.keymap.set("n", "<localleader>c", function()
          require("snacks").terminal("xcede clean", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Clean with xcede" }))

        -- xcede with scheme selection (async)
        vim.keymap.set("n", "<localleader>bs", function()
          local Job = require("plenary.job")
          Job:new({
            command = "sh",
            args = { "-c", "xcede list --schemes 2>/dev/null | grep -E '^-\\s+' | sed 's/^-\\s*//'" },
            on_exit = function(j, return_val)
              vim.schedule(function()
                local schemes = table.concat(j:result(), "\n")
                if schemes == "" then
                  require("snacks").terminal("xcede build", {
                    win = { position = "bottom", height = 0.3 },
                  })
                else
                  vim.ui.select(vim.split(schemes, "\n"), {
                    prompt = "Select scheme to build:",
                  }, function(choice)
                    if choice then
                      require("snacks").terminal("xcede build --scheme " .. choice, {
                        win = { position = "bottom", height = 0.3 },
                      })
                    end
                  end)
                end
              end)
            end,
          }):start()
        end, vim.tbl_extend("force", opts, { desc = "Build scheme with xcede" }))

        -- xcede device targeting for iOS apps (async)
        vim.keymap.set("n", "<localleader>bd", function()
          local Job = require("plenary.job")
          Job:new({
            command = "sh",
            args = { "-c", "xcede list --devices 2>/dev/null | grep -E '^-\\s+' | sed 's/^-\\s*//'" },
            on_exit = function(j, return_val)
              vim.schedule(function()
                local devices = table.concat(j:result(), "\n")
                if devices == "" then
                  require("snacks").terminal("xcede buildrun", {
                    win = { position = "bottom", height = 0.3 },
                  })
                else
                  vim.ui.select(vim.split(devices, "\n"), {
                    prompt = "Select device:",
                  }, function(choice)
                    if choice then
                      require("snacks").terminal("xcede buildrun --device '" .. choice .. "'", {
                        win = { position = "bottom", height = 0.3 },
                      })
                    end
                  end)
                end
              end)
            end,
          }):start()
        end, vim.tbl_extend("force", opts, { desc = "Build and run on device with xcede" }))

        -- Swift Package Manager commands (if Package.swift exists)
        vim.keymap.set("n", "<localleader>pb", function()
          if vim.fn.filereadable("Package.swift") == 1 then
            require("snacks").terminal("swift build", {
              win = {
                position = "bottom",
                height = 0.3,
              },
            })
          else
            vim.notify("Package.swift not found", vim.log.levels.WARN)
          end
        end, vim.tbl_extend("force", opts, { desc = "Swift package build" }))

        vim.keymap.set("n", "<localleader>pr", function()
          if vim.fn.filereadable("Package.swift") == 1 then
            local package_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
            require("snacks").terminal("swift run " .. package_name, {
              win = {
                position = "bottom",
                height = 0.3,
              },
            })
          else
            vim.notify("Package.swift not found", vim.log.levels.WARN)
          end
        end, vim.tbl_extend("force", opts, { desc = "Swift package run" }))

        vim.keymap.set("n", "<localleader>pt", function()
          if vim.fn.filereadable("Package.swift") == 1 then
            require("snacks").terminal("swift test", {
              win = {
                position = "bottom",
                height = 0.3,
              },
            })
          else
            vim.notify("Package.swift not found", vim.log.levels.WARN)
          end
        end, vim.tbl_extend("force", opts, { desc = "Swift package test" }))

        -- Format with swift-format
        vim.keymap.set("n", "<localleader>f", function()
          vim.lsp.buf.format({ async = true })
        end, vim.tbl_extend("force", opts, { desc = "Format Swift code" }))

        -- Toggle inlay hints
        vim.keymap.set("n", "<localleader>h", function()
          vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
        end, vim.tbl_extend("force", opts, { desc = "Toggle inlay hints" }))

        -- List available schemes and devices
        vim.keymap.set("n", "<localleader>l", function()
          require("snacks").terminal("xcede list", {
            win = {
              position = "bottom",
              height = 0.4,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "List schemes and devices" }))

        -- BSP and Xcode Build Server commands
        if vim.fn.executable('xcode-build-server') == 1 then
          -- BSP build target (async)
          vim.keymap.set("n", "<localleader>bb", function()
            local Job = require("plenary.job")
            Job:new({
              command = "sh",
              args = { "-c", "xcode-build-server buildTargets 2>/dev/null | jq -r '.targets[].id'" },
              on_exit = function(j, return_val)
                vim.schedule(function()
                  local targets = table.concat(j:result(), "\n")
                  if targets == "" then
                    require("snacks").terminal("xcode-build-server build", {
                      win = { position = "bottom", height = 0.3 },
                    })
                  else
                    vim.ui.select(vim.split(targets, "\n"), {
                      prompt = "Select build target:",
                    }, function(choice)
                      if choice then
                        require("snacks").terminal("xcode-build-server build --target " .. choice, {
                          win = { position = "bottom", height = 0.3 },
                        })
                      end
                    end)
                  end
                end)
              end,
            }):start()
          end, vim.tbl_extend("force", opts, { desc = "BSP build target" }))

          -- BSP test target (async)
          vim.keymap.set("n", "<localleader>bt", function()
            local Job = require("plenary.job")
            Job:new({
              command = "sh",
              args = { "-c", "xcode-build-server buildTargets 2>/dev/null | jq -r '.targets[].id'" },
              on_exit = function(j, return_val)
                vim.schedule(function()
                  local targets = table.concat(j:result(), "\n")
                  if targets == "" then
                    require("snacks").terminal("xcode-build-server test", {
                      win = { position = "bottom", height = 0.3 },
                    })
                  else
                    vim.ui.select(vim.split(targets, "\n"), {
                      prompt = "Select test target:",
                    }, function(choice)
                      if choice then
                        require("snacks").terminal("xcode-build-server test --target " .. choice, {
                          win = { position = "bottom", height = 0.3 },
                        })
                      end
                    end)
                  end
                end)
              end,
            }):start()
          end, vim.tbl_extend("force", opts, { desc = "BSP test target" }))

          -- BSP clean
          vim.keymap.set("n", "<localleader>bc", function()
            require("snacks").terminal("xcode-build-server clean", {
              win = {
                position = "bottom",
                height = 0.3,
              },
            })
          end, vim.tbl_extend("force", opts, { desc = "BSP clean" }))

          -- List BSP build targets
          vim.keymap.set("n", "<localleader>bl", function()
            require("snacks").terminal("xcode-build-server buildTargets", {
              win = {
                position = "bottom",
                height = 0.4,
              },
            })
          end, vim.tbl_extend("force", opts, { desc = "List BSP build targets" }))

          -- BSP restart server
          vim.keymap.set("n", "<localleader>brs", function()
            vim.notify("Restarting Xcode Build Server...", vim.log.levels.INFO)
            require("snacks").terminal("pkill -f xcode-build-server && sleep 1 && xcode-build-server", {
              win = {
                position = "bottom",
                height = 0.3,
              },
            })
          end, vim.tbl_extend("force", opts, { desc = "Restart BSP server" }))

          -- Generate compile commands for BSP
          vim.keymap.set("n", "<localleader>bg", function()
            require("snacks").terminal("xcode-build-server compileCommands", {
              win = {
                position = "bottom",
                height = 0.3,
              },
            })
          end, vim.tbl_extend("force", opts, { desc = "Generate compile commands" }))
        end

        -- Unified build menu that chooses between xcede and BSP
        vim.keymap.set("n", "<localleader>ub", function()
          local has_xcede = vim.fn.executable('xcede') == 1
          local has_bsp = vim.fn.executable('xcode-build-server') == 1

          local choices = {}
          if has_xcede then
            table.insert(choices, { name = "xcede build", cmd = "xcede build" })
            table.insert(choices, { name = "xcede buildrun", cmd = "xcede buildrun" })
          end
          if has_bsp then
            table.insert(choices, { name = "BSP build", cmd = "xcode-build-server build" })
            table.insert(choices, { name = "BSP test", cmd = "xcode-build-server test" })
          end

          vim.ui.select(choices, {
            prompt = "Select build system:",
            format_item = function(item) return item.name end,
          }, function(choice)
            if choice then
              require("snacks").terminal(choice.cmd, {
                win = {
                  position = "bottom",
                  height = 0.3,
                },
              })
            end
          end)
        end, vim.tbl_extend("force", opts, { desc = "Unified build menu" }))
      end,
      })
      safe_enable("sourcekit")
    end

    local expert_path = vim.fn.expand("~/.tools/expert/expert")
    if vim.fn.executable(expert_path) == 1 then
      vim.lsp.config("expert", {
        cmd = { expert_path, "server" },
        filetypes = { "elixir", "eex", "heex", "surface" },
        root_markers = { "mix.exs", ".git" },
        single_file_support = true,
        init_options = {
          experimental = {
            completions = {
              enable = true
            }
          }
        },
        settings = {},
        on_attach = function(client, bufnr)
          vim.bo[bufnr].omnifunc = 'v:lua.vim.lsp.omnifunc'
        end,
      })
      safe_enable("expert")
    else
      print("Expert LSP not found at " .. expert_path .. ", falling back to ElixirLS")
      safe_enable("elixirls")
    end

    if vim.fn.executable("jdtls") == 1 then
      vim.lsp.config("jdtls", {
        cmd = { "jdtls" },
        filetypes = { "java" },
        root_markers = { "build.gradle", "pom.xml", ".git", "mvnw", "gradlew" },
        settings = {
          java = {
            signatureHelp = { enabled = true },
            contentProvider = { preferred = "fernflower" },
            completion = {
              favoriteStaticMembers = {
                "org.junit.jupiter.api.Assertions.*",
                "org.junit.jupiter.api.Assumptions.*",
                "org.junit.Assert.*",
                "org.junit.Assume.*",
                "org.mockito.Mockito.*"
              },
              importOrder = {
                "java",
                "javax",
                "com",
                "org"
              },
            },
            sources = {
              organizeImports = {
                starThreshold = 9999,
                staticStarThreshold = 9999,
              },
            },
            codeGeneration = {
              toString = {
                template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}"
              },
              hashCodeEquals = {
                useJava7Objects = true,
              },
              useBlocks = true,
            },
          },
        },
      })
      safe_enable("jdtls")
    end

    if vim.fn.executable("kotlin-language-server") == 1 then
      vim.lsp.config("kotlin_language_server", {
        cmd = { "kotlin-language-server" },
        filetypes = { "kotlin", "kt", "kts" },
        root_markers = { "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts", "pom.xml", ".git" },
      })
      safe_enable("kotlin_language_server")
    end

    if vim.fn.executable("yaml-language-server") == 1 then
      vim.lsp.config("yamlls", {
      cmd = { "yaml-language-server", "--stdio" },
      filetypes = { "yaml", "yml" },
      root_markers = { ".git", vim.fn.getcwd() },
      capabilities = vim.tbl_deep_extend("force", capabilities, {
        workspace = { didChangeConfiguration = { dynamicRegistration = true } },
      }),
      settings = {
        yaml = {
          hover = true,
          completion = true,
          validate = true,
          schemaStore = {
            enable = true,
            url = "https://www.schemastore.org/api/json/catalog.json",
          },
          schemas = {
            ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
            ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "docker-compose*.yml",
            ["https://json.schemastore.org/chart.json"] = "Chart.yaml",
            ["https://json.schemastore.org/dependabot-v2"] = ".github/dependabot.yml",
            ["https://json.schemastore.org/gitlab-ci"] = ".gitlab-ci.yml",
            ["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.0/schema.json"] = "*api*.yml",
            ["https://raw.githubusercontent.com/ansible-community/schemas/main/f/ansible.json#/$defs/tasks"] = "roles/*/tasks/*.yml",
            ["https://raw.githubusercontent.com/ansible-community/schemas/main/f/ansible.json#/$defs/playbook"] = "*playbook*.yml",
          },
          format = {
            enable = true,
          },
          customTags = {
            "!reference sequence",
          },
        },
        redhat = {
          telemetry = {
            enabled = false,
          },
        },
      },
      })
      safe_enable("yamlls")
    end

    if vim.fn.executable("taplo") == 1 then
      vim.lsp.config("taplo", {
      cmd = { "taplo", "lsp", "stdio" },
      filetypes = { "toml" },
      root_markers = { "*.toml", ".git" },
      settings = {
        taplo = {
          formatter = {
            alignEntries = true,
            alignComments = true,
            arrayTrailingComma = true,
            arrayAutoExpand = true,
            arrayAutoCollapse = true,
            compactArrays = true,
            compactInlineTables = false,
            compactEntries = false,
            columnWidth = 80,
            indentTables = false,
            indentEntries = false,
            indentString = "  ",
            reorderKeys = true,
            allowedBlankLines = 2,
            trailingNewline = true,
            crlf = false,
          },
        },
      },
      })
      safe_enable("taplo")
    end
  end,

  vim.keymap.set("n", "<localleader>ol", function()
    require("mobile-dev.android.logcat").toggle()
  end, { desc = "Toggle Android logcat" })
}
