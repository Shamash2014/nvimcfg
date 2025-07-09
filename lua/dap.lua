return {
  -- DAP (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    event = "VeryLazy",
    dependencies = {
      "miroshQa/debugmaster.nvim",
      { "stevearc/overseer.nvim" },
    },
    keys = {
      { "<leader>db", desc = "Toggle Breakpoint" },
      { "<leader>dc", desc = "Continue" },
      { "<leader>do", desc = "Step Over" },
      { "<leader>di", desc = "Step Into" },
      { "<leader>dr", desc = "Open REPL" },
      { "<leader>dt", desc = "Terminate" },
      { "<leader>du", desc = "Step Out" },
      { "<leader>dF", desc = "Debug Flutter App" },
      { "<leader>dP", desc = "Debug Flutter Profile" },
      { "<leader>dm", desc = "Toggle Debugmaster UI" },
    },
    config = function()
      local dap = require("dap")

      -- Ensure DAP is fully loaded before configuration
      if not dap.adapters then
        dap.adapters = {}
      end

      if not dap.configurations then
        dap.configurations = {}
      end


      if not dap.listeners then
        dap.listeners = {}
      end



      -- Flutter/Dart Debug Adapter
      dap.adapters.dart = {
        type = "executable",
        command = "dart",
        args = { "debug_adapter" },
      }

      -- Flutter Debug Adapter
      dap.adapters.flutter = {
        type = "executable",
        command = "flutter",
        args = { "debug_adapter" },
      }

      -- Dart configurations
      dap.configurations.dart = {
        {
          type = "dart",
          request = "launch",
          name = "Launch Dart",
          dartSdkPath = vim.fn.expand("~/flutter/bin/cache/dart-sdk/"),
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
        },
        {
          type = "flutter",
          request = "launch",
          name = "Launch Flutter",
          dartSdkPath = vim.fn.expand("~/flutter/bin/cache/dart-sdk/"),
          flutterSdkPath = vim.fn.expand("~/flutter/"),
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
          args = { "--debug" },
        },
        {
          type = "flutter",
          request = "launch",
          name = "Launch Flutter (Profile)",
          dartSdkPath = vim.fn.expand("~/flutter/bin/cache/dart-sdk/"),
          flutterSdkPath = vim.fn.expand("~/flutter/"),
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
          args = { "--profile" },
        },
      }

      -- Python
      dap.adapters.python = {
        type = "executable",
        command = "python",
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

      -- Set up keybindings after DAP is loaded
      vim.keymap.set("n", "<leader>db", function() dap.toggle_breakpoint() end, { desc = "Toggle Breakpoint" })
      vim.keymap.set("n", "<leader>dc", function() dap.continue() end, { desc = "Continue" })
      vim.keymap.set("n", "<leader>do", function() dap.step_over() end, { desc = "Step Over" })
      vim.keymap.set("n", "<leader>di", function() dap.step_into() end, { desc = "Step Into" })
      vim.keymap.set("n", "<leader>dr", function() dap.repl.open() end, { desc = "Open REPL" })
      vim.keymap.set("n", "<leader>dt", function() dap.terminate() end, { desc = "Terminate" })
      vim.keymap.set("n", "<leader>du", function() dap.step_out() end, { desc = "Step Out" })

      -- Flutter/Dart specific debug keybindings
      vim.keymap.set("n", "<leader>dF", function()
        dap.run(dap.configurations.dart[2]) -- Launch Flutter
      end, { desc = "Debug Flutter App" })

      vim.keymap.set("n", "<leader>dP", function()
        dap.run(dap.configurations.dart[3]) -- Launch Flutter Profile
      end, { desc = "Debug Flutter Profile" })

      -- Debugmaster integration
      vim.keymap.set("n", "<leader>dm", function()
        local ok, debugmaster = pcall(require, "debugmaster")
        if ok then
          debugmaster.toggle()
        else
          vim.notify("Debugmaster not available", vim.log.levels.WARN)
        end
      end, { desc = "Toggle Debugmaster UI" })

      -- Enhanced DAP signs
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapCurrentLine" })

      -- Configure overseer since it's a dependency
      local overseer = require("overseer")
      overseer.setup({
        task_list = {
          direction = "bottom",
          min_height = 10,
          max_height = 20,
          default_detail = 1,
        },
        dap = false, -- Disable DAP integration during setup
        strategy = "terminal",
      })

      -- Enable DAP integration after overseer is configured
      -- overseer.enable_dap()

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

      -- Set up overseer keybindings
      vim.keymap.set("n", "<leader>rr", "<cmd>OverseerRun<cr>", { desc = "Run Task" })
      vim.keymap.set("n", "<leader>rt", "<cmd>OverseerToggle<cr>", { desc = "Toggle Overseer" })
      vim.keymap.set("n", "<leader>rb", "<cmd>OverseerBuild<cr>", { desc = "Build Task" })
      vim.keymap.set("n", "<leader>rq", "<cmd>OverseerQuickAction<cr>", { desc = "Quick Action" })
      vim.keymap.set("n", "<leader>ra", "<cmd>OverseerTaskAction<cr>", { desc = "Task Action" })
    end,
  },
}

