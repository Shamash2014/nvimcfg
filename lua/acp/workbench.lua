local M = {}

local _view        = "index"
local _thread_path = nil
local _thread_row  = -1
local _contexts     = {} -- [cwd] -> context_items[]
local _folds       = {}
local _sb_line_meta = {}
local _title_cache  = {}

local function async(f)
  local co = coroutine.create(f)
  local function resume(...)
    local ok, res = coroutine.resume(co, ...)
    if not ok then error(debug.traceback(co, res)) end
    if coroutine.status(co) ~= "dead" and type(res) == "function" then
      res(resume)
    end
  end
  resume()
end

local function await(f)
  return coroutine.yield(f)
end

local function exec_async(cmd)
  return await(function(resume)
    vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        local s = table.concat(data, "\n"):gsub("%s+$", "")
        resume(s)
      end,
      on_exit = function(_, code)
        if code ~= 0 then resume(nil) end
      end
    })
  end)
end

-- ── cache: cheap-to-display, expensive-to-fetch values ───────
local _uv = vim.uv or vim.loop
local CACHE_TTL_MS    = 30000
local _branch_cache   = {}     -- [cwd] = { value = "...", ts = ms }
local _branch_inflight = {}
local _wt_cache       = {}     -- [cwd] = { value = list, ts = ms }
local _wt_inflight    = {}

local function refresh_branch(cwd, on_done)
  if _branch_inflight[cwd] then return end
  _branch_inflight[cwd] = true
  local out = {}
  vim.fn.jobstart({ "git", "-C", cwd, "branch", "--show-current" }, {
    stdout_buffered = true,
    on_stdout = function(_, data) if data then vim.list_extend(out, data) end end,
    on_exit = function()
      _branch_inflight[cwd] = nil
      local s = (table.concat(out, "\n")):gsub("%s+$", "")
      _branch_cache[cwd] = { value = s, ts = _uv.now() }
      if on_done then vim.schedule(on_done) end
    end,
  })
end

local function cached_branch(cwd, on_refresh)
  local entry = _branch_cache[cwd]
  local fresh = entry and (_uv.now() - entry.ts) < CACHE_TTL_MS
  if not fresh then refresh_branch(cwd, on_refresh) end
  return entry and entry.value or ""
end

local function refresh_worktrees(cwd, on_done)
  if _wt_inflight[cwd] then return end
  if vim.fn.executable("wt") == 0 then
    _wt_cache[cwd] = { value = {}, ts = _uv.now() }
    return
  end
  _wt_inflight[cwd] = true
  local out = {}
  vim.fn.jobstart({ "wt", "list", "--format=json" }, {
    cwd = cwd,
    stdout_buffered = true,
    on_stdout = function(_, data) if data then vim.list_extend(out, data) end end,
    on_exit = function(_, code)
      _wt_inflight[cwd] = nil
      local list = {}
      if code == 0 then
        local raw = table.concat(out, "\n")
        local ok, parsed = pcall(vim.json.decode, raw)
        if ok and type(parsed) == "table" then list = parsed end
      end
      _wt_cache[cwd] = { value = list, ts = _uv.now() }
      if on_done then vim.schedule(on_done) end
    end,
  })
end

local function cached_worktrees(cwd, on_refresh)
  local entry = _wt_cache[cwd]
  local fresh = entry and (_uv.now() - entry.ts) < CACHE_TTL_MS
  if not fresh then refresh_worktrees(cwd, on_refresh) end
  return entry and entry.value or {}
end

local _index_render_timer
local function debounced_render()
  if _index_render_timer then
    _index_render_timer:stop()
    if not _index_render_timer:is_closing() then _index_render_timer:close() end
  end
  _index_render_timer = _uv.new_timer()
  local timer = _index_render_timer
  timer:start(80, 0, vim.schedule_wrap(function()
    if _index_render_timer == timer then _index_render_timer = nil end
    if not timer:is_closing() then timer:close() end
    if _view == "index" then M.render() end
  end))
end

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
  local agents = require("acp.agents")
  local function compose()
    local title_bar = "New Work Item [" .. agents.provider_label(cwd) .. "]"
    require("acp.float").open_composer_float(title_bar, {
      on_submit = function(text)
        if vim.trim(text) == "" then return end
        local lines = vim.split(text, "\n", { plain = true })
        local first = vim.trim(lines[1] or "")
        local title_clean = first:gsub("^#+%s*", "")
        local title = title_clean ~= "" and (title_clean:len() > 30 and title_clean:sub(1, 30) or title_clean) or "untitled"
        local path  = M.new_file(cwd, title)
        local f     = io.open(path, "w")
        if f then
          f:write(text)
          if not text:match("\n$") then f:write("\n") end
          f:close()
        end
        vim.notify("Starting: " .. title, vim.log.levels.INFO, {title="acp"})
        M.run(cwd, path)
      end,
    })
  end
  agents.resolve(cwd, function(err)
    if err then
      vim.notify("ACP: " .. err, vim.log.levels.WARN, { title = "acp" }); return
    end
    vim.schedule(compose)
  end)
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

  local mentions = require("acp.mentions")
  local cleaned_text = text
  local function add_mention_context(item)
    table.insert(_contexts[cwd] or {}, item)
  end
  _contexts[cwd] = _contexts[cwd] or {}
  cleaned_text = mentions.parse_and_inject(text, cwd, add_mention_context)

  local diff = require("acp.diff")
  diff.upsert_thread(cwd, path, -1, {
    prompt   = cleaned_text,
    messages = {{ role = "user", text = cleaned_text }},
  })

  local prompt = M.drain_context()
  table.insert(prompt, { type = "text", text = "Complete the following work item:\n\n" .. cleaned_text })

  local key = diff.thread_session_key(cwd, path, -1)
  require("acp.session").get_or_create({ key = key, cwd = cwd }, function(err, sess)
    if err then
      vim.notify("ACP: " .. err, vim.log.levels.ERROR, { title = "acp" }); return
    end
    vim.notify("ACP work started", vim.log.levels.INFO, { title = "acp" })
    M.show_thread(path, -1)
    diff.subscribe_to_thread(sess, cwd, path, -1)

    sess.rpc:request("session/prompt", {
      sessionId = sess.session_id,
      prompt    = prompt,
    }, function(req_err, res)
      local reason = (res and res.stopReason) or (req_err and "error") or "unknown"
      diff.append_thread_msg(cwd, path, -1, { role = "agent", type = "info", text = "stop: " .. reason })
      vim.schedule(function()
        M.on_event(path)
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

  require("acp.session").get_or_create({ key = cwd .. ":left", cwd = cwd }, function(err, sess)
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
        for _, l in ipairs(vim.split(res.text or "", "\n", { plain = true })) do
          if vim.trim(l) ~= "" then table.insert(items, { text = l, bufnr = 0, lnum = 0 }) end
        end
        vim.fn.setqflist(items, "r", { title = "ACP: What's left?" })
        vim.cmd("copen")
      end
    end)
  end)
end

-- ── Push context ──────────────────────────────────────────────

function M.push(label, content, cwd)
  cwd = cwd or _cur_cwd or vim.fn.getcwd()
  _contexts[cwd] = _contexts[cwd] or {}
  table.insert(_contexts[cwd], { type = "text", text = label .. "\n\n" .. content, _label = label })
  vim.notify("Pinned context: " .. label, vim.log.levels.INFO, { title = "acp" })
  if _view == "index" then M.render() end
end

function M.push_image(path)
  local cwd = _cur_cwd or vim.fn.getcwd()
  _contexts[cwd] = _contexts[cwd] or {}
  local f = io.open(path, "rb")
  if not f then
    vim.notify("Cannot read: " .. path, vim.log.levels.WARN, { title = "acp" }); return
  end
  local raw = f:read("*a"); f:close()
  local b64  = vim.base64.encode(raw)
  local ext  = (path:match("%.(%w+)$") or "png"):lower()
  local mime = ({ png="image/png", jpg="image/jpeg", jpeg="image/jpeg", gif="image/gif", webp="image/webp" })
  table.insert(_contexts[cwd], { type = "image", mediaType = mime[ext] or "image/png", data = b64,
                             _label = vim.fn.fnamemodify(path, ":t") })
  vim.notify("Pinned image: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO, { title = "acp" })
  if _view == "index" then M.render() end
end

function M.drain_context(cwd)
  cwd = cwd or _cur_cwd or vim.fn.getcwd()
  local items = {}
  local context = _contexts[cwd] or {}
  for _, c in ipairs(context) do
    if c.type == "image" then
      table.insert(items, { type = "image", mediaType = c.mediaType, data = c.data })
    else
      table.insert(items, { type = "text", text = c.text })
    end
  end
  _contexts[cwd] = {}
  return items
end

function M.push_visual()
  local cwd = vim.fn.getcwd()
  vim.schedule(function()
    local l1 = vim.fn.line("'<"); local l2 = vim.fn.line("'>")
    local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
    M.push(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.") .. ":" .. l1 .. "-" .. l2,
           table.concat(lines, "\n"), cwd)
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

function M.pick_to_pin()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    vim.notify("Snacks picker not available", vim.log.levels.ERROR); return
  end
  snacks.picker.files({
    prompt = "Pin multiple files:",
    confirm = function(picker, item)
      local items = picker:selected()
      if #items == 0 then items = { item } end
      for _, it in ipairs(items) do
        local path = it.file or it.path or it[1]
        local f = io.open(path, "r")
        if f then
          local content = f:read("*a")
          f:close()
          M.push("file: " .. vim.fn.fnamemodify(path, ":t"), content)
        end
      end
      picker:close()
    end
  })
end

function M.push_open_buffers()
  local bufs = vim.api.nvim_list_bufs()
  local count = 0
  for _, b in ipairs(bufs) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" then
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        M.push("file: " .. vim.fn.fnamemodify(name, ":t"), table.concat(lines, "\n"))
        count = count + 1
      end
    end
  end
  vim.notify("Pinned " .. count .. " open buffers", vim.log.levels.INFO, { title = "acp" })
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
  hl("AcpDiffAdd",         { link = "NeogitDiffAdd",         default = true })
  hl("AcpDiffDelete",      { link = "NeogitDiffDelete",      default = true })
  hl("AcpDiffHunk",        { link = "NeogitHunkHeader",      default = true })
  hl("AcpDiffFile",        { link = "NeogitFilePath",        default = true })
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
  hl("AcpHelpKey",         { link = "Special",         default = true })
  hl("AcpSectionHeader",   { link = "Title",           bold = true })
  hl("AcpThreadPrefix",    { link = "Comment",         default = true })
  hl("AcpThreadAgent",     { link = "Function",        default = true })
  hl("AcpThreadUser",      { link = "AcpSectionHeader", default = true })
  hl("AcpThreadThought",   { link = "Comment",         italic = true })
  hl("AcpThreadAction",    { link = "Special",         bold = true })
  hl("AcpThreadResult",    { link = "String",          default = true })
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

local function set_winbar(win, title, tokens, model)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local token_str = (tokens and ("  " .. tokens)) or ""
  local model_str = (model and ("  " .. model)) or ""
  vim.wo[win].winbar = "%#AcpWinbarText#  " .. title .. token_str .. model_str .. "  %*"
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
        local wins = vim.api.nvim_tabpage_list_wins(0)
        local normal_wins = 0
        for _, w in ipairs(wins) do
          if vim.api.nvim_win_get_config(w).relative == "" then
            normal_wins = normal_wins + 1
          end
        end
        if normal_wins > 1 then
          pcall(vim.api.nvim_win_close, other_win, true)
        end
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

function M._render_sidebar(cwd)
  cwd            = cwd or vim.fn.getcwd()
  require("acp.diff").load_threads(cwd)
  local sb_buf   = get_or_create_sb_buf()
  M._install_keymaps(sb_buf)
  local agents   = require("acp.session").active()
  local pending  = require("acp.mailbox").pending_count()
  local work_files  = M.list(cwd)
  local diff_files  = require("acp.diff").list_files(cwd)
  local ls, hls  = {}, {}
  _sb_line_meta  = {}

  local function add(s, hl, meta, virt)
    local row = #ls
    table.insert(ls, s or "")
    if hl   then table.insert(hls, { row = row, hl = hl, virt = virt }) end
    if not hl and virt then table.insert(hls, { row = row, virt = virt }) end
    if meta then _sb_line_meta[row] = meta end
  end

  local function sect(key, title, items)
    local is_open = _folds[key] ~= false
    local icon    = is_open and "▼ " or "▶ "
    add(icon .. title .. " (" .. #items .. ")", "AcpSectionHeader",
        { kind = "section", key = key })
    if is_open then
      for _, item in ipairs(items) do
        add(item[1], item[2], item[3], item[4])
      end
    end
    add("")
  end

  -- Header (magit-style: project + branch)
  local branch = cached_branch(cwd, debounced_render)
  if branch ~= "" then
    add("Head: " .. branch, "AcpBranch")
  end
  add("Hint: ", "AcpFooter", nil, {
    { "?", "AcpHelpKey" }, { " help ", "AcpFooter" },
    { "n", "AcpHelpKey" }, { " new ", "AcpFooter" },
    { "p", "AcpHelpKey" }, { " pipeline", "AcpFooter" },
  })
  add("")

  -- Pending notice (not a section — always visible)
  if pending > 0 then
    add("  ! " .. pending .. " permission(s) pending  <leader>am", "AcpPending")
    add("")
  end

  -- Threads (work-item chats)
  do
    local items = {}
    for _, f in ipairs(work_files) do
      local name = vim.fn.fnamemodify(f, ":t:r"):gsub("^%d+%-", "", 1)
      table.insert(items, { "· " .. name, nil, { kind = "thread", file = f, row = -1 } })
    end
    sect("threads", "Threads", items)
  end

  -- Context (always visible)
  do
    local items = {}
    local context = _contexts[cwd] or {}
    for _, c in ipairs(context) do
      local kind = c.type == "image" and "🖼 " or "📝 "
      table.insert(items, { kind .. " " .. (c._label or "context"), "AcpContextItem" })
    end
    sect("context", "Context", items)
  end

  -- Worktrees
  do
    local wt_data = cached_worktrees(cwd, debounced_render)
    local items = {}
    for _, wt in ipairs(wt_data) do
      if wt.kind == "worktree" then
        local prefix = wt.is_current and "* " or "  "
        local name = wt.branch or "(detached)"
        local hl = wt.is_current and "AcpBranch" or "Comment"
        local path_short = wt.path:gsub("^" .. vim.env.HOME, "~")
        table.insert(items, {
          prefix .. name,
          hl,
          { kind = "worktree", path = wt.path },
          { { "  " .. path_short, "Comment" } }
        })
      end
    end
    if #items > 0 then
      sect("worktrees", "Worktrees", items)
    end
  end


  -- Pipelines
  do
    local runs = require("acp.pipeline").list_runs(cwd, 5)
    local items = {}
    for _, r in ipairs(runs) do
      local icon = (r.status == "in_progress" and "⟳ ") or (r.status == "queued" and "· ") or (r.conclusion == "success" and "✓ ") or (r.conclusion == "failure" and "✗ ") or "· "
      local hl = (r.status == "in_progress" and "AcpPipeRunning") or (r.status == "queued" and "AcpPipePend") or (r.conclusion == "success" and "AcpPipeOk") or (r.conclusion == "failure" and "AcpPipeFail") or "Comment"
      local virt = r.conclusion and { { "  " .. r.conclusion, hl } } or nil
      table.insert(items, {
        icon .. (r.displayTitle or "?"):sub(1,30),
        hl,
        { kind = "pipeline", id = r.databaseId },
        virt
      })
    end
    sect("pipelines", "Pipelines", items)
  end

  -- Changed Files
  do
    local STATUS_WORDS = { A = "A ", M = "M ", D = "D " }
    local items = {}
    for _, f in ipairs(diff_files) do
      local word = STATUS_WORDS[f.status] or "M "
      table.insert(items, { word .. " " .. f.path, nil, { kind = "diff", path = f.path } })
    end
    sect("changed", "Unstaged changes", items)
  end

  -- Comments: line-level threads on diff files (work-item chats live in Plans)
  do
    local items = {}
    local seen  = {}
    for _, entry in ipairs(require("acp.diff").get_threads(cwd)) do
      local t   = entry.thread
      local row = tonumber(entry.row)
      if type(t) == "table"
         and not entry.file:match("%.nowork/")
         and row and row >= 0 then
        local key = entry.file .. ":" .. row
        if not seen[key] then
          seen[key] = true
          local status = t.resolved and "✔ " or "💬 "
          local hl     = t.resolved and "AcpWorkDone" or "AcpThreadOpen"
          local fname  = vim.fn.fnamemodify(entry.file, ":t")
          local prompt = (t.prompt or ""):sub(1, 32)
          if (t.prompt or ""):len() > 32 then prompt = prompt .. "…" end
          local label  = fname .. ":" .. (row + 1) .. "  " .. prompt
          table.insert(items, {
            status .. " " .. label,
            hl,
            { kind = "thread", file = entry.file, row = entry.row },
          })
        end
      end
    end
    sect("comments", "Comments", items)
  end

  add("  TAB fold  <CR> open  n new  p pipeline  q close  g? help", "AcpFooter")

  vim.bo[sb_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sb_buf, 0, -1, false, ls)
  vim.bo[sb_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(sb_buf, NS, 0, -1)
  for _, h in ipairs(hls) do
    local opts = {}
    if h.hl   then opts.line_hl_group = h.hl end
    if h.virt then opts.virt_text = h.virt; opts.virt_text_pos = "right_align" end
    vim.api.nvim_buf_set_extmark(sb_buf, NS, h.row, 0, opts)
  end
end

function M.render()
  require("acp.neogit_workbench").refresh()
end

function M.show_help()
  local sections = {
    {
      title = "Sidebar",
      keys = {
        { "TAB", "fold/unfold" }, { "<CR>", "run/diff" }, { "n", "new item" }, { "o", "edit file" },
        { "L", "show log" }, { "gL", "comm log" }, { "p", "pipeline" }, { "R", "refresh" }, { "q", "close" },
      },
    },
    {
      title = "Diff",
      keys = {
        { "a", "comment" }, { "r", "reply" }, { "x", "resolve" }, { "d", "delete" },
        { "gL", "thread" }, { "gt", "global chat" }, { "s", "send" }, { "n", "new thread" },
        { "m", "mode" }, { "M", "model" }, { "]c", "next hunk" }, { "[c", "prev hunk" },
        { "R", "refresh" },
      },
    },
    {
      title = "Thread",
      keys = {
        { "<CR>", "reply" }, { "R", "restart" }, { "m", "mode" },
        { "M", "model" }, { "i", "index" }, { "q", "close" },
      },
    },
  }

  local lines, hls = {}, {}
  local ns = vim.api.nvim_create_namespace("acp_help")

  for _, s in ipairs(sections) do
    table.insert(lines, " " .. s.title)
    table.insert(hls, { #lines - 1, 0, -1, "AcpSectionHeader" })
    local row_str = ""
    for i, k in ipairs(s.keys) do
      local k_str = string.format(" %-4s %-12s", k[1], k[2])
      local start_col = #row_str
      row_str = row_str .. k_str
      table.insert(hls, { #lines, start_col + 1, start_col + 1 + #k[1], "AcpHelpKey" })
      if i % 4 == 0 or i == #s.keys then
        table.insert(lines, row_str)
        row_str = ""
      end
    end
    table.insert(lines, "")
  end

  local hbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, lines)
  local h = #lines
  local hwin = vim.api.nvim_open_win(hbuf, true, {
    relative = "editor", width = vim.o.columns, height = h,
    row = vim.o.lines - h - 2, col = 0, style = "minimal", border = "single",
  })

  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(hbuf, ns, hl[4], hl[1], hl[2], hl[3])
  end

  vim.bo[hbuf].modifiable = false
  local function close() pcall(vim.api.nvim_win_close, hwin, true) end
  for _, k in ipairs({ "q", "?", "g?", "<Esc>", "<CR>" }) do
    vim.keymap.set("n", k, close, { buffer = hbuf, nowait = true })
  end
end

function M.pick_project()
  local sessions = require("acp.session").active()
  local items = {}
  local seen = {}

  for _, s in ipairs(sessions) do
    if not seen[s.cwd] then
      seen[s.cwd] = true
      table.insert(items, {
        text = "📁 " .. vim.fn.fnamemodify(s.cwd, ":t") .. " (" .. vim.fn.fnamemodify(s.cwd, ":~") .. ")",
        cwd  = s.cwd,
        kind = "project"
      })
      
      -- Add threads under this project
      local threads = require("acp.diff").get_threads(s.cwd)
      for _, t in ipairs(threads) do
        table.insert(items, {
          text = "  thread: " .. t.thread.prompt:sub(1, 50),
          cwd  = s.cwd,
          file = t.file,
          row  = t.row,
          kind = "thread"
        })
      end
    end
  end

  if #items == 0 then
    vim.notify("No active projects or threads", vim.log.levels.WARN); return
  end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker.pick({
      source = "acp_workbench",
      items  = items,
      layout = "select",
      format = "text",
      confirm = function(picker, item)
        picker:close()
        M.set(item.cwd)
        if item.kind == "thread" then
          M.render()
          require("acp.diff").show_file(item.file, _main_win, _main_buf, function(t, tokens) set_winbar(_main_win, t, tokens) end)
          vim.schedule(function()
            if _main_win and vim.api.nvim_win_is_valid(_main_win) then
               vim.api.nvim_win_set_cursor(_main_win, { item.row + 1, 0 })
               require("acp.diff").open_thread_view(item.row, _main_win)
            end
          end)
        else
          M.render()
        end
      end
    })
  end
end

function M.close()
  local buf = require("acp.neogit_workbench")._buffer
  if buf then
    pcall(function() buf:close() end)
  end
end

function M.pick_mode(key)
  local agents = require("acp.session").active()
  local s
  if key then
    for _, a in ipairs(agents) do if a.key == key then s = a; break end end
  else
    local cwd = _cur_cwd or vim.fn.getcwd()
    for _, a in ipairs(agents) do if a.cwd == cwd then s = a; break end end
    if not s then s = agents[1] end
  end

  if not s or not s.modes or #s.modes == 0 then
    vim.notify("No modes available", vim.log.levels.WARN); return
  end

  local labels = {}
  for _, m in ipairs(s.modes) do
    local cur = (m.id or m.modeId) == s.current_mode and " ✓" or ""
    table.insert(labels, (m.name or m.id or "?") .. (m.description and (" — " .. m.description) or "") .. cur)
  end

  vim.ui.select(labels, { prompt = "Set mode for " .. (s.key or "agent") .. ":" }, function(_, idx)
    if not idx then return end
    local mode_id = s.modes[idx].id or s.modes[idx].modeId
    require("acp.session").set_mode(s.key, mode_id)
    M.render()
  end)
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
    if meta.kind == "diff" then
      require("acp.diff").show_file(meta.path, _main_win, _main_buf,
        function(t, tokens) set_winbar(_main_win, t, tokens) end)
      vim.api.nvim_set_current_win(_main_win)
    elseif meta.kind == "thread" then
      local row = tonumber(meta.row) or -1
      if meta.file:match("%.nowork/") then
        M.show_thread(meta.file, row)
      else
        require("acp.diff").show_file(meta.file, _main_win, _main_buf,
          function(t, tokens) set_winbar(_main_win, t, tokens) end)
        vim.api.nvim_set_current_win(_main_win)
        if row >= 0 then
          vim.api.nvim_win_set_cursor(_main_win, { math.floor(row) + 1, 0 })
        end
        require("acp.diff").open_thread_view(row, _main_win)
      end
    elseif meta.kind == "worktree" then
      if meta.path ~= vim.fn.getcwd() then
        vim.cmd("cd " .. vim.fn.fnameescape(meta.path))
        M.render()
        vim.notify("Switched to worktree: " .. meta.path, vim.log.levels.INFO, {title="acp"})
      end
    elseif meta.kind == "pipeline" then
      require("acp.pipeline").open(vim.fn.getcwd(), _main_win, _main_buf,
        function(t) set_winbar(_main_win, t) end)
    end
  end, "Open / edit")

  local function thread_path_at_cursor()
    local meta = meta_at_cursor()
    if meta and meta.kind == "thread" and meta.file
       and meta.file:match("%.nowork/") then
      return meta.file
    end
  end

  km("r", function()
    local p = thread_path_at_cursor()
    if p then M.run(vim.fn.getcwd(), p) end
  end, "Run thread")

  km("o", function()
    local p = thread_path_at_cursor()
    if p then
      vim.api.nvim_set_current_win(_main_win)
      vim.cmd("edit " .. vim.fn.fnameescape(p))
    end
  end, "Edit goal")

  km("L", function()
    local p = thread_path_at_cursor()
    if p then M.show_thread(p, -1) end
  end, "Open thread")

  km("gL", M.show_comm_log, "Comm log")
  
  km("m", function()
    M.pick_mode(nil)
  end, "Set mode")

  km("M", function()
    require("acp").pick_model(_cur_cwd or vim.fn.getcwd())
  end, "Set model")

  km("n", function()
    M.set(vim.fn.getcwd())
  end, "New work item")

  km("dd", function()
    local meta = meta_at_cursor()
    if meta and meta.kind == "thread" then
      require("acp.diff").delete_thread(meta.file, meta.row)
    end
  end, "Remove thread")

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
    if _view == "thread" and _thread_path then M.show_thread(_thread_path, _thread_row) else M.render() end
  end, "Refresh")

  km("q", M.close, "Close")
end

function M.open()
  require("acp.neogit_workbench").open()
end

function M.show_comm_log()
  local path = vim.fn.stdpath("cache") .. "/acp.log"
  local lines = vim.fn.systemlist("tail -n 500 " .. vim.fn.shellescape(path))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "json"
  vim.bo[buf].readonly = true
  vim.bo[buf].buftype = "nofile"
  vim.cmd("botright vsplit")
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { #lines, 0 })
  set_winbar(vim.api.nvim_get_current_win(), "comm log (last 500)")
end

function M.show_thread(file, row)
  row = row or -1
  require("acp.neogit_workbench").show_thread(file, row)
end

function M.on_event(file, t_live)
  require("acp.neogit_workbench").refresh()
end

function M._cached_branch(cwd)
  return cached_branch(cwd)
end

function M._stop_all_timers()
  if _index_render_timer then
    pcall(function()
      _index_render_timer:stop()
      if not _index_render_timer:is_closing() then _index_render_timer:close() end
    end)
    _index_render_timer = nil
  end
end

return M
