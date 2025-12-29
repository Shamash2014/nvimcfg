return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    preset = "helix",
    delay = 300,
    win = {
      border = "single",
      padding = { 1, 2 },
    },
    layout = {
      height = { min = 4, max = 25 },
      width = { min = 20, max = 50 },
      spacing = 3,
      align = "center",
    },
    icons = {
      breadcrumb = "»",
      separator = "➜",
      group = "+",
    },
    spec = {
      { "<leader>c", group = "code" },
      { "<leader>f", group = "file/find" },
      { "<leader>g", group = "git" },
      { "<leader>gk", group = "stack" },
      { "<leader>o", group = "options/config" },
      { "<leader>p", group = "project" },
      { "<leader>r", group = "run/tasks" },
      { "<leader>t", group = "tabs" },
      { "<leader>w", group = "windows" },
      { "<leader>b", group = "buffers" },
      { "<leader>d", group = "debug/diagnostics" },
      { "<leader>s", group = "search" },
      { "[", group = "prev" },
      { "]", group = "next" },
      { "g", group = "goto" },
    },
  },
  keys = {
    {
      "<leader>?",
      function()
        require("which-key").show({ global = false })
      end,
      desc = "Buffer Keymaps",
    },
  },
}