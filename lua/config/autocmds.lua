local group = vim.api.nvim_create_augroup("nvim2", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 120 })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = {
    "bash",
    "dart",
    "elixir",
    "go",
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
  callback = function()
    vim.bo.indentexpr = "v:lua.vim.treesitter.indentexpr()"
  end,
})
