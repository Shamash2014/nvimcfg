return {
  "cappyzawa/trim.nvim",
  event = "BufWritePre",
  opts = {
    trim_on_write = true,
    trim_trailing = true,
    trim_last_line = false,
    trim_first_line = false,
    ft_blocklist = {
      "markdown",
      "text",
      "rst",
      "org",
      "tex",
    },
    patterns = {
      [[%s/\s\+$//e]],
      [[%s/\($\n\s*\)\+\%$//]],
    },
    highlight = false,
  }
}