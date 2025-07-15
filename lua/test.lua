return {
  -- Neotest for running tests
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-python",
      "nvim-neotest/neotest-jest",
      "rouge8/neotest-rust",
      "lawrence-laz/neotest-zig",
      "rcasia/neotest-java",
      {
        "sidlatau/neotest-dart",
        dependencies = "nvim-lua/plenary.nvim",
      },
    },
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-python")({
            dap = { justMyCode = false },
            runner = "pytest",
            python = ".venv/bin/python",
          }),
          require("neotest-jest")({
            jestCommand = "npm test --",
            jestConfigFile = "custom.jest.config.ts",
            env = { CI = true },
            cwd = function(path)
              return vim.fn.getcwd()
            end,
          }),
          require("neotest-rust")({
            args = { "--no-capture" },
          }),
          require("neotest-zig"),
          require("neotest-java")({
            ignore_wrapper = false,
          }),
          require("neotest-dart")({
            command = "flutter",
            use_lsp = true,
          }),
        },
        discovery = {
          enabled = false,
          concurrent = 1,
        },
        running = {
          concurrent = true,
        },
        summary = {
          enabled = true,
          animated = true,
          follow = true,
          expand_errors = true,
        },
        output = {
          enabled = true,
          open_on_run = "short",
        },
        output_panel = {
          enabled = true,
          open = "botright split | resize 15",
        },
        quickfix = {
          enabled = false,
          open = false,
        },
        status = {
          enabled = true,
          signs = true,
          virtual_text = false,
        },
        strategies = {
          integrated = {
            height = 40,
            width = 120,
          },
        },
        icons = {
          child_indent = "│",
          child_prefix = "├",
          collapsed = "─",
          expanded = "╮",
          failed = "✖",
          final_child_indent = " ",
          final_child_prefix = "╰",
          non_collapsible = "─",
          passed = "✓",
          running = "↻",
          running_animated = { "/", "|", "\\", "-", "/", "|", "\\", "-" },
          skipped = "○",
          unknown = "?",
        },
        highlights = {
          adapter_name = "NeotestAdapterName",
          border = "NeotestBorder",
          dir = "NeotestDir",
          expand_marker = "NeotestExpandMarker",
          failed = "NeotestFailed",
          file = "NeotestFile",
          focused = "NeotestFocused",
          indent = "NeotestIndent",
          marked = "NeotestMarked",
          namespace = "NeotestNamespace",
          passed = "NeotestPassed",
          running = "NeotestRunning",
          select_win = "NeotestWinSelect",
          skipped = "NeotestSkipped",
          target = "NeotestTarget",
          test = "NeotestTest",
          unknown = "NeotestUnknown",
        },
      })
    end,
    keys = {
      { "<leader>otr", function() require("neotest").run.run() end, desc = "Run Nearest Test" },
      { "<leader>otf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run File Tests" },
      { "<leader>ota", function() require("neotest").run.run(vim.fn.getcwd()) end, desc = "Run All Tests" },
      { "<leader>ots", function() require("neotest").summary.toggle() end, desc = "Toggle Test Summary" },
      { "<leader>oto", function() require("neotest").output.open({ enter = true, auto_close = true }) end, desc = "Show Test Output" },
      { "<leader>otO", function() require("neotest").output_panel.toggle() end, desc = "Toggle Output Panel" },
      { "<leader>otS", function() require("neotest").run.stop() end, desc = "Stop Tests" },
      { "<leader>otw", function() require("neotest").watch.toggle(vim.fn.expand("%")) end, desc = "Watch File" },
      { "<leader>otl", function() require("neotest").run.run_last() end, desc = "Run Last Test" },
      { "<leader>otd", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug Nearest Test" },
      { "]t", function() require("neotest").jump.next({ status = "failed" }) end, desc = "Next Failed Test" },
      { "[t", function() require("neotest").jump.prev({ status = "failed" }) end, desc = "Previous Failed Test" },
    },
  },
}