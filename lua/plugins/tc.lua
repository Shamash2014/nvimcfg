return {
  dir = vim.fn.stdpath("config") .. "/lua/core/tasks",
  name = "wildtest",
  event = "VeryLazy",
  ft = "markdown",
  keys = {
    { "<leader>ozz", function() require("core.tasks").start_test_run() end, desc = "WildTest: Start" },
    { "<leader>ozp", function() require("core.tasks").pick_test() end, desc = "WildTest: Pick" },
    { "<leader>ozr", function() require("core.tasks").open_results() end, desc = "WildTest: Results" },
    { "<leader>ozi", function() require("core.tasks").open_issues() end, desc = "WildTest: Issues" },
  },
  config = function()
    require("core.tasks").setup()
  end,
}
