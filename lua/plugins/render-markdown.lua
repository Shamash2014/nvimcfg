vim.treesitter.language.register("markdown", "nowork-chat")

return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  ft = { "markdown", "nowork-chat" },
  opts = {
    file_types = { "markdown", "nowork-chat" },
    render_modes = { "n", "c" },
    ignore = function(buf)
      if vim.bo[buf].filetype ~= "nowork-chat" then return false end
      return vim.api.nvim_buf_line_count(buf) > 3000
    end,
  },
}
