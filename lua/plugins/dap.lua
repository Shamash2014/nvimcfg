return {
  -- DAP Core
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "theHamsta/nvim-dap-virtual-text",
      -- DAP View for better debugging experience
      "igorlfs/nvim-dap-view",
      "nvim-lua/plenary.nvim",
    },
    config = function()
      local dap = require("dap")

      -- Fix for Snacks ui_select compatibility with DAP
      -- DAP expects the item, but sometimes gets the index
      local original_ui_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        original_ui_select(items, opts, function(item, idx)
          -- If item is a number and items exists, get the actual item
          if type(item) == "number" and items and items[item] then
            on_choice(items[item], item)
          else
            on_choice(item, idx)
          end
        end)
      end

      -- Virtual text
      require("nvim-dap-virtual-text").setup({
        enabled = true,
        enabled_commands = false,
        highlight_changed_variables = true,
        highlight_new_as_changed = true,
        commented = false,
      })

      -- DAP View setup
      require("dap-view").setup({
        winbar = {
          show = true,
        },
      })

      -- JavaScript/TypeScript/Node Debug
      -- Install vscode-js-debug from: https://github.com/microsoft/vscode-js-debug
      -- Build and place in ~/.tools/vscode-js-debug/
      local js_debug_path = vim.fn.expand("~/.tools/vscode-js-debug")
      if vim.fn.isdirectory(js_debug_path) == 1 then
        -- Node adapter
        dap.adapters["pwa-node"] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "node",
            args = {
              js_debug_path .. "/js-debug/src/dapDebugServer.js",
              "${port}",
            },
          },
        }

        -- Chrome adapter
        dap.adapters["pwa-chrome"] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "node",
            args = {
              js_debug_path .. "/js-debug/src/dapDebugServer.js",
              "${port}",
            },
          },
        }

        -- Edge adapter
        dap.adapters["pwa-msedge"] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "node",
            args = {
              js_debug_path .. "/js-debug/src/dapDebugServer.js",
              "${port}",
            },
          },
        }
      end

      -- JavaScript/TypeScript configurations
      for _, language in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
        dap.configurations[language] = {
          -- Node.js configurations
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch file",
            program = "${file}",
            cwd = "${workspaceFolder}",
            sourceMaps = true,
          },
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch via NPM",
            runtimeExecutable = "npm",
            runtimeArgs = { "run", "start" },
            cwd = "${workspaceFolder}",
            sourceMaps = true,
            protocol = "inspector",
            console = "integratedTerminal",
          },
          {
            type = "pwa-node",
            request = "launch",
            name = "Debug Jest tests",
            runtimeExecutable = "node",
            runtimeArgs = {
              "./node_modules/.bin/jest",
              "--runInBand"
            },
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            internalConsoleOptions = "neverOpen",
          },
          {
            type = "pwa-node",
            request = "attach",
            name = "Attach to Node Process",
            processId = require("dap.utils").pick_process,
            cwd = "${workspaceFolder}",
            sourceMaps = true,
          },
          {
            type = "pwa-node",
            request = "attach",
            name = "Attach to Remote",
            address = "localhost",
            port = 9229,
            localRoot = "${workspaceFolder}",
            remoteRoot = "/app",
            sourceMaps = true,
          },
          -- Browser configurations
          {
            type = "pwa-chrome",
            request = "launch",
            name = "Launch Chrome against localhost",
            url = "http://localhost:3000",
            webRoot = "${workspaceFolder}",
            sourceMaps = true,
            userDataDir = false,
          },
          {
            type = "pwa-chrome",
            request = "launch",
            name = "Launch Chrome against localhost (incognito)",
            url = "http://localhost:3000",
            webRoot = "${workspaceFolder}",
            sourceMaps = true,
            userDataDir = false,
            runtimeArgs = { "--incognito" },
          },
          {
            type = "pwa-chrome",
            request = "attach",
            name = "Attach to Chrome",
            port = 9222,
            webRoot = "${workspaceFolder}",
            sourceMaps = true,
          },
          {
            type = "pwa-msedge",
            request = "launch",
            name = "Launch Edge against localhost",
            url = "http://localhost:3000",
            webRoot = "${workspaceFolder}",
            sourceMaps = true,
            userDataDir = false,
          },
          -- Next.js configurations
          {
            type = "pwa-node",
            request = "launch",
            name = "Next.js: debug server-side",
            runtimeExecutable = "node",
            runtimeArgs = { "--inspect" },
            program = "${workspaceFolder}/node_modules/.bin/next",
            args = { "dev" },
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            env = { NODE_OPTIONS = "--inspect" },
            sourceMaps = true,
          },
          {
            type = "pwa-chrome",
            request = "launch",
            name = "Next.js: debug client-side",
            url = "http://localhost:3000",
            webRoot = "${workspaceFolder}",
            sourceMaps = true,
          },
          -- Vite configurations
          {
            type = "pwa-chrome",
            request = "launch",
            name = "Vite: debug in Chrome",
            url = "http://localhost:5173",
            webRoot = "${workspaceFolder}",
            sourceMaps = true,
            sourceMapPathOverrides = {
              ["/@fs/*"] = "${workspaceFolder}/*",
            },
          },
        }
      end

      -- Dart/Flutter configuration
      dap.adapters.dart = {
        type = "executable",
        command = "flutter",
        args = { "debug_adapter" },
        options = {
          detached = false,
        },
      }

      -- Store selected Flutter device
      vim.g.flutter_device_id = nil

      -- Shared function to get Flutter devices using plenary
      local function get_flutter_devices(callback)
        local Job = require('plenary.job')

        Job:new({
          command = 'flutter',
          args = { 'devices', '--machine' },
          on_exit = function(j, return_val)
            if return_val ~= 0 then
              vim.schedule(function()
                vim.notify('Failed to enumerate devices', vim.log.levels.ERROR)
                callback(nil)
              end)
              return
            end

            local result = table.concat(j:result(), '\n')
            local ok, devices = pcall(vim.json.decode, result)

            if not ok or not devices or #devices == 0 then
              vim.schedule(function()
                vim.notify('No devices available', vim.log.levels.ERROR)
                callback(nil)
              end)
              return
            end

            vim.schedule(function()
              callback(devices)
            end)
          end,
        }):start()
      end

      -- Create Flutter device selection command
      vim.api.nvim_create_user_command('FlutterSelectDevice', function()
        get_flutter_devices(function(devices)
          if not devices then return end

          if #devices == 1 then
            vim.g.flutter_device_id = devices[1].id
            vim.notify('Selected device: ' .. devices[1].name, vim.log.levels.INFO)
            return
          end

          local items = {}
          for _, device in ipairs(devices) do
            local device_type = device.emulator and "[Emulator]" or "[Device]"
            local platform = device.targetPlatform or device.platformName or "unknown"
            local sdk = device.sdk and (" • SDK " .. device.sdk) or ""
            table.insert(items, {
              text = string.format('%s %s • %s • %s%s', device_type, device.name, platform, device.id, sdk),
              device = device,
            })
          end

          require('snacks').picker({
            title = 'Select Flutter Device',
            items = items,
            format = 'text',
            layout = { preset = 'vscode' },
            confirm = function(picker, item)
              picker:close()
              if item and item.device then
                vim.g.flutter_device_id = item.device.id
                vim.notify('Selected device: ' .. item.device.name, vim.log.levels.INFO)
              end
            end,
          })
        end)
      end, { desc = 'Select Flutter device for debugging' })

      dap.configurations.dart = {
        -- Primary configuration: Use pre-selected device
        {
          type = "dart",
          request = "launch",
          name = "Flutter",
          program = "${workspaceFolder}/lib/main.dart",
          cwd = "${workspaceFolder}",
          args = function()
            -- Check if device was pre-selected
            if vim.g.flutter_device_id then
              vim.notify("Using selected device: " .. vim.g.flutter_device_id, vim.log.levels.INFO)
              return { "-d", vim.g.flutter_device_id }
            end

            -- No device selected, show picker during DAP launch
            return coroutine.create(function(dap_run_co)
              get_flutter_devices(function(devices)
                if not devices then
                  coroutine.resume(dap_run_co, dap.ABORT)
                  return
                end

                -- Auto-select if single device
                if #devices == 1 then
                  vim.g.flutter_device_id = devices[1].id
                  vim.notify("Auto-selected device: " .. devices[1].name, vim.log.levels.INFO)
                  coroutine.resume(dap_run_co, { "-d", devices[1].id })
                else
                  -- Multiple devices, show Snacks picker
                  vim.schedule(function()
                    local items = {}
                    for _, device in ipairs(devices) do
                      local device_type = device.emulator and "[Emulator]" or "[Device]"
                      local platform = device.targetPlatform or device.platformName or "unknown"
                      local sdk = device.sdk and (" • SDK " .. device.sdk) or ""
                      table.insert(items, {
                        text = string.format('%s %s • %s • %s%s', device_type, device.name, platform, device.id, sdk),
                        device = device,
                      })
                    end

                    require('snacks').picker({
                      title = 'Select Flutter Device for Debug',
                      items = items,
                      format = 'text',
                      layout = { preset = 'vscode' },
                      confirm = function(picker, item)
                        picker:close()
                        if item and item.device then
                          vim.g.flutter_device_id = item.device.id
                          vim.notify('Selected device: ' .. item.device.name, vim.log.levels.INFO)
                          coroutine.resume(dap_run_co, { "-d", item.device.id })
                        else
                          vim.notify('No device selected', vim.log.levels.WARN)
                          coroutine.resume(dap_run_co, dap.ABORT)
                        end
                      end,
                      cancel = function()
                        vim.notify('Debug cancelled', vim.log.levels.WARN)
                        coroutine.resume(dap_run_co, dap.ABORT)
                      end,
                    })
                  end)
                end
              end)
            end)
          end,
        },
        {
          type = "dart",
          request = "attach",
          name = "Attach",
          cwd = "${workspaceFolder}",
        }
      }

      -- Go debugging with delve
      -- Requires:
      -- * You have initialized your module with 'go mod init module_name'
      -- * You :cd your project before running DAP
      -- Install delve: go install github.com/go-delve/delve/cmd/dlv@latest
      -- Or place binary in ~/.tools/delve/dlv
      local delve_cmd = vim.fn.executable(vim.fn.expand("~/.tools/delve/dlv")) == 1
        and vim.fn.expand("~/.tools/delve/dlv")
        or "dlv"

      dap.adapters.delve = {
        type = "server",
        port = "${port}",
        executable = {
          command = delve_cmd,
          args = { "dap", "-l", "127.0.0.1:${port}" },
        },
      }

      dap.configurations.go = {
        {
          type = "delve",
          name = "Debug current file",
          request = "launch",
          program = "${file}",
          cwd = "${workspaceFolder}",
        },
        {
          type = "delve",
          name = "Debug package",
          request = "launch",
          program = "./${relativeFileDirname}",
        },
        {
          type = "delve",
          name = "Debug test",
          request = "launch",
          mode = "test",
          program = "./${relativeFileDirname}",
        },
        {
          type = "delve",
          name = "Debug test (current file)",
          request = "launch",
          mode = "test",
          program = "${file}",
        },
        {
          type = "delve",
          name = "Attach to process",
          request = "attach",
          processId = require("dap.utils").pick_process,
        },
      }

      -- Kotlin debugging
      -- Install kotlin-debug-adapter from: https://github.com/fwcd/kotlin-debug-adapter
      -- Build and place in ~/.tools/kotlin-debug-adapter/
      dap.adapters.kotlin = {
        type = "executable",
        command = vim.fn.expand("~/.tools/kotlin-debug-adapter/bin/kotlin-debug-adapter"),
        options = { auto_continue_if_many_stopped = false }
      }

      dap.configurations.kotlin = {
        {
          type = "kotlin",
          request = "launch",
          name = "Launch kotlin program",
          mainClass = function()
            local root = vim.fs.find("src", { path = vim.uv.cwd(), upward = true, stop = vim.env.HOME })[1] or ""
            local fname = vim.api.nvim_buf_get_name(0)
            -- src/main/kotlin/websearch/Main.kt -> websearch.MainKt
            return fname:gsub(root, ""):gsub("main/kotlin/", ""):gsub(".kt", "Kt"):gsub("/", "."):sub(2, -1)
          end,
          projectRoot = "${workspaceFolder}",
          jsonLogFile = "",
          enableJsonLogging = false,
        },
        {
          type = "kotlin",
          request = "attach",
          name = "Attach to process",
          hostName = "localhost",
          port = 5005,
          timeout = 2000
        }
      }

      -- Python debugging
      -- Install debugpy with uv: uv tool install debugpy
      -- Or create venv in ~/.tools/debugpy/: cd ~/.tools/debugpy && uv venv && uv pip install debugpy
      dap.adapters.python = {
        type = "executable",
        command = function()
          -- Check for debugpy in ~/.tools first
          local tools_debugpy = vim.fn.expand("~/.tools/debugpy/venv/bin/python")
          if vim.fn.executable(tools_debugpy) == 1 then
            return tools_debugpy
          end
          -- Check for uv-managed virtual environment
          local cwd = vim.fn.getcwd()
          if vim.fn.executable(cwd .. "/.venv/bin/python") == 1 then
            return cwd .. "/.venv/bin/python"
          elseif vim.fn.executable(cwd .. "/venv/bin/python") == 1 then
            return cwd .. "/venv/bin/python"
          end
          -- Fallback to system python with uv
          return "python"
        end,
        args = { "-m", "debugpy.adapter" },
      }

      dap.configurations.python = {
        {
          type = "python",
          request = "launch",
          name = "Launch file",
          program = "${file}",
          pythonPath = function()
            -- Prefer uv-managed environments
            local cwd = vim.fn.getcwd()
            if vim.fn.executable(cwd .. "/.venv/bin/python") == 1 then
              return cwd .. "/.venv/bin/python"
            elseif vim.fn.executable(cwd .. "/venv/bin/python") == 1 then
              return cwd .. "/venv/bin/python"
            end
            -- Check for uv python
            if vim.fn.executable("uv") == 1 then
              local handle = io.popen("uv python find 2>/dev/null")
              if handle then
                local result = handle:read("*a")
                handle:close()
                if result and result ~= "" then
                  return vim.trim(result)
                end
              end
            end
            return "python"
          end,
        },
        {
          type = "python",
          request = "launch",
          name = "Launch with arguments",
          program = "${file}",
          args = function()
            local args = vim.fn.input("Arguments: ")
            return vim.split(args, " ")
          end,
          pythonPath = function()
            local cwd = vim.fn.getcwd()
            if vim.fn.executable(cwd .. "/.venv/bin/python") == 1 then
              return cwd .. "/.venv/bin/python"
            elseif vim.fn.executable(cwd .. "/venv/bin/python") == 1 then
              return cwd .. "/venv/bin/python"
            end
            return "python"
          end,
        },
        {
          type = "python",
          request = "launch",
          name = "Launch module",
          module = function()
            return vim.fn.input("Module name: ")
          end,
          pythonPath = function()
            local cwd = vim.fn.getcwd()
            if vim.fn.executable(cwd .. "/.venv/bin/python") == 1 then
              return cwd .. "/.venv/bin/python"
            elseif vim.fn.executable(cwd .. "/venv/bin/python") == 1 then
              return cwd .. "/venv/bin/python"
            end
            return "python"
          end,
        },
        {
          type = "python",
          request = "attach",
          name = "Attach to process",
          processId = require("dap.utils").pick_process,
        },
      }

      -- Signs (monochrome friendly)
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DapBreakpointCondition", linehl = "", numhl = "" })
      vim.fn.sign_define("DapLogPoint", { text = "▶", texthl = "DapLogPoint", linehl = "", numhl = "" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapStoppedLine", numhl = "" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "✕", texthl = "DapBreakpointRejected", linehl = "", numhl = "" })

      -- Highlights (monochrome with red for errors)
      vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#FF4444" })
      vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = "#CCCCCC" })
      vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#AAAAAA" })
      vim.api.nvim_set_hl(0, "DapStopped", { fg = "#FFFFFF" })
      vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = "#2A2A2A" })
      vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = "#666666" })
    end,
    keys = {
      -- Debugging controls
      { "<leader>dd", function() require("dap").continue() end, desc = "Debug: Continue" },
      { "<leader>do", function() require("dap").step_over() end, desc = "Debug: Step Over" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Debug: Step Into" },
      { "<leader>dO", function() require("dap").step_out() end, desc = "Debug: Step Out" },
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "Conditional Breakpoint" },
      { "<leader>dl", function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: ")) end, desc = "Log Point" },
      { "<leader>dr", function() require("dap").repl.open() end, desc = "Open REPL" },
      { "<leader>dR", function() require("dap").run_last() end, desc = "Run Last" },
      { "<leader>dx", function() require("dap").terminate() end, desc = "Terminate Debug" },

      -- DAP View control
      { "<leader>dv", function() require("dap-view").toggle() end, desc = "Toggle DAP View" },
      { "<leader>de", function() require("dap-view").eval() end, desc = "Evaluate Expression", mode = { "n", "v" } },

      -- Flutter DAP controls
      { "<localleader>ds", "<cmd>FlutterSelectDevice<cr>", desc = "Select Flutter Device", ft = "dart" },
      { "<localleader>hr", function()
        local dap = require("dap")
        if dap.session() then
          -- Send custom hot restart request to Flutter DAP
          dap.session():request("hotRestart", function(err, response)
            if err then
              vim.notify("Hot restart failed: " .. vim.inspect(err), vim.log.levels.ERROR)
            else
              vim.notify("Flutter hot restart complete", vim.log.levels.INFO)
            end
          end)
        else
          -- Send 'R' to existing Flutter process for hot restart
          local Job = require('plenary.job')
          Job:new({
            command = 'sh',
            args = { '-c', "echo 'R' | nc localhost 8181 2>/dev/null || pkill -USR2 -f 'flutter.*run'" },
            on_exit = function(j, return_val)
              vim.schedule(function()
                if return_val == 0 then
                  vim.notify("Flutter hot restart sent", vim.log.levels.INFO)
                else
                  vim.notify("No Flutter process found", vim.log.levels.WARN)
                end
              end)
            end,
          }):start()
        end
      end, desc = "Flutter Hot Restart", ft = "dart" },
      { "<localleader>hl", function()
        local dap = require("dap")
        if dap.session() then
          -- Send custom hot reload request to Flutter DAP
          dap.session():request("hotReload", function(err, response)
            if err then
              vim.notify("Hot reload failed: " .. vim.inspect(err), vim.log.levels.ERROR)
            else
              vim.notify("Flutter hot reload complete", vim.log.levels.INFO)
            end
          end)
        else
          -- Send 'r' to existing Flutter process for hot reload
          local Job = require('plenary.job')
          Job:new({
            command = 'sh',
            args = { '-c', "echo 'r' | nc localhost 8181 2>/dev/null || pkill -USR1 -f 'flutter.*run'" },
            on_exit = function(j, return_val)
              vim.schedule(function()
                if return_val == 0 then
                  vim.notify("Flutter hot reload sent", vim.log.levels.INFO)
                else
                  vim.notify("No Flutter process found", vim.log.levels.WARN)
                end
              end)
            end,
          }):start()
        end
      end, desc = "Flutter Hot Reload", ft = "dart" },

      -- Widgets
      { "<leader>dh", function() require("dap.ui.widgets").hover() end, desc = "Hover Variables" },
      { "<leader>dp", function() require("dap.ui.widgets").preview() end, desc = "Preview" },
      { "<leader>ds", function()
        local widgets = require("dap.ui.widgets")
        widgets.centered_float(widgets.scopes)
      end, desc = "Scopes" },
      { "<leader>dS", function()
        local widgets = require("dap.ui.widgets")
        widgets.centered_float(widgets.frames)
      end, desc = "Stack Frames" },
    },
  },
}
