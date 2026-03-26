vim.treesitter.language.register("markdown", "nowork-chat")

return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  ft = { "markdown", "nowork-chat" },
  opts = {
    file_types = { "markdown", "nowork-chat" },
  },
}
