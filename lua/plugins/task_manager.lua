return {
  dir = vim.fn.stdpath("config"),
  name = "task-manager",
  cmd = { "TaskManager" },
  config = function()
    require("task_manager").setup()
  end,
}
