return {
  "pwntester/octo.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  cmd = "Octo",
  keys = {
    { "<leader>gO", "", desc = "+Octo" },
    { "<leader>gOl", "<cmd>Octo pr list<cr>", desc = "List PRs" },
    { "<leader>gOs", "<cmd>Octo pr search<cr>", desc = "Search PRs" },
    { "<leader>gOi", "<cmd>Octo issue list<cr>", desc = "List issues" },
    { "<leader>gOc", "<cmd>Octo pr create<cr>", desc = "Create PR" },
    { "<leader>gOr", "<cmd>Octo review start<cr>", desc = "Start review" },
  },
  opts = {},
}
