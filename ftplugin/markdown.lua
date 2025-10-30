local ok, lint = pcall(require, 'lint')
if ok then
  local linters = {}

  -- Use Vale if available (now installed)
  if vim.fn.executable("vale") == 1 then
    table.insert(linters, "vale")
  end

  -- Use markdownlint if available
  if vim.fn.executable("markdownlint") == 1 then
    table.insert(linters, "markdownlint")
  end

  if #linters > 0 then
    lint.linters_by_ft.markdown = linters
  end
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.markdown = { "prettier" }
end
