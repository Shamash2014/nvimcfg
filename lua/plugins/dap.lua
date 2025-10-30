return {
  {
    'mfussenegger/nvim-dap',
    lazy = true,
    keys = {
      { '<leader>db', function() require('dap').toggle_breakpoint() end, desc = 'Toggle Breakpoint' },
      { '<leader>dB', function() require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, desc = 'Conditional Breakpoint' },
      { '<leader>dL', function() require('dap').set_breakpoint(nil, nil, vim.fn.input('Log message: ')) end, desc = 'Log Point' },
      { '<leader>dc', function() require('dap').continue() end, desc = 'Continue' },
      { '<leader>di', function() require('dap').step_into() end, desc = 'Step Into' },
      { '<leader>do', function() require('dap').step_over() end, desc = 'Step Over' },
      { '<leader>dO', function() require('dap').step_out() end, desc = 'Step Out' },
      { '<leader>dj', function() require('dap').down() end, desc = 'Down Stack Frame' },
      { '<leader>dk', function() require('dap').up() end, desc = 'Up Stack Frame' },
      { '<leader>dR', function() require('dap').run_to_cursor() end, desc = 'Run to Cursor' },
      { '<leader>dr', function() require('dap').repl.toggle() end, desc = 'Toggle REPL' },
      { '<leader>dt', function() require('dapui').toggle() end, desc = 'Toggle DAP UI' },
      { '<leader>de', function() require('dapui').eval() end, desc = 'Eval Expression', mode = {'n', 'v'} },
    },
  },
  {
    'rcarriga/nvim-dap-ui',
    dependencies = { 'mfussenegger/nvim-dap', 'nvim-neotest/nvim-nio' },
    lazy = true,
    keys = {
      { '<leader>dt', function() require('dapui').toggle() end, desc = 'Toggle DAP UI' },
      { '<leader>de', function() require('dapui').eval() end, desc = 'Eval Expression', mode = {'n', 'v'} },
    },
    config = function()
      local dap, dapui = require('dap'), require('dapui')

      dapui.setup({
        icons = { expanded = '▾', collapsed = '▸', current_frame = '▸' },
        mappings = {
          expand = { '<CR>', '<2-LeftMouse>' },
          open = 'o',
          remove = 'd',
          edit = 'e',
          repl = 'r',
          toggle = 't',
        },
        layouts = {
          {
            elements = {
              { id = 'scopes', size = 0.25 },
              { id = 'breakpoints', size = 0.25 },
              { id = 'stacks', size = 0.25 },
              { id = 'watches', size = 0.25 },
            },
            size = 40,
            position = 'left',
          },
          {
            elements = {
              { id = 'repl', size = 0.5 },
              { id = 'console', size = 0.5 },
            },
            size = 10,
            position = 'bottom',
          },
        },
        floating = {
          max_height = nil,
          max_width = nil,
          border = 'single',
          mappings = {
            close = { 'q', '<Esc>' },
          },
        },
      })

      dap.listeners.after.event_initialized['dapui_config'] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated['dapui_config'] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited['dapui_config'] = function()
        dapui.close()
      end

      vim.fn.sign_define('DapBreakpoint', { text = '●', texthl = 'DapBreakpoint', linehl = '', numhl = '' })
      vim.fn.sign_define('DapBreakpointCondition', { text = '◆', texthl = 'DapBreakpointCondition', linehl = '', numhl = '' })
      vim.fn.sign_define('DapLogPoint', { text = '◉', texthl = 'DapLogPoint', linehl = '', numhl = '' })
      vim.fn.sign_define('DapStopped', { text = '▶', texthl = 'DapStopped', linehl = 'DapStoppedLine', numhl = '' })
      vim.fn.sign_define('DapBreakpointRejected', { text = '✘', texthl = 'DapBreakpointRejected', linehl = '', numhl = '' })
    end,
  },
}
