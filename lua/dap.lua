return {
  {
    "stevearc/overseer.nvim",
    config = function()
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
      "stevearc/overseer.nvim",
      "miroshQa/debugmaster.nvim",
    },
    keys = {
      { "<leader>d", function() require("debugmaster").mode.toggle() end, desc = "Toggle Debug Mode", nowait = true },
    },
    config = function()
      local dap = require("dap")

      -- Properly initialize DAP listeners table structure per nvim-dap docs
      if not dap.listeners then
        dap.listeners = {
          before = {},
          after = {}
        }
      end
      if not dap.listeners.before then
        dap.listeners.before = {}
      end
      if not dap.listeners.after then
        dap.listeners.after = {}
      end

      -- Configure debug adapters
      dap.adapters.dart = {
        type = "executable",
        command = "dart",
        args = { "debug_adapter" },
      }

      dap.adapters.python = {
        type = "executable",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      }

      -- Configure debug configurations
      dap.configurations.dart = {
        {
          type = "dart",
          request = "launch",
          name = "Launch Dart",
          program = "${file}",
          cwd = "${workspaceFolder}",
        },
        {
          type = "dart",
          request = "launch",
          name = "Launch Flutter",
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
          toolArgs = { "--debug" },
        },
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

      -- Set up signs
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapCurrentLine" })
    end,
  },
}

