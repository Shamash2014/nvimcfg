return {
  dir = vim.fn.stdpath("config"),
  name = "djinni",
  dependencies = {
    "folke/snacks.nvim",
    "folke/which-key.nvim",
    "MeanderingProgrammer/render-markdown.nvim",
  },
  cmd = {
    "NeoworkTask",
    "NeoworkPick",
    "NeoworkSessions",
    "NeoworkConsole",
    "NeoworkSplit",
  },
  keys = {
    { "<leader>fo", function()
      require("neowork").setup()
      require("neowork.index").open({ tab = false })
    end, desc = "Neowork sessions" },
    { "<leader>fp", function() require("djinni.code").create_task() end, desc = "New neowork task" },
    { "<leader>ft", function() require("djinni.code").create_task() end, desc = "New neowork task" },
    { "ga", function() return require("djinni.code").ga_operator() end, expr = true, desc = "AI task operator" },
    { "gac", function() return require("djinni.code").gac_operator() end, expr = true, desc = "AI named task operator" },
    { "gav", function() require("djinni.code").create_with_selection() end, mode = "v", desc = "Task with selection" },
    { "gas", function() require("djinni.code").send_selection_to_chat() end, mode = "v", desc = "Send to chat" },
  },
  config = function()
    require("djinni").setup()
  end,
}
