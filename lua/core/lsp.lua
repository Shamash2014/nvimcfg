local M = {}

local did_setup = false

local function root(bufnr, markers)
  return vim.fs.root(bufnr, markers)
end

local function cmd_or_nil(candidates)
  for _, cmd in ipairs(candidates) do
    if vim.fn.executable(cmd[1]) == 1 then
      return cmd
    end
  end
end

local function npm_global_root()
  local env_root = vim.env.NODE_MODULES_GLOBAL
  if env_root and env_root ~= "" and vim.uv.fs_stat(env_root) then
    return env_root
  end

  if vim.fn.executable("npm") ~= 1 then
    return nil
  end

  local result = vim.system({ "npm", "root", "-g" }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local root_dir = vim.trim(result.stdout or "")
  if root_dir == "" or not vim.uv.fs_stat(root_dir) then
    return nil
  end

  return root_dir
end

local function configure(name, config)
  vim.lsp.config(name, config)
  vim.lsp.enable(name)
end

local function configure_optional(name, config, cmd)
  if cmd == nil then
    return false
  end
  config = config or {}
  config.cmd = cmd
  configure(name, config)
  return true
end

local function typescript_tsdk(root_dir)
  if root_dir then
    local local_tsdk = vim.fs.joinpath(root_dir, "node_modules", "typescript", "lib")
    if vim.uv.fs_stat(local_tsdk) then
      return local_tsdk
    end
  end

  local global_root = npm_global_root()
  if global_root then
    local global_tsdk = vim.fs.joinpath(global_root, "typescript", "lib")
    if vim.uv.fs_stat(global_tsdk) then
      return global_tsdk
    end
  end
end

local function angular_core_version(root_dir)
  if not root_dir then
    return ""
  end

  local package_json = vim.fs.joinpath(root_dir, "package.json")
  if not vim.uv.fs_stat(package_json) then
    return ""
  end

  local ok, contents = pcall(vim.fn.readfile, package_json)
  if not ok or not contents or #contents == 0 then
    return ""
  end

  local decoded_ok, decoded = pcall(vim.json.decode, table.concat(contents, "\n"))
  if not decoded_ok or type(decoded) ~= "table" then
    return ""
  end

  local angular_core = decoded.dependencies and decoded.dependencies["@angular/core"]
  if type(angular_core) ~= "string" then
    angular_core = decoded.devDependencies and decoded.devDependencies["@angular/core"]
  end

  if type(angular_core) ~= "string" then
    return ""
  end

  return (angular_core:match("%d+%.%d+%.%d+") or angular_core)
end

local function angular_probe_locations(root_dir)
  local locations = {}

  if root_dir then
    local local_node_modules = vim.fs.joinpath(root_dir, "node_modules")
    if vim.uv.fs_stat(local_node_modules) then
      locations[#locations + 1] = local_node_modules
    end
  end

  local global_root = npm_global_root()
  if global_root then
    locations[#locations + 1] = global_root
  end

  return table.concat(locations, ",")
end

local function setup_keymaps()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("nvim3-lsp-keymaps", { clear = true }),
    callback = function(ev)
      local bufnr = ev.buf
      local opts = { buffer = bufnr, noremap = true, silent = true }

      vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
      vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
      vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
      vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
      vim.keymap.set("n", "gs", vim.lsp.buf.signature_help, opts)
      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
      vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, opts)
      vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
      vim.keymap.set("n", "<leader>ds", vim.lsp.buf.document_symbol, opts)
      vim.keymap.set("n", "<leader>ws", vim.lsp.buf.workspace_symbol, opts)
      vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
      vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
      vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
      vim.keymap.set("n", "<leader>cf", function()
        local ok, conform = pcall(require, "conform")
        if ok then
          conform.format({ bufnr = bufnr, async = true, lsp_fallback = true })
          return
        end
        vim.lsp.buf.format({ bufnr = bufnr, async = true })
      end, opts)
    end,
  })
end

local function setup_diagnostics()
  vim.diagnostic.config({
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = "󰅚 ",
        [vim.diagnostic.severity.WARN] = "󰀪 ",
        [vim.diagnostic.severity.INFO] = "󰋽 ",
        [vim.diagnostic.severity.HINT] = "󰌵 ",
      },
      linehl = {
        [vim.diagnostic.severity.ERROR] = "ErrorMsg",
      },
      numhl = {
        [vim.diagnostic.severity.ERROR] = "ErrorMsg",
      },
    },
    virtual_text = false,
    severity_sort = true,
    float = {
      border = "rounded",
      source = "always",
      header = "",
      prefix = "",
      focusable = false,
    },
    update_in_insert = false,
  })
end

local function setup_lua_ls()
  configure("lua_ls", {
    cmd = { "lua-language-server" },
    filetypes = { "lua" },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, { ".luarc.json", ".luarc.jsonc", ".git" })
      if project_root then
        on_dir(project_root)
        return
      end
      on_dir(vim.fn.stdpath("config"))
    end,
    settings = {
      Lua = {
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = {
          checkThirdParty = false,
          library = vim.list_extend(vim.api.nvim_get_runtime_file("", true), {
            vim.fn.stdpath("config") .. "/lua",
          }),
        },
        telemetry = { enable = false },
      },
    },
  })
end

local function setup_typescript()
  local ts_cmd = cmd_or_nil({
    { "typescript-language-server", "--stdio" },
    { "bunx", "typescript-language-server", "--stdio" },
  })

  if not ts_cmd then
    return
  end

  configure("ts_ls", {
    cmd = ts_cmd,
    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
    init_options = { hostInfo = "neovim" },
    root_dir = function(bufnr, on_dir)
      local bun_root = root(bufnr, { "bun.lockb", "bun.lock" })
      if bun_root then
        return
      end

      local deno_root = root(bufnr, { "deno.json", "deno.jsonc" })
      local deno_lock_root = root(bufnr, { "deno.lock" })
      local project_root = root(bufnr, { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", ".git" })

      if deno_lock_root and (not project_root or #deno_lock_root > #project_root) then
        return
      end

      if deno_root and (not project_root or #deno_root >= #project_root) then
        return
      end

      if project_root then
        on_dir(project_root)
      end
    end,
  })

  configure("bun_ts_ls", {
    cmd = ts_cmd,
    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
    init_options = { hostInfo = "neovim" },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, { "bun.lockb", "bun.lock" })
      if project_root then
        on_dir(project_root)
      end
    end,
  })
end

local function setup_gopls()
  configure("gopls", {
    cmd = { "gopls" },
    filetypes = { "go", "gomod", "gowork", "gotmpl" },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, { "go.work", "go.mod", ".git" })
      if project_root then
        on_dir(project_root)
      end
    end,
  })
end

local function setup_dartls()
  configure("dartls", {
    cmd = { "dart", "language-server", "--protocol=lsp" },
    filetypes = { "dart" },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, { "pubspec.yaml", "analysis_options.yaml", ".git" })
      if project_root then
        on_dir(project_root)
      end
    end,
  })
end

local function setup_astro()
  configure_optional("astro", {
    filetypes = { "astro" },
    init_options = {
      typescript = {},
    },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, { "package.json", "tsconfig.json", "jsconfig.json", ".git" })
      if project_root then
        on_dir(project_root)
      end
    end,
    before_init = function(_, config)
      config.init_options = config.init_options or {}
      config.init_options.typescript = config.init_options.typescript or {}
      if not config.init_options.typescript.tsdk then
        config.init_options.typescript.tsdk = typescript_tsdk(config.root_dir)
      end
    end,
  }, cmd_or_nil({
    { "astro-ls", "--stdio" },
  }))
end

local function setup_angular()
  configure_optional("angularls", {
    filetypes = { "html", "typescript", "typescriptreact", "typescript.tsx", "htmlangular" },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, { "angular.json", "nx.json", ".git" })
      if project_root then
        on_dir(project_root)
      end
    end,
    before_init = function(_, config)
      local root_dir = config.root_dir or vim.fn.getcwd()
      local probe_locations = angular_probe_locations(root_dir)
      local angular_core = angular_core_version(root_dir)

      config.cmd = {
        "ngserver",
        "--stdio",
        "--tsProbeLocations",
        probe_locations,
        "--ngProbeLocations",
        probe_locations,
        "--angularCoreVersion",
        angular_core,
      }
    end,
  }, cmd_or_nil({
    { "ngserver", "--stdio" },
  }))
end

local function setup_swift()
  configure_optional("sourcekit_lsp", {
    filetypes = { "swift" },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, { "Package.swift", ".git" })
      if project_root then
        on_dir(project_root)
        return
      end
      on_dir(vim.fn.getcwd())
    end,
  }, cmd_or_nil({
    { "sourcekit-lsp" },
  }))
end

local function setup_kotlin()
  configure_optional("kotlin_lsp", {
    filetypes = { "kotlin", "kts" },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, {
        "settings.gradle.kts",
        "settings.gradle",
        "build.gradle.kts",
        "build.gradle",
        ".git",
      })
      if project_root then
        on_dir(project_root)
        return
      end
      on_dir(vim.fn.getcwd())
    end,
  }, cmd_or_nil({
    { "kotlin-lsp", "--stdio" },
  }))
end

local function setup_emmet()
  configure_optional("emmet_language_server", {
    filetypes = {
      "css",
      "html",
      "javascriptreact",
      "less",
      "sass",
      "scss",
      "typescriptreact",
    },
    init_options = {
      includeLanguages = {},
      excludeLanguages = {},
      extensionsPath = {},
      preferences = {},
      showAbbreviationSuggestions = true,
      showExpandedAbbreviation = "always",
      showSuggestionsAsSnippets = false,
      syntaxProfiles = {},
      variables = {},
    },
    root_dir = function(bufnr, on_dir)
      local project_root = root(bufnr, { ".git" })
      if project_root then
        on_dir(project_root)
        return
      end
      on_dir(vim.fn.getcwd())
    end,
  }, cmd_or_nil({
    { "emmet-language-server", "--stdio" },
  }))
end

local function setup_elixir()
  local expert_cmd = { "expert", "--stdio" }

  if vim.fn.executable(expert_cmd[1]) == 1 then
    configure("expert", {
      cmd = expert_cmd,
      filetypes = { "elixir", "eelixir", "heex", "surface" },
      root_dir = function(bufnr, on_dir)
        local project_root = root(bufnr, { "mix.exs", ".git" })
        if project_root then
          on_dir(project_root)
        end
      end,
    })
  else
    vim.schedule(function()
      vim.notify("expert is not on PATH; install it to enable Elixir LSP", vim.log.levels.WARN)
    end)
  end
end

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  setup_keymaps()
  setup_diagnostics()

  setup_lua_ls()
  setup_typescript()
  setup_gopls()
  setup_dartls()
  setup_astro()
  setup_angular()
  setup_swift()
  setup_kotlin()
  setup_emmet()
  setup_elixir()
end

return M
