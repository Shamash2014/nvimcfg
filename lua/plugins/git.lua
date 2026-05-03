return {
  {
    src = "https://github.com/NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = {
      {
        src = "https://github.com/nvim-lua/plenary.nvim",
      },
    },
    config = function()
      require("neogit").setup({
        mappings = {
          status = {
            ["W"] = function()
              require("acp.neogit_workbench").open({ kind = "replace" })
            end,
          },
        },
      })
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
