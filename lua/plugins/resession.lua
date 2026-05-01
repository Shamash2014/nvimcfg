return {
  {
    src = "https://github.com/stevearc/resession.nvim",
    lazy = false,
    config = function()
      local resession = require("resession")
      local wt = require("config.wt")

      resession.setup({})

      local function session_name()
        return wt.session_name(vim.fn.getcwd())
      end

      local function started_without_args()
        return vim.fn.argc(-1) == 0
      end

      vim.api.nvim_create_autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("nvim2-resession", { clear = true }),
        nested = true,
        callback = function()
          if started_without_args() then
            resession.load(session_name(), { dir = "dirsession", silence_errors = true })
          end
        end,
      })

      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("nvim2-resession-leave", { clear = true }),
        callback = function()
          if started_without_args() then
            resession.save(session_name(), { dir = "dirsession", notify = false })
          end
        end,
      })
    end,
  },
}
