return {
  {
    src = "https://github.com/romus204/referencer.nvim",
    lazy = false,
    config = function()
      require("referencer").setup({
        enable = true,
        hl_group = "Comment",
        show_no_reference = false,
      })
    end,
  },
}
