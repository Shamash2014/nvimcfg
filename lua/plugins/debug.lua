return {
  {
    src = "https://github.com/mfussenegger/nvim-dap",
    lazy = false,
    config = function()
      local dap = require("dap")

      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "✕", texthl = "DiagnosticError", linehl = "", numhl = "" })
      vim.fn.sign_define("DapLogPoint", { text = "󰆈", texthl = "DiagnosticInfo", linehl = "", numhl = "" })
      vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticOk", linehl = "Visual", numhl = "" })

      dap.defaults.fallback.exception_breakpoints = { "raised", "uncaught" }
    end,
  },
  {
    src = "https://github.com/igorlfs/nvim-dap-view",
    lazy = false,
    cond = function()
      return vim.fn.has("nvim-0.11") == 1
    end,
    config = function()
      require("dap-view").setup({})
    end,
  },
}
