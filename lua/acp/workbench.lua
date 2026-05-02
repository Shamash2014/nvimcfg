local M = {}

local _view        = "index"
local _log_path    = nil
local _context     = {}
local _folds       = {}
local _sb_line_meta = {}

local function pick(items, labels, prompt, on_choice)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker.select(labels, { prompt = prompt }, function(_, idx)
      if idx then on_choice(items[idx], idx) end
    end)
  else
    vim.ui.select(labels, { prompt = prompt }, function(_, idx)
      if idx then on_choice(items[idx], idx) end
    end)
  end
end

local function input(prompt, on_confirm)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.input then
    snacks.input({ prompt = prompt }, on_confirm)
  else
    vim.ui.input({ prompt = prompt }, on_confirm)
  end
end

-- ── .nowork file helpers ──────────────────────────────────────

local function nowork_dir(cwd) return cwd .. "/.nowork" end

function M.new_file(cwd, title)
  vim.fn.mkdir(nowork_dir(cwd), "p")
  local slug = (title or "work"):lower():gsub("[^a-z0-9]+", "-"):sub(1, 40)
  return nowork_dir(cwd) .. "/" .. os.time() .. "-" .. slug .. ".md"
end

function M.log_path(p) return p:gsub("%.md$", ".log.md") end

function M.log(path, line)
  if not path then return end
  local f = io.open(M.log_path(path), "a")
  if f then f:write(os.date("[%H:%M:%S] ") .. line .. "\n"); f:close() end
end

function M.list(cwd)
  local files = vim.fn.glob(nowork_dir(cwd) .. "/*.md", false, true)
  files = vim.tbl_filter(function(f) return not f:match("%.log%.md$") end, files)
  table.sort(files, function(a, b) return a > b end)
  return files
end

function M.load_file(path)
  if not path then return nil end
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close()
  return s ~= "" and s or nil
end

-- ── Scratch goal buffer ───────────────────────────────────────

function M.set(cwd)
  cwd = cwd or vim.fn.getcwd()
  require("acp.float").open_composer_float("New Work Item", {
    on_submit = function(text)
      local first = vim.trim((vim.split(text, "\n", { plain = true })[1] or ""))
      local title = first ~= "" and first or "untitled"
      local path  = M.new_file(cwd, title)
      local f     = io.open(path, "w")
      if f then f:write(text); f:close() end
      M.run(cwd, path)
    end,
  })
end

-- ── Run ──────────────────────────────────────────────────────

function M.run(cwd, path)
  cwd  = cwd  or vim.fn.getcwd()
  path = path or M.list(cwd)[1]
  local text = M.load_file(path)
  if not text or vim.trim(text) == "" then
    vim.notify("No work item. Use <leader>aw to create one.", vim.log.levels.WARN, { title = "acp" })
    return
  end

  M.log(path, "--- start ---")
  local prompt = M.drain_context()
  table.insert(prompt, { type = "text", text = "Complete the following work item:\n\n" .. text })

  require("acp.session").get_or_create(cwd, function(err, sess)
    if err then
      vim.notify("ACP: " .. err, vim.log.levels.ERROR, { title = "acp" }); return
    end
    vim.notify("ACP work started", vim.log.levels.INFO, { title = "acp" })
    M.show_log(path)

    sess.rpc:subscribe(sess.session_id, function(notif)
      local update = (notif.params or {}).update or {}
      local su     = update.sessionUpdate

      if su == "tool_call" then
        local line = "tool: " .. (update.kind or "?") .. " — " .. (update.title or "")
        M.log(path, line)
        vim.schedule(function() M.on_event(path, line) end)
      elseif su == "tool_call_update" and update.status then
        local line = "  " .. update.status
        M.log(path, line)
        vim.schedule(function() M.on_event(path, line) end)
      elseif su == "text" and update.text then
        local f = io.open(M.log_path(path), "a")
        if f then f:write(update.text); f:close() end
        vim.schedule(function() M.on_event(path, update.text) end)
      elseif su == "plan" and update.entries then
        local icons = { pending = "·", in_progress = "▸", completed = "✓" }
        local parts = { "--- plan ---" }
        for _, e in ipairs(update.entries) do
          table.insert(parts, (icons[e.status] or "·") .. " " .. e.content)
        end
        local line = table.concat(parts, "\n")
        M.log(path, line)
        vim.schedule(function() M.on_event(path, line) end)
      elseif su == "agent_thought_chunk" and update.text then
        local line = "> " .. update.text
        M.log(path, line)
        vim.schedule(function() M.on_event(path, line) end)
      elseif su == "agent_message_chunk" and update.text then
        local f = io.open(M.log_path(path), "a")
        if f then f:write(update.text); f:close() end
        vim.schedule(function() M.on_event(path, update.text) end)
      elseif su == "activity" and update.activity then
        local line = "  ~ " .. update.activity
        M.log(path, line)
        vim.schedule(function() M.on_event(path, line) end)
      end
    end)

    sess.rpc:request("session/prompt", {
      sessionId = sess.session_id,
      prompt    = prompt,
    }, function(req_err, res)
      local reason = (res and res.stopReason) or (req_err and "error") or "unknown"
      local line = "--- stop: " .. reason .. " ---"
      M.log(path, line)
      vim.schedule(function()
        M.on_event(path, line)
        vim.notify("ACP done (" .. reason .. ")", vim.log.levels.INFO, { title = "acp" })
      end)
    end)
  end)
end

function M.check_left(cwd)
  cwd = cwd or vim.fn.getcwd()
  local path = M.list(cwd)[1]
  local text = M.load_file(path)
  if not text then vim.notify("No work item.", vim.log.levels.WARN, { title = "acp" }); return end

  require("acp.session").get_or_create(cwd, function(err, sess)
    if err then vim.notify(err, vim.log.levels.ERROR, { title = "acp" }); return end
    local result = ""
    sess.rpc:subscribe(sess.session_id, function(notif)
      local update = (notif.params or {}).update or {}
      if update.sessionUpdate == "text" then result = result .. (update.text or "") end
    end)
    sess.rpc:request("session/prompt", {
      sessionId = sess.session_id,
      prompt    = { { type = "text", text = "Work item:\n\n" .. text
        .. "\n\nList what is still left as bullet points." } },
    }, function(_, res)
      if res then
        local items = {}
        for _, l in ipairs(vim.split(result, "\n", { plain = true })) do
          if vim.trim(l) ~= "" then table.insert(items, { text = l, bufnr = 0, lnum = 0 }) end
        end
        vim.fn.setqflist(items, "r", { title = "ACP: What's left?" })
        vim.cmd("copen")
      end
    end)
  end)
end

-- ── Push context ──────────────────────────────────────────────

function M.push(label, content)
  table.insert(_context, { type = "text", text = "--- " .. label .. " ---\n\n" .. content, _label = label })
  vim.notify("Pinned: " .. label, vim.log.levels.INFO, { title = "acp" })
  if _view == "index" then M.render() end
end

function M.push_image(path)
  local f = io.open(path, "rb")
  if not f then
    vim.notify("Cannot read: " .. path, vim.log.levels.WARN, { title = "acp" }); return
  end
  local raw = f:read("*a"); f:close()
  local b64  = vim.base64.encode(raw)
  local ext  = (path:match("%.(%w+)$") or "png"):lower()
  local mime = ({ png="image/png", jpg="image/jpeg", jpeg="image/jpeg", gif="image/gif", webp="image/webp" })
  table.insert(_context, { type = "image", mediaType = mime[ext] or "image/png", data = b64,
                            _label = vim.fn.fnamemodify(path, ":t") })
  vim.notify("Pinned image: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO, { title = "acp" })
  if _view == "index" then M.render() end
end

function M.drain_context()
  local items = {}
  for _, c in ipairs(_context) do
    if c.type == "image" then
      table.insert(items, { type = "image", mediaType = c.mediaType, data = c.data })
    else
      table.insert(items, { type = "text", text = c.text })
    end
  end
  _context = {}
  return items
end

function M.push_visual()
  vim.schedule(function()
    local l1 = vim.fn.line("'<"); local l2 = vim.fn.line("'>")
    local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
    M.push(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.") .. ":" .. l1 .. "-" .. l2,
           table.concat(lines, "\n"))
  end)
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
  for _, d in ipairs(diags) do table.insert(ls, name .. ":" .. (d.lnum + 1) .. ": " .. d.message) end
  M.push("diagnostics: " .. name, table.concat(ls, "\n"))
end

-- ── Display layer (codereview.nvim style) ────────────────────

local NS     = vim.api.nvim_create_namespace("acp_wb")
local _sb_win   = nil
local _main_buf = nil
local _main_win = nil

local _hl_ready = false
local function setup_hl()
  if _hl_ready then return end
  _hl_ready = true
  local hl = function(n, o) vim.api.nvim_set_hl(0, n, o) end
  hl("AcpHeader",          { link = "Comment",         default = true })
  hl("AcpBranch",          { link = "Title",           default = true })
  hl("AcpSectionHeader",   { link = "Title",           default = true })
  hl("AcpAgentOk",         { link = "DiagnosticOk",    default = true })
  hl("AcpAgentBusy",       { link = "DiagnosticWarn",  default = true })
  hl("AcpPending",         { link = "DiagnosticError", default = true })
  hl("AcpContextItem",     { link = "Special",         default = true })
  hl("AcpWorkDone",        { link = "DiagnosticOk",    default = true })
  hl("AcpFooter",          { link = "Comment",         default = true })
  hl("AcpDiffAdd",         { link = "DiffAdd",         default = true })
  hl("AcpDiffDelete",      { link = "DiffDelete",      default = true })
  hl("AcpDiffHunk",        { link = "Comment",         default = true })
  hl("AcpDiffFile",        { link = "Title",           default = true })
  hl("AcpDiffFileM",       { link = "Changed",         default = true })
  hl("AcpDiffFileA",       { link = "Added",           default = true })
  hl("AcpDiffFileD",       { link = "Removed",         default = true })
  hl("AcpCommentContext",  { link = "CursorLine",      default = true })
  hl("AcpCommentBorder",   { link = "Comment",         default = true })
  hl("AcpThreadBorder",    { link = "Function",        default = true })
  hl("AcpFloatTitle",      { link = "Title",           default = true })
  hl("AcpFloatFooterKey",  { link = "Special",         default = true })
  hl("AcpFloatFooterText", { link = "Comment",         default = true })
  hl("AcpThreadOpen",      { link = "DiagnosticWarn",  default = true })
  hl("AcpThreadResolved",  { link = "DiagnosticOk",    default = true })
  hl("AcpThreadPrefix",    { link = "Comment",         default = true })
  hl("AcpThreadAgent",     { link = "Function",        default = true })
  hl("AcpPipeOk",          { link = "DiagnosticOk",    default = true })
  hl("AcpPipeFail",        { link = "DiagnosticError", default = true })
  hl("AcpPipePend",        { link = "DiagnosticWarn",  default = true })
  hl("AcpPipeRunning",     { link = "DiagnosticInfo",  default = true })
  hl("AcpWinbarText",      { link = "WinBar",          default = true })
  vim.fn.sign_define("AcpThreadOpen",     { text = "▍ ", texthl = "AcpThreadOpen"    })
  vim.fn.sign_define("AcpThreadResolved", { text = "▍ ", texthl = "AcpThreadResolved"})
  vim.fn.sign_define("AcpAgentSign",      { text = "● ", texthl = "AcpAgentOk"       })
end

local function get_or_create_sb_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):match("%[acp%]$") then return b end
  end
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].buftype   = "nofile"
  vim.bo[b].swapfile  = false
  vim.bo[b].filetype  = "acp"
  vim.api.nvim_buf_set_name(b, "[acp]")
  return b
end

local function get_or_create_main_buf()
  if _main_buf and vim.api.nvim_buf_is_valid(_main_buf) then return _main_buf end
  _main_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_main_buf].bufhidden = "hide"
  vim.bo[_main_buf].buftype   = "nofile"
  vim.bo[_main_buf].swapfile  = false
  vim.bo[_main_buf].filetype  = "acp"
  vim.api.nvim_buf_set_name(_main_buf, "[acp-main]")
  return _main_buf
end

local function set_winbar(win, title)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].winbar = "%#AcpWinbarText#  " .. title .. "  %*"
end

function M._open_panels()
  setup_hl()
  local sb_buf   = get_or_create_sb_buf()
  local main_buf = get_or_create_main_buf()

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == sb_buf then
      _sb_win = win
      vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(win))
      vim.api.nvim_set_current_win(win)
      goto found_sb
    end
  end
  do
    vim.cmd("tabnew")
    _sb_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(_sb_win, sb_buf)
    vim.wo[_sb_win].number         = false
    vim.wo[_sb_win].relativenumber = false
    vim.wo[_sb_win].signcolumn     = "no"
    vim.wo[_sb_win].winfixwidth    = true
    vim.wo[_sb_win].wrap           = false
    vim.wo[_sb_win].cursorline     = true
    M._install_keymaps(sb_buf)
  end
  ::found_sb::

  local current_tab = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
    if vim.api.nvim_win_get_buf(win) == main_buf then
      _main_win = win
      return
    end
  end

  vim.api.nvim_set_current_win(_sb_win)
  vim.cmd("botright vsplit")
  _main_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(_main_win, main_buf)
  vim.api.nvim_win_set_width(_sb_win, 40)
  vim.wo[_main_win].number         = false
  vim.wo[_main_win].relativenumber = false
  vim.wo[_main_win].signcolumn     = "yes"
  vim.wo[_main_win].wrap           = false
  vim.wo[_main_win].cursorline     = true
  set_winbar(_main_win, "diff")

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(_sb_win), tostring(_main_win) },
    once = true,
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      local other_win = (closed_win == _sb_win) and _main_win or _sb_win
      if other_win and vim.api.nvim_win_is_valid(other_win) then
        pcall(vim.api.nvim_win_close, other_win, true)
      end
      if closed_win == _sb_win then _sb_win = nil else _main_win = nil end
    end,
  })

  local saved_visual
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = main_buf,
    callback = function()
      saved_visual = vim.api.nvim_get_hl(0, { name = "Visual" })
      vim.api.nvim_set_hl(0, "Visual", { bg = "#1e2030", fg = "#565f89", italic = true })
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = main_buf,
    callback = function()
      if saved_visual then vim.api.nvim_set_hl(0, "Visual", saved_visual) end
    end,
  })
end

function M.render()
  _view          = "index"
  local cwd      = vim.fn.getcwd()
  local sb_buf   = get_or_create_sb_buf()
  local agents   = require("acp.session").active()
  local pending  = require("acp.mailbox").pending_count()
  local work_files  = M.list(cwd)
  local diff_files  = require("acp.diff").list_files(cwd)
  local ls, hls  = {}, {}
  _sb_line_meta  = {}

  local function add(s, hl, meta)
    local row = #ls
    table.insert(ls, s or "")
    if hl   then table.insert(hls, { row, hl }) end
    if meta then _sb_line_meta[row] = meta end
  end

  local function sect(key, title, items)
    local is_open = _folds[key] ~= false
    local icon    = is_open and "▼ " or "▶ "
    add(icon .. title .. " (" .. #items .. ")", "AcpSectionHeader",
        { kind = "section", key = key })
    if is_open then
      for _, item in ipairs(items) do
        add(item[1], item[2], item[3])
      end
    end
    add("")
  end

  -- Header (magit-style: project + branch)
  local branch = vim.trim(vim.fn.system(
    "git -C " .. vim.fn.shellescape(cwd) .. " branch --show-current 2>/dev/null"))
  
  if branch ~= "" then
    add("Head: " .. branch, "AcpBranch")
  end
  add("Path: " .. vim.fn.fnamemodify(cwd, ":~"), "AcpHeader")
  add("")

  -- Pending notice (not a section — always visible)
  if pending > 0 then
    add("  ! " .. pending .. " permission(s) pending  <leader>am", "AcpPending")
    add("")
  end

  -- Plans (always visible)
  do
    local items = {}
    for _, f in ipairs(work_files) do
      local has_log = vim.fn.filereadable(M.log_path(f)) == 1
      local status  = has_log and "✔ " or "· "
      local hl      = has_log and "AcpWorkDone" or nil
      local name    = vim.fn.fnamemodify(f, ":t:r"):gsub("^%d+%-", "", 1)
      table.insert(items, { status .. " " .. name, hl, { kind = "work", path = f } })
    end
    sect("work", "Plans", items)
  end

  -- Context (always visible)
  do
    local items = {}
    for _, c in ipairs(_context) do
      local kind = c.type == "image" and "🖼 " or "📝 "
      table.insert(items, { kind .. " " .. (c._label or "context"), "AcpContextItem" })
    end
    sect("context", "Context", items)
  end

  -- Worktrees
  do
    local wt_json = vim.fn.system("wt list --format=json")
    if vim.v.shell_error == 0 then
      local ok, wt_data = pcall(vim.json.decode, wt_json)
      if ok and type(wt_data) == "table" then
        local items = {}
        for _, wt in ipairs(wt_data) do
          if wt.kind == "worktree" then
            local prefix = wt.is_current and "* " or "  "
            local name = wt.branch or "(detached)"
            local hl = wt.is_current and "AcpBranch" or "Comment"
            table.insert(items, { prefix .. name .. "  " .. wt.path:gsub("^" .. vim.env.HOME, "~"), hl, { kind = "worktree", path = wt.path } })
          end
        end
        if #items > 0 then
          sect("worktrees", "Worktrees", items)
        end
      end
    end
  end

  -- Agents (only when active)
  if #agents > 0 then
    local items = {}
    for _, a in ipairs(agents) do
      local status = a.state == "ready" and "✓ " or "⟳ "
      local ahl    = a.state == "ready" and "AcpAgentOk" or "AcpAgentBusy"
      table.insert(items, { status .. " " .. vim.fn.fnamemodify(a.cwd, ":~"), ahl })
    end
    sect("agents", "Active Agents", items)
  end

  -- Changed Files
  do
    local STATUS_WORDS = { A = "A ", M = "M ", D = "D " }
    local STATUS_HLS   = { A = "AcpDiffFileA", M = "AcpDiffFileM", D = "AcpDiffFileD" }
    local items = {}
    for _, f in ipairs(diff_files) do
      local word = STATUS_WORDS[f.status] or "M "
      local hl   = STATUS_HLS[f.status]
      table.insert(items, { word .. " " .. f.path, hl, { kind = "diff", path = f.path } })
    end
    sect("changed", "Unstaged changes", items)
  end

  -- Threads: work item sessions + diff line comments
  do
    local items = {}
    for _, f in ipairs(work_files) do
      local has_log = vim.fn.filereadable(M.log_path(f)) == 1
      local status  = has_log and "✔ " or "· "
      local hl      = has_log and "AcpWorkDone" or "AcpThreadOpen"
      local name    = vim.fn.fnamemodify(f, ":t:r"):gsub("^%d+%-", "", 1)
      table.insert(items, { status .. " " .. name, hl, { kind = "work", path = f } })
    end
    for _, entry in ipairs(require("acp.diff").get_threads(cwd)) do
      local t      = entry.thread
      local status = t.resolved and "✔ " or "💬 "
      local hl     = t.resolved and "AcpWorkDone" or "AcpThreadOpen"
      local fname  = vim.fn.fnamemodify(entry.file, ":t")
      local prompt = t.prompt:sub(1, 28) .. (t.prompt:len() > 28 and "…" or "")
      table.insert(items, {
        status .. " " .. fname .. ":" .. entry.row .. "  " .. prompt,
        hl,
        { kind = "thread", file = entry.file, row = entry.row },
      })
    end
    sect("threads", "Active threads", items)
  end

  add("  TAB fold  <CR> open  n new  p pipeline  q close  g? help", "AcpFooter")

  vim.bo[sb_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sb_buf, 0, -1, false, ls)
  vim.bo[sb_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(sb_buf, NS, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(sb_buf, NS, h[1], 0, { line_hl_group = h[2] })
  end
end

function M.show_help()
  local lines = {
    "  ACP  key bindings",
    "",
    "  Sidebar",
    "  TAB    fold / unfold section",
    "  <CR>   run work item / open diff",
    "  n      new work item",
    "  o      edit work item file",
    "  L      show work item log",
    "  p      pipeline view",
    "  R      refresh",
    "  q      close",
    "",
    "  Diff pane",
    "  a      new comment thread",
    "  r      reply to thread",
    "  x      toggle resolve",
    "  d      delete thread",
    "  s      send diff to ACP",
    "  ]c/[c  next / prev hunk",
  }
  local hbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[hbuf].bufhidden = "wipe"
  vim.bo[hbuf].filetype  = "acp"
  vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, lines)
  vim.bo[hbuf].modifiable = false
  local h = #lines
  local hwin = vim.api.nvim_open_win(hbuf, true, {
    relative  = "editor",
    width     = 42,
    height    = h,
    row       = math.floor((vim.o.lines - h) / 2),
    col       = math.floor((vim.o.columns - 42) / 2),
    style     = "minimal",
    border    = "rounded",
    title     = " help ",
    title_pos = "center",
    noautocmd = true,
  })
  vim.wo[hwin].cursorline = false
  local function close() pcall(vim.api.nvim_win_close, hwin, true) end
  for _, k in ipairs({ "q", "<Esc>", "g?", "?", "<CR>" }) do
    vim.keymap.set("n", k, close,
      { buffer = hbuf, nowait = true, noremap = true, silent = true })
  end
end

function M._install_keymaps(buf)
  local function km(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn,
      { buffer = buf, nowait = true, noremap = true, silent = true, desc = desc })
  end

  local function meta_at_cursor()
    return _sb_line_meta[vim.api.nvim_win_get_cursor(0)[1] - 1]
  end

  km("<CR>", function()
    local meta = meta_at_cursor()
    if not meta then return end
    if meta.kind == "work" and vim.fn.filereadable(meta.path) == 1 then
      M.run(vim.fn.getcwd(), meta.path)
    elseif meta.kind == "diff" then
      require("acp.diff").show_file(meta.path, _main_win, _main_buf,
        function(t) set_winbar(_main_win, t) end)
      vim.api.nvim_set_current_win(_main_win)
    elseif meta.kind == "thread" then
      require("acp.diff").show_file(meta.file, _main_win, _main_buf,
        function(t) set_winbar(_main_win, t) end)
      vim.api.nvim_set_current_win(_main_win)
      vim.api.nvim_win_set_cursor(_main_win, { meta.row + 1, 0 })
    elseif meta.kind == "worktree" then
      if meta.path ~= vim.fn.getcwd() then
        vim.cmd("cd " .. vim.fn.fnameescape(meta.path))
        M.render()
        vim.notify("Switched to worktree: " .. meta.path, vim.log.levels.INFO, {title="acp"})
      end
    end
  end, "Run / open diff")

  km("o", function()
    local meta = meta_at_cursor()
    if meta and meta.kind == "work" then
      vim.cmd("edit " .. vim.fn.fnameescape(meta.path))
    end
  end, "Edit goal")

  km("L", function()
    local meta = meta_at_cursor()
    if meta and meta.kind == "work" then M.show_log(meta.path) end
  end, "Show log")

  km("n", function()
    M.set(vim.fn.getcwd())
  end, "New work item")

  km("p", function()
    require("acp.pipeline").open(vim.fn.getcwd(), _main_win, _main_buf,
      function(t) set_winbar(_main_win, t) end)
  end, "Pipeline")

  km("<Tab>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local section_key
    for r = row, 0, -1 do
      local m = _sb_line_meta[r]
      if m and m.kind == "section" then
        section_key = m.key
        break
      end
    end
    if section_key then
      if _folds[section_key] == false then
        _folds[section_key] = nil
      else
        _folds[section_key] = false
      end
      M.render()
    end
  end, "Fold/unfold section")

  km("g?", M.show_help, "Help")
  km("?", M.show_help, "Help")

  km("i", M.render, "Index")
  km("R", function()
    if _view == "log" and _log_path then M.show_log(_log_path) else M.render() end
  end, "Refresh")

  km("q", function()
    for _, win in ipairs({ _sb_win, _main_win }) do
      if win and vim.api.nvim_win_is_valid(win) then
        pcall(function() vim.wo[win].winbar = "" end)
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    _sb_win = nil; _main_win = nil
  end, "Close")
end

function M.open()
  M._open_panels()
  M.render()
  local cwd = vim.fn.getcwd()
  local df  = require("acp.diff").list_files(cwd)
  if #df > 0 then
    require("acp.diff").show_file(df[1].path, _main_win, _main_buf,
      function(t) set_winbar(_main_win, t) end)
  end
  if _sb_win and vim.api.nvim_win_is_valid(_sb_win) then
    vim.api.nvim_set_current_win(_sb_win)
  end
end

function M.show_log(work_path)
  _view     = "log"
  _log_path = work_path
  M._open_panels()
  local buf = get_or_create_main_buf()
  local log = M.log_path(work_path)
  local ls  = { "# " .. vim.fn.fnamemodify(work_path, ":t:r"), "", "  i=index  R=refresh", "" }
  if vim.fn.filereadable(log) == 1 then
    vim.list_extend(ls, vim.fn.readfile(log))
  else
    table.insert(ls, "  (no log yet)")
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, ls)
  vim.bo[buf].modifiable = false
  set_winbar(_main_win, vim.fn.fnamemodify(work_path, ":t:r"))
  local function km(lhs, fn)
    vim.keymap.set("n", lhs, fn,
      { buffer = buf, nowait = true, noremap = true, silent = true })
  end
  km("i", M.render)
  km("R", function() M.show_log(_log_path) end)
  km("?", M.show_help)
  km("g?", M.show_help)
end

function M.on_event(work_path, line)
  if _view == "log" and _log_path == work_path then
    local buf = get_or_create_main_buf()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
    vim.bo[buf].modifiable = false
    if _main_win and vim.api.nvim_win_is_valid(_main_win) then
      vim.api.nvim_win_set_cursor(_main_win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  elseif _view == "index" then
    M.render()
  end
end

return M
