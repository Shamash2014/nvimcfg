return {
  {
    src = "https://github.com/mosheavni/yaml-companion.nvim",
    ft = { "yaml" },
    config = function()
      local opts = {
        format = { enable = true },
        hover = true,
        schemaStore = {
          enable = true,
          url = "https://www.schemastore.org/api/json/catalog.json",
        },
        schemaDownload = { enable = true },
        schemas = {},
        trace = { server = "info" },
      }

      local cfg = require("yaml-companion").setup(opts)
      vim.lsp.config("yamlls", cfg)
      vim.lsp.enable("yamlls")
    end,
  },
}
