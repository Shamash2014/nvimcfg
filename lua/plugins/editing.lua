return {
  {
    src = "https://github.com/kylechui/nvim-surround",
    lazy = false,
    config = function()
      require("nvim-surround").setup({})
    end,
  },
  {
    src = "https://codeberg.org/andyg/leap.nvim",
    lazy = false,
    dependencies = {
      {
        src = "https://github.com/tpope/vim-repeat",
      },
    },
  },
  {
    src = "https://github.com/windwp/nvim-autopairs",
    lazy = false,
    config = function()
      require("nvim-autopairs").setup({
        check_ts = true,
        ts_config = {
          lua = { "string", "comment" },
          javascript = { "string", "template_string", "comment" },
          javascriptreact = { "string", "template_string", "comment" },
          typescript = { "string", "template_string", "comment" },
          typescriptreact = { "string", "template_string", "comment" },
          elixir = { "string", "comment" },
          go = { "string", "comment" },
          dart = { "string", "comment" },
        },
      })
    end,
  },
}
