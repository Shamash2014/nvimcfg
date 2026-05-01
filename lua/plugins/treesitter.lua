return {
  {
    src = "https://github.com/romus204/tree-sitter-manager.nvim",
    lazy = false,
    config = function()
      require("tree-sitter-manager").setup({
        ensure_installed = {
          "bash",
          "dart",
          "elixir",
          "go",
          "sql",
          "yaml",
          "json",
          "javascript",
          "lua",
          "markdown",
          "markdown_inline",
          "typescript",
          "tsx",
          "vim",
          "vimdoc",
        },
        auto_install = false,
        highlight = true,
      })
    end,
  },
}
