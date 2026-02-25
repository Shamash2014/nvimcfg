return {
  "echasnovski/mini.bracketed",
  keys = {
    { "[", desc = "Previous" },
    { "]", desc = "Next" },
    { "[T", "<cmd>tabprevious<cr>", desc = "Previous tab" },
    { "]T", "<cmd>tabnext<cr>", desc = "Next tab" },
  },
  opts = {},
  config = function(_, opts)
    require("mini.bracketed").setup(opts)
  end,
}