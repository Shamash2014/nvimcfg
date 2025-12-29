return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lspconfig = require("lspconfig")
    -- Get capabilities from blink.cmp
    local capabilities = require("blink.cmp").get_lsp_capabilities()

    -- Performance optimized LSP settings
    local default_config = {
      capabilities = capabilities,
      flags = {
        debounce_text_changes = 150,
      },
    }

    -- TypeScript/JavaScript with vtsls - comprehensive settings
    lspconfig.vtsls.setup(vim.tbl_extend("force", default_config, {
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
        typescript = {
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
      }
    }}))

    -- Python with basedpyright
    lspconfig.basedpyright.setup(default_config)

    -- Rust with comprehensive rust-analyzer settings
    lspconfig.rust_analyzer.setup(vim.tbl_extend("force", default_config, {
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
    }))

    -- Flutter/Dart LSP with enhanced settings
    lspconfig.dartls.setup(vim.tbl_extend("force", default_config, {
      cmd = { "dart", "language-server", "--protocol=lsp" },
      filetypes = { "dart" },
      root_dir = lspconfig.util.root_pattern("pubspec.yaml", ".git"),
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
        -- Store Flutter outline data
        vim.b[bufnr].flutter_outline = nil

        -- Enable virtual text for closing labels
        local namespace = vim.api.nvim_create_namespace("flutter_closing_labels")

        -- Set up handlers for Dart/Flutter notifications
        local handlers = client.handlers or {}

        -- Handler for Flutter outline notifications
        handlers["dart/textDocument/publishFlutterOutline"] = function(err, result, ctx)
          if err then return end
          -- Get buffer from URI
          local uri = result.uri
          local buf = vim.uri_to_bufnr(uri)
          if result and result.outline and vim.api.nvim_buf_is_valid(buf) then
            vim.b[buf].flutter_outline = result.outline
          end
        end

        -- Handler for closing labels notifications
        handlers["dart/textDocument/publishClosingLabels"] = function(err, result, ctx)
          -- Get buffer from URI
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

        -- Use localleader (\) for Flutter-specific commands
        vim.keymap.set("n", "<localleader>r", ":FlutterReload<CR>", { buffer = bufnr, desc = "Flutter Hot Reload" })
        vim.keymap.set("n", "<localleader>R", ":FlutterRestart<CR>", { buffer = bufnr, desc = "Flutter Hot Restart" })
        vim.keymap.set("n", "<localleader>q", ":FlutterQuit<CR>", { buffer = bufnr, desc = "Flutter Quit" })
        vim.keymap.set("n", "<localleader>d", ":FlutterDevices<CR>", { buffer = bufnr, desc = "Flutter Devices" })
        vim.keymap.set("n", "<localleader>l", ":FlutterLog<CR>", { buffer = bufnr, desc = "Flutter Logs" })
        vim.keymap.set("n", "<localleader>c", ":FlutterLogClear<CR>", { buffer = bufnr, desc = "Clear Flutter Logs" })
        vim.keymap.set("n", "<localleader>p", ":FlutterPubGet<CR>", { buffer = bufnr, desc = "Flutter Pub Get" })
        vim.keymap.set("n", "<localleader>u", ":FlutterPubUpgrade<CR>", { buffer = bufnr, desc = "Flutter Pub Upgrade" })
        vim.keymap.set("n", "<localleader>o", ":FlutterOutline<CR>", { buffer = bufnr, desc = "Flutter Widget Outline" })

        -- Create Flutter commands using plenary for non-blocking execution
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

        -- Flutter log viewer in a new terminal
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

        -- Clear Flutter logs
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

        -- Pub commands
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

        -- Flutter Widget Outline
        vim.api.nvim_buf_create_user_command(bufnr, "FlutterOutline", function()
          local outline = vim.b[bufnr].flutter_outline

          if not outline then
            vim.notify("No Flutter outline available. Make sure the file has been analyzed.", vim.log.levels.WARN)
            return
          end

          -- Convert outline to flat list for picker
          local items = {}
          local function traverse_outline(node, depth)
            depth = depth or 0
            local indent = string.rep("  ", depth)

            -- Add current node
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

            -- Traverse children
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

          -- Show in Snacks picker
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

        -- Widget wrap helper
        vim.keymap.set("v", "<localleader>w", function()
          local start_row, start_col = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
          local end_row, end_col = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))
          local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

          -- Simple widget wrap with Container
          local indent = lines[1]:match("^%s*")
          vim.api.nvim_buf_set_lines(bufnr, start_row - 1, start_row - 1, false, { indent .. "Container(" })
          vim.api.nvim_buf_set_lines(bufnr, end_row + 1, end_row + 1, false, { indent .. "  child: " })
          vim.api.nvim_buf_set_lines(bufnr, end_row + 2, end_row + 2, false, { indent .. ")," })
        end, { buffer = bufnr, desc = "Wrap with Widget" })
      end,
    }))

    -- Go with comprehensive gopls settings
    lspconfig.gopls.setup(vim.tbl_extend("force", default_config, {
      cmd = { "gopls" },
      filetypes = { "go", "gomod", "gowork", "gotmpl" },
      root_dir = lspconfig.util.root_pattern("go.work", "go.mod", ".git"),
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
        -- Enable inlay hints for Go
        if client.server_capabilities.inlayHintProvider then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end

        -- Go-specific keybindings using localleader
        local opts = { buffer = bufnr, silent = true }

        -- Code organization
        vim.keymap.set("n", "<localleader>i", function()
          vim.lsp.buf.code_action({
            context = { only = { "source.organizeImports" } },
            apply = true,
          })
        end, vim.tbl_extend("force", opts, { desc = "Organize Imports" }))

        -- Fill struct
        vim.keymap.set("n", "<localleader>fs", function()
          vim.lsp.buf.code_action({
            context = { only = { "refactor.rewrite" } },
            apply = true,
          })
        end, vim.tbl_extend("force", opts, { desc = "Fill struct" }))

        -- Generate test
        vim.keymap.set("n", "<localleader>gt", function()
          vim.lsp.buf.code_action({
            context = { only = { "source.generateTest" } },
            apply = true,
          })
        end, vim.tbl_extend("force", opts, { desc = "Generate test" }))

        -- Run go mod tidy
        vim.keymap.set("n", "<localleader>m", function()
          vim.lsp.buf.code_action({
            context = { only = { "source.fixAll" } },
            apply = true,
          })
          vim.notify("Running go mod tidy", vim.log.levels.INFO)
        end, vim.tbl_extend("force", opts, { desc = "Go mod tidy" }))

        -- Toggle inlay hints
        vim.keymap.set("n", "<localleader>h", function()
          vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
        end, vim.tbl_extend("force", opts, { desc = "Toggle inlay hints" }))

        -- Run tests
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

        -- Run current file
        vim.keymap.set("n", "<localleader>r", function()
          local current_file = vim.fn.expand("%")
          require("snacks").terminal("go run " .. current_file, {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Run current file" }))

        -- Build
        vim.keymap.set("n", "<localleader>b", function()
          require("snacks").terminal("go build", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Build project" }))
      end,
    }))

    -- Angular Language Server
    lspconfig.angularls.setup(vim.tbl_extend("force", default_config, {
      cmd = { "ngserver", "--stdio", "--tsProbeLocations", "", "--ngProbeLocations", "" },
      filetypes = { "typescript", "html", "typescriptreact", "typescript.tsx", "htmlangular" },
      root_dir = lspconfig.util.root_pattern("angular.json", ".git"),
      on_attach = function(client, bufnr)
        -- Angular-specific keybindings
        local opts = { buffer = bufnr, silent = true }

        -- Component navigation
        vim.keymap.set("n", "<localleader>gc", function()
          vim.lsp.buf.definition()
        end, vim.tbl_extend("force", opts, { desc = "Go to component" }))

        -- Template navigation
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
    }))

    -- Astro Language Server
    lspconfig.astro.setup(vim.tbl_extend("force", default_config, {
      cmd = { "astro-ls", "--stdio" },
      filetypes = { "astro" },
      root_dir = lspconfig.util.root_pattern("package.json", "tsconfig.json", "jsconfig.json", ".git"),
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
        -- Astro-specific keybindings
        local opts = { buffer = bufnr, silent = true }

        -- Format with prettier
        vim.keymap.set("n", "<localleader>f", function()
          vim.lsp.buf.format({ async = true })
        end, vim.tbl_extend("force", opts, { desc = "Format Astro file" }))

        -- Build
        vim.keymap.set("n", "<localleader>b", function()
          require("snacks").terminal("npm run build", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Build Astro project" }))

        -- Dev server
        vim.keymap.set("n", "<localleader>d", function()
          require("snacks").terminal("npm run dev", {
            win = {
              position = "bottom",
              height = 0.3,
            },
          })
        end, vim.tbl_extend("force", opts, { desc = "Start dev server" }))
      end,
    }))

    -- Tailwind CSS Language Server (useful for both Angular and Astro)
    lspconfig.tailwindcss.setup(vim.tbl_extend("force", default_config, {
      cmd = { "tailwindcss-language-server", "--stdio" },
      filetypes = { "html", "css", "scss", "javascript", "javascriptreact", "typescript", "typescriptreact", "astro", "vue", "svelte" },
      root_dir = lspconfig.util.root_pattern("tailwind.config.js", "tailwind.config.cjs", "tailwind.config.mjs", "tailwind.config.ts", ".git"),
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
    }))

    -- HTML Language Server (enhanced for Angular templates)
    lspconfig.html.setup(vim.tbl_extend("force", default_config, {
      cmd = { "vscode-html-language-server", "--stdio" },
      filetypes = { "html", "htmlangular" },
      root_dir = lspconfig.util.root_pattern("package.json", ".git"),
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
    }))

    -- CSS/SCSS Language Server
    lspconfig.cssls.setup(vim.tbl_extend("force", default_config, {
      cmd = { "vscode-css-language-server", "--stdio" },
      filetypes = { "css", "scss", "less" },
      root_dir = lspconfig.util.root_pattern("package.json", ".git"),
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
    }))

    -- Emmet Language Server
    lspconfig.ls_emmet.setup(vim.tbl_extend("force", default_config, {
      cmd = { "ls_emmet", "--stdio" },
      filetypes = { "html", "css", "scss", "javascript", "typescript", "vue", "svelte" },
      root_dir = lspconfig.util.root_pattern("package.json", ".git"),
      settings = {
        html = {
          preferences = {
            -- Enable emmet abbreviation expansion
            expandAbbreviation = true,
          },
        },
      },
    }))

    -- Xcode Build Server configuration for BSP support
    local function setup_xcode_build_server()
      local configs = require('lspconfig.configs')
      if not configs.xcode_build_server then
        configs.xcode_build_server = {
          default_config = {
            name = 'xcode_build_server',
            cmd = { 'xcode-build-server' },
            root_dir = lspconfig.util.root_pattern('*.xcodeproj', '*.xcworkspace', 'Package.swift', '.git'),
            filetypes = { 'swift', 'objective-c', 'objective-cpp' },
            capabilities = capabilities,
            init_options = {
              preferences = {
                useBuildSystemSettings = true,
                enableIndexing = true,
              },
            },
          },
        }
      end
      lspconfig.xcode_build_server.setup({})
    end

    -- Try to setup Xcode Build Server if available
    if vim.fn.executable('xcode-build-server') == 1 then
      setup_xcode_build_server()
    end

    -- Swift SourceKit-LSP configuration with xcede and BSP integration
    lspconfig.sourcekit.setup(vim.tbl_extend("force", default_config, {
      cmd = { "sourcekit-lsp" },
      filetypes = { "swift", "objective-c", "objective-cpp" },
      root_dir = lspconfig.util.root_pattern("Package.swift", "Package.resolved", ".git", "*.xcodeproj", "*.xcworkspace"),
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
          -- Enable BSP support if available
          enableBSP = vim.fn.executable('xcode-build-server') == 1,
        },
      },
      on_attach = function(client, bufnr)
        -- Enable inlay hints for Swift
        if client.server_capabilities.inlayHintProvider then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end

        -- Swift-specific keybindings using localleader
        local opts = { buffer = bufnr, silent = true }

        -- xcede build commands
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
    }))

    -- Elixir Expert LSP (Official Elixir Language Server)
    -- Using custom Expert installation path
    local expert_path = vim.fn.expand("~/.tools/expert/expert")
    if vim.fn.executable(expert_path) == 1 then
      -- Register custom config for Expert if not already defined
      local configs = require('lspconfig.configs')
      if not configs.expert then
        configs.expert = {
          default_config = {
            cmd = { expert_path, "server" },
            filetypes = { "elixir", "eex", "heex", "surface" },
            root_dir = lspconfig.util.root_pattern("mix.exs", ".git"),
            single_file_support = true,
            init_options = {
              experimental = {
                completions = {
                  enable = true
                }
              }
            },
            settings = {},
          },
        }
      end
      lspconfig.expert.setup(vim.tbl_extend("force", default_config, {
        on_attach = function(client, bufnr)
          -- Enable completion triggered by <c-x><c-o>
          vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
        end,
      }))
    else
      -- Fallback to ElixirLS if Expert not found
      print("Expert LSP not found at " .. expert_path .. ", falling back to ElixirLS")
      lspconfig.elixirls.setup(default_config)
    end

    -- Java Language Server (jdtls)
    lspconfig.jdtls.setup(vim.tbl_extend("force", default_config, {
      cmd = { "jdtls" },
      filetypes = { "java" },
      root_dir = lspconfig.util.root_pattern("build.gradle", "pom.xml", ".git", "mvnw", "gradlew"),
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
    }))

    -- Kotlin Language Server
    lspconfig.kotlin_language_server.setup(vim.tbl_extend("force", default_config, {
      cmd = { "kotlin-language-server" },
      filetypes = { "kotlin", "kt", "kts" },
      root_dir = lspconfig.util.root_pattern("settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts", "pom.xml", ".git"),
    }))

    -- YAML Language Server
    lspconfig.yamlls.setup(vim.tbl_extend("force", default_config, {
      cmd = { "yaml-language-server", "--stdio" },
      filetypes = { "yaml", "yml" },
      root_dir = lspconfig.util.root_pattern(".git", vim.fn.getcwd()),
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
    }))

    -- TOML Language Server (Taplo)
    lspconfig.taplo.setup(vim.tbl_extend("force", default_config, {
      cmd = { "taplo", "lsp", "stdio" },
      filetypes = { "toml" },
      root_dir = lspconfig.util.root_pattern("*.toml", ".git"),
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
    }))
  end,
}
