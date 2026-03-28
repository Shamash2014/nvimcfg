return {
  "clabby/difftastic.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "folke/snacks.nvim",
  },
  cmd = { "Difft", "DifftPick", "DifftPickRange", "DifftClose" },
  keys = {
    { "<leader>gd", "<cmd>Difft<cr>", desc = "Difftastic diff" },
    { "<leader>gs", "<cmd>Difft --staged<cr>", desc = "Difftastic staged" },
    { "<leader>gp", "<cmd>DifftPick<cr>", desc = "Difftastic pick commit" },
  },
  config = function()
    require("difftastic-nvim").setup({
      download = true,
      snacks_picker = { enabled = true },
    })
  end,
}
