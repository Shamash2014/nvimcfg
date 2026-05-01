return {
  {
    src = "https://github.com/lima1909/resty.nvim",
    cmd = { "Resty" },
    ft = { "resty" },
    dependencies = {
      {
        src = "https://github.com/nvim-lua/plenary.nvim",
      },
    },
    keys = {
      {
        "<leader>or",
        "<cmd>Resty run<CR>",
        mode = { "n", "v" },
        desc = "Run request",
      },
      {
        "<leader>ol",
        "<cmd>Resty last<CR>",
        desc = "Run last request",
      },
      {
        "<leader>oe",
        "<cmd>Resty env select<CR>",
        desc = "Select env file",
      },
    },
  },
  {
    src = "https://github.com/MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    opts = {
      completions = {
        lsp = {
          enabled = true,
        },
      },
      file_types = { "markdown", "vimwiki" },
    },
  },
}
