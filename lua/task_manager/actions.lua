local M = {}

function M.add_card(board, col_idx, title)
  local col = board.columns[col_idx]
  if not col then return end
  table.insert(col.cards, {
    title = title,
    description = "",
    priority = nil,
    tags = {},
    due = nil,
    done = nil,
    created = os.date("%Y-%m-%d"),
    checkbox = " ",
  })
end

function M.delete_card(board, col_idx, card_idx)
  local col = board.columns[col_idx]
  if not col then return end
  table.remove(col.cards, card_idx)
end

function M.move_card(board, from_col, card_idx, to_col)
  local src = board.columns[from_col]
  local dst = board.columns[to_col]
  if not src or not dst then return end
  local card = table.remove(src.cards, card_idx)
  if not card then return end

  if to_col == 4 then
    card.checkbox = "x"
    card.done = os.date("%Y-%m-%d")
  elseif to_col == 3 then
    card.checkbox = "~"
    card.done = nil
  else
    card.checkbox = " "
    card.done = nil
  end

  table.insert(dst.cards, card)
  return card
end

function M.set_priority(card, priority)
  if priority == "none" or priority == "" then
    card.priority = nil
  else
    card.priority = priority
  end
end

function M.add_tag(card, tag)
  card.tags = card.tags or {}
  for _, t in ipairs(card.tags) do
    if t == tag then return end
  end
  table.insert(card.tags, tag)
end

function M.remove_tag(card, tag)
  card.tags = card.tags or {}
  for i, t in ipairs(card.tags) do
    if t == tag then
      table.remove(card.tags, i)
      return
    end
  end
end

function M.set_due(card, due_str)
  if not due_str or due_str == "" or due_str == "none" then
    card.due = nil
    return
  end

  local num, unit = due_str:match("^%+(%d+)([dwm])$")
  if num then
    num = tonumber(num)
    local now = os.time()
    local seconds = 0
    if unit == "d" then seconds = num * 86400
    elseif unit == "w" then seconds = num * 7 * 86400
    elseif unit == "m" then seconds = num * 30 * 86400
    end
    card.due = os.date("%Y-%m-%d", now + seconds)
  else
    card.due = due_str
  end
end

function M.set_description(card, desc)
  card.description = desc or ""
end

function M.update_title(card, title)
  card.title = title or card.title
end

return M
