return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  ft = { "markdown" },
  opts = {
    file_types = { "markdown" },
    render_modes = { "n", "c" },
    ignore = function(buf)
      if not vim.b[buf].neowork_chat then return false end
      return vim.api.nvim_buf_line_count(buf) > 3000
    end,
    heading = {
      sign = false,
      icons = {},
      width = "block",
      left_pad = 0,
      right_pad = 0,
      border = false,
    },
  },
}
