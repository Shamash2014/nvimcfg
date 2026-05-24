return {
  {
    "kylechui/nvim-surround",
    lazy = false,
    config = function()
      local ok, surround = pcall(require, "nvim-surround")
      if ok then
        surround.setup({})
      end
    end,
  },
  {
    "mistweaverco/kulala.nvim",
    lazy = false,
    opts = {
      global_keymaps_prefix = "<leader>oz",
    },
  },
  {
    src = "https://codeberg.org/andyg/leap.nvim",
    lazy = false,
    dependencies = {
      {
        "tpope/vim-repeat",
      },
    },
  },
  {
    "windwp/nvim-autopairs",
    lazy = false,
    config = function()
      local ok, autopairs = pcall(require, "nvim-autopairs")
      if ok then
        autopairs.setup({
          check_ts = true,
        })
      end
    end,
  },
  {
    src = "https://github.com/serhez/editr",
    lazy = false,
  },
}
