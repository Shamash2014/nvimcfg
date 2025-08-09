 -- Pure native LSP configuration 
return {
    name = "native-lsp",
    dir = vim.fn.stdpath("config"),
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      -- Global mappings
      vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float)
      vim.keymap.set("n", "[d", vim.diagnostic.goto_prev)
      vim.keymap.set("n", "]d", vim.diagnostic.goto_next)
      vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist)
      
      -- Global LSP restart (works even when not in LSP buffer)
      vim.keymap.set("n", "<leader>lR", function()
        -- Stop all active LSP clients
        local clients = vim.lsp.get_clients()
        for _, client in ipairs(clients) do
          vim.lsp.stop_client(client.id, true)
        end
        -- Trigger LSP to restart on next buffer entry
        vim.cmd('edit')
        vim.notify("All LSP servers restarted", vim.log.levels.INFO)
      end, { desc = "Restart all LSP servers" })

      -- Open LSP log
      vim.keymap.set("n", "<leader>ll", function()
        vim.cmd('edit ' .. vim.lsp.get_log_path())
      end, { desc = "Open LSP log" })

      -- Enhanced workspace rename function
      local function workspace_rename()
        local current_word = vim.fn.expand("<cword>")
        local new_name = vim.fn.input("Rename " .. current_word .. " to: ", current_word)

        if new_name == "" or new_name == current_word then
          return
        end

        -- Get all clients that support rename
        local clients = vim.lsp.get_clients({
          bufnr = vim.api.nvim_get_current_buf(),
          method = "textDocument/rename",
        })

        if #clients == 0 then
          vim.notify("No LSP clients support rename", vim.log.levels.WARN)
          return
        end

        -- Prepare rename request
        local params = vim.lsp.util.make_position_params()
        params.newName = new_name

        -- Show progress
        vim.notify("Renaming " .. current_word .. " to " .. new_name .. "...", vim.log.levels.INFO)

        -- Send rename request to all supporting clients
        for _, client in ipairs(clients) do
          client.request("textDocument/rename", params, function(err, result)
            if err then
              vim.notify("Rename failed: " .. err.message, vim.log.levels.ERROR)
              return
            end

            if result then
              -- Apply workspace edits
              vim.lsp.util.apply_workspace_edit(result, client.offset_encoding)

              -- Count changes
              local changes = 0
              if result.changes then
                for _, file_changes in pairs(result.changes) do
                  changes = changes + #file_changes
                end
              elseif result.documentChanges then
                for _, change in ipairs(result.documentChanges) do
                  if change.edits then
                    changes = changes + #change.edits
                  end
                end
              end

              vim.notify(
                string.format("Renamed %s to %s (%d changes)", current_word, new_name, changes),
                vim.log.levels.INFO
              )
            else
              vim.notify("No references found for " .. current_word, vim.log.levels.WARN)
            end
          end)
        end
      end

      -- LSP attach function
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local opts = { buffer = ev.buf }
          vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
          vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
          vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)

          -- Enhanced rename mappings
          vim.keymap.set("n", "<leader>crr", function()
            return ":IncRename " .. vim.fn.expand("<cword>")
          end, vim.tbl_extend("force", opts, { desc = "Inc Rename", expr = true }))
          vim.keymap.set("n", "<leader>crw", workspace_rename,
            vim.tbl_extend("force", opts, { desc = "Workspace Rename" }))

          vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "<leader>f", function()
            vim.lsp.buf.format { async = true }
          end, opts)
          
          -- LSP restart keybinding
          vim.keymap.set("n", "<leader>cR", function()
            vim.cmd('LspRestart')
            vim.notify("LSP servers restarted", vim.log.levels.INFO)
          end, vim.tbl_extend("force", opts, { desc = "Restart LSP" }))
        end,
      })

      -- LSP Configuration using Neovim 0.11 native API
      vim.lsp.config.lua_ls = {
        cmd = { 'lua-language-server' },
        filetypes = { 'lua' },
        root_markers = { { '.luarc.json', '.luarc.jsonc' }, '.git' },
        settings = {
          Lua = {
            runtime = { version = 'LuaJIT' },
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
          },
        },
      }

      vim.lsp.config.vtsls = {
        cmd = { 'vtsls', '--stdio' },
        filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'vue' },
        root_markers = { 'package.json', 'tsconfig.json', 'jsconfig.json', '.git' },
        workspace_required = false,
        settings = {
          vtsls = {
            enableMoveToFileCodeAction = true,
            autoUseWorkspaceTsdk = true,
            experimental = {
              completion = {
                enableServerSideFuzzyMatch = true,
              },
            },
          },
          typescript = {
            updateImportsOnFileMove = { enabled = "always" },
            suggest = {
              completeFunctionCalls = true,
              includeCompletionsForModuleExports = true,
              includeAutomaticOptionalChainCompletions = true,
            },
            preferences = {
              includePackageJsonAutoImports = "on",
              importModuleSpecifier = "relative",
              includeCompletionsForImportStatements = true,
            },
            inlayHints = {
              parameterNames = { enabled = "literals" },
              parameterTypes = { enabled = true },
              variableTypes = { enabled = true },
              propertyDeclarationTypes = { enabled = true },
              functionLikeReturnTypes = { enabled = true },
              enumMemberValues = { enabled = true },
            },
          },
          javascript = {
            updateImportsOnFileMove = { enabled = "always" },
            suggest = {
              completeFunctionCalls = true,
              includeCompletionsForModuleExports = true,
              includeAutomaticOptionalChainCompletions = true,
            },
            preferences = {
              includePackageJsonAutoImports = "on",
              importModuleSpecifier = "relative",
              includeCompletionsForImportStatements = true,
            },
            inlayHints = {
              parameterNames = { enabled = "literals" },
              parameterTypes = { enabled = true },
              variableTypes = { enabled = true },
              propertyDeclarationTypes = { enabled = true },
              functionLikeReturnTypes = { enabled = true },
              enumMemberValues = { enabled = true },
            },
          },
        },
      }

      vim.lsp.config.dartls = {
        cmd = { 'dart', 'language-server', '--protocol=lsp' },
        filetypes = { 'dart' },
        root_markers = { 'pubspec.yaml', 'pubspec.yml', '.git' },
        init_options = {
          onlyAnalyzeProjectsWithOpenFiles = false,
          suggestFromUnimportedLibraries = true,
          closingLabels = true,
          outline = true,
          flutterOutline = true,
          includeDependenciesInWorkspaceSymbols = true,
        },
        settings = {
          dart = {
            analysisExcludedFolders = {
              vim.fn.expand("~/.pub-cache"),
              vim.fn.expand("~/fvm/versions"),
              vim.fn.expand("/opt/homebrew"),
              vim.fn.expand("$HOME/AppData/Local/Pub/Cache"),
              vim.fn.expand("$HOME/.pub-cache"),
              vim.fn.expand("/Applications/Flutter"),
            },
            updateImportsOnRename = true,
            completeFunctionCalls = true,
            showTodos = true,
            renameFilesWithClasses = "prompt",
            enableSdkFormatter = true,
            lineLength = 80,
            insertArgumentPlaceholders = true,
            previewFlutterUiGuides = true,
            previewFlutterUiGuidesCustomTracking = true,
            flutterSdkPath = (function()
              -- Check direnv first for FLUTTER_ROOT
              local flutter_root = vim.env.FLUTTER_ROOT
              if flutter_root and vim.fn.isdirectory(flutter_root) == 1 then
                return flutter_root
              end

              -- Check for FVM
              local fvm_default = vim.fn.expand("~/fvm/default")
              if vim.fn.isdirectory(fvm_default) == 1 then
                return fvm_default
              end

              -- Check .fvm/flutter_sdk in current project
              local fvm_local = vim.fn.getcwd() .. "/.fvm/flutter_sdk"
              if vim.fn.isdirectory(fvm_local) == 1 then
                return fvm_local
              end

              -- Fallback to standard locations
              local flutter_home = vim.fn.expand("~/flutter")
              if vim.fn.isdirectory(flutter_home) == 1 then
                return flutter_home
              end

              return nil
            end)(),
            checkForSdkUpdates = false,
            openDevTools = "never",
          }
        },
        capabilities = (function()
          local capabilities = vim.lsp.protocol.make_client_capabilities()

          -- Enhanced completion capabilities for blink.cmp
          capabilities.textDocument.completion.completionItem = {
            documentationFormat = { "markdown", "plaintext" },
            snippetSupport = true,
            preselectSupport = true,
            insertReplaceSupport = true,
            labelDetailsSupport = true,
            deprecatedSupport = true,
            commitCharactersSupport = true,
            tagSupport = { valueSet = { 1 } },
            resolveSupport = {
              properties = {
                "documentation",
                "detail",
                "additionalTextEdits",
              },
            },
          }

          -- Dart-specific capabilities
          capabilities.textDocument.codeAction = {
            dynamicRegistration = true,
            isPreferredSupport = true,
            disabledSupport = true,
            dataSupport = true,
            honorsChangeAnnotations = false,
            resolveSupport = {
              properties = { "edit" }
            },
            codeActionLiteralSupport = {
              codeActionKind = {
                valueSet = {
                  "",
                  "quickfix",
                  "refactor",
                  "refactor.extract",
                  "refactor.inline",
                  "refactor.rewrite",
                  "source",
                  "source.organizeImports",
                  "source.organizeImports.dart",
                  "source.fixAll",
                  "source.fixAll.dart",
                }
              }
            }
          }

          return capabilities
        end)()
      }

      vim.lsp.config.elixirls = {
        cmd = { vim.fn.expand('~/.tools/elixir-ls/launch.sh') },
        filetypes = { 'elixir', 'eelixir', 'heex', 'surface' },
        root_markers = { 'mix.exs', '.git' },
        cmd_env = {
          ELS_MODE = "language_server"
        },
        settings = {
          elixirLS = {
            dialyzerEnabled = true,
            fetchDeps = false,
          }
        }
      }

      vim.lsp.config.basedpyright = {
        cmd = { 'basedpyright-langserver', '--stdio' },
        filetypes = { 'python' },
        root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.envrc', '.git' },
        settings = {
          python = {
            analysis = {
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              autoImportCompletions = true,
              diagnosticMode = "workspace",
              typeCheckingMode = "basic",
              autoFormatStrings = true,
              indexing = true,
              logLevel = "Information",
              stubPath = vim.fn.stdpath("data") .. "/lazy/python-type-stubs",
            },
            pythonPath = function()
              -- Use direnv environment if available
              if vim.env.VIRTUAL_ENV then
                return vim.env.VIRTUAL_ENV .. "/bin/python"
              end
              -- Fallback to system python
              return "python3"
            end,
          },
          basedpyright = {
            disableOrganizeImports = false,
            analysis = {
              autoImportCompletions = true,
              typeCheckingMode = "basic",
              diagnosticMode = "workspace",
              useLibraryCodeForTypes = true,
              autoSearchPaths = true,
            },
          },
        },
      }

      vim.lsp.config.rust_analyzer = {
        cmd = { 'rust-analyzer' },
        filetypes = { 'rust' },
        root_markers = { 'Cargo.toml', 'rust-project.json', '.git' },
        settings = {
          ['rust-analyzer'] = {
            cargo = {
              allFeatures = true,
              loadOutDirsFromCheck = true,
              buildScripts = {
                enable = true,
              },
            },
            checkOnSave = {
              allFeatures = true,
              command = 'clippy',
              extraArgs = { '--no-deps' },
            },
            procMacro = {
              enable = true,
              ignored = {
                ['async-trait'] = { 'async_trait' },
                ['napi-derive'] = { 'napi' },
                ['async-recursion'] = { 'async_recursion' },
              },
            },
            inlayHints = {
              bindingModeHints = { enable = false },
              chainingHints = { enable = true },
              closingBraceHints = { enable = true, minLines = 25 },
              closureReturnTypeHints = { enable = 'never' },
              lifetimeElisionHints = { enable = 'never', useParameterNames = false },
              maxLength = 25,
              parameterHints = { enable = true },
              reborrowHints = { enable = 'never' },
              renderColons = true,
              typeHints = { enable = true, hideClosureInitialization = false, hideNamedConstructor = false },
            },
          },
        },
      }

      vim.lsp.config.clangd = {
        cmd = { 'clangd', '--background-index', '--clang-tidy', '--header-insertion=iwyu', '--completion-style=detailed', '--function-arg-placeholders', '--fallback-style=llvm' },
        filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
        root_markers = { '.clangd', '.clang-tidy', '.clang-format', 'compile_commands.json', 'compile_flags.txt', 'configure.ac', '.git' },
        init_options = {
          usePlaceholders = true,
          completeUnimported = true,
          clangdFileStatus = true,
        },
        capabilities = {
          textDocument = {
            completion = {
              editsNearCursor = true,
            },
          },
          offsetEncoding = { 'utf-16' },
        },
      }

      vim.lsp.config.sourcekit = {
        cmd = { 'sourcekit-lsp' },
        filetypes = { 'swift', 'c', 'cpp', 'objective-c', 'objective-cpp' },
        root_markers = { 'Package.swift', '.git', '*.xcodeproj', '*.xcworkspace' },
        settings = {
          sourcekit = {
            indexDatabasePath = ".sourcekit-lsp",
            indexStorePath = ".sourcekit-lsp/index",
          },
        },
        init_options = {
          ["sourcekit-lsp"] = {
            indexDatabasePath = ".sourcekit-lsp",
            indexStorePath = ".sourcekit-lsp/index",
          },
        },
      }

      vim.lsp.config.r_language_server = {
        cmd = { 'R', '--slave', '-e', 'languageserver::run()' },
        filetypes = { 'r', 'rmd', 'quarto' },
        root_markers = { '.Rprofile', 'renv.lock', 'DESCRIPTION', '.git' },
        settings = {
          r = {
            lsp = {
              rich_documentation = false,
            },
          },
        },
      }

      vim.lsp.config.astro = {
        cmd = { 'astro-ls', '--stdio' },
        filetypes = { 'astro' },
        root_markers = { 'package.json', 'astro.config.mjs', 'astro.config.js', 'astro.config.ts', '.git' },
        init_options = {
          typescript = {
            tsdk = vim.fn.getcwd() .. "/node_modules/typescript/lib"
          }
        },
        settings = {
          astro = {
            format = {
              indentFrontmatter = false,
            },
          },
        },
      }

      vim.lsp.config.gopls = {
        cmd = { 'gopls' },
        filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
        root_markers = { 'go.work', 'go.mod', '.git' },
        settings = {
          gopls = {
            completeUnimported = true,
            usePlaceholders = true,
            analyses = {
              unusedparams = true,
              unreachable = true,
              fillstruct = true,
              nilness = true,
              shadow = true,
              unusedwrite = true,
              useany = true,
            },
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
            buildFlags = { "-tags", "integration" },
            env = {
              GOFLAGS = "-tags=integration",
            },
            directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
            semanticTokens = true,
            staticcheck = true,
            gofumpt = true,
          },
        },
      }

      vim.lsp.config.yamlls = {
        cmd = { 'yaml-language-server', '--stdio' },
        filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab' },
        root_markers = { '.git', 'docker-compose.yml', 'docker-compose.yaml', '.gitlab-ci.yml' },
        settings = {
          yaml = {
            schemas = {
              -- Kubernetes schemas
              ["https://json.schemastore.org/kustomization"] = "kustomization.yaml",
              ["kubernetes"] = "*.yaml",
              -- Docker Compose schemas
              ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = {
                "docker-compose*.yml",
                "docker-compose*.yaml",
                "compose*.yml",
                "compose*.yaml"
              },
              -- CI/CD schemas
              ["https://json.schemastore.org/github-workflow"] = ".github/workflows/*.yml",
              ["https://json.schemastore.org/github-action"] = ".github/action.yml",
              ["https://json.schemastore.org/ansible-playbook"] = "playbook.yml",
              ["https://json.schemastore.org/prettierrc"] = ".prettierrc.{yml,yaml}",
              ["https://json.schemastore.org/chart"] = "Chart.yaml",
              ["https://json.schemastore.org/dependabot-v2"] = ".github/dependabot.yml",
              ["https://json.schemastore.org/gitlab-ci"] = "*gitlab-ci*.yml",
              ["https://json.schemastore.org/bamboo-spec"] = "*bamboo-specs*.yml",
              ["https://json.schemastore.org/bitbucket-pipelines"] = "bitbucket-pipelines.yml",
              ["https://json.schemastore.org/esmrc"] = ".esmrc.yml",
              ["https://json.schemastore.org/mkdocs-1.0"] = "mkdocs.yml",
              ["https://json.schemastore.org/pubspec"] = "pubspec.yaml",
              ["https://json.schemastore.org/replit"] = ".replit.yml"
            },
            validate = true,
            completion = true,
            hover = true,
            schemaStore = {
              enable = true,
              url = "https://www.schemastore.org/api/json/catalog.json",
            },
            format = {
              enable = true,
              singleQuote = false,
              bracketSpacing = true,
            },
            trace = {
              server = "off",
            },
          },
        },
      }

      vim.lsp.config.html = {
        cmd = { 'vscode-html-language-server', '--stdio' },
        filetypes = { 'html' },
        root_markers = { 'package.json', '.git' },
        init_options = {
          configurationSection = { "html", "css", "javascript" },
          embeddedLanguages = {
            css = true,
            javascript = true
          },
          provideFormatter = true,
        },
        settings = {
          html = {
            format = {
              templating = false,
              wrapLineLength = 120,
              unformatted = "wbr",
              contentUnformatted = "pre,code,textarea",
              indentInnerHtml = false,
              preserveNewLines = true,
              indentHandlebars = false,
              endWithNewline = false,
              extraLiners = "head, body, /html",
              wrapAttributes = "auto"
            },
            hover = {
              documentation = true,
              references = true
            },
            completion = {
              attributeDefaultValue = "doublequotes"
            }
          }
        }
      }

      vim.lsp.config.cssls = {
        cmd = { 'vscode-css-language-server', '--stdio' },
        filetypes = { 'css', 'scss', 'less' },
        root_markers = { 'package.json', '.git' },
        settings = {
          css = {
            validate = true,
            lint = {
              unknownAtRules = "ignore",
            }
          },
          scss = {
            validate = true,
            lint = {
              unknownAtRules = "ignore",
            }
          },
          less = {
            validate = true,
            lint = {
              unknownAtRules = "ignore",
            }
          }
        }
      }

      vim.lsp.config.dockerls = {
        cmd = { 'docker-langserver', '--stdio' },
        filetypes = { 'dockerfile' },
        root_markers = { 'Dockerfile', '.git' },
        settings = {}
      }

      vim.lsp.config.docker_compose_language_service = {
        cmd = { 'docker-compose-langserver', '--stdio' },
        filetypes = { 'yaml.docker-compose' },
        root_markers = { 'docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml', '.git' },
        settings = {}
      }

      vim.lsp.config.jsonls = {
        cmd = { 'vscode-json-language-server', '--stdio' },
        filetypes = { 'json', 'jsonc' },
        root_markers = { 'package.json', '.git' },
        init_options = {
          provideFormatter = true,
        },
        settings = {
          json = {
            schemas = {
              {
                fileMatch = { "package.json" },
                url = "https://json.schemastore.org/package.json"
              },
              {
                fileMatch = { "tsconfig*.json" },
                url = "https://json.schemastore.org/tsconfig.json"
              },
              {
                fileMatch = { ".eslintrc", ".eslintrc.json" },
                url = "https://json.schemastore.org/eslintrc.json"
              },
              {
                fileMatch = { ".prettierrc", ".prettierrc.json" },
                url = "https://json.schemastore.org/prettierrc.json"
              },
              {
                fileMatch = { "composer.json" },
                url = "https://json.schemastore.org/composer.json"
              },
              {
                fileMatch = { ".babelrc", ".babelrc.json", "babel.config.json" },
                url = "https://json.schemastore.org/babelrc.json"
              },
              {
                fileMatch = { "*.workflow" },
                url = "https://json.schemastore.org/github-workflow.json"
              }
            },
            validate = { enable = true },
            format = {
              enable = true,
            },
          },
          jsonc = {
            validate = { enable = true },
            format = {
              enable = true,
            },
          }
        }
      }

      vim.lsp.config.ruby_lsp = {
        cmd = { 'ruby-lsp' },
        filetypes = { 'ruby' },
        root_markers = { 'Gemfile', 'Rakefile', '.git' },
        init_options = {
          enabledFeatures = {
            "codeActions",
            "diagnostics",
            "documentHighlights",
            "documentLink",
            "documentSymbols",
            "foldingRanges",
            "formatting",
            "hover",
            "inlayHint",
            "onTypeFormatting",
            "selectionRanges",
            "semanticHighlighting",
            "completion",
            "codeLens",
            "definition",
            "workspaceSymbol",
            "signatureHelp",
            "typeHierarchy"
          },
          featuresConfiguration = {
            inlayHint = {
              enableAll = true,
            },
          },
          formatter = "rubocop",
          linters = { "rubocop" },
        },
        settings = {
          rubyLsp = {
            rubyVersionManager = "auto",
            formatter = "rubocop",
            linters = { "rubocop" },
            enableExperimentalFeatures = true,
          },
        },
      }

      vim.lsp.config.jdtls = {
        cmd = { 'jdtls' },
        filetypes = { 'java' },
        root_markers = { 'pom.xml', 'build.gradle', 'build.gradle.kts', '.git', 'gradlew', 'mvnw' },
        settings = {
          java = {
            eclipse = {
              downloadSources = true,
            },
            configuration = {
              updateBuildConfiguration = "interactive",
            },
            maven = {
              downloadSources = true,
            },
            implementationsCodeLens = {
              enabled = true,
            },
            referencesCodeLens = {
              enabled = true,
            },
            references = {
              includeDecompiledSources = true,
            },
            format = {
              enabled = true,
              settings = {
                url = vim.fn.stdpath("config") .. "/lang-servers/intellij-java-google-style.xml",
                profile = "GoogleStyle",
              },
            },
            signatureHelp = { enabled = true },
            contentProvider = { preferred = 'fernflower' },
          },
        },
        init_options = {
          bundles = {}
        },
      }

      vim.lsp.config.angularls = {
        cmd = { 'ngserver', '--stdio', '--tsProbeLocations', '', '--ngProbeLocations', '' },
        filetypes = { 'typescript', 'html', 'typescriptreact', 'typescript.tsx' },
        root_markers = { 'angular.json', '.git' },
        on_new_config = function(new_config, new_root_dir)
          new_config.cmd = {
            'ngserver',
            '--stdio',
            '--tsProbeLocations',
            new_root_dir .. '/node_modules',
            '--ngProbeLocations',
            new_root_dir .. '/node_modules/@angular/language-service',
          }
        end,
      }

      -- Enable configured LSP servers directly
      vim.lsp.enable('lua_ls')
      vim.lsp.enable('vtsls')
      vim.lsp.enable('dartls')
      vim.lsp.enable('elixirls')
      vim.lsp.enable('basedpyright')
      vim.lsp.enable('rust_analyzer')
      vim.lsp.enable('clangd')
      vim.lsp.enable('sourcekit')
      vim.lsp.enable('r_language_server')
      vim.lsp.enable('astro')
      vim.lsp.enable('gopls')
      vim.lsp.enable('yamlls')
      vim.lsp.enable('html')
      vim.lsp.enable('cssls')
      vim.lsp.enable('dockerls')
      vim.lsp.enable('docker_compose_language_service')
      vim.lsp.enable('jsonls')
      vim.lsp.enable('ruby_lsp')
      vim.lsp.enable('jdtls')
      vim.lsp.enable('angularls')

      -- Performance: Configure LSP with optimizations
      vim.lsp.set_log_level("WARN") -- Reduce LSP logging overhead

      -- Optimize LSP handlers for better performance
      local orig_util_open_floating_preview = vim.lsp.util.open_floating_preview
      function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
        opts = opts or {}
        opts.border = opts.border or "single"
        opts.max_width = opts.max_width or 80
        opts.max_height = opts.max_height or math.floor(vim.o.lines * 0.4)
        return orig_util_open_floating_preview(contents, syntax, opts, ...)
      end

      -- Optimize LSP for Zed-like performance
      vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
        border = "single",
        max_width = 80,
        max_height = 20,
      })

      vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
        border = "single",
        max_width = 80,
        max_height = 15,
      })

      -- Reduce LSP update frequency for better performance
      vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
        update_in_insert = false, -- Don't update diagnostics while typing
        severity_sort = true,
        virtual_text = false,     -- We use diagflow.nvim for this
      })

      -- Configure diagnostic display (no virtual text/lines, diagflow handles it)
      vim.diagnostic.config({
        virtual_text = false,
        virtual_lines = false,
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
      })

      -- Optimize completion performance
      local completion_capabilities = vim.lsp.protocol.make_client_capabilities()
      completion_capabilities.textDocument.completion.completionItem.snippetSupport = true
      completion_capabilities.textDocument.completion.completionItem.resolveSupport = {
        properties = { "documentation", "detail", "additionalTextEdits" }
      }

      -- Debounce LSP requests for better performance
      local function debounce(func, timeout)
        local timer_id
        return function(...)
          if timer_id then
            vim.fn.timer_stop(timer_id)
          end
          local args = { ... }
          timer_id = vim.fn.timer_start(timeout, function()
            func(unpack(args))
          end)
        end
      end

      -- Debounced document highlight
      local highlight_debounced = debounce(vim.lsp.buf.document_highlight, 100)

      -- LSP attach autocommand for keybindings
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
        callback = function(args)
          -- Skip large files for LSP performance
          if vim.b[args.buf].large_file then
            return
          end

          local client = vim.lsp.get_client_by_id(args.data.client_id)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = args.buf, desc = 'LSP: ' .. desc })
          end

          -- Doom Emacs/Spacemacs style LSP keybindings (ca is handled by snacks in plugins.lua)
          map('<leader>cr', vim.lsp.buf.rename, 'Rename')
          map('<leader>cf', vim.lsp.buf.format, 'Format Document')
          map('<leader>cR', function()
            vim.cmd('LspRestart')
          end, 'Restart LSP')

          -- Language-specific enhancements
          local filetype = vim.bo[args.buf].filetype
          if filetype == "typescript" or filetype == "typescriptreact" or filetype == "javascript" or filetype == "javascriptreact" then
            map('<leader>co', function()
              vim.lsp.buf.code_action({
                filter = function(action)
                  return action.kind and string.match(action.kind, "source.organizeImports")
                end,
                apply = true,
              })
            end, 'Organize Imports')

            map('<leader>cu', function()
              vim.lsp.buf.code_action({
                filter = function(action)
                  return action.kind and string.match(action.kind, "source.removeUnused")
                end,
                apply = true,
              })
            end, 'Remove Unused')
          end

          if filetype == "python" then
            map('<leader>co', function()
              vim.lsp.buf.code_action({
                filter = function(action)
                  return action.kind and string.match(action.kind, "source.organizeImports")
                end,
                apply = true,
              })
            end, 'Organize Imports')
          end

          if filetype == "dart" then
            -- Dart/Flutter specific code actions under <leader>cd (code dart)
            map('<leader>cdo', function()
              vim.lsp.buf.code_action({
                filter = function(action)
                  return action.kind and string.match(action.kind, "source.organizeImports")
                end,
                apply = true,
              })
            end, 'Organize Imports')

            map('<leader>cdf', function()
              vim.lsp.buf.code_action({
                filter = function(action)
                  return action.kind and string.match(action.kind, "source.fixAll")
                end,
                apply = true,
              })
            end, 'Fix All')

            map('<leader>cdw', function()
              vim.lsp.buf.code_action({
                filter = function(action)
                  return action.title and string.match(action.title:lower(), "wrap")
                end,
                apply = true,
              })
            end, 'Wrap with Widget')

            map('<leader>cde', function()
              vim.lsp.buf.code_action({
                filter = function(action)
                  return action.title and
                      (string.match(action.title:lower(), "extract") or string.match(action.title:lower(), "refactor"))
                end,
              })
            end, 'Extract Widget/Method')
          end
          map('gd', vim.lsp.buf.definition, 'Goto Definition')
          map('gD', vim.lsp.buf.declaration, 'Goto Declaration')
          map('gr', vim.lsp.buf.references, 'Goto References')
          map('gI', vim.lsp.buf.implementation, 'Goto Implementation')
          map('<leader>D', vim.lsp.buf.type_definition, 'Type Definition')
          map('K', vim.lsp.buf.hover, 'Hover Documentation')
          map('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation', 'i')

          -- Highlight references under cursor (debounced for performance)
          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local highlight_augroup = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold' }, {
              buffer = args.buf,
              group = highlight_augroup,
              callback = highlight_debounced,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = args.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })
          end
        end,
      })
    end,
  }


