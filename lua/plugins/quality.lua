return {
  {
    "stevearc/conform.nvim",
    lazy = false,
    config = function()
      local ok, conform = pcall(require, "conform")
      if not ok then
        return
      end

      conform.setup({
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
    "mfussenegger/nvim-lint",
    lazy = false,
    config = function()
      local ok, lint = pcall(require, "lint")
      if not ok then
        return
      end

      lint.linters_by_ft = {
        lua = { "luacheck" },
        sh = { "shellcheck" },
        bash = { "shellcheck" },
        json = { "jsonlint" },
        markdown = { "markdownlint" },
      }

      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("nvim3-lint", { clear = true }),
        callback = function()
          if vim.bo.buftype ~= "" then
            return
          end
          lint.try_lint()
        end,
      })
    end,
  },
}
