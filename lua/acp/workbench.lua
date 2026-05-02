local M = {}

local BUF_NAME    = "[acp]"
local _view       = "index"    -- "index" | "log"
local _active_log = nil        -- path of currently shown .log.md
local _context    = {}         -- pushed items awaiting next prompt

local function get_or_create_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):match(vim.pesc(BUF_NAME) .. "$") then
      return b
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype  = "markdown"
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].buflisted = false
  vim.api.nvim_buf_set_name(buf, BUF_NAME)
  M._install_keymaps(buf)
  return buf
end

local function buf_set(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function buf_append(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  vim.bo[buf].modifiable = false
  -- Auto-scroll if workbench window is visible
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end
end

-- ── Index view ────────────────────────────────────────────────────────────

function M.render()
  _view = "index"
  local buf  = get_or_create_buf()
  local work = require("acp.work")
  local cwd  = vim.fn.getcwd()
  local ls   = {}
  local function add(s) table.insert(ls, s or "") end

  add("# ACP  " .. vim.fn.fnamemodify(cwd, ":~"))
  add("")

  local active = require("acp.session").active()
  if #active > 0 then
    for _, s in ipairs(active) do
      add("  ● " .. s.state .. "  " .. vim.fn.fnamemodify(s.cwd, ":~"))
    end
    add("")
  end

  local pending = require("acp.mailbox").pending_count()
  if pending > 0 then
    add("  ⚠ " .. pending .. " permission(s) pending  (<leader>am)")
    add("")
  end

  if #_context > 0 then
    add("  ✦ " .. #_context .. " item(s) pinned  (will attach to next prompt)")
    add("")
  end

  local files = work.list(cwd)
  if #files > 0 then
    add("  Work Items  <CR>=run  o=edit  L=log  d=delete")
    add("")
    for _, f in ipairs(files) do
      local name    = vim.fn.fnamemodify(f, ":t:r")
      local has_log = vim.fn.filereadable(work.log_path(f)) == 1
      add("  " .. (has_log and "✓ " or "  ") .. name
          .. "  [" .. vim.fn.fnamemodify(f, ":.") .. "]")
    end
  else
    add("  No work items yet.  <leader>aw to create one.")
  end

  add(""); add("  R=refresh  <leader>aw=new  <leader>am=permissions  q=close")
  buf_set(buf, ls)
  vim.b[buf].acp_work_files = files
end

-- ── Log view ──────────────────────────────────────────────────────────────

function M.show_log(work_path)
  _view       = "log"
  _active_log = work_path
  local buf   = get_or_create_buf()
  local name  = vim.fn.fnamemodify(work_path, ":t:r")
  local log   = require("acp.work").log_path(work_path)

  local ls = { "# Log: " .. name, "", "  i=index  R=refresh  q=close", "" }
  if vim.fn.filereadable(log) == 1 then
    vim.list_extend(ls, vim.fn.readfile(log))
  else
    table.insert(ls, "  (no log yet — run this work item first)")
  end
  buf_set(buf, ls)
end

-- Called from work.run() subscriber for live append during a session.
function M.on_event(work_path, line)
  local buf = get_or_create_buf()
  if _view == "log" and _active_log == work_path then
    buf_append(buf, { line })
  end
  -- Also re-render index badge if in index view (session state changed)
  if _view == "index" then
    M.render()
  end
end

-- ── Pushed context ────────────────────────────────────────────────────────

-- Append a labelled block to the context queue (called from push_* helpers).
function M.push(label, content)
  table.insert(_context, { label = label, content = content })
  vim.notify("Pinned to workbench: " .. label, vim.log.levels.INFO, { title = "acp" })
  if _view == "index" then M.render() end
end

-- Pop all pending context blocks; returns them as a markdown string.
-- Called by init.lua before sending any prompt — clears the queue.
function M.drain_context()
  if #_context == 0 then return nil end
  local parts = {}
  for _, item in ipairs(_context) do
    table.insert(parts, "--- " .. item.label .. " ---\n\n" .. item.content)
  end
  _context = {}
  return table.concat(parts, "\n\n")
end

-- Push helpers (called from keymaps / init.lua):
function M.push_visual()
  local l1 = vim.fn.line("'<"); local l2 = vim.fn.line("'>")
  local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  local name  = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  M.push(name .. ":" .. l1 .. "-" .. l2, table.concat(lines, "\n"))
end

function M.push_quickfix()
  local qf = vim.fn.getqflist()
  if #qf == 0 then vim.notify("Quickfix is empty", vim.log.levels.WARN, { title = "acp" }); return end
  local ls = {}
  for _, item in ipairs(qf) do
    local fname = item.bufnr > 0 and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.bufnr), ":.") or "?"
    table.insert(ls, fname .. ":" .. item.lnum .. ": " .. (item.text or ""))
  end
  M.push("quickfix (" .. #qf .. " items)", table.concat(ls, "\n"))
end

function M.push_diagnostics()
  local diags = vim.diagnostic.get(0)
  if #diags == 0 then vim.notify("No diagnostics", vim.log.levels.INFO, { title = "acp" }); return end
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  local ls = {}
  for _, d in ipairs(diags) do
    table.insert(ls, name .. ":" .. (d.lnum + 1) .. ": " .. d.message)
  end
  M.push("diagnostics: " .. name, table.concat(ls, "\n"))
end

-- ── Keymaps ───────────────────────────────────────────────────────────────

function M._install_keymaps(buf)
  local function work_path_at_cursor()
    local row  = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local rel  = line:match("%[([^%]]+%.md)%]")
    return rel and vim.fn.fnamemodify(rel, ":p") or nil
  end

  -- <CR>: run work item (index) or no-op (log)
  vim.keymap.set("n", "<CR>", function()
    local path = work_path_at_cursor()
    if path and vim.fn.filereadable(path) == 1 then
      M.show_log(path)
      require("acp.work").run(vim.fn.getcwd(), path)
    end
  end, { buffer = buf, desc = "Run work item" })

  -- o: open goal file for editing
  vim.keymap.set("n", "o", function()
    local path = work_path_at_cursor()
    if path then vim.cmd("edit " .. vim.fn.fnameescape(path)) end
  end, { buffer = buf, desc = "Open work goal" })

  -- L: switch to log view for item under cursor
  vim.keymap.set("n", "L", function()
    local path = work_path_at_cursor()
    if path then M.show_log(path) end
  end, { buffer = buf, desc = "Show log" })

  -- i: back to index
  vim.keymap.set("n", "i", function() M.render() end, { buffer = buf, desc = "Index view" })

  -- R: refresh
  vim.keymap.set("n", "R", function()
    if _view == "log" and _active_log then M.show_log(_active_log)
    else M.render() end
  end, { buffer = buf, desc = "Refresh" })

  -- q: close window
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, desc = "Close" })
end

-- ── Toggle ────────────────────────────────────────────────────────────────

function M.toggle()
  local buf = get_or_create_buf()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_close(win, false); return
    end
  end
  M.render()
  local width = math.max(52, math.floor(vim.o.columns * 0.35))
  vim.cmd("botright vsplit | vertical resize " .. width)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_set_option_value("number",      false,    { win = 0 })
  vim.api.nvim_set_option_value("signcolumn",  "no",     { win = 0 })
  vim.api.nvim_set_option_value("winfixwidth", true,     { win = 0 })
  vim.api.nvim_set_option_value("statusline",  " 󰮮  ACP", { win = 0 })
end

return M
