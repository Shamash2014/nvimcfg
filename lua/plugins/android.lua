return {
  dir = vim.fn.stdpath("config") .. "/lua/mobile-dev/android",
  name = "android-dev",
  event = "VeryLazy",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("mobile-dev.android").setup()
  end,
}
