return {
  {
    "romus204/tree-sitter-manager.nvim",
    lazy = false,
    config = function()
      local ok, manager = pcall(require, "tree-sitter-manager")
      if not ok then
        return
      end

      manager.setup({
        ensure_installed = {
          "bash",
          "dart",
          "go",
          "json",
          "lua",
          "markdown",
          "markdown_inline",
          "typescript",
          "tsx",
          "vim",
          "vimdoc",
          "yaml",
        },
        auto_install = false,
        highlight = true,
      })
    end,
  },
}
