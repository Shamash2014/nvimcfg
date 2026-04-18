local M = {}

M.ns = vim.api.nvim_create_namespace("neowork")
M.ns_roles = vim.api.nvim_create_namespace("neowork_roles")

local function detail_tag(line)
  if type(line) ~= "string" then return nil end
  return line:match("^#### %[([^%]]+)%]")
end

local function hl_fg(name, fallback)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl and hl.fg then return string.format("#%06x", hl.fg) end
  return fallback
end

local function hl_bg(name, fallback)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl and hl.bg then return string.format("#%06x", hl.bg) end
  return fallback
end

function M.setup()
  local muted = hl_fg("Comment", "#7a7f88")
  local running = hl_fg("DiagnosticOk", hl_fg("String", "#9ece6a"))
  local input = hl_fg("DiagnosticWarn", hl_fg("WarningMsg", "#e0af68"))
  local info = hl_fg("DiagnosticInfo", "#7dcfff")
  local title = hl_fg("Title", hl_fg("Function", "#7aa2f7"))
  local section = hl_fg("Statement", hl_fg("Type", "#bb9af7"))
  local project = hl_fg("Directory", "#7dcfff")
  local normal = hl_fg("Normal", "#d0d0d0")
  local cost = hl_fg("String", running)
  local tokens = hl_fg("Number", "#ff9e64")
  local base_bg = hl_bg("Normal", "#101418")
  local bg = hl_bg("NormalFloat", hl_bg("Pmenu", base_bg))
  local cursor_bg = hl_bg("Visual", hl_bg("CursorLine", nil))
  local error = hl_fg("DiagnosticError", "#f7768e")
  local subtle_bg = hl_bg("CursorLine", bg)
  local panel_bg = hl_bg("Pmenu", bg)
  local role_you_bg = subtle_bg or bg
  local role_djinni_bg = panel_bg or bg
  local role_system_bg = bg
  local card_bg = panel_bg or bg
  local card_tool_bg = hl_bg("DiffText", card_bg)
  local card_edit_bg = hl_bg("DiffChange", card_bg)
  local card_session_bg = hl_bg("StatusLine", card_bg)
  local section_bg = subtle_bg or card_bg

  vim.api.nvim_set_hl(0, "NeoworkCompose", { fg = input, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkYou", { fg = title, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkDjinni", { fg = running, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkSystem", { fg = muted, italic = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkWindow", { fg = normal, bg = bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkCursorLine", { bg = subtle_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkFolded", { fg = muted, bg = bg, default = true })

  vim.api.nvim_set_hl(0, "NeoworkYouLine", { bg = role_you_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkDjinniLine", { bg = role_djinni_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkSystemLine", { bg = role_system_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkFrontmatterLine", { bg = bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkSeparator", { fg = muted, default = true })
  vim.api.nvim_set_hl(0, "NeoworkTool", { fg = input, default = true })
  vim.api.nvim_set_hl(0, "NeoworkCardTool", { fg = input, bg = card_tool_bg, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkCardEdit", { fg = title, bg = card_edit_bg, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkCardSession", { fg = info, bg = card_session_bg, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkToolDone", { fg = muted, default = true })
  vim.api.nvim_set_hl(0, "NeoworkPlan", { fg = section, default = true })
  vim.api.nvim_set_hl(0, "NeoworkPlanDone", { fg = running, default = true })
  vim.api.nvim_set_hl(0, "NeoworkPlanPending", { fg = muted, default = true })
  vim.api.nvim_set_hl(0, "NeoworkThinking", { fg = muted, italic = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkMeta", { fg = muted, bg = section_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkSummaryLabel", { fg = title, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkSummaryText", { fg = normal, default = true })
  vim.api.nvim_set_hl(0, "NeoworkSummaryEmpty", { fg = muted, italic = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkStatus", { fg = info, default = true })
  vim.api.nvim_set_hl(0, "NeoworkCost", { fg = cost, default = true })
  vim.api.nvim_set_hl(0, "NeoworkTokens", { fg = tokens, default = true })

  local diff_add_fg = hl_fg("DiffAdd", hl_fg("Added", hl_fg("String", "#9ece6a")))
  local diff_add_bg = hl_bg("DiffAdd", "#1f2d1a")
  local diff_del_fg = hl_fg("DiffDelete", hl_fg("Removed", hl_fg("ErrorMsg", "#f7768e")))
  local diff_del_bg = hl_bg("DiffDelete", "#2d1a1a")
  local diff_change_fg = hl_fg("DiffChange", hl_fg("Function", "#7aa2f7"))

  vim.api.nvim_set_hl(0, "NeoworkDiffAdded", { fg = diff_add_fg, bg = diff_add_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkDiffRemoved", { fg = diff_del_fg, bg = diff_del_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkDiffAddedBold", { fg = diff_add_fg, bg = diff_add_bg, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkDiffRemovedBold", { fg = diff_del_fg, bg = diff_del_bg, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkDiffHunk", { fg = diff_change_fg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkDiffFile", { fg = muted, italic = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkToolBody", { fg = muted, bg = card_bg, default = true })

  local pill_bg = hl_bg("Pmenu", hl_bg("StatusLine", bg))
  vim.api.nvim_set_hl(0, "NeoworkPill", { fg = normal, bg = pill_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkBtn", { fg = info, bg = pill_bg, bold = true, default = true })

  vim.api.nvim_set_hl(0, "NeoworkIdxNormal", { fg = normal, bg = bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxCursorLine", { bg = cursor_bg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxTitle", { fg = title, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxSection", { fg = section, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxProject", { fg = project, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxSession", { fg = normal, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxMuted", { fg = muted, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxChevron", { fg = muted, default = true })
  local review_fg = hl_fg("DiagnosticInfo", info)
  local ready_fg = hl_fg("DiagnosticHint", hl_fg("Function", "#7aa2f7"))
  vim.api.nvim_set_hl(0, "NeoworkIdxRunning", { fg = running, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxAwaiting", { fg = input, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxReview", { fg = review_fg, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxReady", { fg = ready_fg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxInput", { link = "NeoworkIdxAwaiting", default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxIdle", { link = "NeoworkIdxReady", default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxDone", { fg = muted, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxActivity", { fg = info, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxCost", { fg = cost, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxTokens", { fg = tokens, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxError", { fg = error, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxSignRunning",  { fg = running, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxSignAwaiting", { fg = input,   default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxSignReview",   { fg = review_fg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxSignReady",    { fg = ready_fg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxSignDone",     { fg = muted,   default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxColProject",   { fg = project, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxColAge",       { fg = muted,   default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxColCtx",       { fg = muted,   default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxColCtxWarn",   { fg = input,   default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxColCtxErr",    { fg = error,   default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxColCost",      { fg = cost,    default = true })

  vim.api.nvim_set_hl(0, "NeoworkIdxStatusRun",  { fg = running,  bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxStatusWait", { fg = input,    bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxStatusPerm", { fg = error,    bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxStatusRvw",  { fg = review_fg, bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxStatusRdy",  { fg = ready_fg, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxStatusEnd",  { fg = muted,    default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxActionKind", { fg = info,     default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxRequiredPerm", { fg = error,  bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxRequiredRun",  { fg = running, default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxRule",         { fg = muted,   default = true })
  vim.api.nvim_set_hl(0, "NeoworkIdxCount",        { fg = muted,   italic = true, default = true })
end

local ROLE_LINE_HL = {
  You = "NeoworkYouLine",
  Djinni = "NeoworkDjinniLine",
  System = "NeoworkSystemLine",
}
local ROLE_TEXT_HL = {
  You = "NeoworkYou",
  Djinni = "NeoworkDjinni",
  System = "NeoworkSystem",
}

local function role_of(line)
  if not line then return nil end
  if line:match("^@You") then return "You" end
  if line:match("^@Djinni") then return "Djinni" end
  if line:match("^@System") then return "System" end
  return nil
end

function M.apply(buf, start_row, end_row)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local total = vim.api.nvim_buf_line_count(buf)
  start_row = start_row or 0
  end_row = end_row or total
  if start_row < 0 then start_row = 0 end
  if end_row > total then end_row = total end
  if start_row >= end_row then return end

  local scan_start = start_row
  if scan_start > 0 then
    for i = start_row - 1, 0, -1 do
      local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
      if role_of(line) then scan_start = i break end
      if i == 0 then scan_start = 0 end
    end
  end

  local clear_end = end_row == total and -1 or end_row
  vim.api.nvim_buf_clear_namespace(buf, M.ns, scan_start, clear_end)
  vim.api.nvim_buf_clear_namespace(buf, M.ns_roles, 0, -1)

  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local fm_end
  if all_lines[1] == "---" then
    for i = 2, #all_lines do
      if all_lines[i] == "---" then fm_end = i break end
    end
  end
  if fm_end then
    vim.api.nvim_buf_set_extmark(buf, M.ns_roles, 0, 0, {
      end_row = fm_end - 1,
      end_col = #(all_lines[fm_end] or ""),
      line_hl_group = "NeoworkFrontmatterLine",
      priority = 50,
    })
    if scan_start == 0 then
      for i = 1, fm_end do
        vim.api.nvim_buf_set_extmark(buf, M.ns, i - 1, 0, {
          end_col = #(all_lines[i] or ""),
          hl_group = all_lines[i] == "---" and "NeoworkSeparator" or "NeoworkMeta",
          priority = 60,
        })
      end
    end
  end

  local n = #all_lines
  local content_start_abs = fm_end or 0
  local current_role, current_role_row
  local function close_range(last_row)
    if not current_role or not current_role_row then return end
    if ROLE_LINE_HL[current_role] and last_row >= current_role_row then
      local end_line = all_lines[last_row + 1] or ""
      vim.api.nvim_buf_set_extmark(buf, M.ns_roles, current_role_row, 0, {
        end_row = last_row,
        end_col = #end_line,
        end_right_gravity = true,
        line_hl_group = ROLE_LINE_HL[current_role],
        priority = 50,
      })
    end
    current_role, current_role_row = nil, nil
  end

  for i = content_start_abs + 1, n do
    local line = all_lines[i]
    local absolute_row = i - 1
    local role = role_of(line)
    if role then
      close_range(absolute_row - 1)
      current_role = role
      current_role_row = absolute_row
    end
  end
  close_range(n - 1)

  local scan_lines = vim.api.nvim_buf_get_lines(buf, scan_start, end_row, false)
  for i = 1, #scan_lines do
    local line = scan_lines[i]
    local absolute_row = scan_start + i - 1
    if absolute_row >= content_start_abs then
      local role = role_of(line)
      if role then
        vim.api.nvim_buf_set_extmark(buf, M.ns, absolute_row, 0, {
          end_col = #line,
          hl_group = ROLE_TEXT_HL[role],
          priority = 100,
        })
      elseif line and line:match("^#### %[[^%]]+%]") then
        local tag = detail_tag(line)
        local hl_group = "NeoworkTool"
        if tag == "tool" then
          hl_group = "NeoworkCardTool"
        elseif tag == "edit" then
          hl_group = "NeoworkCardEdit"
        elseif tag == "session" then
          hl_group = "NeoworkCardSession"
        end
        vim.api.nvim_buf_set_extmark(buf, M.ns, absolute_row, 0, {
          end_col = #line,
          hl_group = hl_group,
          priority = 100,
        })
      elseif line and line:match("^##### ") then
        vim.api.nvim_buf_set_extmark(buf, M.ns, absolute_row, 0, {
          end_col = #line,
          hl_group = "NeoworkMeta",
          priority = 100,
        })
      elseif line and line:match("^>") then
        vim.api.nvim_buf_set_extmark(buf, M.ns, absolute_row, 0, {
          end_col = #line,
          hl_group = "NeoworkThinking",
          priority = 100,
        })
      end
    end
  end
end

return M
