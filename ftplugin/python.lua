-- Python LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'PythonRun',
  function()
    if vim.fn.executable("python") == 0 then
      vim.notify("Python executable not found", vim.log.levels.ERROR)
      return
    end
    local file = vim.fn.expand('%')
    vim.cmd('terminal python ' .. file)
  end, { desc = 'Run current Python file' })

vim.api.nvim_buf_create_user_command(0, 'PythonTest',
  function()
    if vim.fn.executable("python") == 0 then
      vim.notify("Python executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal python -m pytest')
  end, { desc = 'Run Python tests with pytest' })

vim.api.nvim_buf_create_user_command(0, 'PythonFormat',
  function()
    if vim.fn.executable("black") == 1 then
      vim.cmd('terminal black %')
    elseif vim.fn.executable("autopep8") == 1 then
      vim.cmd('terminal autopep8 --in-place %')
    else
      vim.notify("No Python formatter found (black or autopep8)", vim.log.levels.WARN)
    end
  end, { desc = 'Format Python file' })

vim.api.nvim_buf_create_user_command(0, 'PythonLint',
  function()
    if vim.fn.executable("flake8") == 1 then
      vim.cmd('terminal flake8 %')
    elseif vim.fn.executable("pylint") == 1 then
      vim.cmd('terminal pylint %')
    else
      vim.notify("No Python linter found (flake8 or pylint)", vim.log.levels.WARN)
    end
  end, { desc = 'Lint Python file' })

-- Django-specific commands if manage.py exists
local manage_py = vim.fs.root(0, {"manage.py"})
if manage_py and vim.fn.filereadable(manage_py .. "/manage.py") == 1 then
  vim.api.nvim_buf_create_user_command(0, 'DjangoRunServer',
    function()
      vim.cmd('terminal cd ' .. manage_py .. ' && python manage.py runserver')
    end, { desc = 'Run Django development server' })

  vim.api.nvim_buf_create_user_command(0, 'DjangoMigrate',
    function()
      vim.cmd('terminal cd ' .. manage_py .. ' && python manage.py migrate')
    end, { desc = 'Run Django migrations' })

  vim.api.nvim_buf_create_user_command(0, 'DjangoMakeMigrations',
    function()
      vim.cmd('terminal cd ' .. manage_py .. ' && python manage.py makemigrations')
    end, { desc = 'Create Django migrations' })

  vim.api.nvim_buf_create_user_command(0, 'DjangoShell',
    function()
      vim.cmd('terminal cd ' .. manage_py .. ' && python manage.py shell')
    end, { desc = 'Open Django shell' })
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

-- Contextual commands for command palette
local function get_project_root()
  return require('tasks').get_project_root() or vim.fn.getcwd()
end

vim.api.nvim_buf_create_user_command(0, 'PythonRunFile',
  function()
    local file = vim.fn.expand('%:p')
    require('tasks').run_command('python ' .. vim.fn.shellescape(file))
  end, { desc = 'Run Current Python File' })

vim.api.nvim_buf_create_user_command(0, 'PythonRunTests',
  function()
    local root = get_project_root()
    if vim.fn.filereadable(root .. '/pytest.ini') == 1 or vim.fn.glob(root .. '/test_*.py') ~= '' then
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && python -m pytest')
    else
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && python -m unittest discover')
    end
  end, { desc = 'Run Python Tests' })

vim.api.nvim_buf_create_user_command(0, 'PythonLint',
  function()
    local root = get_project_root()
    require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && ruff check .')
  end, { desc = 'Lint Python Project' })

vim.api.nvim_buf_create_user_command(0, 'PythonFormat',
  function()
    local root = get_project_root()
    require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && ruff format .')
  end, { desc = 'Format Python Project' })

vim.api.nvim_buf_create_user_command(0, 'PythonInstallDeps',
  function()
    local root = get_project_root()
    if vim.fn.filereadable(root .. '/requirements.txt') == 1 then
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && pip install -r requirements.txt')
    elseif vim.fn.filereadable(root .. '/pyproject.toml') == 1 then
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && pip install -e .')
    else
      vim.notify('No requirements.txt or pyproject.toml found', vim.log.levels.WARN)
    end
  end, { desc = 'Install Python Dependencies' })

vim.api.nvim_buf_create_user_command(0, 'PythonCreateVenv',
  function()
    local root = get_project_root()
    require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && python -m venv venv')
  end, { desc = 'Create Python Virtual Environment' })

-- Django-specific commands if manage.py exists
local root = get_project_root()
if vim.fn.filereadable(root .. '/manage.py') == 1 then
  vim.api.nvim_buf_create_user_command(0, 'DjangoRunServer',
    function()
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && python manage.py runserver')
    end, { desc = 'Start Django Development Server' })

  vim.api.nvim_buf_create_user_command(0, 'DjangoMigrate',
    function()
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && python manage.py migrate')
    end, { desc = 'Run Django Migrations' })

  vim.api.nvim_buf_create_user_command(0, 'DjangoMakeMigrations',
    function()
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && python manage.py makemigrations')
    end, { desc = 'Create Django Migrations' })
end
