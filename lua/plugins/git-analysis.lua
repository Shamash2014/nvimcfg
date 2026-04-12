return {
  "git-analysis",
  virtual = true,
  keys = {
    { "<leader>gA", function() require("core.git_analysis").open() end, desc = "Git Analysis" },
  },
}
