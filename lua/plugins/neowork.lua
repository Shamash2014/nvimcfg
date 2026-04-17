return {
  dir = vim.fn.stdpath("config"),
  name = "neowork",
  dependencies = {
    "folke/which-key.nvim",
  },
  keys = {
    { "<leader>fn", function() vim.cmd("Neowork new") end, desc = "Neowork new session" },
  },
  cmd = { "Neowork", "NeoworkNew", "NeoworkIndex" },
  config = function()
    require("neowork").setup()
  end,
}
