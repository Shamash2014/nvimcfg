return {
  {
    "stevearc/overseer.nvim",
    event = "VeryLazy",
    config = function()
      local overseer = require("overseer")

      overseer.setup({
        task_list = {
          direction = "bottom",
          min_height = 10,
          max_height = 20,
          default_detail = 1,
        },
        dap = false,
        strategy = "terminal",
      })

      -- Register overseer task templates
      -- Flutter/Dart task templates
      overseer.register_template({
        name = "flutter run",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "run", "--debug" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter build",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "build", "apk", "--debug" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter test",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "test" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter pub get",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "pub", "get" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("pubspec.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "flutter clean",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "clean" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      -- Docker Compose task templates
      overseer.register_template({
        name = "docker-compose up",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "up", "-d" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose down",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "down" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose stop",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "stop" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose exec",
        builder = function()
          local service = vim.fn.input("Service name: ")
          local command = vim.fn.input("Command: ", "/bin/bash")
          return {
            cmd = { "docker-compose" },
            args = { "exec", service, command },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose run --rm",
        builder = function()
          local service = vim.fn.input("Service name: ")
          local command = vim.fn.input("Command: ", "/bin/bash")
          return {
            cmd = { "docker-compose" },
            args = { "run", "--rm", service, command },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "aider --watch-files",
        builder = function()
          return {
            cmd = { "aider" },
            args = { "--watch-files" },
            components = { "default" },
          }
        end,
      })

      overseer.register_template({
        name = "docker-compose up -d --build",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "build", "--no-cache" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      -- iOS CocoaPods task templates
      overseer.register_template({
        name = "pod install",
        builder = function()
          return {
            cmd = { "pod" },
            args = { "install" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("Podfile") == 1 or vim.fn.filereadable("ios/Podfile") == 1
          end,
        },
      })

      overseer.register_template({
        name = "pod update",
        builder = function()
          return {
            cmd = { "pod" },
            args = { "update" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("Podfile") == 1 or vim.fn.filereadable("ios/Podfile") == 1
          end,
        },
      })

      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "*",
        callback = function()
          vim.keymap.set("t", "jk", "<C-\\><C-n>", { buffer = true, desc = "Exit terminal mode" })
        end,
      })
    end,
    keys = {
      { "<leader>rr", "<cmd>OverseerRun<cr>",         desc = "Run Task" },
      { "<leader>rt", "<cmd>OverseerToggle<cr>",      desc = "Toggle Overseer" },
      { "<leader>rb", "<cmd>OverseerBuild<cr>",       desc = "Build Task" },
      { "<leader>rq", "<cmd>OverseerQuickAction<cr>", desc = "Quick Action" },
      { "<leader>ra", "<cmd>OverseerTaskAction<cr>",  desc = "Task Action" },
    },
  },

  -- DAP (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "theHamsta/nvim-dap-virtual-text",
      "nvim-neotest/nvim-nio",
      {
        "miroshQa/debugmaster.nvim",
        config = function()
          local dm = require("debugmaster")
          dm.plugins.osv_integration.enabled = true
        end,
      },
    },
    keys = {
      { "dm",         function() require("debugmaster").mode.toggle() end,                                         desc = "Toggle Debug Mode", nowait = true },
      { "<leader>dd", "<cmd>DapContinue<cr>",                                                                      desc = "Start Debug" },
      { "<leader>do", "<cmd>DapStepOver<cr>",                                                                      desc = "Step Over" },
      { "<leader>di", "<cmd>DapStepInto<cr>",                                                                      desc = "Step Into" },
      { "<leader>du", "<cmd>DapStepOut<cr>",                                                                       desc = "Step Out" },
      { "<leader>db", "<cmd>DapToggleBreakpoint<cr>",                                                              desc = "Toggle Breakpoint" },
      { "<leader>dB", function() require("dap").set_breakpoint() end,                                              desc = "Set Breakpoint" },
      { "<leader>dl", function() require("dap").set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end, desc = "Log Point" },
      { "<leader>dr", "<cmd>DapToggleRepl<cr>",                                                                    desc = "Open REPL" },
      { "<leader>dL", function() require("dap").run_last() end,                                                    desc = "Run Last" },
    },
    config = function()
      local dap = require("dap")

      -- Ensure adapters and configurations tables exist
      dap.adapters = dap.adapters or {}
      dap.configurations = dap.configurations or {}

      -- DAP Python configuration
      dap.adapters.python = {
        type = "executable",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      }

      dap.configurations.python = {
        {
          type = "python",
          request = "launch",
          name = "Launch file",
          program = "${file}",
          pythonPath = function()
            return "/usr/bin/python3"
          end,
        },
      }

      -- DAP Dart configuration
      dap.configurations.dart = {
        {
          type = "dart",
          request = "launch",
          name = "Launch Dart",
          dartSdkPath = function()
            local flutter_root = vim.env.FLUTTER_ROOT
            if flutter_root then
              return flutter_root .. "/bin/cache/dart-sdk"
            end
            return "dart"
          end,
          program = "${file}",
          cwd = "${workspaceFolder}",
        },
        {
          type = "dart",
          request = "launch",
          name = "Launch Flutter",
          flutterSdkPath = function()
            local flutter_root = vim.env.FLUTTER_ROOT
            if flutter_root then
              return flutter_root
            end
            local fvm_local = vim.fn.getcwd() .. "/.fvm/flutter_sdk"
            if vim.fn.isdirectory(fvm_local) == 1 then
              return fvm_local
            end
            return "flutter"
          end,
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
        }
      }
      -- Configure signs with proper symbols
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◐", texthl = "DapBreakpointCondition" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DapBreakpointRejected" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapStoppedLine" })

      -- Setup virtual text
      require("nvim-dap-virtual-text").setup({
        enabled = true,
        enabled_commands = true,
        highlight_changed_variables = true,
        highlight_new_as_changed = false,
        show_stop_reason = true,
        commented = false,
        only_first_definition = true,
        all_references = false,
        clear_on_continue = false,
        display_callback = function(variable, buf, stackframe, node, options)
          if options.virt_text_pos == 'inline' then
            return ' = ' .. variable.value
          else
            return variable.name .. ' = ' .. variable.value
          end
        end,
        virt_text_pos = vim.fn.has 'nvim-0.10' == 1 and 'inline' or 'eol',
        all_frames = false,
        virt_lines = false,
        virt_text_win_col = nil
      })
    end,
  },
}
