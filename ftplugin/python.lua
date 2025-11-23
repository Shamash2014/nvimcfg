if vim.fn.executable("basedpyright-langserver") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "basedpyright",
    cmd = { "basedpyright-langserver", "--stdio" },
    root_dir = vim.fs.root(0, { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git" }),
    settings = {
      basedpyright = {
        analysis = {
          autoSearchPaths = true,
          useLibraryCodeForTypes = true,
          diagnosticMode = "workspace",
        },
      },
    },
  }))
end

if vim.fn.executable("python") == 1 then
  local ok, dap = pcall(require, 'dap')
  if not ok then return end

  if not dap.adapters.python then
    dap.adapters.python = {
      type = 'executable',
      command = 'python',
      args = { '-m', 'debugpy.adapter' },
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

  if not dap.configurations.python then
    local configs = {
      {
        type = 'python',
        request = 'launch',
        name = 'Launch file',
        program = '${file}',
        pythonPath = function()
          local venv = os.getenv('VIRTUAL_ENV')
          if venv then
            return venv .. '/bin/python'
          end
          return 'python'
        end,
      },
      {
        type = 'python',
        request = 'attach',
        name = 'Attach to process',
        processId = require('dap.utils').pick_process,
        pythonPath = function()
          local venv = os.getenv('VIRTUAL_ENV')
          if venv then
            return venv .. '/bin/python'
          end
          return 'python'
        end,
      },
    }

    -- Add Docker configurations if Docker setup is detected
    if has_docker_compose() then
      table.insert(configs, {
        type = 'python',
        request = 'launch',
        name = 'Debug in Docker (Compose)',
        program = '${file}',
        console = 'integratedTerminal',
        env = {
          PYTHONPATH = "/app",
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
        type = 'python',
        request = 'attach',
        name = 'Attach to Docker Container',
        host = 'localhost',
        port = 5678,
        pathMappings = {
          {
            localRoot = '${workspaceFolder}',
            remoteRoot = '/app'
          }
        },
        preLaunchTask = {
          type = "shell",
          command = "docker",
          args = { "compose", "exec", "-d", "app", "python", "-m", "debugpy", "--listen", "0.0.0.0:5678", "--wait-for-client", "${file}" }
        }
      })
    elseif has_dockerfile() then
      table.insert(configs, {
        type = 'python',
        request = 'launch',
        name = 'Debug in Docker',
        program = '${file}',
        console = 'integratedTerminal',
        env = {
          PYTHONPATH = "/app",
        },
        preLaunchTask = {
          type = "shell",
          command = "docker",
          args = { "build", "-t", "python-debug", "." },
          presentation = {
            reveal = "always",
            panel = "new"
          }
        }
      })
    end

    dap.configurations.python = configs
  end
end

local ok, lint = pcall(require, 'lint')
if ok then
  local linters = {}

  if vim.fn.executable("ruff") == 1 then
    table.insert(linters, "ruff")
  end

  if #linters > 0 then
    lint.linters_by_ft.python = linters
  end
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("ruff") == 1 then
  conform.formatters_by_ft.python = { "ruff_format" }
end
