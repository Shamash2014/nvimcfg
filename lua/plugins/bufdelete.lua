return {
  "famiu/bufdelete.nvim",
  keys = {
    { "<leader>bd", function() require("bufdelete").bufdelete(0, false) end, desc = "Delete buffer" },
    { "<leader>bD", function() require("bufdelete").bufdelete(0, true) end, desc = "Force delete buffer" },
  },
}
