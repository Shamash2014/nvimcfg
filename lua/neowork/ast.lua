---@class neowork.ast.Turn
---@field role "You"|"System"|"Djinni"
---@field start_line integer     -- 1-based row of the `# Role` heading
---@field end_line integer       -- 1-based row of last line belonging to this turn
---@field content_start integer  -- 1-based row of first content line (header row + 1)
---@field is_compose boolean     -- true iff last `# You` in document
---@field is_open boolean        -- true iff last `# Djinni` in document (actively streaming)
---@field is_last boolean

---@class neowork.ast.ToolItem
---@field row integer        -- 1-based row of the list item
---@field tool_id string
---@field line string        -- raw buffer line at `row`

---@class neowork.ast.Snapshot
---@field tick integer
---@field lines string[]
---@field fm table<string,string>
---@field fm_end integer
---@field turns neowork.ast.Turn[]

local M = {}

local ROLE_HEADING = "^#%s(%w+)%s*$"
local ROLE_VALID = { You = true, Djinni = true, System = true }
local FM_DELIM = "^%-%-%-%s*$"
local FM_KEY = "^(%w[%w_-]*):%s*(.*)$"
local SUMMARY_HEADING = "^#%s*Summary%s*$"
local TOP_HEADING = "^#%s*[^#%s].*$"
local TOOL_HEADER = "^#### %[([^%]]+)%] "
local BLOCKQUOTE = "^>"
local THEMATIC = "^[%-_%*][%-_%*][%-_%*]+%s*$"

---@param line string
---@return string|nil role
function M.role_of_line(line)
  if not line then return nil end
  local role = line:match(ROLE_HEADING)
  if role and ROLE_VALID[role] then return role end
  return nil
end

local match_role = M.role_of_line

---@param line string
---@return string
function M.escape_role_line(line)
  if not line or line:byte(1) ~= 35 then return line end
  if M.role_of_line(line) ~= nil then
    return "\\" .. line
  end
  return line
end

---@param line string
---@return string|nil tool_id
function M.tool_id_of_line(line)
  if not line then return nil end
  return line:match(TOOL_HEADER)
end

---@param line string
---@return boolean
function M.is_blockquote(line)
  if not line then return false end
  return line:match(BLOCKQUOTE) ~= nil
end

---@param line string
---@return boolean
function M.is_thematic(line)
  if not line then return false end
  return line:match(THEMATIC) ~= nil
end

---@param lines string[]
---@return table<string,string> fm, integer fm_end
local function parse_frontmatter(lines)
  if #lines == 0 or not lines[1]:match(FM_DELIM) then
    return {}, 0
  end
  local fm = {}
  for i = 2, #lines do
    if lines[i]:match(FM_DELIM) then
      return fm, i
    end
    local k, v = lines[i]:match(FM_KEY)
    if k then fm[k] = v end
  end
  return fm, 0
end

---@param lines string[]
---@param fm_end integer
---@return neowork.ast.Turn[]
local function parse_turns(lines, fm_end)
  local turns = {}
  local current
  for i = fm_end + 1, #lines do
    local role = match_role(lines[i])
    if role then
      if current then
        current.end_line = i - 1
        table.insert(turns, current)
      end
      current = { role = role, start_line = i, content_start = i + 1 }
    end
  end
  if current then
    current.end_line = #lines
    table.insert(turns, current)
  end
  local last_you, last_djinni
  for idx, t in ipairs(turns) do
    t.is_last = (idx == #turns)
    t.is_compose = false
    t.is_open = false
    if t.role == "You" then last_you = idx end
    if t.role == "Djinni" then last_djinni = idx end
  end
  if last_you and turns[last_you].is_last then
    turns[last_you].is_compose = true
  end
  if last_djinni then
    local dt = turns[last_djinni]
    local is_open = dt.is_last
    if not is_open then
      is_open = true
      for j = last_djinni + 1, #turns do
        local tj = turns[j]
        if tj.role ~= "System" and not (tj.role == "You" and tj.is_compose) then
          is_open = false
          break
        end
      end
    end
    dt.is_open = is_open
  end
  return turns
end

M._cache = {}

---@param buf integer
---@return neowork.ast.Snapshot
local function snapshot(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = M._cache[buf]
  if c and c.tick == tick then return c end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fm, fm_end = parse_frontmatter(lines)
  local turns = parse_turns(lines, fm_end)
  c = { tick = tick, lines = lines, fm = fm, fm_end = fm_end, turns = turns }
  M._cache[buf] = c
  return c
end

---@param buf integer
function M.invalidate(buf)
  M._cache[buf] = nil
end

---@param buf integer
---@return table<string,string> fields, integer fm_end_row
function M.frontmatter(buf)
  local s = snapshot(buf)
  return s.fm, s.fm_end
end

---@param buf integer
---@return integer  -- 1-based row of closing `---` of frontmatter, or 0
function M.frontmatter_end(buf)
  return snapshot(buf).fm_end
end

---@param buf integer
---@param key string
---@return string|nil
function M.read_frontmatter_field(buf, key)
  return snapshot(buf).fm[key]
end

---@param buf integer
---@return { heading_line: integer, content_start: integer, content_end: integer, next_heading_line: integer|nil }|nil
function M.summary_section(buf)
  local s = snapshot(buf)
  local heading_line
  for i = s.fm_end + 1, #s.lines do
    if s.lines[i]:match(SUMMARY_HEADING) then
      heading_line = i
      break
    end
  end
  if not heading_line then return nil end

  local next_heading_line
  for i = heading_line + 1, #s.lines do
    if s.lines[i]:match(TOP_HEADING) then
      next_heading_line = i
      break
    end
  end

  local content_start = heading_line + 1
  local content_end = (next_heading_line or (#s.lines + 1)) - 1
  while content_end >= content_start and s.lines[content_end] == "" do
    content_end = content_end - 1
  end

  return {
    heading_line = heading_line,
    content_start = content_start,
    content_end = content_end,
    next_heading_line = next_heading_line,
  }
end

---@param buf integer
---@return neowork.ast.Turn[]
function M.turns(buf)
  return snapshot(buf).turns
end

---@param buf integer
---@return neowork.ast.Turn|nil
function M.active_djinni_turn(buf)
  local turns = snapshot(buf).turns
  for i = #turns, 1, -1 do
    if turns[i].role == "Djinni" and turns[i].is_open then
      return turns[i]
    end
  end
  return nil
end

---@param buf integer
---@return neowork.ast.Turn|nil
function M.compose_turn(buf)
  local turns = snapshot(buf).turns
  for i = #turns, 1, -1 do
    if turns[i].role == "You" and turns[i].is_compose then
      return turns[i]
    end
  end
  return nil
end

---@param buf integer
---@param turn neowork.ast.Turn
---@return integer|nil  -- 1-based insertion row at end of turn content
function M.append_row_for_turn(buf, turn)
  if not turn then return nil end
  local s = snapshot(buf)
  local row = math.min(turn.end_line, #s.lines)
  while row >= turn.content_start do
    local line = s.lines[row]
    if line and line ~= "" and not line:match(THEMATIC) then break end
    row = row - 1
  end
  local insert = row + 1
  if insert > turn.end_line + 1 then insert = turn.end_line + 1 end
  if insert < turn.content_start then insert = turn.content_start end
  return insert
end

---@param buf integer
---@return integer|nil  -- 1-based insertion row for the next streamed agent line
function M.insertion_row_for_streaming(buf)
  local s = snapshot(buf)
  local turn
  for i = #s.turns, 1, -1 do
    if s.turns[i].role == "Djinni" and s.turns[i].is_open then turn = s.turns[i]; break end
  end
  if not turn then return nil end
  return M.append_row_for_turn(buf, turn)
end

---@param buf integer
---@param tool_id string
---@return integer|nil
function M.find_tool_row(buf, tool_id)
  local s = snapshot(buf)
  local needle = "#### [" .. tool_id .. "] "
  for i, line in ipairs(s.lines) do
    if line:find(needle, 1, true) then return i end
  end
  return nil
end

---@param buf integer
---@param tool_id string
---@return integer|nil row_start, integer|nil row_end
function M.find_tool_block(buf, tool_id)
  local s = snapshot(buf)
  local needle = "#### [" .. tool_id .. "] "
  local start
  for i = #s.lines, 1, -1 do
    local line = s.lines[i]
    if line and line:find(needle, 1, true) then start = i; break end
  end
  if not start then return nil, nil end
  local turn
  for _, t in ipairs(s.turns) do
    if start >= t.start_line and start <= t.end_line then turn = t; break end
  end
  if not turn then return start, start end
  local stop = start
  for i = start + 1, turn.end_line do
    local line = s.lines[i]
    if line and line:match(TOOL_HEADER) then break end
    stop = i
  end
  while stop > start and (s.lines[stop] == "" or not s.lines[stop]) do stop = stop - 1 end
  return start, stop
end

---@param buf integer
---@param turn neowork.ast.Turn
---@return neowork.ast.ToolItem[]
function M.tool_items(buf, turn)
  if not turn then return {} end
  local s = snapshot(buf)
  local items = {}
  for i = turn.content_start, turn.end_line do
    local line = s.lines[i]
    if line then
      local tid = line:match(TOOL_HEADER)
      if tid then
        table.insert(items, { row = i, tool_id = tid, line = line })
      end
    end
  end
  return items
end

---@param buf integer
---@param lnum integer 1-based
---@return neowork.ast.Turn|nil
function M.turn_at_line(buf, lnum)
  for _, t in ipairs(snapshot(buf).turns) do
    if lnum >= t.start_line and lnum <= t.end_line then
      return t
    end
  end
  return nil
end

---@param buf integer
---@return boolean ok, string|nil reason
function M.check_invariant(buf)
  local turns = snapshot(buf).turns
  if #turns == 0 then return true, nil end
  local last = turns[#turns]
  if last.role ~= "You" or not last.is_compose then
    return false, "last turn must be compose You, got " .. tostring(last.role)
  end
  local open_count = 0
  local open_idx
  for i, t in ipairs(turns) do
    if t.role == "Djinni" and t.is_open then
      open_count = open_count + 1
      open_idx = i
    end
  end
  if open_count > 1 then
    return false, "more than one open Djinni"
  end
  if open_idx then
    for j = open_idx + 1, #turns - 1 do
      if turns[j].role ~= "System" then
        return false, "open Djinni must be followed only by System turns and the compose You"
      end
    end
  end
  return true, nil
end

---@param buf integer
---@param context string|nil
function M.assert_invariant(buf, context)
  if not vim.g.neowork_debug then return end
  local ok, reason = M.check_invariant(buf)
  if not ok then
    vim.notify("neowork invariant: " .. (context or "?") .. " — " .. reason, vim.log.levels.WARN)
  end
end

return M
