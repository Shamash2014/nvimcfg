if vim.fn.executable("gopls") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "gopls",
    cmd = { "gopls" },
    root_dir = vim.fs.root(0, { "go.mod", "go.work", ".git" }),
    settings = {
      gopls = {
        analyses = {
          unusedparams = true,
        },
        staticcheck = true,
        gofumpt = true,
      },
    },
  }))
end

if vim.fn.executable("dlv") == 1 then
  local ok, dap = pcall(require, 'dap')
  if not ok then return end

  if not dap.adapters.delve then
    dap.adapters.delve = {
      type = 'server',
      port = '${port}',
      executable = {
        command = 'dlv',
        args = { 'dap', '-l', '127.0.0.1:${port}' },
      }
    }
  end

  -- Helper function to detect Docker setup
  local has_docker_compose = function()
    return vim.fn.filereadable("docker-compose.yml") == 1 or
           vim.fn.filereadable("docker-compose.yaml") == 1 or
           vim.fn.filereadable("compose.yml") == 1 or
           vim.fn.filereadable("compose.yaml") == 1
  end

  local has_dockerfile = function()
    return vim.fn.filereadable("Dockerfile") == 1 or
           vim.fn.filereadable("Dockerfile.dev") == 1
  end

  if not dap.configurations.go then
    local configs = {
      {
        type = 'delve',
        name = 'Debug',
        request = 'launch',
        program = '${file}',
      },
      {
        type = 'delve',
        name = 'Debug test',
        request = 'launch',
        mode = 'test',
        program = '${file}',
      },
      {
        type = 'delve',
        name = 'Debug Package',
        request = 'launch',
        program = '${fileDirname}',
      },
    }

    -- Add Docker configurations if Docker setup is detected
    if has_docker_compose() then
      table.insert(configs, {
        type = 'delve',
        name = 'Debug in Docker (Compose)',
        request = 'launch',
        program = '${file}',
        env = {
          CGO_ENABLED = "0",
        },
        preLaunchTask = {
          type = "shell",
          command = "docker",
          args = { "compose", "up", "-d", "--build" },
          presentation = {
            reveal = "always",
            panel = "new"
          }
        },
        postDebugTask = {
          type = "shell",
          command = "docker",
          args = { "compose", "down" }
        }
      })

      table.insert(configs, {
        type = 'delve',
        name = 'Attach to Docker Container',
        request = 'attach',
        mode = 'remote',
        remotePath = '/app',
        port = 40000,
        host = '127.0.0.1',
        showLog = true,
        preLaunchTask = {
          type = "shell",
          command = "docker",
          args = { "compose", "exec", "-d", "app", "dlv", "debug", "--headless", "--listen=:40000", "--api-version=2", "." }
        }
      })
    elseif has_dockerfile() then
      table.insert(configs, {
        type = 'delve',
        name = 'Debug in Docker',
        request = 'launch',
        program = '${file}',
        env = {
          CGO_ENABLED = "0",
        },
        preLaunchTask = {
          type = "shell",
          command = "docker",
          args = { "build", "-t", "go-debug", "." },
          presentation = {
            reveal = "always",
            panel = "new"
          }
        }
      })
    end

    dap.configurations.go = configs
  end
end

local ok, lint = pcall(require, 'lint')
if ok then
  local linters = {}

  if vim.fn.executable("golangci-lint") == 1 then
    table.insert(linters, "golangcilint")
  elseif vim.fn.executable("revive") == 1 then
    table.insert(linters, "revive")
  end

  if #linters > 0 then
    lint.linters_by_ft.go = linters
  end
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform then
  local formatters = {}

  if vim.fn.executable("goimports") == 1 then
    table.insert(formatters, "goimports")
  end

  if vim.fn.executable("gofumpt") == 1 then
    table.insert(formatters, "gofumpt")
  end

  if #formatters > 0 then
    conform.formatters_by_ft.go = formatters
  end
end
