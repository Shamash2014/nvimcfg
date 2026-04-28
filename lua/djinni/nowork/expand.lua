local M = {}

local MAX_BUF_LINES = 500

local function expand_buffer(ctx)
  local buf = ctx and ctx.alt_buf or -1
  if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
    return "<Buffer>[no alternate buffer]</Buffer>"
  end
  if vim.bo[buf].filetype == "nowork" then
    return "<Buffer>[alternate is nowork log — skipped]</Buffer>"
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then name = "[No Name]" end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local total = #lines
  local shown = math.min(total, MAX_BUF_LINES)
  local shown_lines = {}
  for i = 1, shown do shown_lines[i] = lines[i] end
  local content = table.concat(shown_lines, "\n")
  local suffix = ""
  if total > shown then
    suffix = string.format("\n... (%d truncated)", total - shown)
  end
  return string.format("<Buffer name=%q lines=%d>\n%s%s\n</Buffer>", name, total, content, suffix)
end

local function expand_qflist()
  local qfix_share = require("djinni.nowork.qfix_share")
  local info = vim.fn.getqflist({ title = 0, items = 0 })
  local items = info.items or {}
  if #items == 0 then
    return "<Quickfix>[empty]</Quickfix>"
  end
  return qfix_share.format_block(info.title, items)
end

local function run_git(args)
  local obj = vim.system({ "git", unpack(args) }, { text = true }):wait()
  if obj.code ~= 0 then return nil, obj.stderr or "" end
  return obj.stdout or "", nil
end

local function expand_diff()
  local out, err = run_git({ "diff" })
  if not out then return "<Diff>[git error: " .. (err or "?") .. "]</Diff>" end
  if out == "" then return "<Diff>[no unstaged changes]</Diff>" end
  return "<Diff>\n" .. out .. "</Diff>"
end

local function expand_staged()
  local out, err = run_git({ "diff", "--cached" })
  if not out then return "<StagedDiff>[git error: " .. (err or "?") .. "]</StagedDiff>" end
  if out == "" then return "<StagedDiff>[no staged changes]</StagedDiff>" end
  return "<StagedDiff>\n" .. out .. "</StagedDiff>"
end

local function expand_worktree()
  local out, err = run_git({ "status", "--short" })
  if not out then return "<Worktree>[git error: " .. (err or "?") .. "]</Worktree>" end
  if out == "" then return "<Worktree>[clean]</Worktree>" end
  return "<Worktree>\n" .. out .. "</Worktree>"
end

local function expand_changed()
  local out, err = run_git({ "diff", "--name-only" })
  if not out then return "<Changed>[git error]</Changed>" end
  local staged = select(1, run_git({ "diff", "--cached", "--name-only" })) or ""
  local combined = (out .. "\n" .. staged):gsub("^%s+", ""):gsub("%s+$", "")
  if combined == "" then return "<Changed>[none]</Changed>" end
  return "<Changed>\n" .. combined .. "\n</Changed>"
end

local function expand_project_context(ctx)
  local ok, pragmas = pcall(function()
    return require("djinni.pragmas").project_context()
  end)
  if not ok or not pragmas or pragmas == "" then return "" end
  return pragmas
end

local expanders = {
  buffer = expand_buffer,
  buf = expand_buffer,
  qflist = expand_qflist,
  qf = expand_qflist,
  diff = expand_diff,
  staged = expand_staged,
  worktree = expand_worktree,
  status = expand_worktree,
  changed = expand_changed,
  project_context = expand_project_context,
}

function M.expand(text, ctx)
  if not text or text == "" then return text end
  ctx = ctx or {}
  return (text:gsub("#{(%w+)}", function(tok)
    local fn = expanders[tok]
    if fn then return fn(ctx) end
    local ok, feature_xml = pcall(function()
      return require("djinni.pragmas").resolve_feature(tok)
    end)
    if ok and feature_xml then return feature_xml end
    return "#{" .. tok .. "}"
  end))
end

return M
