return {
  dir = vim.fn.stdpath("config"),
  name = "worktrunk",
  keys = {
    { "<leader>oww", function() require("djinni.integrations.worktrunk_ui").toggle() end, desc = "Worktrunk UI" },
  },
  cmd = { "Worktrunk" },
  config = function()
    require("djinni.integrations.worktrunk_ui").setup()
  end,
}
