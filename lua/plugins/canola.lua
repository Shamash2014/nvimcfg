return {
  {
    src = "https://github.com/barrettruth/canola.nvim",
    lazy = false,
    opts = {
      default_file_explorer = true,
      columns = { "icon" },
      view_options = {
        show_hidden = true,
      },
      buf_options = {
        buflisted = false,
        bufhidden = "hide",
      },
      win_options = {
        wrap = false,
        signcolumn = "no",
        cursorcolumn = false,
        foldcolumn = "0",
        spell = false,
        list = false,
        conceallevel = 3,
        concealcursor = "nvic",
      },
    },
    config = function(_, opts)
      require("oil").setup(opts)
    end,
  },
}
