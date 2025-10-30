local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("nixfmt") == 1 then
  conform.formatters_by_ft.nix = { "nixfmt" }
end
