return {
  "nvim-treesitter/nvim-treesitter-context",
  event = "VeryLazy",
  dependencies = "nvim-treesitter/nvim-treesitter",
  opts = {
    enable = true,
    max_lines = 3,
    min_window_height = 0,
    line_numbers = true,
    multiline_threshold = 20,
    line_timeout = 200,
    trim_scope = 'outer',
    mode = 'cursor',
    zindex = 20,
  },
}
