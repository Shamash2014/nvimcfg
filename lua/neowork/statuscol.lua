local M = {}

M._cache = {}

local CHAR_TOP = "╭"
local CHAR_MIDDLE = "│"
local CHAR_BOTTOM = "╰"
local EMPTY = " "

local ROLE_HL = {
  You = "NeoworkYou",
  Djinni = "NeoworkDjinni",
  System = "NeoworkSystem",
}

local function role_of(line)
  if not line then return nil end
  if line:match("^@You") then return "You" end
  if line:match("^@Djinni") then return "Djinni" end
  if line:match("^@System") then return "System" end
  return nil
end

local function build(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local total = #lines
  local positions = {}

  local i = 1
  while i <= total do
    local role = role_of(lines[i])
    if role then
      local j = i + 1
      while j <= total do
        if role_of(lines[j]) then break end
        j = j + 1
      end
      local e = j - 1
      while e > i and (lines[e] == nil or lines[e] == "") do
        e = e - 1
      end

      if e == i then
        positions[i] = { char = CHAR_TOP, role = role }
      else
        positions[i] = { char = CHAR_TOP, role = role }
        for k = i + 1, e - 1 do
          positions[k] = { char = CHAR_MIDDLE, role = role }
        end
        positions[e] = { char = CHAR_BOTTOM, role = role }
      end
      i = j
    else
      i = i + 1
    end
  end

  return positions
end

local function get(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = M._cache[buf]
  if c and c.tick == tick then return c.positions end
  local positions = build(buf)
  M._cache[buf] = { tick = tick, positions = positions }
  return positions
end

function M.expr()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.b[buf].neowork_chat then return "" end
  if not vim.api.nvim_buf_is_valid(buf) then return "" end

  local lnum = vim.v.lnum
  local positions = get(buf)
  local pos = positions[lnum]
  if not pos then return EMPTY end

  local hl = ROLE_HL[pos.role] or "NeoworkSeparator"
  return string.format("%%#%s#%s%%*", hl, pos.char)
end

function M.attach_window(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].statuscolumn = "%!v:lua.require'neowork.statuscol'.expr()"
      vim.wo[win].signcolumn = "no"
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
    end
  end
end

function M.invalidate(buf)
  M._cache[buf] = nil
end

function M.detach(buf)
  M._cache[buf] = nil
end

return M
