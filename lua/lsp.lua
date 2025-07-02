-- LSP Configuration (Neovim 0.11 native API)

-- Configure LSP servers using vim.lsp.config
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

vim.lsp.config.pyright = {
  cmd = { 'pyright-langserver', '--stdio' },
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
    pyright = {
      disableOrganizeImports = false,
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

-- Enable configured LSP servers
vim.lsp.enable({ 'lua_ls', 'vtsls', 'dartls', 'elixirls', 'pyright', 'rust_analyzer', 'clangd', 'sourcekit',
  'r_language_server', 'astro', 'gopls', 'yamlls', 'html', 'cssls', 'dockerls', 'docker_compose_language_service',
  'jsonls', 'ruby_lsp' })

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

