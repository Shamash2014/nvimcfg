return {
  {
    "folke/snacks.nvim",
    lazy = false,
    config = function()
      local ok, snacks = pcall(require, "snacks")
      if not ok then
        return
      end

      snacks.setup({
        notifier = {
          enabled = true,
        },
        picker = {
          enabled = true,
          layout = {
            preset = "vscode",
            preview = false,
          },
        },
      })
    end,
  },
  {
    "dmtrKovalenko/fff.nvim",
    lazy = false,
    build = function()
      require("fff.download").download_or_build_binary()
    end,
  },
  {
    "so1ve/snacks-fff.nvim",
    lazy = false,
    dependencies = {
      "folke/snacks.nvim",
      "dmtrKovalenko/fff.nvim",
    },
  },
}
