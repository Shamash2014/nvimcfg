-- CSS LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'CSSLint',
  function()
    vim.cmd('terminal npx stylelint %')
  end, { desc = 'Lint CSS file' })

vim.api.nvim_buf_create_user_command(0, 'CSSFormat',
  function()
    vim.cmd('terminal npx prettier --write %')
  end, { desc = 'Format CSS file' })

vim.api.nvim_buf_create_user_command(0, 'CSSMinify',
  function()
    vim.cmd('terminal npx clean-css-cli -o %.min.css %')
  end, { desc = 'Minify CSS file' })

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.css = { "prettier" }
end
