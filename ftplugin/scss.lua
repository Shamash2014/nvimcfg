-- SCSS LSP now handled by centralized CSS server in lua/lsp.lua

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.scss = { "prettier" }
end

local ok, lint = pcall(require, 'lint')
if ok then
  if vim.fn.executable("stylelint") == 1 then
    lint.linters_by_ft.scss = { "stylelint" }
  end
end