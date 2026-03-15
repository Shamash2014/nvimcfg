return {
  "bravoecho/brook.nvim",
  cmd = { "Rg", "RgStop", "RgRepeat" },
  keys = {
    { "<leader>sm", mode = "n", desc = "Rg current word" },
    { "<leader>sm", mode = "x", desc = "Rg visual selection" },
    { "<leader>sM", mode = "n", desc = "Rg prompt" },
    { "<localleader>r", function()
        local keys = vim.api.nvim_replace_termcodes(":cfdo %s///gc | update<Left><Left><Left><Left><Left><Left><Left><Left><Left><Left><Left><Left><Left><Left><Left>", true, false, true)
        vim.api.nvim_feedkeys(keys, "n", false)
      end, desc = "Quickfix replace" },
  },
  opts = {
    keymap_cword = "<leader>sm",
    keymap_visual = "<leader>sm",
    keymap_prompt = "<leader>sM",
    keymap_stop = false,
    keymap_repeat = false,
  },
}
