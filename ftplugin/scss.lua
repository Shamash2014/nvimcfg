if vim.fn.executable("vscode-css-language-server") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "scss",
    cmd = { "vscode-css-language-server", "--stdio" },
    root_dir = vim.fs.root(0, { "package.json", ".git" }),
    init_options = {
      provideFormatter = true,
      emmet = {
        showExpandedAbbreviation = "always",
        showAbbreviationSuggestions = true,
        syntaxProfiles = {
          scss = "scss",
        },
        variables = {
          lang = "en",
        },
        excludeSuggestions = [],
        preferences = {},
      },
    },
    settings = {
      css = {
        lint = {
          unknownProperties = "ignore"
        },
        validate = true
      },
      scss = {
        lint = {
          unknownProperties = "ignore"
        },
        validate = true
      }
    },
    single_file_support = true,
  }))
end

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