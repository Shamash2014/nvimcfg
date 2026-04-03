local M = {}

M._buf          = nil
M._win          = nil
M._prev_win     = nil
M._tab          = "sessions"   -- "sessions" | "issues"
M._filter       = "all"
M._cursor_row   = 1
M._line_items   = {}           -- row -> SessionDesc | IssueDesc
M._first_item_row = nil
M._last_item_row  = nil
M._timer        = nil
M._dirty        = false
M._closing      = false

local ns = vim.api.nvim_create_namespace("nowork_console")

local status_icons = {
  running    = "●",
  input      = "⚠",
  idle       = "◆",
  done       = "✓",
}

local status_hl = {
  running    = "DiagnosticOk",
  input      = "DiagnosticWarn",
  idle       = "Comment",
  done       = "DiagnosticHint",
}

local issue_status_icons = {
  backlog    = "○",
  todo       = "◉",
  in_progress = "●",
  in_review  = "◈",
  blocked    = "⊘",
  done       = "✓",
}

local issue_status_hl = {
  backlog    = "Comment",
  todo       = "DiagnosticHint",
  in_progress = "DiagnosticOk",
  in_review  = "DiagnosticInfo",
  blocked    = "DiagnosticError",
  done       = "DiagnosticHint",
}

local priority_icons = {
  critical   = "▲",
  high       = "■",
  medium     = "●",
  low        = "▼",
}

local priority_hl = {
  critical   = "DiagnosticError",
  high       = "DiagnosticWarn",
  medium     = "DiagnosticOk",
  low        = "Comment",
}

local function is_valid()
  return M._buf and vim.api.nvim_buf_is_valid(M._buf)
end

local function _status_for(buf)
  local chat = require("djinni.nowork.chat")
  if chat._streaming[buf] then return "running" end
  if chat._last_perm_tool[buf] then return "input" end
  if chat._sessions[buf] then return "idle" end
  return "done"
end

local function _activity_for(buf)
  local chat = require("djinni.nowork.chat")
  if chat._streaming[buf] then
    local title = chat._last_tool_title[buf]
    return title and title or "streaming…"
  end
  if chat._last_perm_tool[buf] then
    return "⚠ " .. chat._last_perm_tool[buf]
  end
  return ""
end

local function _fmt_tokens(usage)
  if not usage then return "" end
  local total = (usage.input_tokens or 0) + (usage.output_tokens or 0)
  if total <= 0 then return "" end
  return total >= 1000 and string.format("%.1fk", total / 1000) or tostring(total)
end

local function _fmt_cost(usage)
  if not usage or not usage.cost or usage.cost <= 0 then return "" end
  return string.format("$%.2f", usage.cost)
end

local function _collect_sessions()
  local chat = require("djinni.nowork.chat")
  local seen = {}
  local result = {}

  local candidates = {}
  for buf in pairs(chat._sessions or {})  do candidates[buf] = true end
  for buf in pairs(chat._streaming or {}) do candidates[buf] = true end

  for buf in pairs(candidates) do
    if not vim.api.nvim_buf_is_valid(buf) then goto continue end
    if seen[buf] then goto continue end
    seen[buf] = true

    local name = vim.api.nvim_buf_get_name(buf)
    local short = vim.fn.fnamemodify(name, ":t:r")
    if short == "" then short = "[buf " .. buf .. "]" end

    local sid = chat._sessions[buf] or ""
    local sid_short = sid:sub(1, 8)

    local usage = chat._usage[buf]

    table.insert(result, {
      _type      = "session",
      buf        = buf,
      name       = short,
      session_id = sid_short,
      status     = _status_for(buf),
      activity   = _activity_for(buf),
      tokens     = _fmt_tokens(usage),
      cost       = _fmt_cost(usage),
    })
    ::continue::
  end

  table.sort(result, function(a, b)
    local order = { running = 1, input = 2, idle = 3, done = 4 }
    local oa = order[a.status] or 9
    local ob = order[b.status] or 9
    if oa ~= ob then return oa < ob end
    return a.name < b.name
  end)
  return result
end

local function _collect_issues()
  local issue = require("djinni.nowork.issue")
  local projects = require("djinni.integrations.projects")
  local result = {}
  for _, root in ipairs(projects.discover()) do
    local list = issue.list(root)
    for _, iss in ipairs(list) do
      iss._type = "issue"
      table.insert(result, iss)
    end
  end
  table.sort(result, function(a, b)
    return (a.updated_at or "") > (b.updated_at or "")
  end)
  return result
end

local function _filter_sessions(list)
  if M._filter == "all" then return list end
  local result = {}
  for _, sd in ipairs(list) do
    local ok = false
    if M._filter == "active" and sd.status == "running" then ok = true end
    if M._filter == "input"  and sd.status == "input"   then ok = true end
    if M._filter == "done"   and (sd.status == "idle" or sd.status == "done") then ok = true end
    if ok then table.insert(result, sd) end
  end
  return result
end

local function _filter_issues(list)
  if M._filter == "all" then return list end
  local result = {}
  for _, iss in ipairs(list) do
    local ok = false
    if M._filter == "active"  and iss.status == "in_progress" then ok = true end
    if M._filter == "review"  and iss.status == "in_review"   then ok = true end
    if M._filter == "blocked" and iss.status == "blocked"      then ok = true end
    if M._filter == "done"    and iss.status == "done"         then ok = true end
    if ok then table.insert(result, iss) end
  end
  return result
end

local function _set_hl(marks, line, col, end_col, hl)
  table.insert(marks, { line = line, col = col, end_col = end_col, hl = hl })
end

local function _set_virt(virts, line, chunks)
  virts[line] = chunks
end

local function _render()
  if not is_valid() then return end

  local lines   = {}
  local marks   = {}
  local virts   = {}
  local items   = {}

  local function push(text)
    table.insert(lines, text)
    return #lines
  end

  local function sep()
    local row = push(string.rep("─", vim.api.nvim_win_get_width(M._win) - 2))
    _set_hl(marks, row - 1, 0, -1, "NonText")
    return row
  end

  -- Tab bar
  local sessions_label = M._tab == "sessions" and "[Sessions]" or "Sessions"
  local issues_label   = M._tab == "issues"   and "[Issues]"   or "Issues"
  local tab_line = " " .. sessions_label .. "  " .. issues_label .. " "
  local tab_row = push(tab_line)
  -- Highlight active tab
  if M._tab == "sessions" then
    _set_hl(marks, tab_row - 1, 1, 1 + #sessions_label, "DiagnosticInfo")
  else
    local off = 1 + #sessions_label + 2
    _set_hl(marks, tab_row - 1, off, off + #issues_label, "DiagnosticInfo")
  end

  -- Filter bar
  local filter_line
  if M._tab == "sessions" then
    local filters = {
      { id = "all",    label = "All"    },
      { id = "active", label = "Active" },
      { id = "input",  label = "Input"  },
      { id = "done",   label = "Done"   },
    }
    local parts = {}
    local filter_row_marks = {}
    local col = 1
    for _, f in ipairs(filters) do
      local lbl = (M._filter == f.id) and ("[" .. f.label .. "]") or f.label
      table.insert(parts, lbl)
      if M._filter == f.id then
        table.insert(filter_row_marks, { col = col, end_col = col + #lbl, hl = "DiagnosticOk" })
      end
      col = col + #lbl + 2
    end
    filter_line = " " .. table.concat(parts, "  ") .. " "
    local frow = push(filter_line)
    for _, m in ipairs(filter_row_marks) do
      _set_hl(marks, frow - 1, m.col, m.end_col, m.hl)
    end
  else
    local filters = {
      { id = "all",     label = "All"     },
      { id = "active",  label = "Active"  },
      { id = "review",  label = "Review"  },
      { id = "blocked", label = "Blocked" },
      { id = "done",    label = "Done"    },
    }
    local parts = {}
    local filter_row_marks = {}
    local col = 1
    for _, f in ipairs(filters) do
      local lbl = (M._filter == f.id) and ("[" .. f.label .. "]") or f.label
      table.insert(parts, lbl)
      if M._filter == f.id then
        table.insert(filter_row_marks, { col = col, end_col = col + #lbl, hl = "DiagnosticOk" })
      end
      col = col + #lbl + 2
    end
    filter_line = " " .. table.concat(parts, "  ") .. " "
    local frow = push(filter_line)
    for _, m in ipairs(filter_row_marks) do
      _set_hl(marks, frow - 1, m.col, m.end_col, m.hl)
    end
  end

  sep()
  M._first_item_row = #lines + 1

  -- Content rows
  if M._tab == "sessions" then
    local sessions = _filter_sessions(_collect_sessions())
    if #sessions == 0 then
      local row = push("  No active sessions")
      _set_hl(marks, row - 1, 0, -1, "Comment")
    else
      for _, sd in ipairs(sessions) do
        local icon  = status_icons[sd.status] or "◆"
        local ihl   = status_hl[sd.status] or "Comment"
        local name  = sd.name
        local sid   = sd.session_id ~= "" and sd.session_id or "--------"
        local act   = sd.activity

        local row_text = string.format("  %s  %-22s %-9s %s", icon, name, sid, act)
        local row = push(row_text)
        items[row] = sd

        local icon_col = 2
        _set_hl(marks, row - 1, icon_col, icon_col + #icon, ihl)
        _set_hl(marks, row - 1, icon_col + #icon + 2, icon_col + #icon + 2 + #name, "Normal")

        if sd.sid ~= "" then
          local sid_col = icon_col + #icon + 2 + 22 + 1
          _set_hl(marks, row - 1, sid_col, sid_col + #sid, "Comment")
        end

        local vt = {}
        if sd.tokens ~= "" then
          table.insert(vt, { sd.tokens, "Number" })
        end
        if sd.cost ~= "" then
          if #vt > 0 then table.insert(vt, { "  ", "Normal" }) end
          table.insert(vt, { sd.cost, "String" })
        end
        if #vt > 0 then
          _set_virt(virts, row - 1, vt)
        end
      end
    end
  else
    local all_issues = _filter_issues(_collect_issues())
    if #all_issues == 0 then
      local row = push("  No issues")
      _set_hl(marks, row - 1, 0, -1, "Comment")
    else
      -- Group by project_root preserving sort order
      local groups = {}
      local group_map = {}
      for _, iss in ipairs(all_issues) do
        local key = iss.project_root or ""
        if not group_map[key] then
          group_map[key] = { name = iss.project_name or key, issues = {} }
          table.insert(groups, group_map[key])
        end
        table.insert(group_map[key].issues, iss)
      end

      for _, group in ipairs(groups) do
        local count = #group.issues
        local header = group.name .. " (" .. count .. " issue" .. (count ~= 1 and "s" or "") .. ")"
        local hrow = push("  " .. header)
        _set_hl(marks, hrow - 1, 2, 2 + #header, "Directory")

        for _, iss in ipairs(group.issues) do
          local picon = priority_icons[iss.priority] or "●"
          local phl   = priority_hl[iss.priority] or "Comment"
          local sicon = issue_status_icons[iss.status] or "○"
          local shl   = issue_status_hl[iss.status] or "Comment"

          local row_text = string.format("    %s %s  %s", picon, sicon, iss.title)
          local row = push(row_text)
          items[row] = iss

          _set_hl(marks, row - 1, 4, 4 + #picon, phl)
          _set_hl(marks, row - 1, 4 + #picon + 1, 4 + #picon + 1 + #sicon, shl)

          if iss.assignee_session then
            _set_virt(virts, row - 1, { { "→ " .. iss.assignee_session:sub(1, 8), "DiagnosticHint" } })
          end
        end
      end
    end
  end

  M._last_item_row = #lines
  sep()

  -- Footer
  local footer
  if M._tab == "sessions" then
    footer = "  <CR> jump  x interrupt  <Tab> issues  1-4 filter  r refresh  q close"
  else
    footer = "  <CR> open  n new  s status  d dispatch  <Tab> sessions  1-5 filter  r refresh  q close"
  end
  local frow = push(footer)
  _set_hl(marks, frow - 1, 0, -1, "Comment")

  -- Apply to buffer
  vim.bo[M._buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(M._buf, ns, 0, -1)
  for _, mk in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, M._buf, ns, mk.line, mk.col, {
      end_col  = mk.end_col,
      hl_group = mk.hl,
    })
  end
  for line_idx, vt in pairs(virts) do
    pcall(vim.api.nvim_buf_set_extmark, M._buf, ns, line_idx, 0, {
      virt_text     = vt,
      virt_text_pos = "right_align",
    })
  end

  M._line_items = items

  -- Restore cursor clamped to item rows
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    local first = M._first_item_row or 1
    local last  = M._last_item_row  or #lines
    local row   = math.max(first, math.min(M._cursor_row, last))
    pcall(vim.api.nvim_win_set_cursor, M._win, { row, 0 })
  end
end

local function _start_timer()
  M._timer = vim.uv.new_timer()
  M._timer:start(0, 500, vim.schedule_wrap(function()
    if not is_valid() then
      M._stop_timer()
      return
    end
    local chat = require("djinni.nowork.chat")
    for buf in pairs(chat._streaming or {}) do
      if chat._streaming[buf] then
        M._dirty = true
        break
      end
    end
    if M._dirty then
      M._dirty = false
      _render()
    end
  end))
end

function M._stop_timer()
  if M._timer then
    pcall(function() M._timer:stop() end)
    pcall(function() M._timer:close() end)
    M._timer = nil
  end
end

local function _item_at_cursor()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return nil end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  M._cursor_row = row
  return M._line_items[row]
end

local function _jump_to_session(sd)
  M.close()
  if M._prev_win and vim.api.nvim_win_is_valid(M._prev_win) then
    pcall(vim.api.nvim_set_current_win, M._prev_win)
  end
  if vim.api.nvim_buf_is_valid(sd.buf) then
    vim.api.nvim_set_current_buf(sd.buf)
  end
end

local function _interrupt_session(sd)
  local chat = require("djinni.nowork.chat")
  chat.interrupt(sd.buf)
  M._dirty = true
end

local function _open_issue(iss)
  M.close()
  if M._prev_win and vim.api.nvim_win_is_valid(M._prev_win) then
    pcall(vim.api.nvim_set_current_win, M._prev_win)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(iss.path))
end

local function _current_project_root()
  if M._prev_win and vim.api.nvim_win_is_valid(M._prev_win) then
    return vim.fn.getcwd(M._prev_win)
  end
  return vim.fn.getcwd()
end

local function _create_issue()
  local project_root = _current_project_root()
  vim.ui.input({ prompt = "Issue title: " }, function(title)
    if not title or title == "" then return end
    local issue = require("djinni.nowork.issue")
    issue.create(project_root, { title = title })
    M._dirty = true
    _render()
  end)
end

local function _cycle_status(iss)
  local issue = require("djinni.nowork.issue")
  local next_s = issue.next_status(iss.status)
  issue.update(iss.project_root, iss.id, { status = next_s })
  M._dirty = true
  _render()
end

local function _dispatch_issue(iss)
  M.close()
  if M._prev_win and vim.api.nvim_win_is_valid(M._prev_win) then
    pcall(vim.api.nvim_set_current_win, M._prev_win)
  end
  local issue = require("djinni.nowork.issue")
  issue.dispatch(iss.project_root, iss.id)
end

local function _set_filter(f)
  M._filter = f
  M._dirty = true
  _render()
end

local function _set_tab(t)
  M._tab = t
  M._filter = "all"
  M._cursor_row = 1
  M._dirty = true
  _render()
end

function M.cursor_down()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local first = M._first_item_row or 1
  local last  = M._last_item_row  or 1
  local cur   = vim.api.nvim_win_get_cursor(M._win)[1]
  local new   = math.min(cur + 1, last)
  if new < first then new = first end
  M._cursor_row = new
  pcall(vim.api.nvim_win_set_cursor, M._win, { new, 0 })
end

function M.cursor_up()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local first = M._first_item_row or 1
  local cur   = vim.api.nvim_win_get_cursor(M._win)[1]
  local new   = math.max(cur - 1, first)
  M._cursor_row = new
  pcall(vim.api.nvim_win_set_cursor, M._win, { new, 0 })
end

function M.open()
  if M._win and vim.api.nvim_win_is_valid(M._win) then return end

  M._prev_win = vim.api.nvim_get_current_win()

  local width  = math.floor(vim.o.columns * 0.95)
  local height = math.floor(vim.o.lines   * 0.90)
  local col    = math.floor((vim.o.columns - width)  / 2)
  local row    = math.floor((vim.o.lines   - height) / 2)

  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].buftype   = "nofile"
  vim.bo[M._buf].bufhidden = "wipe"
  vim.bo[M._buf].swapfile  = false
  vim.bo[M._buf].filetype  = "nowork-console"

  M._win = vim.api.nvim_open_win(M._buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    col        = col,
    row        = row,
    style      = "minimal",
    border     = "rounded",
    title      = " Nowork Console ",
    title_pos  = "center",
  })

  vim.wo[M._win].cursorline     = true
  vim.wo[M._win].wrap           = false
  vim.wo[M._win].number         = false
  vim.wo[M._win].relativenumber = false
  vim.wo[M._win].signcolumn     = "no"
  vim.wo[M._win].foldenable     = false

  local buf = M._buf
  local function map(keys, fn)
    if type(keys) == "string" then keys = { keys } end
    for _, k in ipairs(keys) do
      vim.keymap.set("n", k, fn, { buffer = buf, nowait = true })
    end
  end

  map({ "j", "<Down>" }, M.cursor_down)
  map({ "k", "<Up>" },   M.cursor_up)

  map("<CR>", function()
    local item = _item_at_cursor()
    if not item then return end
    if item._type == "session" then
      _jump_to_session(item)
    elseif item._type == "issue" then
      _open_issue(item)
    end
  end)

  map("x", function()
    local item = _item_at_cursor()
    if item and item._type == "session" then _interrupt_session(item) end
  end)

  map("n", function()
    if M._tab == "issues" then _create_issue() end
  end)

  map("s", function()
    local item = _item_at_cursor()
    if item and item._type == "issue" then _cycle_status(item) end
  end)

  map("d", function()
    local item = _item_at_cursor()
    if item and item._type == "issue" then _dispatch_issue(item) end
  end)

  map("<Tab>", function()
    _set_tab(M._tab == "sessions" and "issues" or "sessions")
  end)

  map("<S-Tab>", function()
    _set_tab(M._tab == "issues" and "sessions" or "issues")
  end)

  map("1", function() _set_filter("all") end)
  map("2", function()
    _set_filter(M._tab == "sessions" and "active" or "active")
  end)
  map("3", function()
    _set_filter(M._tab == "sessions" and "input" or "review")
  end)
  map("4", function()
    _set_filter(M._tab == "sessions" and "done" or "blocked")
  end)
  map("5", function()
    if M._tab == "issues" then _set_filter("done") end
  end)

  map({ "r", "<C-r>" }, function()
    M._dirty = true
    _render()
  end)

  map("D", function()
    local item = _item_at_cursor()
    if item and item._type == "issue" then
      local issue = require("djinni.nowork.issue")
      issue.delete(item.project_root, item.id)
      M._dirty = true
      _render()
    end
  end)

  map("?", function()
    if M._tab == "sessions" then
      vim.api.nvim_echo({
        { " Sessions: ", "DiagnosticInfo" },
        { "<CR>", "DiagnosticOk" }, { " jump  ", "Comment" },
        { "x", "DiagnosticOk" }, { " interrupt  ", "Comment" },
        { "<Tab>", "DiagnosticOk" }, { " issues  ", "Comment" },
        { "1-4", "DiagnosticOk" }, { " filter  ", "Comment" },
        { "r/<C-r>", "DiagnosticOk" }, { " refresh  ", "Comment" },
        { "q", "DiagnosticOk" }, { " close", "Comment" },
      }, false, {})
    else
      vim.api.nvim_echo({
        { " Issues: ", "DiagnosticInfo" },
        { "<CR>", "DiagnosticOk" }, { " open  ", "Comment" },
        { "n", "DiagnosticOk" }, { " new  ", "Comment" },
        { "s", "DiagnosticOk" }, { " status  ", "Comment" },
        { "d", "DiagnosticOk" }, { " dispatch  ", "Comment" },
        { "D", "DiagnosticOk" }, { " delete  ", "Comment" },
        { "<Tab>", "DiagnosticOk" }, { " sessions  ", "Comment" },
        { "1-5", "DiagnosticOk" }, { " filter  ", "Comment" },
        { "q", "DiagnosticOk" }, { " close", "Comment" },
      }, false, {})
    end
  end)

  map({ "q", "<Esc>" }, M.close)

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer   = M._buf,
    once     = true,
    callback = function() M.close() end,
  })

  _start_timer()
  M._dirty = true
  _render()
end

function M.close()
  if M._closing then return end
  M._closing = true
  M._stop_timer()
  local win = M._win
  M._win = nil
  M._buf = nil
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  M._closing = false
end

function M.toggle()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    M.close()
  else
    M.open()
  end
end

return M
