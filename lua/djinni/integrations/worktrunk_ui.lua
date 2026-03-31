local M = {}
local wt = require("djinni.integrations.worktrunk")

local _buf = nil
local _win = nil
local _entries = {}
local _line_map = {}
local _dirty_cache = {}
local _show_help = true
local _ns = vim.api.nvim_create_namespace("worktrunk_ui")

local DIRTY_TTL = 30000
local SPLIT_HEIGHT = 15

local function setup_highlights()
  local links = {
    WorktrunkHeader = "Title",
    WorktrunkSection = "Statement",
    WorktrunkSectionCount = "Comment",
    WorktrunkBranch = "Function",
    WorktrunkCurrent = "DiagnosticOk",
    WorktrunkTrunk = "DiagnosticInfo",
    WorktrunkDirty = "DiagnosticWarn",
    WorktrunkPath = "Comment",
    WorktrunkSeparator = "NonText",
    WorktrunkHelp = "Comment",
  }
  for group, fallback in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = fallback, default = true })
  end
end

local function is_open()
  return _win and vim.api.nvim_win_is_valid(_win)
end

local function entry_at_cursor()
  if not is_open() then return nil end
  local row = vim.api.nvim_win_get_cursor(_win)[1]
  return _line_map[row]
end

local function get_dirty(branch, cb)
  local cached = _dirty_cache[branch]
  if cached and (vim.uv.now() - cached.ts) < DIRTY_TTL then
    cb(cached.dirty)
    return
  end
  wt.is_dirty(branch, function(dirty)
    if dirty ~= nil then
      _dirty_cache[branch] = { dirty = dirty, ts = vim.uv.now() }
    end
    cb(dirty)
  end)
end

local function add_hl(hls, line, col_start, col_end, hl_group)
  table.insert(hls, { line = line, col = col_start, end_col = col_end, hl = hl_group })
end

local function render()
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return end

  local lines = {}
  local hls = {}
  _line_map = {}

  local current_branch = ""
  for _, e in ipairs(_entries) do
    if e.current then current_branch = e.branch; break end
  end

  local head_line = "Head:  " .. current_branch
  table.insert(lines, head_line)
  add_hl(hls, #lines, 0, 5, "WorktrunkHeader")
  add_hl(hls, #lines, 7, #head_line, "WorktrunkBranch")

  table.insert(lines, "")

  local section_title = "Worktrees (" .. #_entries .. ")"
  table.insert(lines, section_title)
  add_hl(hls, #lines, 0, #("Worktrees"), "WorktrunkSection")
  add_hl(hls, #lines, #("Worktrees"), #section_title, "WorktrunkSectionCount")

  if #_entries == 0 then
    table.insert(lines, "  (no worktrees)")
    add_hl(hls, #lines, 0, #("  (no worktrees)"), "WorktrunkHelp")
  end

  for _, entry in ipairs(_entries) do
    local marker = entry.current and "@" or (entry.trunk and "^" or " ")
    local branch_text = entry.branch
    local path_text = entry.path and ("  " .. entry.path) or ""
    local line = "  " .. marker .. " " .. branch_text .. path_text
    table.insert(lines, line)

    local ln = #lines
    _line_map[ln] = entry

    local marker_hl = entry.current and "WorktrunkCurrent"
      or (entry.trunk and "WorktrunkTrunk" or "NonText")
    add_hl(hls, ln, 2, 3, marker_hl)

    local branch_hl = entry.current and "WorktrunkCurrent"
      or (entry.trunk and "WorktrunkTrunk" or "WorktrunkBranch")
    add_hl(hls, ln, 4, 4 + #branch_text, branch_hl)

    if #path_text > 0 then
      add_hl(hls, ln, 4 + #branch_text, #line, "WorktrunkPath")
    end
  end

  table.insert(lines, "")
  local sep = string.rep("─", 50)
  table.insert(lines, sep)
  add_hl(hls, #lines, 0, #sep, "WorktrunkSeparator")

  if _show_help then
    local help_lines = {
      " <CR> switch    c create    d remove    m merge",
      " D    diff      C commit    S squash    r rebase",
      " p    push      P promote   x prune     R refresh",
      " ?    help      q close",
    }
    for _, h in ipairs(help_lines) do
      table.insert(lines, h)
      add_hl(hls, #lines, 0, #h, "WorktrunkHelp")
    end
  else
    table.insert(lines, " Press ? for help")
    add_hl(hls, #lines, 0, #(" Press ? for help"), "WorktrunkHelp")
  end

  vim.bo[_buf].modifiable = true
  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.bo[_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(_buf, _ns, 0, -1)
  for _, hl in ipairs(hls) do
    if hl.end_col and hl.end_col > hl.col then
      pcall(vim.api.nvim_buf_add_highlight, _buf, _ns, hl.hl, hl.line - 1, hl.col, hl.end_col)
    end
  end

  for ln, entry in pairs(_line_map) do
    local cached = _dirty_cache[entry.branch]
    if cached and cached.dirty then
      pcall(vim.api.nvim_buf_set_extmark, _buf, _ns, ln - 1, 0, {
        virt_text = { { " ●", "WorktrunkDirty" } },
        virt_text_pos = "eol",
      })
    end
  end
end

local function refresh()
  wt.list(function(entries)
    if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return end
    if not entries then
      _entries = {}
      vim.schedule(render)
      return
    end

    _entries = entries

    local pending = 0
    local done = false
    for _, entry in ipairs(_entries) do
      pending = pending + 1
      get_dirty(entry.branch, function()
        pending = pending - 1
        if pending == 0 and not done then
          done = true
          vim.schedule(render)
        end
      end)
    end

    if pending == 0 then
      vim.schedule(render)
    end
  end)
end

local function invalidate_and_refresh(branch)
  if branch then _dirty_cache[branch] = nil end
  refresh()
end

local function setup_keymaps()
  if not _buf then return end
  local opts = { buffer = _buf, nowait = true, silent = true }

  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)

  vim.keymap.set("n", "R", function() refresh() end, opts)

  vim.keymap.set("n", "?", function()
    _show_help = not _show_help
    render()
  end, opts)

  vim.keymap.set("n", "<CR>", function()
    local entry = entry_at_cursor()
    if not entry then return end
    M.close()
    wt.switch_to(entry.branch)
  end, opts)

  vim.keymap.set("n", "c", function()
    vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
      if not branch or branch == "" then return end
      wt.create(branch, function(ok, result)
        vim.schedule(function()
          if ok then
            vim.notify("[wt] Created: " .. branch, vim.log.levels.INFO)
            invalidate_and_refresh(branch)
          else
            vim.notify("[wt] Create failed: " .. (result or ""), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end, opts)

  vim.keymap.set("n", "d", function()
    local entry = entry_at_cursor()
    if not entry then return end
    vim.ui.input({ prompt = "Remove '" .. entry.branch .. "'? (y/n): " }, function(answer)
      if answer ~= "y" then return end
      wt.remove(entry.branch, function(ok, msg)
        vim.schedule(function()
          if ok then
            vim.notify("[wt] Removed: " .. entry.branch, vim.log.levels.INFO)
            invalidate_and_refresh(entry.branch)
          else
            vim.notify("[wt] Remove failed: " .. (msg or ""), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end, opts)

  vim.keymap.set("n", "m", function()
    local entry = entry_at_cursor()
    if not entry then return end
    vim.ui.input({ prompt = "Merge '" .. entry.branch .. "' into: " }, function(target)
      if not target or target == "" then return end
      wt.merge(target, entry.branch, function(ok, lines, stderr)
        vim.schedule(function()
          wt.notify_result("merge", ok, lines, stderr)
          invalidate_and_refresh(entry.branch)
        end)
      end)
    end)
  end, opts)

  vim.keymap.set("n", "D", function()
    local entry = entry_at_cursor()
    if not entry then return end
    wt.diff(entry.branch, function(ok, lines, stderr)
      vim.schedule(function()
        if ok and #lines > 0 then
          wt.open_diff_buf(lines)
        elseif ok then
          vim.notify("[wt] No changes", vim.log.levels.INFO)
        else
          vim.notify("[wt] Diff failed: " .. table.concat(stderr or {}, "\n"), vim.log.levels.ERROR)
        end
      end)
    end)
  end, opts)

  vim.keymap.set("n", "C", function()
    local entry = entry_at_cursor()
    if not entry then return end
    wt.commit(entry.branch, function(ok, lines, stderr)
      vim.schedule(function()
        wt.notify_result("commit", ok, lines, stderr)
        invalidate_and_refresh(entry.branch)
      end)
    end)
  end, opts)

  vim.keymap.set("n", "S", function()
    local entry = entry_at_cursor()
    if not entry then return end
    wt.squash(entry.branch, function(ok, lines, stderr)
      vim.schedule(function()
        wt.notify_result("squash", ok, lines, stderr)
        invalidate_and_refresh(entry.branch)
      end)
    end)
  end, opts)

  vim.keymap.set("n", "r", function()
    local entry = entry_at_cursor()
    if not entry then return end
    vim.ui.input({ prompt = "Rebase '" .. entry.branch .. "' onto: " }, function(target)
      if not target then return end
      wt.rebase(target, entry.branch, function(ok, lines, stderr)
        vim.schedule(function()
          wt.notify_result("rebase", ok, lines, stderr)
          invalidate_and_refresh(entry.branch)
        end)
      end)
    end)
  end, opts)

  vim.keymap.set("n", "p", function()
    local entry = entry_at_cursor()
    if not entry then return end
    vim.ui.input({ prompt = "Push '" .. entry.branch .. "' to (empty=trunk): " }, function(target)
      if not target then return end
      wt.push(target, entry.branch, function(ok, lines, stderr)
        vim.schedule(function()
          wt.notify_result("push", ok, lines, stderr)
          invalidate_and_refresh(entry.branch)
        end)
      end)
    end)
  end, opts)

  vim.keymap.set("n", "P", function()
    local entry = entry_at_cursor()
    if not entry then return end
    wt.promote(entry.branch, function(ok, lines, stderr)
      vim.schedule(function()
        wt.notify_result("promote", ok, lines, stderr)
        invalidate_and_refresh(entry.branch)
      end)
    end)
  end, opts)

  vim.keymap.set("n", "x", function()
    wt.prune(function(ok, lines, stderr)
      vim.schedule(function()
        wt.notify_result("prune", ok, lines, stderr)
        _dirty_cache = {}
        refresh()
      end)
    end)
  end, opts)
end

function M.open()
  if is_open() then
    vim.api.nvim_set_current_win(_win)
    return
  end

  setup_highlights()

  _buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_buf].buftype = "nofile"
  vim.bo[_buf].bufhidden = "wipe"
  vim.bo[_buf].swapfile = false
  vim.bo[_buf].filetype = "worktrunk"
  vim.bo[_buf].modifiable = false

  vim.cmd("botright split")
  _win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(_win, _buf)
  vim.api.nvim_win_set_height(_win, SPLIT_HEIGHT)

  vim.wo[_win].number = false
  vim.wo[_win].relativenumber = false
  vim.wo[_win].signcolumn = "no"
  vim.wo[_win].foldcolumn = "0"
  vim.wo[_win].wrap = false
  vim.wo[_win].cursorline = true
  vim.wo[_win].winhighlight = "CursorLine:Visual"

  setup_keymaps()
  refresh()

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = _buf,
    once = true,
    callback = function()
      _buf = nil
      _win = nil
      _line_map = {}
    end,
  })
end

function M.close()
  if is_open() then
    vim.api.nvim_win_close(_win, true)
  end
  _win = nil
  if _buf and vim.api.nvim_buf_is_valid(_buf) then
    vim.api.nvim_buf_delete(_buf, { force = true })
  end
  _buf = nil
  _line_map = {}
end

function M.toggle()
  if is_open() then
    M.close()
  else
    M.open()
  end
end

function M.setup()
  setup_highlights()

  vim.api.nvim_create_user_command("Worktrunk", function()
    M.toggle()
  end, {})

  vim.keymap.set("n", "<leader>oww", function()
    M.toggle()
  end, { desc = "Worktrunk UI" })
end

return M
