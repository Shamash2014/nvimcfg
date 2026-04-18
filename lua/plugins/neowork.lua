return {
  dir = vim.fn.stdpath("config"),
  name = "neowork",
  dependencies = {
    "folke/which-key.nvim",
  },
  keys = {
    { "<leader>oo", function()
      require("neowork").setup()
      require("neowork.index").open({ tab = false })
    end, desc = "Neowork index" },
    { "<leader>fn", function() vim.cmd("Neowork new") end, desc = "Neowork new session" },
  },
  cmd = {
    "Neowork",
    "NeoworkNew",
    "NeoworkIndex",
    "NeoworkIndexToggle",
    "NeoworkPlanToggle",
    "NeoworkTranscript",
    "NeoworkTranscriptFull",
  },
  config = function()
    require("neowork").setup()
  end,
}
