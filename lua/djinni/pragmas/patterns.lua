local M = {}

M.FEATURE_PATTERN = "@feature:([%w_%-%.]+)"
M.PROJECT_PATTERN = "@%s*project"
M.CONSTRAINT_PATTERN = "@%s*constraint"
M.STACK_PATTERN = "@%s*stack"
M.CONVENTION_PATTERN = "@%s*convention"

function M.is_comment(line)
  local trimmed = vim.trim(line)
  return trimmed:match("^%/%-%-") or trimmed:match("^%-%-") or trimmed:match("^#") or trimmed:match("^%-%-") or
    trimmed:match("^%/%-%-") or trimmed:match("^%*") or trimmed:match("^;") or trimmed:match("^%%") or
    trimmed:match("^%(%*")
end

function M.strip_comment(line)
  local trimmed = vim.trim(line)
  trimmed = trimmed:gsub("^%-%-", ""):gsub("^#", ""):gsub("^%/%/%s*", ""):gsub("^%/%*%s*", ""):gsub("^%*%s*", ""):gsub("^;%s*", ""):gsub("^%%%s*", ""):gsub("^%(%%s*", "")
  return vim.trim(trimmed)
end

function M.has_any_pragma(text)
  return text:match(M.FEATURE_PATTERN) or text:match(M.PROJECT_PATTERN) or text:match(M.CONSTRAINT_PATTERN) or
    text:match(M.STACK_PATTERN) or text:match(M.CONVENTION_PATTERN)
end

function M.match_kind(line)
  local name = line:match(M.FEATURE_PATTERN)
  if name then return "feature", name end
  if line:match(M.PROJECT_PATTERN) then return "project" end
  if line:match(M.CONSTRAINT_PATTERN) then return "constraint" end
  if line:match(M.STACK_PATTERN) then return "stack" end
  if line:match(M.CONVENTION_PATTERN) then return "convention" end
  return nil
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

local FT_FALLBACK = {
  lua = "--", sql = "--", haskell = "--", ada = "--",
  python = "#", ruby = "#", sh = "#", bash = "#", zsh = "#",
  yaml = "#", toml = "#", make = "#", dockerfile = "#",
  javascript = "//", typescript = "//", javascriptreact = "//", typescriptreact = "//",
  go = "//", rust = "//", c = "//", cpp = "//", java = "//", scala = "//",
  clojure = ";", lisp = ";", asm = ";",
  erlang = "%", tex = "%", matlab = "%",
}

function M.marker_for_buffer(bufnr)
  bufnr = (bufnr == 0 or bufnr == nil) and vim.api.nvim_get_current_buf() or bufnr
  local cs = vim.bo[bufnr].commentstring or ""
  local prefix = cs:match("^(.-)%%s")
  if prefix then
    local trimmed = vim.trim(prefix)
    if trimmed ~= "" then return trimmed end
  end
  return FT_FALLBACK[vim.bo[bufnr].filetype or ""] or "//"
end

function M.marker_for_filetype(ft)
  return FT_FALLBACK[ft or ""] or "//"
end

return M
