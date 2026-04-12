return {
  "f-person/git-blame.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>gb", "<cmd>GitBlameToggle<cr>", desc = "Toggle blame" },
    { "<leader>go", "<cmd>GitBlameOpenCommitURL<cr>", desc = "Open commit URL" },
    { "<leader>bY", "<cmd>GitBlameCopySHA<cr>", desc = "Copy SHA (blame)" },
  },
  opts = {
    enabled = false,
    date_format = "%Y-%m-%d",
    message_when_not_committed = "Not committed yet",
    virtual_text_column = 80,
  },
}
