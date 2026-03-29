return {
  "dgagn/diagflow.nvim",
  event = { "LspAttach", "BufReadPost" },
  opts = {
    scope = "line",
    show_sign = false,
    placement = "top",
    format = function(diagnostic)
      return diagnostic.message
    end,
  },
}
