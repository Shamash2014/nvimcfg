local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("yamllint") == 1 then
  lint.linters_by_ft.yaml = { "yamllint" }
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.yaml = { "prettier" }
end
