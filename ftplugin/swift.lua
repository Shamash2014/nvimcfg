if vim.fn.executable("sourcekit-lsp") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "sourcekit",
    cmd = { "sourcekit-lsp" },
    root_dir = vim.fs.root(0, { "Package.swift", ".git" }),
    settings = {},
  }))
end

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
