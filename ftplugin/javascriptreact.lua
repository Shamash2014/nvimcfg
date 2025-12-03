-- React/JSX LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'ReactStart',
  function()
    if vim.fn.executable("npm") == 1 then
      vim.cmd('terminal npm start')
    elseif vim.fn.executable("yarn") == 1 then
      vim.cmd('terminal yarn start')
    else
      vim.notify("No package manager found (npm or yarn)", vim.log.levels.ERROR)
    end
  end, { desc = 'Start React development server' })

vim.api.nvim_buf_create_user_command(0, 'ReactBuild',
  function()
    if vim.fn.executable("npm") == 1 then
      vim.cmd('terminal npm run build')
    elseif vim.fn.executable("yarn") == 1 then
      vim.cmd('terminal yarn build')
    else
      vim.notify("No package manager found (npm or yarn)", vim.log.levels.ERROR)
    end
  end, { desc = 'Build React app' })

vim.api.nvim_buf_create_user_command(0, 'ReactTest',
  function()
    if vim.fn.executable("npm") == 1 then
      vim.cmd('terminal npm test')
    elseif vim.fn.executable("yarn") == 1 then
      vim.cmd('terminal yarn test')
    else
      vim.notify("No package manager found (npm or yarn)", vim.log.levels.ERROR)
    end
  end, { desc = 'Run React tests' })

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

  if not dap.configurations.javascriptreact then
    dap.configurations.javascriptreact = {
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
  end
end

local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("eslint") == 1 then
  lint.linters_by_ft.javascriptreact = { "eslint" }
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.javascriptreact = { "prettier" }
end
