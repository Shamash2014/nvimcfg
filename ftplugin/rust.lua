-- Rust LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'CargoTest',
  function()
    if vim.fn.executable("cargo") == 0 then
      vim.notify("Cargo executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal cargo test')
  end, { desc = 'Run Cargo tests' })

vim.api.nvim_buf_create_user_command(0, 'CargoBuild',
  function()
    if vim.fn.executable("cargo") == 0 then
      vim.notify("Cargo executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal cargo build')
  end, { desc = 'Build Rust project' })

vim.api.nvim_buf_create_user_command(0, 'CargoRun',
  function()
    if vim.fn.executable("cargo") == 0 then
      vim.notify("Cargo executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal cargo run')
  end, { desc = 'Run Rust project' })

vim.api.nvim_buf_create_user_command(0, 'CargoCheck',
  function()
    if vim.fn.executable("cargo") == 0 then
      vim.notify("Cargo executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal cargo check')
  end, { desc = 'Check Rust project' })

vim.api.nvim_buf_create_user_command(0, 'CargoClippy',
  function()
    if vim.fn.executable("cargo") == 0 then
      vim.notify("Cargo executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal cargo clippy')
  end, { desc = 'Run Clippy linter' })

vim.api.nvim_buf_create_user_command(0, 'CargoFmt',
  function()
    if vim.fn.executable("cargo") == 0 then
      vim.notify("Cargo executable not found", vim.log.levels.ERROR)
      return
    end
    vim.cmd('terminal cargo fmt')
  end, { desc = 'Format Rust code' })

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

  if not dap.configurations.rust then
    dap.configurations.rust = {
      {
        name = 'Launch',
        type = 'lldb',
        request = 'launch',
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        args = {},
      },
    }
  end
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("rustfmt") == 1 then
  conform.formatters_by_ft.rust = { "rustfmt" }
end
