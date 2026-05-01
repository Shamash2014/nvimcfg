return {
  {
    src = "https://github.com/barrettruth/diffs.nvim",
    priority = 1000,
    lazy = false,
    init = function()
      vim.g.diffs = {
        integrations = {
          neogit = true,
        },
        highlights = {
          gutter = true,
          intra = { enabled = true },
        },
      }
    end,
  },
  {
    src = "https://github.com/NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = {
      {
        src = "https://github.com/nvim-lua/plenary.nvim",
      },
    },
    config = function()
      require("neogit").setup({})
    end,
  },
  {
    src = "https://github.com/sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
      "DiffviewRefresh",
      "DiffviewFileHistory",
    },
    config = function()
      require("diffview").setup({})
    end,
  },
}
