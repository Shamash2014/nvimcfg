local M = {}

function M.serialize(board)
  local lines = {}
  table.insert(lines, "# " .. (board.title or "Default Board"))
  table.insert(lines, "")

  for _, col in ipairs(board.columns) do
    table.insert(lines, "## " .. col.name)
    table.insert(lines, "")

    for _, card in ipairs(col.cards) do
      local checkbox = " "
      if card.checkbox == "x" then
        checkbox = "x"
      elseif card.checkbox == "~" then
        checkbox = "~"
      end

      local meta_parts = {}
      if card.priority then
        table.insert(meta_parts, "@priority:" .. card.priority)
      end
      for _, tag in ipairs(card.tags or {}) do
        table.insert(meta_parts, "@tag:" .. tag)
      end

      local title_line = string.format("- [%s] %s", checkbox, card.title)
      if #meta_parts > 0 then
        title_line = title_line .. " " .. table.concat(meta_parts, " ")
      end
      table.insert(lines, title_line)

      if card.description and card.description ~= "" then
        for _, desc_line in ipairs(vim.split(card.description, "\n")) do
          table.insert(lines, "  " .. desc_line)
        end
      end

      if card.due then
        table.insert(lines, "  @due:" .. card.due)
      end
      if card.done then
        table.insert(lines, "  @done:" .. card.done)
      end
      if card.created then
        table.insert(lines, "  @created:" .. card.created)
      end

      table.insert(lines, "")
    end

    if #col.cards == 0 then
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

return M
