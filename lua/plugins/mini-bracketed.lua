return {
  "echasnovski/mini.bracketed",
  event = "VeryLazy",
  opts = {},
  config = function(_, opts)
    require("mini.bracketed").setup(opts)
    vim.keymap.set("n", "[T", "<cmd>tabprevious<cr>", { desc = "Previous tab" })
    vim.keymap.set("n", "]T", "<cmd>tabnext<cr>", { desc = "Next tab" })
  end,
}