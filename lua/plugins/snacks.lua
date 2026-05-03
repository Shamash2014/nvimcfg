return {
  {
    src = "https://github.com/folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    config = function()
      require("snacks").setup({
        bigfile = { enabled = true },
        dashboard = { enabled = false },
        explorer = { enabled = true, replace_netrw = true },
        indent = { enabled = true },
        input = { enabled = true },
        notifier = { enabled = true, timeout = 2500 },
        picker = {
          enabled = true,
          layout = {
            preset = "vscode",
            preview = false,
          },
          formatters = {
            file = {
              git_status_hl = false,
            },
          },
          win = {
            input = {
              keys = {
                ["<C-j>"] = { "list_down", mode = { "i", "n" } },
                ["<C-k>"] = { "list_up", mode = { "i", "n" } },
                ["<C-q>"] = { "qf", mode = { "i", "n" } },
              },
            },
            list = {
              keys = {
                ["<C-j>"] = "list_down",
                ["<C-k>"] = "list_up",
                ["<C-q>"] = "qf",
              },
            },
          },
        },
        quickfile = { enabled = true },
        scope = { enabled = true },
        scroll = { enabled = true },
        statuscolumn = { enabled = true },
        terminal = { enabled = true },
        words = { enabled = true },
      })
    end,
  },
}
