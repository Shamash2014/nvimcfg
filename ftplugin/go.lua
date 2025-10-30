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

  if not dap.configurations.go then
    dap.configurations.go = {
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
