return {
  "smjonas/inc-rename.nvim",
  cmd = "IncRename",
  opts = {
    input_buffer_type = "dressing",
  },
  keys = {
    {
      "<leader>cr",
      function()
        return ":IncRename " .. vim.fn.expand("<cword>")
      end,
      desc = "Inc Rename",
      expr = true,
    },
  },
}