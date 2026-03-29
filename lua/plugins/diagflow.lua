return {
  "dgagn/diagflow.nvim",
  event = { "LspAttach", "BufReadPost" },
  opts = {
    scope = "line",
    show_sign = false,
    placement = "top",
    format = function(diagnostic)
      local parts = { diagnostic.message }
      if diagnostic.source then
        table.insert(parts, 1, "[" .. diagnostic.source .. "]")
      end
      if diagnostic.code then
        parts[#parts] = parts[#parts] .. " (" .. tostring(diagnostic.code) .. ")"
      end
      return table.concat(parts, " ")
    end,
  },
}
