-- JavaScript LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'NodeRun',
  function()
    if vim.fn.executable("node") == 0 then
      vim.notify("Node.js executable not found", vim.log.levels.ERROR)
      return
    end
    local file = vim.fn.expand('%')
    vim.cmd('terminal node ' .. file)
  end, { desc = 'Run current JS file with Node.js' })

vim.api.nvim_buf_create_user_command(0, 'NpmTest',
  function()
    if vim.fn.executable("npm") == 0 then
      vim.notify("npm executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal npm test')
  end, { desc = 'Run npm tests' })

vim.api.nvim_buf_create_user_command(0, 'NpmStart',
  function()
    if vim.fn.executable("npm") == 0 then
      vim.notify("npm executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal npm start')
  end, { desc = 'Start npm development server' })

vim.api.nvim_buf_create_user_command(0, 'NpmBuild',
  function()
    if vim.fn.executable("npm") == 0 then
      vim.notify("npm executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal npm run build')
  end, { desc = 'Build npm project' })

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

  if not dap.configurations.javascript then
    dap.configurations.javascript = {
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
  lint.linters_by_ft.javascript = { "eslint" }
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.javascript = { "prettier" }
end
