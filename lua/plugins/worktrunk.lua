return {
  dir = vim.fn.stdpath("config"),
  name = "worktrunk",
  event = "VeryLazy",
  keys = {
    { "<leader>oww", function() require("djinni.integrations.worktrunk_ui").create() end, desc = "Worktrunk" },
    { "<leader>ows", function() require("djinni.integrations.worktrunk_ui").quick_switch() end, desc = "Switch worktree" },
    { "<leader>owc", function() require("djinni.integrations.worktrunk_ui").quick_create() end, desc = "Create worktree" },
    { "<leader>owd", function() require("djinni.integrations.worktrunk_ui").quick_diff() end, desc = "Diff worktree" },
  },
  cmd = { "Worktrunk" },
  config = function()
    require("djinni.integrations.worktrunk_ui").setup()
    require("djinni.integrations.worktrunk").start_statusline()
  end,
}
