return {
  {
    dir = vim.fn.stdpath("config") .. "/lua/core/stack",
    name = "stack",
    keys = {
      { "<leader>gk", function() require("core.stack").popup() end, desc = "Stack popup" },
      { "[k", function() require("core.stack").up() end, desc = "Stack up (parent)" },
      { "]k", function() require("core.stack").down() end, desc = "Stack down (child)" },
    },
    config = function()
      require("core.stack").setup()
    end,
  },
}
