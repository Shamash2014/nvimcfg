local M = {}

local COLUMNS = { "Not Now", "Maybe", "In Progress", "Done" }

function M.parse(content)
  local board = {
    title = "Default Board",
    columns = {},
  }

  for _, col_name in ipairs(COLUMNS) do
    table.insert(board.columns, { name = col_name, cards = {} })
  end

  if not content or content == "" then
    return board
  end

  local lines = vim.split(content, "\n")
  local current_col = nil
  local current_card = nil

  for _, line in ipairs(lines) do
    local h1 = line:match("^#%s+(.+)$")
    if h1 then
      board.title = h1
      goto continue
    end

    local h2 = line:match("^##%s+(.+)$")
    if h2 then
      current_col = nil
      for _, col in ipairs(board.columns) do
        if col.name == h2 then
          current_col = col
          break
        end
      end
      current_card = nil
      goto continue
    end

    if not current_col then
      goto continue
    end

    local checkbox, rest = line:match("^%- %[([%s~x])%]%s+(.+)$")
    if checkbox and rest then
      local title = rest
      local priority = nil
      local tags = {}
      local due = nil
      local done = nil
      local created = nil

      title = title:gsub("@priority:(%S+)", function(v) priority = v; return "" end)
      title = title:gsub("@tag:(%S+)", function(v) table.insert(tags, v); return "" end)
      title = title:gsub("@due:(%S+)", function(v) due = v; return "" end)
      title = title:gsub("@done:(%S+)", function(v) done = v; return "" end)
      title = title:gsub("@created:(%S+)", function(v) created = v; return "" end)
      title = vim.trim(title)

      current_card = {
        title = title,
        description = "",
        priority = priority,
        tags = tags,
        due = due,
        done = done,
        created = created or os.date("%Y-%m-%d"),
        checkbox = checkbox,
      }
      table.insert(current_col.cards, current_card)
      goto continue
    end

    if current_card then
      local indented = line:match("^  (.+)$")
      if indented then
        local meta_key, meta_val = indented:match("^@(%S+):(%S+)$")
        if meta_key and meta_val then
          if meta_key == "due" then current_card.due = meta_val
          elseif meta_key == "done" then current_card.done = meta_val
          elseif meta_key == "created" then current_card.created = meta_val
          elseif meta_key == "priority" then current_card.priority = meta_val
          elseif meta_key == "tag" then table.insert(current_card.tags, meta_val)
          end
        else
          if current_card.description ~= "" then
            current_card.description = current_card.description .. "\n"
          end
          current_card.description = current_card.description .. vim.trim(indented)
        end
      elseif line == "" then
        current_card = nil
      end
    end

    ::continue::
  end

  return board
end

return M
