return {
  {
    src = "https://github.com/folke/which-key.nvim",
    lazy = false,
    opts = {
      spec = {
        { "<leader>aw", desc = "New thread" },
        { "<leader>pp", desc = "Projects / worktrees" },
      },
    },
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
