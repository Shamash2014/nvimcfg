-- Dart LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'DartAnalyze',
  function()
    vim.cmd('terminal dart analyze')
  end, { desc = 'Run Dart analyzer' })

vim.api.nvim_buf_create_user_command(0, 'DartFormat',
  function()
    vim.cmd('terminal dart format .')
  end, { desc = 'Format Dart code' })

vim.api.nvim_buf_create_user_command(0, 'DartTest',
  function()
    vim.cmd('terminal dart test')
  end, { desc = 'Run Dart tests' })

vim.api.nvim_buf_create_user_command(0, 'DartRun',
  function()
    local file = vim.fn.expand('%')
    vim.cmd('terminal dart run ' .. file)
  end, { desc = 'Run current Dart file' })

vim.api.nvim_buf_create_user_command(0, 'DartPubGet',
  function()
    vim.cmd('terminal dart pub get')
  end, { desc = 'Get Dart dependencies' })

vim.api.nvim_buf_create_user_command(0, 'DartPubUpgrade',
  function()
    vim.cmd('terminal dart pub upgrade')
  end, { desc = 'Upgrade Dart dependencies' })

-- Flutter-specific commands if pubspec.yaml contains flutter
local pubspec_path = vim.fs.root(0, {'pubspec.yaml'})
if pubspec_path then
  local pubspec_file = pubspec_path .. '/pubspec.yaml'
  if vim.fn.filereadable(pubspec_file) == 1 then
    local content = vim.fn.readfile(pubspec_file)
    local is_flutter = false
    for _, line in ipairs(content) do
      if line:match('flutter:') then
        is_flutter = true
        break
      end
    end

    if is_flutter then
      vim.api.nvim_buf_create_user_command(0, 'FlutterRun',
        function()
          if vim.fn.executable("flutter") == 0 then
            vim.notify("Flutter executable not found", vim.log.levels.ERROR)
            return
          end
          vim.cmd('terminal flutter run')
        end, { desc = 'Run Flutter app' })

      vim.api.nvim_buf_create_user_command(0, 'FlutterBuild',
        function()
          if vim.fn.executable("flutter") == 0 then
            vim.notify("Flutter executable not found", vim.log.levels.ERROR)
            return
          end
          vim.cmd('terminal flutter build')
        end, { desc = 'Build Flutter app' })

      vim.api.nvim_buf_create_user_command(0, 'FlutterClean',
        function()
          if vim.fn.executable("flutter") == 0 then
            vim.notify("Flutter executable not found", vim.log.levels.ERROR)
            return
          end
          vim.cmd('terminal flutter clean')
        end, { desc = 'Clean Flutter build files' })

      vim.api.nvim_buf_create_user_command(0, 'FlutterDoctor',
        function()
          if vim.fn.executable("flutter") == 0 then
            vim.notify("Flutter executable not found", vim.log.levels.ERROR)
            return
          end
          vim.cmd('terminal flutter doctor')
        end, { desc = 'Run Flutter doctor' })

      vim.api.nvim_buf_create_user_command(0, 'FlutterDevices',
        function()
          if vim.fn.executable("flutter") == 0 then
            vim.notify("Flutter executable not found", vim.log.levels.ERROR)
            return
          end
          vim.cmd('terminal flutter devices')
        end, { desc = 'List Flutter devices' })
    end
  end
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

