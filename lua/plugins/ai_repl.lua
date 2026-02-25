return {
  name = "ai_repl",
  dir = vim.fn.stdpath("config") .. "/lua/ai_repl",
  cmd = { "AIReplChat", "AIReplChatPicker", "AIReplAddAnnotation", "AIReplSyncAnnotations" },
  ft = "chat",
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
      permission_mode = "default",
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
}
