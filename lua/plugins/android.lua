return {
  dir = vim.fn.stdpath("config") .. "/lua/android",
  name = "android-dev",
  event = "VeryLazy",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("android").setup()
  end,
}
