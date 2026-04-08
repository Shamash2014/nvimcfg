return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "igorlfs/nvim-dap-view",
      "mxsdev/nvim-dap-vscode-js",
    },
    keys = {
      { "<leader>dc", function() require("dap").continue() end,          desc = "Continue" },
      { "<leader>ds", function() require("dap").step_over() end,         desc = "Step Over" },
      { "<leader>di", function() require("dap").step_into() end,         desc = "Step Into" },
      { "<leader>do", function() require("dap").step_out() end,          desc = "Step Out" },
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dB", function()
          require("dap").set_breakpoint(vim.fn.input("Condition: "))
        end, desc = "Conditional Breakpoint" },
      { "<leader>dl", function() require("dap").run_last() end,          desc = "Run Last" },
      { "<leader>dt", function() require("dap").terminate() end,         desc = "Terminate" },
      { "<leader>dr", function() require("dap").repl.toggle() end,       desc = "REPL" },
      { "<leader>dv", "<cmd>DapViewToggle<cr>",                          desc = "Toggle DAP View" },
    },
    config = function()
      local dap = require("dap")

      local function flutter_pick_device(cb)
        local Job = require("plenary.job")
        Job:new({
          command = "flutter",
          args = { "devices", "--machine" },
          on_exit = function(j, code)
            if code ~= 0 then
              vim.schedule(function() cb(nil) end)
              return
            end
            local raw = table.concat(j:result(), "")
            local ok, devices = pcall(vim.json.decode, raw)
            if not ok or #devices == 0 then
              vim.schedule(function() cb(nil) end)
              return
            end
            vim.schedule(function()
              vim.ui.select(devices, {
                prompt = "Select device:",
                format_item = function(d) return d.name .. " (" .. d.id .. ")" end,
              }, function(choice)
                cb(choice and choice.id or nil)
              end)
            end)
          end,
        }):start()
      end

      dap.adapters.flutter = {
        type = "executable",
        command = "flutter",
        args = { "debug_adapter" },
      }

      dap.adapters.dart = {
        type = "executable",
        command = "dart",
        args = { "debug_adapter" },
      }

      dap.configurations.dart = {
        {
          type = "flutter",
          request = "launch",
          name = "Launch Flutter",
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
        },
        {
          type = "flutter",
          request = "launch",
          name = "Launch Flutter (pick device)",
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
          toolArgs = function()
            local co = coroutine.running()
            flutter_pick_device(function(device_id)
              if device_id then
                coroutine.resume(co, { "-d", device_id })
              else
                coroutine.resume(co, {})
              end
            end)
            return coroutine.yield()
          end,
        },
        {
          type = "flutter",
          request = "attach",
          name = "Attach to Flutter",
          cwd = "${workspaceFolder}",
          debugExternalPackageLibraries = true,
          evaluateGettersInDebugViews = true,
        },
        {
          type = "dart",
          request = "launch",
          name = "Run Dart",
          program = "${file}",
          cwd = "${workspaceFolder}",
        },
        {
          type = "flutter",
          request = "launch",
          name = "Flutter Test (current file)",
          program = "${file}",
          cwd = "${workspaceFolder}",
          noDebug = false,
        },
      }

      require("dap-vscode-js").setup({
        debugger_path = vim.fn.stdpath("data") .. "/lazy/vscode-js-debug",
        adapters = { "pwa-node", "pwa-chrome", "pwa-msedge", "node-terminal", "pwa-extensionHost" },
      })
      for _, lang in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact", "astro" }) do
        dap.configurations[lang] = {
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch React Native (Metro)",
            cwd = "${workspaceFolder}",
            runtimeExecutable = "node",
            runtimeArgs = { "--inspect-brk", "${workspaceFolder}/node_modules/.bin/react-native", "start" },
            port = 9229,
            skipFiles = { "<node_internals>/**" },
          },
          {
            type = "pwa-node",
            request = "attach",
            name = "Attach to Metro",
            port = 9229,
            cwd = "${workspaceFolder}",
            skipFiles = { "<node_internals>/**" },
          },
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch with Bun",
            runtimeExecutable = "bun",
            program = "${file}",
            cwd = "${workspaceFolder}",
            skipFiles = { "<node_internals>/**" },
          },
          {
            type = "pwa-node",
            request = "launch",
            name = "Bun test (current file)",
            runtimeExecutable = "bun",
            runtimeArgs = { "test" },
            program = "${file}",
            cwd = "${workspaceFolder}",
            skipFiles = { "<node_internals>/**" },
          },
        }
      end

      local type_to_ft = {
        flutter            = { "dart" },
        ["pwa-node"]       = { "javascript", "typescript", "javascriptreact", "typescriptreact", "astro" },
        ["pwa-chrome"]     = { "javascript", "typescript", "javascriptreact", "typescriptreact", "astro" },
        ["node-terminal"]  = { "javascript", "typescript" },
      }

      local function load_launch_json()
        local path = vim.fn.getcwd() .. "/.vscode/launch.json"
        if vim.fn.filereadable(path) == 1 then
          require("dap.ext.vscode").load_launchjs(path, type_to_ft)
        end
      end

      load_launch_json()

      vim.api.nvim_create_autocmd("DirChanged", {
        callback = load_launch_json,
      })

      local dv = require("dap-view")
      dap.listeners.before.attach["dap-view-config"] = function() dv.open() end
      dap.listeners.before.launch["dap-view-config"] = function() dv.open() end
      dap.listeners.before.event_terminated["dap-view-config"] = function() dv.close() end
      dap.listeners.before.event_exited["dap-view-config"] = function() dv.close() end
    end,
  },
  {
    "igorlfs/nvim-dap-view",
    lazy = true,
    opts = {},
  },
  {
    "mxsdev/nvim-dap-vscode-js",
    lazy = true,
    dependencies = {
      {
        "microsoft/vscode-js-debug",
        build = "npm install --legacy-peer-deps && npx gulp vsDebugServerBundle && mv dist out",
      },
    },
  },
  {
    "leoluz/nvim-dap-go",
    lazy = true,
    ft = "go",
    opts = {},
  },
  {
    "mfussenegger/nvim-dap-python",
    lazy = true,
    ft = "python",
    config = function()
      require("dap-python").setup("python3")
    end,
  },
}
