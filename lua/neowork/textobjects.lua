local M = {}

local util = require("neowork.util")

local function ts_root(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if not ok or not parser then return nil end
  local trees = parser:parse()
  if not trees or not trees[1] then return nil end
  return trees[1]:root()
end

local function ts_nodes(buf, query_str)
  local root = ts_root(buf)
  if not root then return nil end
  local ok, query = pcall(vim.treesitter.query.parse, "markdown", query_str)
  if not ok or not query then return nil end
  local out = {}
  for _, node in query:iter_captures(root, buf, 0, -1) do
    out[#out + 1] = node
  end
  return out
end

local function role_line_rows(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local rows = {}
  for i, l in ipairs(lines) do
    if util.is_role_line(l) then rows[#rows + 1] = i end
  end
  return rows, lines
end

local function turn_bounds_ts(buf, cursor_row)
  local rows, lines = role_line_rows(buf)
  if #rows == 0 then return nil end

  local start_row
  for i = #rows, 1, -1 do
    if rows[i] <= cursor_row then start_row = rows[i]; break end
  end
  if not start_row then return nil end

  local breaks = ts_nodes(buf, "(thematic_break) @b")
  local next_role = nil
  for _, r in ipairs(rows) do
    if r > start_row then next_role = r; break end
  end

  local stop_row = #lines
  if breaks then
    for _, n in ipairs(breaks) do
      local br = n:start() + 1
      if br > start_row and (not next_role or br < next_role) then
        stop_row = math.min(stop_row, br - 1)
        break
      end
    end
  end
  if next_role then stop_row = math.min(stop_row, next_role - 1) end

  return start_row, stop_row, lines
end

local function select_range(s, e)
  vim.api.nvim_win_set_cursor(0, { s, 0 })
  vim.cmd("normal! V")
  vim.api.nvim_win_set_cursor(0, { e, 0 })
end

local function select_turn(inner)
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local s, e, lines = turn_bounds_ts(buf, row)
  if not s then return end
  if inner then
    s = s + 1
    while e > s and vim.trim(lines[e] or "") == "" do e = e - 1 end
    if s > e then return end
  end
  select_range(s, e)
end

local function select_code_block(inner)
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local root = ts_root(buf)
  if not root then return end
  local ok, query = pcall(vim.treesitter.query.parse, "markdown", "(fenced_code_block) @b")
  if not ok or not query then return end
  local hit
  for _, node in query:iter_captures(root, buf, 0, -1) do
    local sr, _, er, _ = node:range()
    if row >= sr and row <= er then hit = { sr + 1, er } break end
  end
  if not hit then return end
  local s, e = hit[1], hit[2]
  if inner then s = s + 1; e = e - 1 end
  if s > e then return end
  select_range(s, e)
end

local function select_plan_entry(inner)
  local buf = vim.api.nvim_get_current_buf()
  local ok_plan, plan = pcall(require, "neowork.plan")
  if not ok_plan then return end
  local section = plan._section_lines and plan._section_lines[buf]
  if not section then return end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  if row <= section.start or row > section["end"] then return end

  local root = ts_root(buf)
  if root then
    local ok, query = pcall(vim.treesitter.query.parse, "markdown", "(list_item) @i")
    if ok and query then
      local hit
      for _, node in query:iter_captures(root, buf, section.start, section["end"]) do
        local sr, _, er, _ = node:range()
        if row - 1 >= sr and row - 1 <= er then hit = { sr + 1, er } break end
      end
      if hit then
        local s, e = hit[1], hit[2]
        if inner then
          local line = vim.api.nvim_buf_get_lines(buf, s - 1, s, false)[1] or ""
          local col = line:find("%]")
          if col then
            while col < #line and line:sub(col + 1, col + 1) == " " do col = col + 1 end
            vim.api.nvim_win_set_cursor(0, { s, col })
            vim.cmd("normal! v")
            vim.api.nvim_win_set_cursor(0, { e, #(vim.api.nvim_buf_get_lines(buf, e - 1, e, false)[1] or "") })
            return
          end
        end
        select_range(s, e)
        return
      end
    end
  end

  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  if not line:match("^%- %[") then return end
  if inner then
    local col = line:find("%]")
    if not col then return end
    while col < #line and line:sub(col + 1, col + 1) == " " do col = col + 1 end
    if col >= #line then return end
    vim.api.nvim_win_set_cursor(0, { row, col })
    vim.cmd("normal! v$")
    if vim.fn.col(".") > col + 1 then vim.cmd("normal! h") end
  else
    select_range(row, row)
  end
end

function M.setup(buf)
  local opts = { buffer = buf, silent = true, nowait = true }
  local function m(lhs, fn, desc)
    vim.keymap.set({ "o", "x" }, lhs, fn, vim.tbl_extend("force", opts, { desc = "neowork: " .. desc }))
  end
  m("a@", function() select_turn(false) end, "a turn")
  m("i@", function() select_turn(true) end, "inner turn")
  m("ac", function() select_code_block(false) end, "a code block")
  m("ic", function() select_code_block(true) end, "inner code block")
  m("ap", function() select_plan_entry(false) end, "a plan entry")
  m("ip", function() select_plan_entry(true) end, "inner plan entry")
end

return M
