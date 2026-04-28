local patterns = require("djinni.pragmas.patterns")

local M = {}

local function pragma_kind_and_name(line)
  local name = line:match(patterns.FEATURE_PATTERN)
  if name then return "feature", name end
  if line:match(patterns.PROJECT_PATTERN) then return "project" end
  if line:match(patterns.CONSTRAINT_PATTERN) then return "constraint" end
  if line:match(patterns.STACK_PATTERN) then return "stack" end
  if line:match(patterns.CONVENTION_PATTERN) then return "convention" end
  return nil
end

local function is_comment_line(line)
  local trimmed = vim.trim(line or "")
  if trimmed == "" then return false end
  return trimmed:match("^%-%-") or trimmed:match("^#") or trimmed:match("^%/%/")
    or trimmed:match("^%*") or trimmed:match("^;") or trimmed:match("^%%")
    or trimmed:match("^%(%*") or trimmed:match("^%/%*")
end

local function strip_comment_marker(line)
  local trimmed = vim.trim(line or "")
  trimmed = trimmed:gsub("^%-%-%s?", ""):gsub("^#%s?", ""):gsub("^%/%/%s?", "")
                   :gsub("^%/%*%s?", ""):gsub("^%*/?%s?", ""):gsub("^;%s?", "")
                   :gsub("^%%%s?", ""):gsub("^%(%%s?", "")
  return vim.trim(trimmed)
end

local function find_pragma_row(lines, start_row)
  if start_row < 1 or start_row > #lines then return nil end
  local kind, name = pragma_kind_and_name(lines[start_row])
  if kind then return start_row, kind, name end

  if is_comment_line(lines[start_row]) then
    local i = start_row + 1
    while i <= #lines do
      local line = lines[i]
      local k, n = pragma_kind_and_name(line)
      if k then return i, k, n end
      if not is_comment_line(line) then break end
      i = i + 1
    end
    i = start_row - 1
    while i >= 1 do
      local line = lines[i]
      local k, n = pragma_kind_and_name(line)
      if k then return i, k, n end
      if not is_comment_line(line) then break end
      i = i - 1
    end
  end
  return nil
end

local function description_block_above(lines, pragma_row)
  local desc_lines = {}
  local desc_start, desc_end
  local i = pragma_row - 1
  while i >= 1 do
    local line = lines[i]
    if line == "" or vim.trim(line) == "" then
      i = i - 1
    elseif is_comment_line(line) then
      local stripped = strip_comment_marker(line)
      if patterns.FEATURE_PATTERN and (line:match(patterns.FEATURE_PATTERN)
        or line:match(patterns.PROJECT_PATTERN)
        or line:match(patterns.CONSTRAINT_PATTERN)
        or line:match(patterns.STACK_PATTERN)
        or line:match(patterns.CONVENTION_PATTERN)) then
        break
      end
      table.insert(desc_lines, 1, stripped)
      desc_end = desc_end or i
      desc_start = i
      i = i - 1
    else
      break
    end
  end
  return desc_start, desc_end, desc_lines
end

function M.locate(bufnr, row)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local pragma_row, kind, name = find_pragma_row(lines, row)
  if not pragma_row then return nil end

  local desc_start, desc_end, desc_lines = description_block_above(lines, pragma_row)
  local hint_text = table.concat(desc_lines or {}, "\n")
  local ft = vim.bo[bufnr].filetype
  local marker = patterns.marker_for_buffer(bufnr)
  local pragma_line_text = lines[pragma_row]
  local indent = pragma_line_text:match("^(%s*)") or ""

  return {
    bufnr = bufnr,
    pragma_row = pragma_row,
    pragma_kind = kind,
    pragma_name = name,
    desc_start = desc_start,
    desc_end = desc_end,
    hint_text = hint_text,
    comment_marker = marker,
    filetype = ft,
    indent = indent,
  }
end

return M
