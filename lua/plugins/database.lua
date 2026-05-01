return {
  {
    src = "https://github.com/joryeugene/dadbod-grip.nvim",
    sem_version = "*",
    ft = { "sql" },
    cmd = {
      "GripConnect",
      "GripToggle",
      "GripOpen",
      "GripSave",
      "GripAttach",
      "GripFill",
    },
    config = function()
      vim.keymap.set("n", "<leader>od", "<cmd>GripConnect<CR>", { desc = "Database connect" })
      vim.keymap.set("n", "<leader>ot", "<cmd>GripToggle<CR>", { desc = "Database toggle" })
    end,
  },
}
