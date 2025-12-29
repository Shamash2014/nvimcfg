return {
  "itsfrank/swell.nvim",
  keys = {
    {
      "<leader>wm",
      function()
        local swell = require("swell")
        if swell.is_swollen() then
          swell.unswell_window()
        else
          swell.swell_window(vim.api.nvim_get_current_win())
        end
      end,
      desc = "Toggle window maximize"
    },
  },
}