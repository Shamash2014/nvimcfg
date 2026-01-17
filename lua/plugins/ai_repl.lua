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
      default_provider = "claude",
      providers = {
        claude = { name = "Claude", cmd = "claude-code-acp", args = {}, env = {} },
        cursor = { name = "Cursor", cmd = "cursor-agent-acp", args = {}, env = {} },
        goose = { name = "Goose", cmd = "goose", args = {"acp"}, env = {} },
        opencode = { name = "OpenCode", cmd = "opencode", args = {"acp"}, env = {} },
        codex = { name = "Codex", cmd = "codex-acp", args = {}, env = {} },
      },
      history_size = 1000,
      permission_mode = "plan",
      show_tool_calls = true
    })
  end,
  keys = {
    {
      "<leader>ar",
      function() require("ai_repl").toggle() end,
      mode = "n",
      desc = "Toggle AI REPL"
    },
    {
      "<leader>aa",
      function() require("ai_repl").new_session() end,
      mode = "n",
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
    },
    {
      "<leader>aq",
      function() require("ai_repl").quick_action() end,
      mode = { "v" },
      desc = "Quick AI action on selection"
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
    }
  },
  cmd = { "AIRepl", "AIReplOpen", "AIReplClose", "AIReplSessions", "AIReplNew", "AIReplAddFile", "AIReplAddSelection", "AIReplPicker" }
}
