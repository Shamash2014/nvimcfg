local M = {}

local MIN_HEIGHT = 3
local NS = vim.api.nvim_create_namespace("acp_float")

local function clamp_line(buf, line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return nil end
  local n = vim.api.nvim_buf_line_count(buf)
  if n == 0 then return 0 end
  if line < 0 then return 0 end
  if line > n - 1 then return n - 1 end
  return line
end

function M.compute_height(content_lines, header_lines, ref_height)
  local max_h = math.floor((ref_height or vim.o.lines) * 0.8)
  return math.max(MIN_HEIGHT, math.min(max_h, content_lines + header_lines))
end

function M.reserve_space(diff_buf, anchor_line, line_count, above)
  local line = clamp_line(diff_buf, anchor_line)
  if line == nil then return nil end
  local virt = {}
  for _ = 1, line_count do table.insert(virt, { { "", "" } }) end
  return vim.api.nvim_buf_set_extmark(diff_buf, NS, line, 0, {
    virt_lines = virt, virt_lines_above = above or false,
  })
end

function M.update_space(diff_buf, extmark_id, anchor_line, line_count, above)
  local line = clamp_line(diff_buf, anchor_line)
  if line == nil then return end
  local virt = {}
  for _ = 1, line_count do table.insert(virt, { { "", "" } }) end
  vim.api.nvim_buf_set_extmark(diff_buf, NS, line, 0, {
    id = extmark_id, virt_lines = virt, virt_lines_above = above or false,
  })
end

function M.clear_space(diff_buf, extmark_id)
  pcall(vim.api.nvim_buf_del_extmark, diff_buf, NS, extmark_id)
end

function M.border()
  local hl = "AcpCommentBorder"
  return {
    { "┏", hl }, { "━", hl }, { "┓", hl }, { "┃", hl },
    { "┛", hl }, { "━", hl }, { "┗", hl }, { "┃", hl },
  }
end

function M.title(text)
  return { { " " .. text .. " ", "AcpFloatTitle" } }
end

local function chipped_title(text, cwd)
  local ok, agents = pcall(require, "acp.agents")
  local chip = (ok and cwd) and agents.chip(cwd) or ""
  if chip == "" then return M.title(text) end
  return {
    { " " .. text .. " ", "AcpFloatTitle" },
    { chip .. " ",        "AcpWinbarText" },
  }
end

function M.footer()
  return {
    { " ", "AcpFloatFooterText" },
    { "<C-CR>", "AcpFloatFooterKey" },
    { "/", "AcpFloatFooterText" },
    { "<C-s>", "AcpFloatFooterKey" },
    { " submit  ", "AcpFloatFooterText" },
    { "<C-p>", "AcpFloatFooterKey" },
    { " provider  ", "AcpFloatFooterText" },
    { "<C-y>", "AcpFloatFooterKey" },
    { " model  ", "AcpFloatFooterText" },
    { "q", "AcpFloatFooterKey" },
    { " cancel ", "AcpFloatFooterText" },
  }
end

function M.highlight_lines(diff_buf, start_line, end_line)
  local ids = {}
  local total_lines = vim.api.nvim_buf_line_count(diff_buf)
  for row = start_line - 1, end_line - 1 do
    if row >= 0 and row < total_lines then
      table.insert(ids, vim.api.nvim_buf_set_extmark(diff_buf, NS, row, 0, {
        line_hl_group = "AcpCommentContext", priority = 4097,
      }))
    end
  end
  return ids
end

function M.clear_line_hl(diff_buf, ids)
  for _, id in ipairs(ids) do pcall(vim.api.nvim_buf_del_extmark, diff_buf, NS, id) end
end

function M.open_comment_float(title, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype  = "markdown"

  local init_lines = (opts.prefill and opts.prefill ~= "") and
    vim.split(opts.prefill, "\n", { plain = true }) or { "" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, init_lines)

  if not vim.api.nvim_win_is_valid(opts.win_id) then return end
  if not opts.diff_buf or not vim.api.nvim_buf_is_valid(opts.diff_buf) then return end
  local ref_height  = vim.api.nvim_win_get_height(opts.win_id)
  local total_h     = M.compute_height(#init_lines, 0, ref_height)
  local anchor_0    = clamp_line(opts.diff_buf, opts.anchor_line - 1) or 0
  local anchor_1    = anchor_0 + 1
  local win_w       = vim.api.nvim_win_get_width(opts.win_id)
  local float_w     = math.min(win_w - 4, 88)

  local handle = {
    buf = buf, win = nil, closed = false,
    extmark_id = nil, line_hl_ids = {},
  }

  handle.line_hl_ids  = M.highlight_lines(opts.diff_buf, anchor_1, anchor_1)
  handle.extmark_id   = M.reserve_space(opts.diff_buf, anchor_0, total_h + 2, false)

  local heal_pending = false
  vim.api.nvim_buf_attach(opts.diff_buf, false, {
    on_lines = function()
      if handle.closed then return true end
      if heal_pending then return end
      heal_pending = true
      vim.schedule(function()
        heal_pending = false
        if handle.closed or not vim.api.nvim_buf_is_valid(opts.diff_buf) then return end
        local cur_h = vim.api.nvim_win_is_valid(handle.win) and
          vim.api.nvim_win_get_height(handle.win) or total_h
        handle.extmark_id = M.reserve_space(opts.diff_buf, anchor_0, cur_h + 2, false)
        if #handle.line_hl_ids > 0 then
          M.clear_line_hl(opts.diff_buf, handle.line_hl_ids)
          handle.line_hl_ids = M.highlight_lines(opts.diff_buf, anchor_1, anchor_1)
        end
      end)
    end,
  })

  local cwd = opts.cwd or vim.fn.getcwd()

  handle.win = vim.api.nvim_open_win(buf, true, {
    relative    = "win",
    win         = opts.win_id,
    bufpos      = { anchor_0, 0 },
    width       = float_w,
    height      = total_h,
    row         = 1,
    col         = 3,
    style       = "minimal",
    border      = M.border(),
    title       = chipped_title(title, cwd),
    title_pos   = "center",
    footer      = M.footer(),
    footer_pos  = "center",
    noautocmd   = true,
  })

  local function refresh_title()
    if handle.closed or not vim.api.nvim_win_is_valid(handle.win) then return end
    pcall(vim.api.nvim_win_set_config, handle.win, { title = chipped_title(title, cwd) })
  end

  vim.wo[handle.win].winblend     = 0
  vim.wo[handle.win].winhighlight = "NormalFloat:Normal"
  vim.wo[handle.win].wrap         = true

  function handle.close()
    if handle.closed then return end
    handle.closed = true
    vim.cmd("stopinsert")
    pcall(vim.api.nvim_win_close, handle.win, true)
    if handle.extmark_id then M.clear_space(opts.diff_buf, handle.extmark_id) end
    if #handle.line_hl_ids > 0 then M.clear_line_hl(opts.diff_buf, handle.line_hl_ids) end
    if opts.on_close then opts.on_close() end
  end

  function handle.get_text()
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
    return ok and vim.trim(table.concat(lines, "\n")) or ""
  end

  local resize_timer = nil
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if handle.closed then return true end
      if resize_timer then vim.fn.timer_stop(resize_timer) end
      resize_timer = vim.fn.timer_start(15, function()
        resize_timer = nil
        if handle.closed or not vim.api.nvim_buf_is_valid(buf) then return end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local new_h = M.compute_height(#lines, 0, ref_height)
        if vim.api.nvim_win_is_valid(handle.win) then
          vim.api.nvim_win_set_height(handle.win, new_h)
        end
        if handle.extmark_id then
          M.update_space(opts.diff_buf, handle.extmark_id, anchor_0, new_h + 2, false)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(handle.win), once = true,
    callback = function() handle.close() end,
  })

  local function km(lhs, fn)
    vim.keymap.set({"n","i"}, lhs, fn,
      { buffer = buf, nowait = true, noremap = true, silent = true })
  end
  local function submit()
    local text = handle.get_text()
    handle.close()
    if text ~= "" and opts.on_submit then opts.on_submit(text) end
  end
  km("<C-s>",     submit)
  km("<C-CR>",    submit)
  km("<C-Enter>", submit)
  km("<C-p>", function()
    require("acp.agents").choose_provider(cwd, function() vim.schedule(refresh_title) end)
  end)
  km("<C-y>", function()
    require("acp").pick_model(cwd, function() vim.schedule(refresh_title) end)
  end)
  km("q", function() handle.close() end)

  vim.cmd("startinsert")
  return handle
end

--- Open a large centered composer float (no diff buffer anchor).
--- @param title string  Float title bar text
--- @param opts { on_submit: fun(text: string), on_close?: fun(), prefill?: string }
--- @return table handle { buf, win, close, get_text, closed }
function M.open_composer_float(title, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype  = "markdown"

  local init_lines = (opts.prefill and opts.prefill ~= "") and
    vim.split(opts.prefill, "\n", { plain = true }) or { "" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, init_lines)

  local max_h   = 30
  local float_h = 12
  local float_w = vim.o.columns
  local row     = vim.o.lines - float_h - 2
  local col     = 0

  local handle = { buf = buf, win = nil, closed = false }

  local cwd = opts.cwd or vim.fn.getcwd()

  handle.win = vim.api.nvim_open_win(buf, true, {
    relative   = "editor",
    width      = float_w,
    height     = float_h,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "single",
    title      = chipped_title(title, cwd),
    title_pos  = "left",
    footer     = M.footer(),
    footer_pos = "center",
    noautocmd  = true,
  })

  local function refresh_title()
    if handle.closed or not vim.api.nvim_win_is_valid(handle.win) then return end
    pcall(vim.api.nvim_win_set_config, handle.win, { title = chipped_title(title, cwd) })
  end

  vim.wo[handle.win].winblend     = 0
  vim.wo[handle.win].winhighlight = "NormalFloat:Normal"
  vim.wo[handle.win].wrap         = true

  function handle.close()
    if handle.closed then return end
    handle.closed = true
    vim.cmd("stopinsert")
    pcall(vim.api.nvim_win_close, handle.win, true)
    if opts.on_close then opts.on_close() end
  end

  function handle.get_text()
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
    return ok and vim.trim(table.concat(lines, "\n")) or ""
  end

  local resize_timer = nil
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if handle.closed then return true end
      if resize_timer then vim.fn.timer_stop(resize_timer) end
      resize_timer = vim.fn.timer_start(15, function()
        resize_timer = nil
        if handle.closed or not vim.api.nvim_buf_is_valid(buf) then return end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local target_h = math.max(MIN_HEIGHT, math.min(max_h, #lines))
        if vim.api.nvim_win_is_valid(handle.win) then
          local cur_h = vim.api.nvim_win_get_height(handle.win)
          local new_h = math.max(cur_h, target_h)
          if new_h ~= cur_h then
            vim.api.nvim_win_set_height(handle.win, new_h)
            vim.api.nvim_win_set_config(handle.win, { relative = "editor", row = vim.o.lines - new_h - 2, col = 0 })
          end
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(handle.win), once = true,
    callback = function() handle.close() end,
  })

  local function km(lhs, fn)
    vim.keymap.set({ "n", "i" }, lhs, fn,
      { buffer = buf, nowait = true, noremap = true, silent = true })
  end
  local function submit()
    local text = handle.get_text()
    handle.close()
    if text ~= "" and opts.on_submit then opts.on_submit(text) end
  end
  km("<C-s>",     submit)
  km("<C-CR>",    submit)
  km("<C-Enter>", submit)
  km("<C-p>", function()
    require("acp.agents").choose_provider(cwd, function() vim.schedule(refresh_title) end)
  end)
  km("<C-y>", function()
    require("acp").pick_model(cwd, function() vim.schedule(refresh_title) end)
  end)
  km("q", function() handle.close() end)

  vim.api.nvim_win_set_cursor(handle.win, { 1, 2 })
  vim.cmd("startinsert!")
  return handle
end

return M
