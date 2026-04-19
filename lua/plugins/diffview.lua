return {
  {
    "dlyongemallo/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewDiffFiles", "DiffviewFileHistory", "DiffviewClose" },
    opts = {
      use_icons = true,
      view = { default = { layout = "diff2_horizontal" } },
    },
  },
}
