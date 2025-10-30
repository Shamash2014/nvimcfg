if vim.fn.executable("vscode-json-language-server") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "jsonls",
    cmd = { "vscode-json-language-server", "--stdio" },
    root_dir = vim.fs.root(0, { ".git" }),
  }))
end

local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("jsonlint") == 1 then
  lint.linters_by_ft.json = { "jsonlint" }
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.json = { "prettier" }
end
