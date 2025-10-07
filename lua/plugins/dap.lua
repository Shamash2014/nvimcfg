return {
  "mfussenegger/nvim-dap",
  lazy = true,
  dependencies = {
    "igorlfs/nvim-dap-view",
    "nvim-neotest/nvim-nio",
    "theHamsta/nvim-dap-virtual-text",
  },
  keys = {
    { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
    { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, desc = "Conditional Breakpoint" },
    { "<leader>dL", function() require("dap").set_breakpoint(nil, nil, vim.fn.input('Log message: ')) end, desc = "Log Point" },
    { "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
    { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
    { "<leader>do", function() require("dap").step_over() end, desc = "Step Over" },
    { "<leader>dO", function() require("dap").step_out() end, desc = "Step Out" },
    { "<leader>dj", function() require("dap").down() end, desc = "Down Stack Frame" },
    { "<leader>dk", function() require("dap").up() end, desc = "Up Stack Frame" },
    { "<leader>dR", function() require("dap").run_to_cursor() end, desc = "Run to Cursor" },
    { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Toggle REPL" },
    { "<leader>du", function() require("dap-view").toggle() end, desc = "Toggle UI" },
    { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
    { "<leader>dp", function() require("dap").pause() end, desc = "Pause" },
    { "<leader>dC", function() require("dap").clear_breakpoints() end, desc = "Clear All Breakpoints" },
    { "<leader>de", function() require("dap.ui.widgets").hover() end, desc = "Eval Under Cursor", mode = { "n", "v" } },
    { "<leader>dE", function()
      require("dap.ui.widgets").centered_float(require("dap.ui.widgets").expression)
    end, desc = "Expression" },
    { "<leader>dw", function()
      require("dap.ui.widgets").centered_float(require("dap.ui.widgets").scopes)
    end, desc = "Scopes" },
    { "<leader>dl", function()
      local files = vim.fn.glob(".vscode/launch.json", false, true)
      vim.list_extend(files, vim.fn.glob("**/launch.json", false, true))

      if #files == 0 then
        vim.notify("No launch.json files found", vim.log.levels.WARN)
        return
      end

      if #files == 1 then
        require("dap.ext.vscode").load_launchjs(files[1])
        vim.notify("Loaded " .. files[1], vim.log.levels.INFO)
      else
        vim.ui.select(files, {
          prompt = "Select launch.json:",
        }, function(choice)
          if choice then
            require("dap.ext.vscode").load_launchjs(choice)
            vim.notify("Loaded " .. choice, vim.log.levels.INFO)
          end
        end)
      end
    end, desc = "Load launch.json" },
    { "<leader>ds", function()
      local dap = require("dap")
      local sessions = dap.sessions()
      if #sessions == 0 then
        vim.notify("No active debug sessions", vim.log.levels.WARN)
        return
      end

      local session_names = {}
      for i, session in ipairs(sessions) do
        local name = session.config and session.config.name or "Session " .. i
        table.insert(session_names, name)
      end

      vim.ui.select(session_names, {
        prompt = "Switch to session:",
      }, function(choice, idx)
        if idx then
          dap.set_session(sessions[idx])
          vim.notify("Switched to: " .. choice, vim.log.levels.INFO)
        end
      end)
    end, desc = "Switch Session" },
    { "<leader>dd", function()
      local dap = require("dap")
      local ft = vim.bo.filetype
      local configs = dap.configurations[ft]

      if not configs or #configs == 0 then
        vim.notify("No debug configurations for " .. ft, vim.log.levels.WARN)
        return
      end

      if #configs == 1 then
        dap.run(configs[1])
        return
      end

      local names = {}
      for _, config in ipairs(configs) do
        table.insert(names, config.name)
      end

      vim.ui.select(names, {
        prompt = "Select debug configuration:",
      }, function(choice, idx)
        if idx then
          dap.run(configs[idx])
        end
      end)
    end, desc = "Debug (Select Config)" },
  },
  config = function()
    local dap = require("dap")

    require("nvim-dap-virtual-text").setup({
      enabled = true,
      enabled_commands = true,
      highlight_changed_variables = true,
      highlight_new_as_changed = false,
      show_stop_reason = true,
      commented = false,
      only_first_definition = true,
      all_references = false,
      filter_references_pattern = '<module',
      virt_text_pos = 'eol',
      all_frames = false,
      virt_lines = false,
      virt_text_win_col = nil
    })

    require("dap-view").setup({
      auto_toggle = true,
    })

    vim.defer_fn(function()
      local ok_overseer, overseer = pcall(require, "overseer")
      if ok_overseer then
        overseer.patch_dap(true)
        overseer.enable_dap()
      end
    end, 100)

    vim.fn.sign_define('DapBreakpoint', { text='●', texthl='DiagnosticError', linehl='', numhl='DiagnosticError' })
    vim.fn.sign_define('DapBreakpointCondition', { text='◆', texthl='DiagnosticInfo', linehl='', numhl='DiagnosticInfo' })
    vim.fn.sign_define('DapBreakpointRejected', { text='○', texthl='DiagnosticHint', linehl='', numhl='DiagnosticHint' })
    vim.fn.sign_define('DapLogPoint', { text='◉', texthl='DiagnosticInfo', linehl='', numhl='DiagnosticInfo' })
    vim.fn.sign_define('DapStopped', { text='→', texthl='DiagnosticWarn', linehl='CursorLine', numhl='DiagnosticWarn' })

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "dap-repl",
      callback = function()
        require("dap.ext.autocompl").attach()
      end,
    })

    -- Debug Adapters
    dap.adapters["pwa-node"] = {
      type = "server",
      host = "localhost",
      port = "${port}",
      executable = {
        command = "node",
        args = {
          vim.fn.expand("~/.tools/vscode-js-debug/js-debug/src/dapDebugServer.js"),
          "${port}"
        },
      }
    }

    dap.adapters["pwa-chrome"] = {
      type = "server",
      host = "localhost",
      port = "${port}",
      executable = {
        command = "node",
        args = {
          vim.fn.expand("~/.tools/vscode-js-debug/js-debug/src/dapDebugServer.js"),
          "${port}"
        },
      }
    }

    dap.adapters.delve = {
      type = "server",
      port = "${port}",
      executable = {
        command = "dlv",
        args = { "dap", "-l", "127.0.0.1:${port}" },
      }
    }

    dap.adapters.python = {
      type = "executable",
      command = "uvx",
      args = { "debugpy-adapter" },
    }

    -- Default Configurations
    dap.configurations.javascript = {
      {
        type = "pwa-node",
        request = "launch",
        name = "Launch File (Node)",
        program = "${file}",
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        protocol = "inspector",
        console = "integratedTerminal",
      },
      {
        type = "pwa-node",
        request = "attach",
        name = "Attach to Port 9229",
        port = 9229,
        address = "localhost",
        localRoot = "${workspaceFolder}",
        remoteRoot = "${workspaceFolder}",
        skipFiles = { "<node_internals>/**" },
        sourceMaps = true,
        protocol = "inspector",
      },
      {
        type = "pwa-node",
        request = "attach",
        name = "Attach to Process",
        processId = require("dap.utils").pick_process,
        skipFiles = { "<node_internals>/**" },
        sourceMaps = true,
        protocol = "inspector",
      },
    }

    dap.configurations.typescript = {
      {
        type = "pwa-node",
        request = "launch",
        name = "Launch TS File (ts-node)",
        runtimeExecutable = "ts-node",
        runtimeArgs = { "--transpile-only" },
        args = { "${file}" },
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        protocol = "inspector",
        console = "integratedTerminal",
        skipFiles = { "<node_internals>/**", "node_modules/**" },
        resolveSourceMapLocations = {
          "${workspaceFolder}/**",
          "!**/node_modules/**",
        },
      },
      {
        type = "pwa-node",
        request = "launch",
        name = "Launch TS File (tsx)",
        runtimeExecutable = "tsx",
        runtimeArgs = { "${file}" },
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        protocol = "inspector",
        console = "integratedTerminal",
        skipFiles = { "<node_internals>/**", "node_modules/**" },
        resolveSourceMapLocations = {
          "${workspaceFolder}/**",
          "!**/node_modules/**",
        },
      },
      {
        type = "pwa-node",
        request = "launch",
        name = "Debug Jest Tests",
        runtimeExecutable = "${workspaceFolder}/node_modules/.bin/jest",
        runtimeArgs = { "--runInBand", "--no-coverage", "--watchAll=false" },
        rootPath = "${workspaceFolder}",
        cwd = "${workspaceFolder}",
        console = "integratedTerminal",
        sourceMaps = true,
        skipFiles = { "<node_internals>/**", "node_modules/**" },
      },
      {
        type = "pwa-node",
        request = "launch",
        name = "Debug Vitest Tests",
        runtimeExecutable = "${workspaceFolder}/node_modules/.bin/vitest",
        runtimeArgs = { "run", "${file}" },
        cwd = "${workspaceFolder}",
        console = "integratedTerminal",
        sourceMaps = true,
        skipFiles = { "<node_internals>/**", "node_modules/**" },
      },
      {
        type = "pwa-node",
        request = "attach",
        name = "Attach to Port 9229",
        port = 9229,
        address = "localhost",
        localRoot = "${workspaceFolder}",
        remoteRoot = "${workspaceFolder}",
        skipFiles = { "<node_internals>/**", "node_modules/**" },
        sourceMaps = true,
        protocol = "inspector",
        resolveSourceMapLocations = {
          "${workspaceFolder}/**",
          "!**/node_modules/**",
        },
      },
    }

    dap.configurations.javascriptreact = vim.list_extend(
      vim.deepcopy(dap.configurations.javascript),
      {
        {
          type = "pwa-chrome",
          request = "launch",
          name = "Debug Ionic (Chrome)",
          url = "http://localhost:8100",
          webRoot = "${workspaceFolder}",
          sourceMaps = true,
          sourceMapPathOverrides = {
            ["webpack://./*"] = "${webRoot}/*",
            ["webpack:///src/*"] = "${webRoot}/src/*",
            ["webpack:///*"] = "*",
          },
        },
        {
          type = "pwa-chrome",
          request = "attach",
          name = "Attach to Capacitor (Chrome DevTools)",
          port = 9222,
          webRoot = "${workspaceFolder}",
          sourceMaps = true,
        },
      }
    )

    dap.configurations.typescriptreact = vim.list_extend(
      vim.deepcopy(dap.configurations.typescript),
      {
        {
          type = "pwa-chrome",
          request = "launch",
          name = "Debug Ionic (Chrome)",
          url = "http://localhost:8100",
          webRoot = "${workspaceFolder}",
          sourceMaps = true,
          sourceMapPathOverrides = {
            ["webpack://./*"] = "${webRoot}/*",
            ["webpack:///src/*"] = "${webRoot}/src/*",
            ["webpack:///*"] = "*",
          },
        },
        {
          type = "pwa-chrome",
          request = "attach",
          name = "Attach to Capacitor (Chrome DevTools)",
          port = 9222,
          webRoot = "${workspaceFolder}",
          sourceMaps = true,
        },
      }
    )

    dap.configurations.go = {
      {
        type = "delve",
        name = "Debug",
        request = "launch",
        program = "${file}"
      },
      {
        type = "delve",
        name = "Debug test",
        request = "launch",
        mode = "test",
        program = "${file}"
      },
      {
        type = "delve",
        name = "Debug test (go.mod)",
        request = "launch",
        mode = "test",
        program = "./${relativeFileDirname}"
      }
    }

    dap.configurations.python = {
      {
        type = "python",
        request = "launch",
        name = "Launch file",
        program = "${file}",
        pythonPath = function()
          local venv = vim.fn.getenv("VIRTUAL_ENV")
          if venv ~= vim.NIL and venv ~= "" then
            return venv .. "/bin/python"
          end
          return "python3"
        end,
      },
    }

    -- Load VSCode launch.json configurations (with error handling for JSON comments)
    pcall(function()
      require("dap.ext.vscode").load_launchjs(nil, {
        ["pwa-node"] = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
        ["pwa-chrome"] = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
        ["node"] = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
        ["delve"] = { "go" },
        ["python"] = { "python" },
      })
    end)
  end,
}
