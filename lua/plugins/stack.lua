return {
  {
    dir = vim.fn.stdpath("config") .. "/lua/core/stack",
    name = "stack",
    lazy = false,
    config = function()
      require("core.stack").setup()
    end,
    keys = {
      { "<leader>gk", function() require("core.stack").popup() end, desc = "Stack popup" },
      { "[k", function() require("core.stack").up() end, desc = "Stack up (parent)" },
      { "]k", function() require("core.stack").down() end, desc = "Stack down (child)" },
    },
  },
}
