-- JSON LSP now configured centrally in lua/lsp.lua

local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("jsonlint") == 1 then
  lint.linters_by_ft.json = { "jsonlint" }
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.json = { "prettier" }
end
