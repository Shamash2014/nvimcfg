if vim.fn.executable("dart") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "dart_analysis_server",
    cmd = { "dart", "language-server", "--protocol=lsp" },
    root_dir = vim.fs.root(0, { "pubspec.yaml", ".git" }),
    settings = {
      dart = {
        analysisExcludedFolders = {
          vim.fn.expand("$HOME") .. "/.pub-cache",
          ".dart_tool",
          "build"
        },
        enableSnippets = true,
        updateImportsOnRename = true,
        completeFunctionCalls = true,
      },
    },
  }))
end

if vim.fn.executable("dart") == 1 then
  local ok, dap = pcall(require, 'dap')
  if not ok then return end

  if not dap.adapters.dart then
    dap.adapters.dart = {
      type = 'executable',
      command = 'dart',
      args = { '--enable-vm-service', '--pause_isolates_on_start' },
    }
  end

  if not dap.configurations.dart then
    dap.configurations.dart = {
      {
        type = 'dart',
        request = 'launch',
        name = 'Launch Dart',
        program = '${file}',
        cwd = '${workspaceFolder}',
        args = {},
      },
      {
        type = 'dart',
        request = 'launch',
        name = 'Launch Dart with arguments',
        program = '${file}',
        cwd = '${workspaceFolder}',
        args = function()
          local arg_string = vim.fn.input('Arguments: ')
          return vim.split(arg_string, " +")
        end,
      },
    }
  end
end

