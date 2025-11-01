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

      lint.linters_by_ft = {
        dart = { 'dartanalyzer' },
      }

      lint.linters.dartanalyzer = {
        cmd = 'dartanalyzer',
        args = { '--format', 'machine' },
        stdin = false,
        stream = 'stdout',
        ignore_exitcode = true,
        parser = function(output, bufnr)
          local diagnostics = {}
          local lines = vim.split(output, '\n', { trimempty = true })

          for _, line in ipairs(lines) do
            local severity, file, line_num, col, message = line:match('^(%w+)|([^|]+)|(%d+)|(%d+)|(.*)$')
            if severity and file and line_num and col and message then
              local level = 'error'
              if severity == 'WARNING' then
                level = 'warn'
              elseif severity == 'INFO' then
                level = 'info'
              end

              table.insert(diagnostics, {
                lnum = tonumber(line_num) - 1,
                col = tonumber(col) - 1,
                message = message,
                severity = vim.diagnostic.severity[level:upper()],
                source = 'dartanalyzer',
              })
            end
          end

          return diagnostics
        end,
      }

      vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
        group = vim.api.nvim_create_augroup('nvim_lint', { clear = true }),
        callback = function()
          require('lint').try_lint()
        end,
      })
    end,
  },
}
