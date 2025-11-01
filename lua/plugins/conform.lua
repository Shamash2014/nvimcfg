return {
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>cf',
        function()
          require('conform').format({ async = true, lsp_fallback = true })
        end,
        desc = 'Format',
      },
    },
    config = function()
      require('conform').setup({
        formatters_by_ft = {
          dart = { "dart_format" },
        },
        formatters = {
          dart_format = {
            command = "dart",
            args = { "format", "--output=write", "$FILENAME" },
            stdin = false,
          },
        },
        format_on_save = function(bufnr)
          if vim.fn.getfsize(vim.api.nvim_buf_get_name(bufnr)) > 100000 then
            return
          end
          return { timeout_ms = 1000, lsp_fallback = true }
        end,
      })
    end,
  },
}
