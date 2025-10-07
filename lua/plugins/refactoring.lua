return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  ft = { "typescript", "javascript", "lua", "c", "cpp", "go", "python", "java", "php", "ruby", "cs", "typescriptreact", "javascriptreact" },
  keys = {
    { "<leader>cmv", function() require("refactoring").refactor("Extract Variable") end, mode = { "x" }, desc = "Extract Variable" },
    { "<leader>cmf", function() require("refactoring").refactor("Extract Function") end, mode = { "x" }, desc = "Extract Function" },
    { "<leader>cmF", function() require("refactoring").refactor("Extract Function To File") end, mode = { "x" }, desc = "Extract Function to File" },
    { "<leader>cmI", function() require("refactoring").refactor("Inline Function") end, mode = { "n" }, desc = "Inline Function" },
    { "<leader>cmi", function() require("refactoring").refactor("Inline Variable") end, mode = { "n", "x" }, desc = "Inline Variable" },
    { "<leader>cmb", function() require("refactoring").refactor("Extract Block") end, mode = { "n" }, desc = "Extract Block" },
    { "<leader>cmB", function() require("refactoring").refactor("Extract Block To File") end, mode = { "n" }, desc = "Extract Block to File" },

    -- Debug helpers
    { "<leader>cmp", function() require("refactoring").debug.printf({ below = false }) end, mode = { "n" }, desc = "Debug Print" },
    { "<leader>cmv", function() require("refactoring").debug.print_var() end, mode = { "x", "n" }, desc = "Debug Print Variable" },
    { "<leader>cmC", function() require("refactoring").debug.cleanup({}) end, mode = { "n" }, desc = "Cleanup Debug Prints" },

    -- Refactor menu
    { "<leader>cmr", function()
      require("refactoring").select_refactor()
    end, mode = { "x", "n" }, desc = "Refactor Menu" },
  },
  config = function()
    require('refactoring').setup({
      prompt_func_return_type = {
        go = true,
        java = true,
        cpp = true,
        c = true,
        h = true,
        hpp = true,
        cxx = true,
        cs = true,
      },
      prompt_func_param_type = {
        go = true,
        java = true,
        cpp = true,
        c = true,
        h = true,
        hpp = true,
        cxx = true,
        cs = true,
      },
      printf_statements = {},
      print_var_statements = {},
      show_success_message = true,
    })

    -- Enable JSX/TSX support by registering language fallbacks
    vim.treesitter.language.register("typescript", "typescriptreact")
    vim.treesitter.language.register("javascript", "javascriptreact")
  end,
}
