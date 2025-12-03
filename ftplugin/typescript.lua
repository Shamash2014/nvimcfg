-- TypeScript LSP now configured centrally in lua/lsp.lua
-- Angular projects still get special handling here for ngserver

-- Check if this is an Angular project
local is_angular_project = vim.fn.filereadable(vim.fn.getcwd() .. "/angular.json") == 1

-- Start Angular Language Server for Angular projects (in addition to centralized vtsls)
if is_angular_project and vim.fn.executable("ngserver") == 1 and _G.lsp_config then
  local ng_probe_locations = { vim.fn.getcwd() .. "/node_modules/@angular/language-service" }

  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "angular",
    cmd = {
      "ngserver",
      "--stdio",
      "--tsProbeLocations",
      table.concat(ng_probe_locations, ","),
      "--ngProbeLocations",
      table.concat(ng_probe_locations, ","),
    },
    root_dir = vim.fs.root(0, { "angular.json", "project.json", ".git" }),
    filetypes = { "html", "typescript" }, -- Limit to HTML templates and TS files
    on_new_config = function(new_config, new_root_dir)
      new_config.cmd = {
        "ngserver",
        "--stdio",
        "--tsProbeLocations",
        new_root_dir .. "/node_modules",
        "--ngProbeLocations",
        new_root_dir .. "/node_modules",
      }
    end,
  }))
end

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'TSCompile',
  function()
    if vim.fn.executable("tsc") == 0 then
      vim.notify("TypeScript compiler not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal tsc')
  end, { desc = 'Compile TypeScript' })

vim.api.nvim_buf_create_user_command(0, 'TSWatch',
  function()
    if vim.fn.executable("tsc") == 0 then
      vim.notify("TypeScript compiler not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal tsc --watch')
  end, { desc = 'Watch and compile TypeScript' })

if is_angular_project then
  vim.api.nvim_buf_create_user_command(0, 'NgServe',
    function()
      if vim.fn.executable("ng") == 0 then
        vim.notify("Angular CLI not found", vim.log.levels.ERROR)
        return
      end
      vim.cmd('terminal ng serve')
    end, { desc = 'Serve Angular app' })

  vim.api.nvim_buf_create_user_command(0, 'NgBuild',
    function()
      if vim.fn.executable("ng") == 0 then
        vim.notify("Angular CLI not found", vim.log.levels.ERROR)
        return
      end
      vim.cmd('terminal ng build')
    end, { desc = 'Build Angular app' })

  vim.api.nvim_buf_create_user_command(0, 'NgTest',
    function()
      if vim.fn.executable("ng") == 0 then
        vim.notify("Angular CLI not found", vim.log.levels.ERROR)
        return
      end
      vim.cmd('terminal ng test')
    end, { desc = 'Run Angular tests' })
end

if vim.fn.executable("node") == 1 then
  local ok, dap = pcall(require, 'dap')
  if not ok then return end

  if not dap.adapters.node2 then
    dap.adapters.node2 = {
      type = 'executable',
      command = 'node',
      args = { vim.fn.stdpath('data') .. '/mason/packages/node-debug2-adapter/out/src/nodeDebug.js' },
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

  if not dap.configurations.typescript then
    local configs = {
      {
        type = 'node2',
        request = 'launch',
        name = 'Launch file',
        program = '${file}',
        cwd = vim.fn.getcwd(),
        sourceMaps = true,
        protocol = 'inspector',
        console = 'integratedTerminal',
      },
      {
        type = 'node2',
        request = 'attach',
        name = 'Attach',
        processId = require('dap.utils').pick_process,
        cwd = vim.fn.getcwd(),
      },
    }

    -- Add Docker configurations if Docker setup is detected
    if has_docker_compose() then
      table.insert(configs, {
        type = 'node2',
        request = 'launch',
        name = 'Debug in Docker (Compose)',
        program = '${file}',
        cwd = '/app',
        sourceMaps = true,
        protocol = 'inspector',
        console = 'integratedTerminal',
        env = {
          NODE_ENV = 'development',
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
        type = 'node2',
        request = 'attach',
        name = 'Attach to Docker Container',
        address = 'localhost',
        port = 9229,
        localRoot = '${workspaceFolder}',
        remoteRoot = '/app',
        sourceMaps = true,
        preLaunchTask = {
          type = "shell",
          command = "docker",
          args = { "compose", "exec", "-d", "app", "node", "--inspect=0.0.0.0:9229", "${file}" }
        }
      })
    elseif has_dockerfile() then
      table.insert(configs, {
        type = 'node2',
        request = 'launch',
        name = 'Debug in Docker',
        program = '${file}',
        cwd = '/app',
        sourceMaps = true,
        protocol = 'inspector',
        console = 'integratedTerminal',
        env = {
          NODE_ENV = 'development',
        },
        preLaunchTask = {
          type = "shell",
          command = "docker",
          args = { "build", "-t", "ts-debug", "." },
          presentation = {
            reveal = "always",
            panel = "new"
          }
        }
      })
    end

    dap.configurations.typescript = configs
  end
end

local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("eslint") == 1 then
  lint.linters_by_ft.typescript = { "eslint" }
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.typescript = { "prettier" }
end

-- Contextual commands for command palette
local function get_project_root()
  return require('tasks').get_project_root() or vim.fn.getcwd()
end

vim.api.nvim_buf_create_user_command(0, 'TypeScriptRunTests',
  function()
    local root = get_project_root()
    require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && npm test')
  end, { desc = 'Run TypeScript Tests' })

vim.api.nvim_buf_create_user_command(0, 'TypeScriptBuild',
  function()
    local root = get_project_root()
    require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && npm run build')
  end, { desc = 'Build TypeScript Project' })

vim.api.nvim_buf_create_user_command(0, 'TypeScriptTypeCheck',
  function()
    local root = get_project_root()
    require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && npx tsc --noEmit')
  end, { desc = 'Run TypeScript Type Check' })

vim.api.nvim_buf_create_user_command(0, 'TypeScriptLint',
  function()
    local root = get_project_root()
    require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && npm run lint')
  end, { desc = 'Lint TypeScript Project' })

vim.api.nvim_buf_create_user_command(0, 'TypeScriptDev',
  function()
    local root = get_project_root()
    require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && npm run dev')
  end, { desc = 'Start Development Server' })

-- Angular-specific commands if it's an Angular project
if is_angular_project then
  vim.api.nvim_buf_create_user_command(0, 'AngularServe',
    function()
      local root = get_project_root()
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && ng serve')
    end, { desc = 'Start Angular Development Server' })

  vim.api.nvim_buf_create_user_command(0, 'AngularBuild',
    function()
      local root = get_project_root()
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && ng build')
    end, { desc = 'Build Angular Project' })

  vim.api.nvim_buf_create_user_command(0, 'AngularTest',
    function()
      local root = get_project_root()
      require('tasks').run_command('cd ' .. vim.fn.shellescape(root) .. ' && ng test')
    end, { desc = 'Run Angular Tests' })
end
