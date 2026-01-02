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
      approvals = "ask",      -- "ask" = prompt when requested, "never" = auto-approve, "always" = always prompt
      show_tool_calls = true  -- show tool execution in buffer
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
      "<leader>ao",
      function() require("ai_repl").open() end,
      mode = { "n", "v", "i" },
      desc = "Open AI REPL"
    },
    {
      "<leader>aq",
      function() require("ai_repl").close() end,
      mode = { "n", "v", "i" },
      desc = "Close AI REPL"
    },
    {
      "<leader>aa",
      function() require("ai_repl").add_file_or_selection_to_context() end,
      mode = { "n", "v" },
      desc = "Add file/selection to AI REPL context"
    },
    {
      "<leader>af",
      function() require("ai_repl").add_current_file_to_context() end,
      mode = { "n" },
      desc = "Add current file to AI REPL context"
    },
    {
      "<leader>as",
      function() require("ai_repl").send_selection() end,
      mode = { "v" },
      desc = "Send selection to AI"
    },
    {
      "<leader>ap",
      function() require("ai_repl").open_session_picker() end,
      mode = { "n", "v", "i" },
      desc = "Open AI REPL session picker"
    }
  },
  cmd = { "AIRepl", "AIReplOpen", "AIReplClose", "AIReplSessions", "AIReplNew", "AIReplAddFile", "AIReplAddSelection", "AIReplPicker" }
}