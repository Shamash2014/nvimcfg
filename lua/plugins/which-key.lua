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
      { "<leader>a", group = "ai" },
      { "<leader>n", group = "android" },
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
    {
      "<leader>ar",
      function()
        require("ai_repl").toggle()
      end,
      mode = { "n", "v" },
      desc = "Toggle AI REPL",
    },
    {
      "<leader>ap",
      function()
        require("ai_repl").open_session_picker()
      end,
      desc = "Session Picker",
    },
    {
      "<leader>ab",
      function()
        require("ai_repl.chat_sessions").toggle()
      end,
      desc = "Chat Sessions Picker",
    },
    {
      "<leader>aa",
      function()
        require("ai_repl.annotations").annotate()
      end,
      mode = "v",
      desc = "Add Annotation",
    },
    {
      "<leader>as",
      function()
        require("ai_repl.annotations").start_session()
      end,
      desc = "Start Annotation Session",
    },
    {
      "<leader>aq",
      function()
        require("ai_repl.annotations").stop_session()
      end,
      desc = "Stop Annotation Session",
    },
    {
      "<leader>aw",
      function()
        require("ai_repl.annotations").toggle_window()
      end,
      desc = "Toggle Annotation Window",
    },
    {
      "<leader>af",
      function()
        require("ai_repl.annotations").send_annotation_to_ai()
      end,
      desc = "Send Annotations to AI",
    },
  },
}