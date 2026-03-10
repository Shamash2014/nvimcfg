local M = {}

local ns_id = vim.api.nvim_create_namespace("TaskManager")

local COLUMN_NAMES = { "NOT NOW", "MAYBE", "IN PROGRESS", "DONE" }
local STATUS_ICONS = { [" "] = "○", ["~"] = "◐", ["x"] = "●" }

local PRIORITY_HL = {
  high = "DiagnosticError",
  medium = "DiagnosticWarn",
  low = "DiagnosticOk",
}

local function pad(str, width)
  local display_len = vim.fn.strdisplaywidth(str)
  if display_len >= width then
    return str:sub(1, width)
  end
  return str .. string.rep(" ", width - display_len)
end

local function truncate(str, width)
  if vim.fn.strdisplaywidth(str) <= width then return str end
  local result = ""
  local byte = 1
  local str_len = #str
  while byte <= str_len do
    local char_len = vim.str_utf_end(str, byte)
    if type(char_len) ~= "number" then break end
    char_len = char_len + 1
    local ch = str:sub(byte, byte + char_len - 1)
    local new_width = vim.fn.strdisplaywidth(result .. ch)
    if new_width >= width then break end
    result = result .. ch
    byte = byte + char_len
  end
  return result .. "…"
end

function M.render(buf, board, board_state)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then return end
  local total_width = vim.api.nvim_win_get_width(wins[1])

  local num_cols = #board.columns
  local col_width = math.floor((total_width - num_cols - 1) / num_cols)
  if col_width < 15 then col_width = 15 end

  local card_map = {}
  local lines = {}
  local highlights = {}

  local function add_hl(line_idx, col_start, col_end, hl_group)
    table.insert(highlights, { line_idx, col_start, col_end, hl_group })
  end

  local function make_border(left, mid, right)
    local parts = {}
    for _ = 1, num_cols do
      table.insert(parts, string.rep("─", col_width))
    end
    return left .. table.concat(parts, mid) .. right
  end

  local top_border = make_border("╭", "┬", "╮")
  local header_sep = make_border("├", "┼", "┤")
  local bottom_border = make_border("╰", "┴", "╯")

  table.insert(lines, top_border)
  add_hl(0, 0, #top_border, "FloatBorder")

  local sep = "│"
  local header = sep
  for i, col in ipairs(board.columns) do
    local name = COLUMN_NAMES[i] or col.name:upper()
    local count = #col.cards
    local label = string.format(" %s (%d) ", name, count)
    header = header .. pad(label, col_width) .. sep
  end
  table.insert(lines, header)
  local hline = #lines - 1
  add_hl(hline, 0, #header, "Title")

  table.insert(lines, header_sep)
  add_hl(#lines - 1, 0, #header_sep, "FloatBorder")

  local col_card_rows = {}
  for ci, col in ipairs(board.columns) do
    col_card_rows[ci] = {}
    for card_idx, card in ipairs(col.cards) do
      local icon = STATUS_ICONS[card.checkbox] or "○"
      local title_str = string.format(" %s %s", icon, truncate(card.title, col_width - 5))
      table.insert(col_card_rows[ci], {
        text = title_str,
        type = "title",
        card = card,
        col_idx = ci,
        card_idx = card_idx,
      })

      local meta = {}
      if card.priority then
        table.insert(meta, card.priority:sub(1, 3))
      end
      for _, tag in ipairs(card.tags or {}) do
        table.insert(meta, tag)
      end
      if #meta > 0 then
        table.insert(col_card_rows[ci], {
          text = "   " .. table.concat(meta, " "),
          type = "meta",
          card = card,
          col_idx = ci,
          card_idx = card_idx,
        })
      end

      if card.due then
        table.insert(col_card_rows[ci], {
          text = "   due:" .. card.due,
          type = "due",
          card = card,
          col_idx = ci,
          card_idx = card_idx,
        })
      end

      table.insert(col_card_rows[ci], {
        text = "",
        type = "spacer",
        col_idx = ci,
        card_idx = card_idx,
      })
    end
  end

  local max_rows = 0
  for _, rows in ipairs(col_card_rows) do
    if #rows > max_rows then max_rows = #rows end
  end
  if max_rows < 3 then max_rows = 3 end

  for row = 1, max_rows do
    local line = sep
    local line_idx = #lines

    for ci = 1, num_cols do
      local cell = col_card_rows[ci] and col_card_rows[ci][row]
      local cell_text = cell and cell.text or ""
      local padded = pad(cell_text, col_width)
      line = line .. padded .. sep

      if cell and cell.type ~= "spacer" then
        card_map[line_idx + 1] = card_map[line_idx + 1] or {}
        card_map[line_idx + 1][ci] = {
          col_idx = cell.col_idx,
          card_idx = cell.card_idx,
          card = cell.card,
          type = cell.type,
        }

        local byte_start = 1 + (ci - 1) * (col_width + 1)
        local byte_end = byte_start + col_width

        if cell.type == "title" then
          local hl = "Normal"
          if cell.card.checkbox == "x" then hl = "Comment" end
          add_hl(line_idx, byte_start, byte_end, hl)
        elseif cell.type == "meta" then
          local hl = PRIORITY_HL[cell.card.priority] or "Comment"
          add_hl(line_idx, byte_start, byte_end, hl)
        elseif cell.type == "due" then
          add_hl(line_idx, byte_start, byte_end, "DiagnosticInfo")
        end
      end
    end

    table.insert(lines, line)
  end

  table.insert(lines, bottom_border)
  add_hl(#lines - 1, 0, #bottom_border, "FloatBorder")

  local active = 0
  local done_count = 0
  for _, col in ipairs(board.columns) do
    for _, card in ipairs(col.cards) do
      if card.checkbox == "x" then
        done_count = done_count + 1
      else
        active = active + 1
      end
    end
  end

  local board_name = board_state and board_state.board_name or "default"
  local footer = string.format("  Board: %s%s%d active, %d done",
    board_name,
    string.rep(" ", math.max(1, total_width - 30 - #board_name)),
    active, done_count)
  table.insert(lines, footer)
  add_hl(#lines - 1, 0, #footer, "Comment")

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
    local line_text = lines[hl[1] + 1] or ""
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, hl[1], math.min(hl[2], #line_text), {
      end_col = math.min(hl[3], #line_text),
      hl_group = hl[4],
    })
  end

  return {
    card_map = card_map,
    col_width = col_width,
    num_cols = num_cols,
    header_lines = 3,
    footer_line = #lines,
  }
end

return M
