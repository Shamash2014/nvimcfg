return {
  "joryeugene/dadbod-grip.nvim",
  version = "*",
  cmd = { "GripStart", "GripConnect", "GripOpen" },
  keys = {
    { "<leader>ods", "<cmd>GripStart<cr>", desc = "Start (demo db)" },
    { "<leader>odc", "<cmd>GripConnect<cr>", desc = "Connect to database" },
    { "<leader>odo", "<cmd>GripOpen<cr>", desc = "Open table" },
  },
  opts = {},
}
