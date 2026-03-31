local M = {}

local ns_id = vim.api.nvim_create_namespace("djinni_codediff")

local _highlights_ready = false
local function ensure_highlights()
  if _highlights_ready then return end
  pcall(function() require("difftastic-nvim.highlight").setup({}) end)

  local function get_fg(name)
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    if hl.fg then return string.format("#%06x", hl.fg) end
    return nil
  end
  local function get_bg(name)
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    if hl.bg then return string.format("#%06x", hl.bg) end
    return nil
  end

  local added_fg = get_fg("DifftAddedFg") or get_fg("Added") or "#9ece6a"
  local removed_fg = get_fg("DifftRemovedFg") or get_fg("Removed") or "#f7768e"
  local added_bg = get_bg("DifftAdded")
  local removed_bg = get_bg("DifftRemoved")

  vim.api.nvim_set_hl(0, "DjinniDiffAdded", { fg = added_fg, bg = added_bg })
  vim.api.nvim_set_hl(0, "DjinniDiffRemoved", { fg = removed_fg, bg = removed_bg })
  vim.api.nvim_set_hl(0, "DjinniDiffAddedBold", { fg = added_fg, bg = added_bg, bold = true })
  vim.api.nvim_set_hl(0, "DjinniDiffRemovedBold", { fg = removed_fg, bg = removed_bg, bold = true })

  _highlights_ready = true
end

local function char_diff(old_line, new_line)
  local prefix = 0
  while prefix < #old_line and prefix < #new_line and old_line:byte(prefix + 1) == new_line:byte(prefix + 1) do
    prefix = prefix + 1
  end
  local suffix = 0
  while suffix < (#old_line - prefix) and suffix < (#new_line - prefix) and old_line:byte(#old_line - suffix) == new_line:byte(#new_line - suffix) do
    suffix = suffix + 1
  end
  return {
    old = { { prefix, #old_line - suffix } },
    new = { { prefix, #new_line - suffix } },
  }
end

function M.compute(old_text, new_text, path)
  ensure_highlights()
  local lines = {}
  lines[#lines + 1] = { text = "  " .. (path or ""), hl = "Comment" }

  local old_str = old_text or ""
  local new_str = new_text or ""
  if not old_str:match("\n$") then old_str = old_str .. "\n" end
  if not new_str:match("\n$") then new_str = new_str .. "\n" end

  local hunks = vim.diff(old_str, new_str, { result_type = "indices" })
  if not hunks or #hunks == 0 then
    lines[#lines + 1] = { text = "  (no changes)", hl = "Comment" }
    return lines
  end

  local old_lines = {}
  for l in old_str:gmatch("([^\n]*)\n") do old_lines[#old_lines + 1] = l end
  local new_lines = {}
  for l in new_str:gmatch("([^\n]*)\n") do new_lines[#new_lines + 1] = l end

  local prev_old_end = 0
  for _, hunk in ipairs(hunks) do
    local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]

    local ctx_from = math.max(prev_old_end + 1, old_start - 2)
    local ctx_to = math.min(#old_lines, old_start - 1)
    for i = ctx_from, ctx_to do
      lines[#lines + 1] = { text = "  " .. old_lines[i], hl = "NonText" }
    end

    local removed = {}
    for i = old_start, old_start + old_count - 1 do
      removed[#removed + 1] = old_lines[i] or ""
    end
    local added = {}
    for i = new_start, new_start + new_count - 1 do
      added[#added + 1] = new_lines[i] or ""
    end

    local char_diffs = {}
    if #removed == #added then
      for i = 1, #removed do
        char_diffs[i] = char_diff(removed[i], added[i])
      end
    end

    for i, r in ipairs(removed) do
      local entry = { text = "- " .. r, hl = "DjinniDiffRemoved" }
      if char_diffs[i] then
        entry.inline = {}
        for _, span in ipairs(char_diffs[i].old) do
          entry.inline[#entry.inline + 1] = { col = span[1] + 2, end_col = span[2] + 2, hl = "DjinniDiffRemovedBold" }
        end
      end
      lines[#lines + 1] = entry
    end
    for i, a in ipairs(added) do
      local entry = { text = "+ " .. a, hl = "DjinniDiffAdded" }
      if char_diffs[i] then
        entry.inline = {}
        for _, span in ipairs(char_diffs[i].new) do
          entry.inline[#entry.inline + 1] = { col = span[1] + 2, end_col = span[2] + 2, hl = "DjinniDiffAddedBold" }
        end
      end
      lines[#lines + 1] = entry
    end

    prev_old_end = old_start + old_count - 1

    local after_from = old_start + old_count
    local after_to = math.min(#old_lines, after_from + 1)
    for i = after_from, after_to do
      lines[#lines + 1] = { text = "  " .. old_lines[i], hl = "NonText" }
    end
  end

  return lines
end

function M.apply_highlights(buf, start_line, diff_lines)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    for i, dl in ipairs(diff_lines) do
      local line_nr = start_line + i - 1
      if dl.hl then
        pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, dl.hl, line_nr, 0, -1)
      end
      if dl.inline then
        for _, span in ipairs(dl.inline) do
          pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, span.hl, line_nr, span.col, span.end_col)
        end
      end
    end
  end)
end

return M
