return {
  {
    src = "https://github.com/nvim-mini/mini.cursorword",
    lazy = false,
    config = function()
      require("mini.cursorword").setup({})
    end,
  },
  {
    src = "https://github.com/kevinhwang91/nvim-bqf",
    lazy = false,
    ft = "qf",
    config = function()
      require("bqf").setup({
        auto_enable = true,
        auto_resize_height = true,
      })
    end,
  },
  {
    src = "https://github.com/stevearc/quicker.nvim",
    lazy = false,
    config = function()
      require("quicker").setup({
        opts = {
          buflisted = false,
          number = false,
          relativenumber = false,
          signcolumn = "auto",
          winfixheight = true,
          wrap = false,
        },
        edit = {
          enabled = true,
          autosave = "unmodified",
        },
        keys = {
          {
            ">",
            function()
              require("quicker").expand({ before = 2, after = 2, add_to_existing = true })
            end,
            desc = "Expand quickfix context",
          },
          {
            "<",
            function()
              require("quicker").collapse()
            end,
            desc = "Collapse quickfix context",
          },
        },
      })
    end,
  },
}
