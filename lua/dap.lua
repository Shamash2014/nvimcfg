return {
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
