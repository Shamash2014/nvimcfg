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
}
