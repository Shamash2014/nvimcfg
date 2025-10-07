return {
  name = "native-lsp",
  dev = true,
  dir = ".",
  lazy = false,
  dependencies = {
    "b0o/SchemaStore.nvim",
    {
      "akinsho/flutter-tools.nvim",
      ft = "dart",
      dependencies = { "nvim-lua/plenary.nvim", "stevearc/dressing.nvim" },
      config = function()
        require('flutter-tools').setup({
          ui = { border = "rounded", notification_style = 'native' },
          decorations = { statusline = { device = true } },
          debugger = { enabled = true, run_via_dap = true },
          widget_guides = { enabled = true },
          closing_tags = { highlight = "Comment", prefix = "// ", enabled = true },
          dev_log = { enabled = true, notify_errors = false },
          dev_tools = { autostart = false, auto_open_browser = false },
          outline = { auto_open = false },
          flutter_path = nil,
          flutter_lookup_cmd = "mise where flutter",
          lsp = {
            color = { enabled = true, virtual_text = true, virtual_text_str = "■" },
            settings = {
              showTodos = true,
              completeFunctionCalls = true,
              renameFilesWithClasses = "prompt",
              enableSnippets = true,
              updateImportsOnRename = true,
              documentation = "full",
              includeDependenciesInWorkspaceSymbols = true,
            },
          },
        })

        vim.keymap.set("n", "<leader>clr", "<cmd>FlutterRun<cr>", { desc = "Flutter Run" })
        vim.keymap.set("n", "<leader>clq", "<cmd>FlutterQuit<cr>", { desc = "Flutter Quit" })
        vim.keymap.set("n", "<leader>clR", "<cmd>FlutterRestart<cr>", { desc = "Flutter Restart" })
        vim.keymap.set("n", "<leader>clh", "<cmd>FlutterReload<cr>", { desc = "Flutter Hot Reload" })
        vim.keymap.set("n", "<leader>cld", "<cmd>FlutterDevices<cr>", { desc = "Flutter Devices" })
        vim.keymap.set("n", "<leader>cle", "<cmd>FlutterEmulators<cr>", { desc = "Flutter Emulators" })
        vim.keymap.set("n", "<leader>clo", "<cmd>FlutterOutlineToggle<cr>", { desc = "Flutter Outline" })
        vim.keymap.set("n", "<leader>clt", "<cmd>FlutterDevTools<cr>", { desc = "Flutter DevTools" })
        vim.keymap.set("n", "<leader>clL", "<cmd>FlutterLspRestart<cr>", { desc = "Flutter LSP Restart" })
      end,
    },
    {
      "mfussenegger/nvim-jdtls",
      ft = "java",
    },
  },
  config = function()
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
    vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Show diagnostic" })
    vim.keymap.set("n", "<leader>cq", function() require("snacks").picker.diagnostics_buffer() end, { desc = "Buffer diagnostics" })

    vim.lsp.inlay_hint.enable(true)

    -- Filter inlay hints to only show on current line
    local methods = vim.lsp.protocol.Methods
    local inlay_hint_handler = vim.lsp.handlers[methods.textDocument_inlayHint]
    vim.lsp.handlers[methods.textDocument_inlayHint] = function(err, result, ctx, config)
      local client = vim.lsp.get_client_by_id(ctx.client_id)
      if client and result then
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        result = vim.iter(result)
          :filter(function(hint)
            return hint.position.line + 1 == row
          end)
          :totable()
      end
      inlay_hint_handler(err, result, ctx, config)
    end

    local capabilities = vim.lsp.protocol.make_client_capabilities()
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

    vim.lsp.config("*", {
      capabilities = capabilities,
    })

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

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", {}),
      callback = function(ev)
        if not vim.api.nvim_buf_is_valid(ev.buf) then
          return
        end
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        local opts = { buffer = ev.buf }

        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "Go to declaration" }))
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
        vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover documentation" }))
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, vim.tbl_extend("force", opts, { desc = "Go to implementation" }))
        vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, vim.tbl_extend("force", opts, { desc = "Signature help" }))
        vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, vim.tbl_extend("force", opts, { desc = "Signature help" }))
        vim.keymap.set("n", "gr", function() require("snacks").picker.lsp_references() end, vim.tbl_extend("force", opts, { desc = "Go to references" }))
        vim.keymap.set("n", "gy", vim.lsp.buf.type_definition, vim.tbl_extend("force", opts, { desc = "Go to type definition" }))
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code action" }))
        vim.keymap.set("n", "<leader>cR", "<cmd>LspRestart<cr>", vim.tbl_extend("force", opts, { desc = "Restart LSP" }))
        vim.keymap.set("n", "<leader>ci", "<cmd>LspInfo<cr>", vim.tbl_extend("force", opts, { desc = "LSP Info" }))
        vim.keymap.set("n", "<leader>cCr", function()
          vim.lsp.codelens.refresh()
        end, vim.tbl_extend("force", opts, { desc = "Refresh codelens" }))
        vim.keymap.set("n", "<leader>cCR", function()
          vim.lsp.codelens.run()
        end, vim.tbl_extend("force", opts, { desc = "Run codelens" }))

        if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
          local highlight_group = vim.api.nvim_create_augroup("lsp_document_highlight", { clear = false })

          vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
            buffer = ev.buf,
            group = highlight_group,
            callback = debounce(vim.lsp.buf.document_highlight, 100),
          })

          vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
            buffer = ev.buf,
            group = highlight_group,
            callback = vim.lsp.buf.clear_references,
          })

          vim.api.nvim_create_autocmd("LspDetach", {
            group = vim.api.nvim_create_augroup("lsp_detach", { clear = true }),
            callback = function(event)
              vim.lsp.buf.clear_references()
              vim.api.nvim_clear_autocmds({ group = "lsp_document_highlight", buffer = event.buf })
            end,
          })
        end

        if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_codeLens) then
          vim.lsp.codelens.refresh()
          vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "InsertLeave" }, {
            buffer = ev.buf,
            callback = vim.lsp.codelens.refresh,
          })
        end

        if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
          vim.keymap.set("n", "<leader>ch", function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = ev.buf }))
          end, vim.tbl_extend("force", opts, { desc = "Toggle inlay hints" }))

          -- Refresh inlay hints on cursor movement (current line only)
          local inlay_hints_group = vim.api.nvim_create_augroup("LSP_inlayHints", { clear = false })
          vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
            group = inlay_hints_group,
            desc = "Update inlay hints on line change",
            buffer = ev.buf,
            callback = function()
              vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
            end,
          })
        end
      end,
    })

    vim.lsp.config.lua_ls = {
      cmd = { 'lua-language-server' },
      filetypes = { 'lua' },
      root_dir = function(fname)
        return vim.fs.root(fname, { '.luarc.json', '.luarc.jsonc', '.git' })
      end,
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
            importModuleSpecifierEnding = "minimal",
            jsxAttributeCompletionStyle = "auto",
            quotePreference = "auto",
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
            jsxAttributeCompletionStyle = "auto",
            quotePreference = "auto",
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
          },
          hints = {
            assignVariableTypes = true,
            compositeLiteralFields = true,
            constantValues = true,
            parameterNames = true,
          },
          staticcheck = true,
          gofumpt = true,
        },
      },
    }

    vim.lsp.config.rust_analyzer = {
      cmd = { 'rust-analyzer' },
      filetypes = { 'rust' },
      root_markers = { 'Cargo.toml', '.git' },
      settings = {
        ['rust-analyzer'] = {
          cargo = { allFeatures = true },
          checkOnSave = { command = 'clippy' },
          inlayHints = {
            chainingHints = { enable = true },
            parameterHints = { enable = true },
            typeHints = { enable = true },
          },
        },
      },
    }

    vim.lsp.config.basedpyright = {
      cmd = { 'basedpyright-langserver', '--stdio' },
      filetypes = { 'python' },
      root_markers = { 'pyproject.toml', 'setup.py', '.envrc', '.git' },
      settings = {
        basedpyright = {
          analysis = {
            autoSearchPaths = true,
            typeCheckingMode = "basic",
            diagnosticMode = "workspace",
          },
        },
      },
    }

    vim.lsp.config.jsonls = {
      cmd = { 'vscode-json-language-server', '--stdio' },
      filetypes = { 'json', 'jsonc' },
      root_markers = { 'package.json', '.git' },
      settings = {
        json = {
          schemas = require('schemastore').json.schemas(),
          validate = { enable = true },
        },
      },
    }

    vim.lsp.config.yamlls = {
      cmd = { 'yaml-language-server', '--stdio' },
      filetypes = { 'yaml', 'yaml.docker-compose' },
      root_markers = { '.git', 'docker-compose.yml' },
      settings = {
        yaml = {
          schemaStore = {
            enable = false,
            url = "",
          },
          schemas = require('schemastore').yaml.schemas(),
        },
      },
    }

    vim.lsp.config.dockerls = {
      cmd = { 'docker-langserver', '--stdio' },
      filetypes = { 'dockerfile' },
      root_markers = { 'Dockerfile', '.git' },
    }

    vim.lsp.config.nixd = {
      cmd = { 'nixd' },
      filetypes = { 'nix' },
      root_markers = { 'flake.nix', 'shell.nix', '.git' },
    }

    vim.lsp.config.expert = {
      cmd = { vim.fn.expand('~/.tools/expert/expert') },
      filetypes = { 'elixir', 'eelixir', 'heex', 'surface' },
      root_markers = { 'mix.exs', '.git' },
    }

    vim.lsp.config.ty = {
      cmd = { 'uvx', '--with', 'ty', 'ty', 'lsp' },
      filetypes = { 'python' },
      root_markers = { 'pyproject.toml', 'setup.py', '.envrc', '.git' },
    }

    vim.lsp.config.tailwindcss = {
      cmd = { 'tailwindcss-language-server', '--stdio' },
      filetypes = { 'html', 'css', 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'vue', 'svelte' },
      root_markers = { 'tailwind.config.js', 'tailwind.config.ts', 'tailwind.config.cjs', 'tailwind.config.mjs', '.git' },
    }

    vim.lsp.config.emmet_language_server = {
      cmd = { 'emmet-language-server', '--stdio' },
      filetypes = { 'css', 'html', 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'vue', 'svelte' },
      root_markers = { 'package.json', '.git' },
    }

    vim.lsp.config.cssls = {
      cmd = { 'vscode-css-language-server', '--stdio' },
      filetypes = { 'css', 'scss', 'less' },
      root_markers = { 'package.json', '.git' },
      settings = {
        css = { validate = true },
        scss = { validate = true },
        less = { validate = true },
      },
    }

    vim.lsp.config.html = {
      cmd = { 'vscode-html-language-server', '--stdio' },
      filetypes = { 'html', 'htmldjango' },
      root_markers = { 'package.json', '.git' },
      settings = {
        html = {
          format = {
            enable = true,
            wrapLineLength = 120,
            wrapAttributes = 'auto',
          },
        },
      },
    }

    vim.lsp.config.air = {
      cmd = { 'air', 'lsp' },
      filetypes = { 'r', 'rmd', 'qmd' },
      root_markers = { '.git', 'renv.lock', 'DESCRIPTION' },
    }

    -- Angular LSP with dynamic probe paths
    local npm_prefix = vim.fn.system('npm prefix -g'):gsub('\n', '')
    vim.lsp.config.angularls = {
      cmd = {
        'ngserver',
        '--stdio',
        '--tsProbeLocations', vim.fn.getcwd() .. '/node_modules,' .. npm_prefix .. '/lib/node_modules',
        '--ngProbeLocations', vim.fn.getcwd() .. '/node_modules,' .. npm_prefix .. '/lib/node_modules'
      },
      filetypes = { 'typescript', 'html', 'typescriptreact', 'typescript.tsx' },
      root_markers = { 'angular.json', 'project.json' },
    }

    vim.lsp.config.cssmodules_ls = {
      cmd = { 'cssmodules-language-server' },
      filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
      root_markers = { 'package.json' },
    }

    vim.lsp.config.astro = {
      cmd = { 'astro-ls', '--stdio' },
      filetypes = { 'astro' },
      root_markers = { 'package.json', 'astro.config.mjs', 'astro.config.js' },
    }

    vim.lsp.config.ruby_lsp = {
      cmd = { 'ruby-lsp' },
      filetypes = { 'ruby' },
      root_markers = { 'Gemfile', '.git' },
    }

    local servers = {
      { name = 'lua_ls', cmd = 'lua-language-server' },
      { name = 'vtsls', cmd = 'vtsls' },
      { name = 'gopls', cmd = 'gopls' },
      { name = 'rust_analyzer', cmd = 'rust-analyzer' },
      { name = 'basedpyright', cmd = 'basedpyright-langserver' },
      { name = 'jsonls', cmd = 'vscode-json-language-server' },
      { name = 'yamlls', cmd = 'yaml-language-server' },
      { name = 'dockerls', cmd = 'docker-langserver' },
      { name = 'nixd', cmd = 'nixd' },
      { name = 'expert', cmd = vim.fn.expand('~/.tools/expert/expert') },
      { name = 'ty', cmd = 'uvx' },
      { name = 'tailwindcss', cmd = 'tailwindcss-language-server' },
      { name = 'emmet_language_server', cmd = 'emmet-language-server' },
      { name = 'cssls', cmd = 'vscode-css-language-server' },
      { name = 'cssmodules_ls', cmd = 'cssmodules-language-server' },
      { name = 'astro', cmd = 'astro-ls' },
      { name = 'html', cmd = 'vscode-html-language-server' },
      { name = 'air', cmd = 'air' },
      { name = 'ruby_lsp', cmd = 'ruby-lsp' },
    }

    for _, server in ipairs(servers) do
      if vim.fn.executable(server.cmd) == 1 then
        vim.lsp.enable(server.name)
      end
    end

    -- Enable Angular LS only for Angular projects
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'typescript', 'html', 'typescriptreact', 'typescript.tsx' },
      callback = function()
        local root = vim.fs.root(0, { 'angular.json', 'project.json' })
        if root and vim.fn.executable('ngserver') == 1 then
          vim.lsp.enable('angularls')
        end
      end,
    })

    vim.lsp.set_log_level("WARN")

    vim.diagnostic.config({
      virtual_text = false,
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = "●",
          [vim.diagnostic.severity.WARN] = "●",
          [vim.diagnostic.severity.HINT] = "●",
          [vim.diagnostic.severity.INFO] = "●",
        },
      },
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = {
        border = "rounded",
        source = "always",
        header = "",
        prefix = "",
      },
    })

    vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
      border = "rounded",
      max_width = 80,
      max_height = 20,
    })

    vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
      border = "rounded",
      max_width = 80,
      max_height = 15,
    })

    -- Override quickfix/loclist to use snacks
    vim.api.nvim_create_user_command('Copen', function()
      require("snacks").picker.qflist()
    end, {})

    vim.api.nvim_create_user_command('Lopen', function()
      require("snacks").picker.loclist()
    end, {})

    vim.cmd([[
      cnoreabbrev copen Copen
      cnoreabbrev lopen Lopen
    ]])

    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client then
          if client.config and client.config.flags then
            client.config.flags.debounce_text_changes = 150
          end
          if client.server_capabilities then
            client.server_capabilities.textDocumentSync = client.server_capabilities.textDocumentSync or {}
            if type(client.server_capabilities.textDocumentSync) == "table" then
              client.server_capabilities.textDocumentSync.change = 2
            end
          end
        end
      end,
    })
  end,
}
