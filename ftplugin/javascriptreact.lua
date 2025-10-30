if vim.fn.executable("vtsls") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "vtsls",
    cmd = { "vtsls", "--stdio" },
    root_dir = vim.fs.root(0, { "package.json", "tsconfig.json", "jsconfig.json", ".git" }),
  }))
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
