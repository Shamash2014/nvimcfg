return {
  "LionyxML/gitlineage.nvim",
  dependencies = {
    "sindrets/diffview.nvim",
  },
  keys = {
    { "<leader>gh", "<cmd>GitLineage<cr>", mode = "v", desc = "Git line history" },
  },
  config = function()
    require("gitlineage").setup({
      split = "auto",
      keymap = nil, -- Disable default keymap, using which-key registered binding
      keys = {
        close = "q",
        next_commit = "]c",
        prev_commit = "[c",
        yank_commit = "yc",
        open_diff = "<CR>",
      },
    })
  end,
}
