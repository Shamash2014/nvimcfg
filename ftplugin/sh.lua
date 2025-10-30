local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("shellcheck") == 1 then
  lint.linters_by_ft.sh = { "shellcheck" }
end
