return {
  name = "ai_repl",
  dir = vim.fn.stdpath("config") .. "/lua/ai_repl",
  config = function()
    require("ai_repl").setup({
      default_provider = "claude",
      providers = {
        claude = { name = "Claude", cmd = "claude-code-acp", args = {}, env = {} },
        goose = { name = "Goose", cmd = "goose", args = {"acp"}, env = {} },
        opencode = { name = "OpenCode", cmd = "opencode", args = {"acp"}, env = {} },
        codex = { name = "Codex", cmd = "codex-acp", args = {}, env = {} },
        droid = { name = "Droid", cmd = "droid", args = {"exec", "--output-format", "acp"}, env = {} },
      },
      history_size = 1000,
      permission_mode = "plan",
      show_tool_calls = true,
      annotations = {
        enabled = true,
        session_dir = vim.fn.stdpath("data") .. "/annotations",
        capture_mode = "snippet",
        auto_open_panel = true,
        keys = {
          start_session = "<leader>as",
          stop_session = "<leader>aq",
          annotate = "<leader>aa",
          toggle_window = "<leader>aw",
          send_to_ai = "<leader>af",
        },
      }
    })
  end,
  keys = {
    {
      "<leader>ac",
      function() require("ai_repl").open_chat_buffer() end,
      mode = "n",
      desc = "Open .chat buffer"
    },
    {
      "<leader>ai",
      function() require("ai_repl").send_selection() end,
      mode = { "v" },
      desc = "Send selection to AI"
    },
    {
      "<leader>av",
      function() require("ai_repl").add_selection_to_prompt() end,
      mode = { "v" },
      desc = "Add selection to .chat buffer"
    },
    {
      "<leader>ae",
      function() require("ai_repl").explain_selection() end,
      mode = { "v" },
      desc = "Explain selection"
    },
    {
      "<leader>ac",
      function() require("ai_repl").check_selection() end,
      mode = { "v" },
      desc = "Check selection for issues"
    },
    {
      "<leader>af",
      function() require("ai_repl.annotations").send_annotation_to_ai() end,
      mode = "n",
      desc = "Send annotation to AI"
    }
  },
  cmd = { "AIReplChat", "AIReplAddAnnotation", "AIReplSyncAnnotations" }
}
