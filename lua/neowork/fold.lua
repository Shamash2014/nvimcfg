local M = {}

M._cache = {}
M._autofolded = {}
M._auto_closed = {}

local ast = require("neowork.ast")

local function role_start(line)
  return ast.role_of_line(line) ~= nil
end

local function tool_start(line)
  return ast.tool_id_of_line(line) ~= nil
end

local function parse_detail_header(line)
  if type(line) ~= "string" then return nil end
  local tag, rest = line:match("^#### %[([^%]]+)%] (.+)$")
  if not tag then return nil end
  local title, meta = rest, nil
  local sep = rest:find(" -- ", 1, true)
  if sep then
    title = rest:sub(1, sep - 1)
    meta = rest:sub(sep + 4)
  end
  return {
    tag = tag,
    title = title,
    meta = meta,
  }
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

  if cfg.tool_output ~= false then
    local i = (fm_end or 0) + 1
    while i <= total do
      if tool_start(lines[i]) then
        local start_l = i
        local j = i + 1
        while j <= total do
          if not ast.is_blockquote(lines[j]) then break end
          j = j + 1
        end
        local end_l = j - 1
        if end_l > start_l then
          levels[start_l] = ">2"
          for k = start_l + 1, end_l do
            levels[k] = "2"
          end
          if levels[end_l + 1] == "=" then
            levels[end_l + 1] = "1"
          end
        end
        i = j
      else
        i = i + 1
      end
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

function M.foldtext()
  local fs = vim.v.foldstart
  local fe = vim.v.foldend
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, fs - 1, fs, false)
  local header = lines[1] or ""
  local count = fe - fs
  local detail = parse_detail_header(header)
  if detail then
    local prefix = "▸ " .. detail.tag
    local body = detail.title or ""
    if detail.meta and detail.meta ~= "" then
      body = body .. "  ·  " .. detail.meta
    end
    return prefix .. "  " .. body .. "  (" .. count .. " lines)"
  end
  return header .. "  … " .. count .. " lines"
end

function M.attach_window(buf)
  local desired_expr = "v:lua.require'neowork.fold'.expr(v:lnum)"
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) and vim.wo[win].foldexpr ~= desired_expr then
      vim.wo[win].foldmethod = "expr"
      vim.wo[win].foldexpr = desired_expr
      vim.wo[win].foldtext = "v:lua.require'neowork.fold'.foldtext()"
      vim.wo[win].foldenable = true
      vim.wo[win].foldlevel = 1
    end
  end

  if not M._autofolded[buf] then
    local document = require("neowork.document")
    local config = require("neowork.config")
    local cfg = config.get("folds") or {}
    local fm_end = document.get_fm_end and document.get_fm_end(buf) or 0
    if fm_end > 0 and cfg.frontmatter ~= false then
      M._autofolded[buf] = true
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_call, win, function()
              vim.cmd("silent! 1foldclose")
            end)
          end
        end
      end)
    end
  end
end

local function safe_foldclose(winid, start_lnum, end_lnum)
  local level = vim.api.nvim_win_call(winid, function()
    return vim.fn.foldlevel(start_lnum)
  end)
  if not level or level < 2 then return false end
  local closed = vim.api.nvim_win_call(winid, function()
    return vim.fn.foldclosed(start_lnum)
  end)
  if closed ~= -1 then return true end
  vim.fn.win_execute(winid, string.format("silent! %d,%d foldclose", start_lnum, end_lnum))
  local verified = vim.api.nvim_win_call(winid, function()
    return vim.fn.foldclosed(start_lnum)
  end)
  return verified ~= -1
end

function M.close_tool_folds(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local winid
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(w) then winid = w; break end
  end
  if not winid then return end

  local turn = ast.active_djinni_turn(buf)
  if not turn then return end

  local items = ast.tool_items(buf, turn)
  if #items == 0 then return end

  M._auto_closed[buf] = M._auto_closed[buf] or {}
  local closed = M._auto_closed[buf]

  for _, item in ipairs(items) do
    if not closed[item.tool_id] then
      local s, e = ast.find_tool_block(buf, item.tool_id)
      if s and e and e > s then
        if safe_foldclose(winid, s, e) then
          closed[item.tool_id] = true
        end
      end
    end
  end
end

function M.detach(buf)
  M._cache[buf] = nil
  M._autofolded[buf] = nil
  M._auto_closed[buf] = nil
end

function M.invalidate(buf)
  M._cache[buf] = nil
end

return M
