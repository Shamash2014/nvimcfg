return {
  {
    src = "https://github.com/folke/which-key.nvim",
    lazy = false,
    opts = {},
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer local keymaps",
      },
    },
  },
}
