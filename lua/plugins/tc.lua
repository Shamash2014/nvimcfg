return {
  dir = vim.fn.stdpath("config") .. "/lua/tc",
  name = "wildtest",
  ft = "markdown",
  keys = {
    { "<leader>ozz", function() require("tc").start_test_run() end, desc = "WildTest: Start" },
    { "<leader>ozp", function() require("tc").pick_test() end, desc = "WildTest: Pick" },
    { "<leader>ozr", function() require("tc").open_results() end, desc = "WildTest: Results" },
    { "<leader>ozi", function() require("tc").open_issues() end, desc = "WildTest: Issues" },
  },
  config = function()
    require("tc").setup()
  end,
}
