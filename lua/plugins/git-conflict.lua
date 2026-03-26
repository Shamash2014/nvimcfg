return {
  "akinsho/git-conflict.nvim",
  version = "*",
  event = "BufReadPre",
  keys = {
    { "<leader>gx", group = "Conflict" },
    { "<leader>gxo", "<Plug>(git-conflict-ours)", desc = "Choose ours" },
    { "<leader>gxt", "<Plug>(git-conflict-theirs)", desc = "Choose theirs" },
    { "<leader>gxb", "<Plug>(git-conflict-both)", desc = "Choose both" },
    { "<leader>gxn", "<Plug>(git-conflict-none)", desc = "Choose none" },
    { "<leader>gxl", "<cmd>GitConflictListQf<cr>", desc = "List conflicts" },
    { "]x", "<Plug>(git-conflict-next-conflict)", desc = "Next conflict" },
    { "[x", "<Plug>(git-conflict-prev-conflict)", desc = "Prev conflict" },
  },
  opts = {
    default_mappings = false,
  },
}
