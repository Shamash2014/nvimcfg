local M = {}

M._cache = {}

local function role_start(line)
  if not line then return false end
  return line:match("^@You") or line:match("^@Djinni") or line:match("^@System")
end

local function tool_start(line)
  if not line then return false end
  return line:match("^#### %[[^%]]+%] ") ~= nil
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
        while j <= total and not tool_start(lines[j]) and not role_start(lines[j]) do
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
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].foldmethod = "expr"
      vim.wo[win].foldexpr = "v:lua.require'neowork.fold'.expr(v:lnum)"
      vim.wo[win].foldtext = "v:lua.require'neowork.fold'.foldtext()"
      vim.wo[win].foldenable = true
      vim.wo[win].foldlevel = 1
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
