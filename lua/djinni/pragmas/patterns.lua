local M = {}

M.FEATURE_PATTERN = "@feature:([%w_%-%.]+)"
M.PROJECT_PATTERN = "@%s*project"
M.CONSTRAINT_PATTERN = "@%s*constraint"
M.STACK_PATTERN = "@%s*stack"
M.CONVENTION_PATTERN = "@%s*convention"

local function is_comment(line)
  local trimmed = vim.trim(line)
  return trimmed:match("^%/%-%-") or trimmed:match("^%-%-") or trimmed:match("^#") or trimmed:match("^%-%-") or
    trimmed:match("^%/%-%-") or trimmed:match("^%*") or trimmed:match("^;") or trimmed:match("^%%") or
    trimmed:match("^%(%*")
end

local function strip_comment(line)
  local trimmed = vim.trim(line)
  trimmed = trimmed:gsub("^%-%-", ""):gsub("^#", ""):gsub("^%/%/%s*", ""):gsub("^%/%*%s*", ""):gsub("^%*%s*", ""):gsub("^;%s*", ""):gsub("^%%%s*", ""):gsub("^%(%%s*", "")
  return vim.trim(trimmed)
end

local function has_any_pragma(text)
  return text:match(M.FEATURE_PATTERN) or text:match(M.PROJECT_PATTERN) or text:match(M.CONSTRAINT_PATTERN) or
    text:match(M.STACK_PATTERN) or text:match(M.CONVENTION_PATTERN)
end

function M.extract_description(lines, line_idx)
  local parts = {}

  local i = line_idx - 1
  while i >= 1 do
    local trimmed = vim.trim(lines[i])
    if trimmed == "" then
      i = i - 1
    elseif is_comment(trimmed) or trimmed:match("^%*") then
      local text = strip_comment(trimmed)
      if has_any_pragma(text) then
        break
      end
      table.insert(parts, 1, text)
      i = i - 1
    else
      break
    end
  end

  local pragma_line = lines[line_idx]
  local stripped = strip_comment(vim.trim(pragma_line))

  local after_pragma = stripped:gsub("^@[^%s]+%s+", "")
  if after_pragma ~= stripped then
    table.insert(parts, after_pragma)
  end

  return table.concat(parts, " ")
end

return M
