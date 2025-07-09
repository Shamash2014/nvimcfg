return {
  -- DAP (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    event = "VeryLazy",
    dependencies = {
      "miroshQa/debugmaster.nvim",
    },
    keys = {
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
      { "<leader>do", function() require("dap").step_over() end, desc = "Step Over" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
      { "<leader>dr", function() require("dap").repl.open() end, desc = "Open REPL" },
      { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
      { "<leader>du", function() require("dap").step_out() end, desc = "Step Out" },
      { "<leader>dm", function() 
        local ok, debugmaster = pcall(require, "debugmaster")
        if ok then
          debugmaster.toggle()
        else
          vim.notify("Debugmaster not available", vim.log.levels.WARN)
        end
      end, desc = "Toggle Debugmaster UI" },
    },
    config = function()
      local dap = require("dap")
      
      -- Ensure dap is properly loaded
      if not dap then
        vim.notify("DAP not loaded", vim.log.levels.ERROR)
        return
      end

      -- Initialize adapters table if it doesn't exist
      if not dap.adapters then
        dap.adapters = {}
      end

      -- Initialize configurations table if it doesn't exist
      if not dap.configurations then
        dap.configurations = {}
      end

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

      -- TypeScript/JavaScript
      dap.adapters.node2 = {
        type = "executable",
        command = "node",
        args = { vim.fn.stdpath("data") .. "/mason/packages/node-debug2-adapter/out/src/nodeDebug.js" },
      }

      dap.configurations.typescript = {
        {
          name = "Launch",
          type = "node2",
          request = "launch",
          program = "${file}",
          cwd = vim.fn.getcwd(),
          sourceMaps = true,
          protocol = "inspector",
          console = "integratedTerminal",
        },
      }

      dap.configurations.javascript = dap.configurations.typescript

      -- Dart/Flutter
      dap.adapters.dart = {
        type = "executable",
        command = "dart",
        args = { "debug_adapter" },
      }

      dap.configurations.dart = {
        {
          type = "dart",
          request = "launch",
          name = "Launch dart",
          dartSdkPath = vim.fn.expand("~/flutter/bin/cache/dart-sdk/"),
          flutterSdkPath = vim.fn.expand("~/flutter/"),
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
        },
      }

      -- Configure debugmaster
      local ok, debugmaster = pcall(require, "debugmaster")
      if ok then
        -- debugmaster doesn't have a setup() function, it uses direct module configuration
        -- Basic keymaps are set up in the keys section above
        vim.notify("Debugmaster loaded successfully", vim.log.levels.INFO)
      else
        vim.notify("Debugmaster not available", vim.log.levels.WARN)
      end

      -- Enhanced DAP signs
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapCurrentLine" })
    end,
  },
}