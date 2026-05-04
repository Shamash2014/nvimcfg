return {
  {
    src = "https://github.com/stevearc/conform.nvim",
    lazy = false,
    config = function()
      require("conform").setup({
        format_on_save = {
          timeout_ms = 500,
          lsp_fallback = true,
        },
        formatters_by_ft = {
          lua = { "stylua" },
          sh = { "shfmt" },
          bash = { "shfmt" },
          json = { "jq" },
          markdown = { "prettier" },
        },
      })
    end,
  },
  {
    src = "https://github.com/mfussenegger/nvim-lint",
    lazy = false,
    config = function()
      local lint = require("lint")

      lint.linters_by_ft = {
        lua = { "luacheck" },
        sh = { "shellcheck" },
        bash = { "shellcheck" },
        json = { "jsonlint" },
        markdown = { "markdownlint" },
      }

      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("nvim2-lint", { clear = true }),
        callback = function()
          if vim.bo.buftype == "nofile" then return end
          lint.try_lint()
        end,
      })
    end,
  },
}
