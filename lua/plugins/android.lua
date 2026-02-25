return {
  dir = vim.fn.stdpath("config") .. "/lua/mobile-dev/android",
  name = "android-dev",
  ft = { "kotlin", "java", "xml" },
  cmd = { "AndroidBuild", "AndroidRun", "AndroidLogcat", "AndroidDevices" },
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("mobile-dev.android").setup()
  end,
}
