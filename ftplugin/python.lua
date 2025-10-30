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

  if not dap.configurations.python then
    dap.configurations.python = {
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
    }
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
