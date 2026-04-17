local M = {}

M._cache = {}

local function role_start(line)
  if not line then return false end
  return line:match("^@You") or line:match("^@Djinni") or line:match("^@System")
end

local function build(buf)
  local total = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local levels = {}

  local document = require("neowork.document")
  local config = require("neowork.config")
  local cfg = config.get("folds") or {}

  local fm_end = document.get_fm_end and document.get_fm_end(buf) or 0

  for i = 1, total do
    levels[i] = "="
  end

  if fm_end and fm_end > 0 and cfg.frontmatter ~= false then
    levels[1] = ">1"
    for i = 2, fm_end do levels[i] = "1" end
    if levels[fm_end + 1] then levels[fm_end + 1] = "0" end
  end

  for i = (fm_end or 0) + 1, total do
    if role_start(lines[i]) then
      levels[i] = ">1"
    end
  end

  return levels
end

local function get(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = M._cache[buf]
  if c and c.tick == tick then return c.levels end
  local levels = build(buf)
  M._cache[buf] = { tick = tick, levels = levels }
  return levels
end

function M.expr(lnum)
  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return "0" end
  local levels = get(buf)
  return levels[lnum] or "="
end

function M.attach_window(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].foldmethod = "expr"
      vim.wo[win].foldexpr = "v:lua.require'neowork.fold'.expr(v:lnum)"
    end
  end
end

function M.detach(buf)
  M._cache[buf] = nil
end

function M.invalidate(buf)
  M._cache[buf] = nil
end

return M
