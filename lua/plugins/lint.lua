return {
  {
    'mfussenegger/nvim-lint',
    event = { 'BufReadPost', 'BufWritePost', 'BufNewFile' },
    keys = {
      {
        '<leader>cl',
        function()
          require('lint').try_lint()
        end,
        desc = 'Lint File',
      },
    },
    config = function()
      local lint = require('lint')

      vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
        group = vim.api.nvim_create_augroup('nvim_lint', { clear = true }),
        callback = function()
          require('lint').try_lint()
        end,
      })
    end,
  },
}
