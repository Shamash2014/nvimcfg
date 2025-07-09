return {
  -- DAP (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    dependencies = {
      "miroshQa/debugmaster.nvim",
      "stevearc/overseer.nvim",
    },
    config = function()
      local dap = require("dap")
      
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
      
      -- DAP UI integration with overseer
      dap.listeners.after.event_initialized["overseer"] = function()
        local overseer = require("overseer")
        vim.notify("DAP session started", vim.log.levels.INFO)
        overseer.open()
      end
      
      dap.listeners.before.event_terminated["overseer"] = function()
        local overseer = require("overseer")
        vim.notify("DAP session terminated", vim.log.levels.INFO)
        overseer.close()
      end
    end,
  },
}