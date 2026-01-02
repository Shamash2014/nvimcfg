return {
  name = "ai_repl",
  dir = vim.fn.stdpath("config") .. "/lua/ai_repl",
  config = function()
    require("ai_repl").setup({
      window = {
        width = 0.3,
        border = "rounded",
        title = "AI REPL"
      },
      provider = {
        cmd = "claude-code-acp",
        args = {},
        env = {}
      },
      history_size = 1000,
      permission_mode = "default",  -- "default" | "acceptEdits" | "plan" | "dontAsk" | "bypassPermissions"
      show_tool_calls = true
    })
  end,
  keys = {
    {
      "<leader>ar",
      function() require("ai_repl").toggle() end,
      mode = { "n", "v", "i" },
      desc = "Toggle AI REPL"
    },
    {
      "<leader>aa",
      function() require("ai_repl").new_session() end,
      mode = { "n", "v", "i" },
      desc = "New AI REPL session"
    },
    {
      "<leader>as",
      function() require("ai_repl").send_selection() end,
      mode = { "v" },
      desc = "Send selection to AI"
    },
    {
      "<leader>av",
      function() require("ai_repl").add_selection_to_prompt() end,
      mode = { "v" },
      desc = "Add selection to AI REPL prompt"
    },
    {
      "<leader>ap",
      function() require("ai_repl").pick_process() end,
      mode = { "n" },
      desc = "Pick AI process/session"
    },
    {
      "<leader>ab",
      function() require("ai_repl").switch_to_buffer() end,
      mode = { "n" },
      desc = "Switch AI session buffer"
    },
    {
      "<leader>ak",
      function() require("ai_repl").kill_current_session() end,
      mode = { "n" },
      desc = "Kill current AI session"
    }
  },
  cmd = { "AIRepl", "AIReplOpen", "AIReplClose", "AIReplSessions", "AIReplNew", "AIReplAddFile", "AIReplAddSelection", "AIReplPicker" }
}