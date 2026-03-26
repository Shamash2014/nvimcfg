return {
  {
    "joryeugene/dadbod-grip.nvim",
    version = "*",
    keys = {
      { "<leader>odg", "<cmd>GripConnect<cr>", desc = "DB connect (grip)" },
      { "<leader>odi", "<cmd>Grip<cr>",        desc = "DB grid" },
      { "<leader>odt", "<cmd>GripTables<cr>",  desc = "DB tables" },
      { "<leader>odq", "<cmd>GripQuery<cr>",   desc = "DB query pad" },
      { "<leader>ods", "<cmd>GripSchema<cr>",  desc = "DB schema" },
      { "<leader>odh", "<cmd>GripHistory<cr>", desc = "DB history" },
    },
    opts = {},
  },
}
