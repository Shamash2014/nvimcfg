-- HTML LSP for standard HTML features is configured centrally

-- HTML LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'HTMLValidate',
  function()
    vim.cmd('terminal npx html-validate %')
  end, { desc = 'Validate HTML file' })

vim.api.nvim_buf_create_user_command(0, 'HTMLFormat',
  function()
    vim.cmd('terminal npx prettier --write %')
  end, { desc = 'Format HTML file' })

vim.api.nvim_buf_create_user_command(0, 'HTMLPreview',
  function()
    vim.cmd('!open %')
  end, { desc = 'Preview HTML in browser' })

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.html = { "prettier" }
end
