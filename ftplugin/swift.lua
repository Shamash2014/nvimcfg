-- Swift LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'SwiftBuild',
  function()
    vim.cmd('terminal swift build')
  end, { desc = 'Build Swift package' })

vim.api.nvim_buf_create_user_command(0, 'SwiftTest',
  function()
    vim.cmd('terminal swift test')
  end, { desc = 'Run Swift tests' })

vim.api.nvim_buf_create_user_command(0, 'SwiftRun',
  function()
    vim.cmd('terminal swift run')
  end, { desc = 'Run Swift package' })

vim.api.nvim_buf_create_user_command(0, 'SwiftFormat',
  function()
    vim.cmd('terminal swift-format --in-place %')
  end, { desc = 'Format Swift file' })

vim.api.nvim_buf_create_user_command(0, 'SwiftClean',
  function()
    vim.cmd('terminal swift package clean')
  end, { desc = 'Clean Swift build artifacts' })

vim.api.nvim_buf_create_user_command(0, 'SwiftResolve',
  function()
    vim.cmd('terminal swift package resolve')
  end, { desc = 'Resolve Swift package dependencies' })

if vim.fn.executable("lldb-vscode") == 1 or vim.fn.executable("codelldb") == 1 then
  local ok, dap = pcall(require, 'dap')
  if not ok then return end

  if not dap.adapters.lldb then
    dap.adapters.lldb = {
      type = 'executable',
      command = vim.fn.executable("codelldb") == 1 and 'codelldb' or 'lldb-vscode',
      name = 'lldb',
    }
  end

  if not dap.configurations.swift then
    dap.configurations.swift = {
      {
        name = 'Launch',
        type = 'lldb',
        request = 'launch',
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/.build/debug/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        args = {},
      },
    }
  end
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("swift-format") == 1 then
  conform.formatters_by_ft.swift = { "swift-format" }
end
