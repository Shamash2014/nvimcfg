return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    bigfile = { enabled = true },
    quickfile = { enabled = true },
    words = { enabled = true },
    terminal = { enabled = true },
    input = {
      enabled = true,
    },
    picker = {
      enabled = true,
      ui_select = true,
      previewers = {
        enabled = false,
      },
      layout = {
        preview = false,
        preset = "default",
      },
      sources = {
        select = {
          layout = {
            preset = "vscode"
          }
        }
      },
      win = {
        input = {
          keys = {
            ["<C-j>"] = { "list_down", mode = { "i", "n" } },
            ["<C-k>"] = { "list_up", mode = { "i", "n" } },
          },
        },
      },
    },
  },
  keys = {
    { "<leader><leader>", function()
        local root = require('core.utils').get_project_root() or vim.fn.getcwd()
        Snacks.picker.smart({ layout = { preset = "vscode" }, cwd = root })
      end, desc = "Smart Find" },
    { "<leader>ff", function()
        local root = require('core.utils').get_project_root() or vim.fn.getcwd()
        Snacks.picker.files({ layout = { preset = "vscode" }, cwd = root })
      end, desc = "Find Files" },
    { "<leader>fr", function() Snacks.picker.recent({ layout = { preset = "vscode" } }) end, desc = "Recent Files" },
    { "<leader>bb", function() require("core.tasks").pick_buffers_tabs_tasks() end, desc = "Buffers/Tabs/Tasks" },
    { "<leader>bd", function() Snacks.bufdelete() end, desc = "Delete Buffer" },
    { "<leader>bD", function() Snacks.bufdelete.delete({ force = true }) end, desc = "Force Delete Buffer" },
    { "<leader>pp", function() Snacks.picker.projects({ layout = { preset = "vscode" } }) end, desc = "Select Projects" },
    { "<leader>si", function() Snacks.picker.lsp_symbols({ layout = { preset = "vscode" } }) end, desc = "LSP Symbols" },
    { "<leader>sg", function()
        local root = require('core.utils').get_project_root() or vim.fn.getcwd()
        Snacks.picker.grep({ layout = { preset = "vscode" }, cwd = root })
      end, desc = "Live Grep" },
    { "<leader>sw", function() Snacks.picker.grep_word({ layout = { preset = "vscode" } }) end, desc = "Grep Word" },
    { "<leader>sW", function() Snacks.picker.lsp_workspace_symbols({ layout = { preset = "vscode" } }) end, desc = "LSP Workspace Symbols" },
    { "<leader>ss", function() Snacks.picker.lines({ layout = { preset = "vscode" } }) end, desc = "Search Lines" },
    { "<leader>sr", function() Snacks.picker.resume({ layout = { preset = "vscode" } }) end, desc = "Resume Picker" },
    { "<leader>hh", function() Snacks.picker.help({ layout = { preset = "vscode" } }) end, desc = "Help Tags" },
    { "<leader>oc", function() require("core.tasks").pick_tasks_and_commands() end, desc = "Run Command" },
    { "<leader>oq", function() Snacks.picker.qflist({ layout = { preset = "vscode" } }) end, desc = "Quickfix List" },
    { "<leader>ol", function() Snacks.picker.loclist({ layout = { preset = "vscode" } }) end, desc = "Location List" },
    { "<leader>om", function() Snacks.picker.marks({ layout = { preset = "vscode" } }) end, desc = "Marks" },
    { "<leader>cd", function() Snacks.picker.diagnostics({ layout = { preset = "vscode" } }) end, desc = "Diagnostics" },
    { "<leader>ot", function() Snacks.terminal() end, desc = "Open Terminal" },
  },
}