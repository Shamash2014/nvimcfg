vim.diagnostic.config({
  virtual_text = false,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    border = "single",
    source = "always",
    header = "",
    prefix = "",
  },
})

local signs = { Error = "✘", Warn = "▲", Hint = "⚑", Info = "»" }
for type, icon in pairs(signs) do
  local hl = "DiagnosticSign" .. type
  vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

local on_attach = function(client, bufnr)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, noremap = true, silent = true })
  end

  map("n", "gd", vim.lsp.buf.definition, "Go to Definition")
  map("n", "gD", vim.lsp.buf.declaration, "Go to Declaration")
  map("n", "gi", vim.lsp.buf.implementation, "Go to Implementation")
  map("n", "gr", vim.lsp.buf.references, "Go to References")
  map("n", "gt", vim.lsp.buf.type_definition, "Go to Type Definition")
  map("n", "K", vim.lsp.buf.hover, "Hover Documentation")
  map("n", "<leader>cs", vim.lsp.buf.signature_help, "Signature Help")
  map("i", "<C-s>", vim.lsp.buf.signature_help, "Signature Help")

  map("n", "<leader>ca", vim.lsp.buf.code_action, "Code Action")
  map("v", "<leader>ca", vim.lsp.buf.code_action, "Code Action")
  map("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
  map("n", "<leader>cd", vim.diagnostic.open_float, "Show Diagnostic")
  map("n", "[d", vim.diagnostic.goto_prev, "Previous Diagnostic")
  map("n", "]d", vim.diagnostic.goto_next, "Next Diagnostic")
  map("n", "<leader>sw", vim.lsp.buf.workspace_symbol, "Workspace Symbol Search")

  if client.server_capabilities.documentHighlightProvider then
    local group = vim.api.nvim_create_augroup("LSPDocumentHighlight_" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        -- Skip if in terminal, prompt, or very large file
        local filetype = vim.bo[bufnr].filetype
        local buftype = vim.bo[bufnr].buftype
        local line_count = vim.api.nvim_buf_line_count(bufnr)

        if buftype == "terminal" or buftype == "prompt" or filetype == "" or line_count > 5000 then
          return
        end

        vim.lsp.buf.clear_references()
        vim.lsp.buf.document_highlight()
      end,
    })
  end

  if client.server_capabilities.inlayHintProvider then
    map("n", "<leader>ch", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
    end, "Toggle Inlay Hints")
  end
end

local capabilities = vim.lsp.protocol.make_client_capabilities()

-- Enhance capabilities for better LSP support
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

capabilities.textDocument.foldingRange = {
  dynamicRegistration = false,
  lineFoldingOnly = true
}

capabilities.workspace.workspaceFolders = true
capabilities.workspace.configuration = true

_G.lsp_config = {
  on_attach = on_attach,
  capabilities = capabilities,
  flags = {
    debounce_text_changes = 150,
    allow_incremental_sync = true,
  },
  -- Add timeout protection for server starts
  handlers = {
    ["textDocument/publishDiagnostics"] = vim.lsp.with(
      vim.lsp.diagnostic.on_publish_diagnostics, {
        severity_sort = true,
        update_in_insert = false,
      }
    ),
  },
}

vim.api.nvim_create_user_command("LspRestart", function()
  vim.lsp.stop_client(vim.lsp.get_active_clients())
  vim.cmd("edit")
end, { desc = "Restart LSP servers" })

vim.api.nvim_create_user_command("LspLog", function()
  vim.cmd("edit " .. vim.lsp.get_log_path())
end, { desc = "Open LSP log" })

vim.api.nvim_create_user_command("LspInfo", function()
  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    vim.notify("No LSP clients attached", vim.log.levels.INFO)
    return
  end

  local lines = { "Active LSP clients:" }
  for _, client in pairs(clients) do
    local buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(vim.lsp.get_clients({ bufnr = buf }), client) then
        table.insert(buffers, vim.api.nvim_buf_get_name(buf))
      end
    end
    table.insert(lines, string.format("  %s (id: %d)", client.name, client.id))
    table.insert(lines, string.format("    filetypes: %s", table.concat(client.config.filetypes or {}, ", ")))
    table.insert(lines, string.format("    root_dir: %s", client.config.root_dir or "unknown"))
    table.insert(lines, string.format("    buffers: %d", #buffers))
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, buf)
end, { desc = "Show LSP client information" })

-- Debug autocmd to notify when LSP attaches
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then
      vim.notify(string.format("LSP '%s' attached to buffer", client.name), vim.log.levels.INFO)
    end
  end
})

-- LSP Server configurations
local servers = {
  -- TypeScript/JavaScript
  vtsls = {
    filetypes = { "typescript", "javascript", "javascriptreact", "typescriptreact" },
    cmd = { "/Users/shamash/.local/share/mise/installs/node/22.18.0/bin/vtsls", "--stdio" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "package.json", "tsconfig.json", "jsconfig.json", ".git" })
    end,
    settings = {
      vtsls = {
        experimental = {
          completion = {
            enableServerSideFuzzyMatch = true,
          },
        },
      },
      typescript = {
        preferences = {
          inlayHints = {
            enumMemberValues = { enabled = true },
            functionLikeReturnTypes = { enabled = true },
            parameterNames = { enabled = "literals" },
            parameterTypes = { enabled = true },
            propertyDeclarationTypes = { enabled = true },
            variableTypes = { enabled = false },
          },
        },
      },
    },
  },

  -- Python
  basedpyright = {
    filetypes = { "python" },
    cmd = { "basedpyright-langserver", "--stdio" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git" })
    end,
    settings = {
      basedpyright = {
        analysis = {
          autoSearchPaths = true,
          useLibraryCodeForTypes = true,
          diagnosticMode = "workspace",
        },
      },
    },
  },

  -- Go
  gopls = {
    filetypes = { "go", "gomod", "gowork", "gotmpl" },
    cmd = { "gopls" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "go.work", "go.mod", ".git" })
    end,
    settings = {
      gopls = {
        analyses = {
          unusedparams = true,
        },
        staticcheck = true,
        gofumpt = true,
      },
    },
  },

  -- Rust
  rust_analyzer = {
    filetypes = { "rust" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "Cargo.toml", "rust-project.json", ".git" })
    end,
    settings = {
      ["rust-analyzer"] = {
        cargo = {
          allFeatures = true,
          loadOutDirsFromCheck = true,
          runBuildScripts = true,
        },
        checkOnSave = {
          allFeatures = true,
          command = "clippy",
          extraArgs = { "--no-deps" },
        },
      },
    },
  },

  -- Lua
  lua_ls = {
    filetypes = { "lua" },
    cmd = { "lua-language-server" },
    root_dir = function(fname)
      return vim.fs.root(fname, { ".luarc.json", ".luarc.jsonc", ".luacheckrc", ".stylua.toml", "stylua.toml", "selene.toml", "selene.yml", ".git" })
    end,
    settings = {
      Lua = {
        runtime = {
          version = "LuaJIT"
        },
        diagnostics = {
          globals = { "vim" },
        },
        workspace = {
          library = vim.api.nvim_get_runtime_file("", true),
          checkThirdParty = false,
        },
        telemetry = {
          enable = false,
        },
      },
    },
  },

  -- Dart/Flutter
  dartls = {
    filetypes = { "dart" },
    cmd = { "dart", "language-server", "--protocol=lsp" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "pubspec.yaml", ".git" })
    end,
    settings = {
      dart = {
        analysisExcludedFolders = {
          vim.fn.expand("$HOME") .. "/.pub-cache",
          ".dart_tool",
          "build"
        },
        enableSnippets = true,
        updateImportsOnRename = true,
        completeFunctionCalls = true,
      },
    },
  },

  -- Swift
  sourcekit = {
    filetypes = { "swift" },
    cmd = { "sourcekit-lsp" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "Package.swift", ".git" })
    end,
    settings = {},
  },

  -- JSON
  jsonls = {
    filetypes = { "json", "jsonc" },
    cmd = { "vscode-json-language-server", "--stdio" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "package.json", ".git" })
    end,
    settings = {
      json = {
        validate = { enable = true },
        format = { enable = true },
      },
    },
  },

  -- CSS/SCSS
  cssls = {
    filetypes = { "css", "scss", "less" },
    cmd = { "vscode-css-language-server", "--stdio" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "package.json", ".git" })
    end,
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
      less = {
        validate = true,
        lint = {
          unknownAtRules = "ignore",
        },
      },
    },
  },

  -- HTML
  html = {
    filetypes = { "html", "templ" },
    cmd = { "vscode-html-language-server", "--stdio" },
    root_dir = function(fname)
      return vim.fs.root(fname, { "package.json", ".git" })
    end,
    settings = {
      html = {
        format = {
          templating = true,
          wrapLineLength = 120,
          wrapAttributes = "auto",
        },
        hover = {
          documentation = true,
          references = true,
        },
      },
    },
  },

  -- YAML
  yamlls = {
    filetypes = { "yaml", "yml" },
    cmd = { "yaml-language-server", "--stdio" },
    root_dir = function(fname)
      return vim.fs.root(fname, { ".yamllint", ".yamllint.yml", ".yamllint.yaml", ".git" })
    end,
    settings = {
      yaml = {
        schemaStore = {
          enable = false,
          url = "",
        },
        validate = true,
        format = { enable = true },
        hover = true,
        completion = true,
      },
    },
  },


}

-- Note: Elixir uses expert LSP configured in ftplugin/elixir.lua
-- Note: Astro LSP remains in ftplugin/astro.lua due to complex TypeScript integration
-- All other LSP servers centralized here for consistent management

-- Auto-start LSP servers based on filetype
vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    local bufnr = args.buf
    local filetype = vim.bo[bufnr].filetype

    for server_name, config in pairs(servers) do
      if vim.tbl_contains(config.filetypes or {}, filetype) then
        -- Check if server is executable (use first cmd element or server name)
        local executable = config.cmd and config.cmd[1] or server_name
        if vim.fn.executable(executable) == 1 then
          -- Check if server is already running for this buffer
          local clients = vim.lsp.get_clients({ bufnr = bufnr, name = server_name })
          if #clients == 0 then
            -- Validate root directory before starting server
            local root_dir = config.root_dir and config.root_dir(vim.api.nvim_buf_get_name(bufnr))
            if not root_dir then
              root_dir = vim.fn.getcwd() -- Fallback to current working directory
            end

            local lsp_opts = vim.tbl_extend("force", _G.lsp_config, {
              name = server_name,
              cmd = config.cmd or { server_name },
              root_dir = root_dir,
              settings = config.settings,
              filetypes = config.filetypes,
            })

            local success, client_id = pcall(vim.lsp.start, lsp_opts)
            if success then
              vim.notify(string.format("Started %s (ID: %s) for %s", server_name, client_id, filetype), vim.log.levels.INFO)
            else
              vim.notify(string.format("Failed to start %s: %s", server_name, client_id), vim.log.levels.ERROR)
            end
          end
        -- Note: Silently skip missing optional LSP servers to avoid spam
        -- Enable this line for debugging LSP server detection:
        -- vim.notify(string.format("LSP server '%s' executable not found: %s", server_name, executable), vim.log.levels.DEBUG)
        end
      end
    end
  end,
})
