return {
  dir = vim.fn.stdpath("config"),
  name = "djinni",
  dependencies = {
    "folke/snacks.nvim",
    "folke/which-key.nvim",
    "MeanderingProgrammer/render-markdown.nvim",
  },
  ft = { "nowork-chat" },
  keys = {
    { "<leader>fo", function()
      require("djinni.nowork.panel").search_tasks()
    end, desc = "Nowork tasks" },
    { "<leader>fp", function() require("djinni.nowork.panel").toggle() end, desc = "Nowork panel" },
    { "<leader>ft", function() require("djinni.nowork.panel").toggle() end, desc = "Nowork panel" },
    { "ga", function() return require("djinni.code").ga_operator() end, expr = true, desc = "AI task operator" },
    { "gac", function() return require("djinni.code").gac_operator() end, expr = true, desc = "AI named task operator" },
    { "gav", function() require("djinni.code").create_with_selection() end, mode = "v", desc = "Task with selection" },
    { "gas", function() require("djinni.code").send_selection_to_chat() end, mode = "v", desc = "Send to chat" },
  },
  config = function()
    require("djinni").setup()
  end,
}
