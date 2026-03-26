local M = {}

local ns = vim.api.nvim_create_namespace("djinni_render")

function M.setup_highlights()
  vim.api.nvim_set_hl(0, "DjinniYou", { fg = "#d0d0d0", bold = true, default = true })
  vim.api.nvim_set_hl(0, "DjinniAI", { fg = "#e8e8e8", bold = true, default = true })
  vim.api.nvim_set_hl(0, "DjinniSystem", { fg = "#777777", bold = true, default = true })
end

local function apply_line(buf, lnum, line)
  if line:match("^@You") then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #line, hl_group = "DjinniYou" })
    return
  end

  if line:match("^@Djinni") then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #line, hl_group = "DjinniAI" })
    return
  end

  if line:match("^@System") then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #line, hl_group = "DjinniSystem" })
    return
  end

  if line:match("^%-%-%-$") then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #line, hl_group = "Comment" })
    return
  end

  if line:match("^╶╶╶") then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #line, hl_group = "Comment" })
    return
  end

  if line:match("^### Plan") or line:match("^### Agents") or line:match("^### Files") then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #line, hl_group = "Title" })
    return
  end

  if line:match("●●● streaming") or line:match("●●● working") then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #line, hl_group = "DiagnosticInfo", hl_mode = "combine" })
    return
  end

  if line:match("●●● interrupted") then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #line, hl_group = "DiagnosticError" })
    return
  end

  local connector_start, connector_end = line:find("[├└│][─ ]?")
  if connector_start then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = connector_end, hl_group = "Comment" })
    local mcp_pos = line:find("mcp:")
    if mcp_pos then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, mcp_pos - 1, { end_col = mcp_pos + 3, hl_group = "Special" })
      if #line > mcp_pos + 3 then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, mcp_pos + 4, { end_col = #line, hl_group = "Function" })
      end
    elseif connector_end < #line then
      local name_start = line:find("%S", connector_end + 1)
      if name_start then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, name_start - 1, { end_col = #line, hl_group = "Function" })
      end
    end
  end

  for pos in function() return line:find("●", pos and pos + 1 or 1) end do
    local byte_end = pos + #"●" - 1
    if not line:match("●●●", pos) then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, pos - 1, { end_col = byte_end, hl_group = "DiagnosticOk" })
    end
  end

  for pos in function() return line:find("⚠", pos and pos + 1 or 1) end do
    local byte_end = pos + #"⚠" - 1
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, pos - 1, { end_col = byte_end, hl_group = "DiagnosticWarn" })
  end

  for pos in function() return line:find("◆", pos and pos + 1 or 1) end do
    local byte_end = pos + #"◆" - 1
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, pos - 1, { end_col = byte_end, hl_group = "Comment" })
  end

  for pos in function() return line:find("✓", pos and pos + 1 or 1) end do
    local byte_end = pos + #"✓" - 1
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, pos - 1, { end_col = byte_end, hl_group = "DiagnosticHint" })
  end

  local check_pos = line:find("%[x%]")
  if check_pos then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, check_pos - 1, { end_col = check_pos + 2, hl_group = "DiagnosticOk" })
  end

  local uncheck_pos = line:find("%[ %]")
  if uncheck_pos then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, uncheck_pos - 1, { end_col = uncheck_pos + 2, hl_group = "Comment" })
  end

  local allow_pos = line:find("%[a%]llow")
  if allow_pos then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, allow_pos - 1, { end_col = allow_pos + 6, hl_group = "DiagnosticOk" })
  end

  local deny_pos = line:find("%[d%]eny")
  if deny_pos then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, deny_pos - 1, { end_col = deny_pos + 5, hl_group = "DiagnosticError" })
  end

  local always_pos = line:find("%[A%]lways")
  if always_pos then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, always_pos - 1, { end_col = always_pos + 7, hl_group = "DiagnosticInfo" })
  end

  for ref_start, ref_end in line:gmatch("()@%./[^%s]+()") do
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, ref_start - 1, { end_col = ref_end - 1, hl_group = "Underlined" })
  end
end

function M.apply(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    apply_line(buf, i - 1, line)
  end
end

function M.apply_streaming_indicator(buf, line_nr)
  return vim.api.nvim_buf_set_extmark(buf, ns, line_nr, 0, {
    virt_text = { { " ●●●", "DiagnosticInfo" } },
    virt_text_pos = "eol",
  })
end

function M.clear_streaming_indicator(buf, extmark_id)
  vim.api.nvim_buf_del_extmark(buf, ns, extmark_id)
end

function M.apply_viewport_only(buf, win)
  local top = vim.fn.line("w0", win) - 1
  local bot = vim.fn.line("w$", win)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, top)
  vim.api.nvim_buf_clear_namespace(buf, ns, bot, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, top, bot, false)
  for i, line in ipairs(lines) do
    apply_line(buf, top + i - 1, line)
  end
end

return M
