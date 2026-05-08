local M = {}

local _view        = "index"
local _thread_path = nil
local _thread_row  = -1
local _contexts     = {} -- [cwd] -> context_items[]
local _folds       = {}

local _projects_path = vim.fn.stdpath("data") .. "/acp/projects.json"

local function _load_projects()
  local f = io.open(_projects_path, "r")
  if not f then return {} end
  local raw = f:read("*a"); f:close()
  local ok, decoded = pcall(vim.json.decode, raw)
  if ok and type(decoded) == "table" then
    local list = {}
    for _, v in ipairs(decoded) do
      if type(v) == "string" then table.insert(list, v) end
    end
    return list
  end
  return {}
end

local function _save_projects(list)
  vim.fn.mkdir(vim.fs.dirname(_projects_path), "p")
  local f = io.open(_projects_path, "w"); if not f then return end
  f:write(vim.json.encode(list)); f:close()
end

local _projects = _load_projects()

function M.register_project(cwd)
  cwd = cwd or vim.fn.getcwd()
  if not cwd or cwd == "" then return end
  for i, p in ipairs(_projects) do
    if p == cwd then
      if i == 1 then return end
      table.remove(_projects, i)
      break
    end
  end
  table.insert(_projects, 1, cwd)
  if #_projects > 100 then _projects = vim.list_slice(_projects, 1, 100) end
  _save_projects(_projects)
end

function M.known_projects()
  return vim.deepcopy(_projects)
end

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
    require("acp.float").open_composer_float("New Work Item", {
      cwd = cwd,
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
  table.insert(_contexts[cwd], { type = "image", mimeType = mime[ext] or "image/png", data = b64,
                             _label = vim.fn.fnamemodify(path, ":t") })
  vim.notify("Pinned image: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO, { title = "acp" })
  if _view == "index" then M.render() end
end

function M.drain_context(cwd, opts)
  cwd = cwd or _cur_cwd or vim.fn.getcwd()
  local items = {}
  local skills_block = require("acp.skills").build_prompt_block(cwd)
  if skills_block then table.insert(items, skills_block) end
  local context = _contexts[cwd] or {}
  local sess = opts and opts.sess or require("acp.session").find_ready_for_cwd(cwd)
  local caps = (sess and sess.agent_capabilities and sess.agent_capabilities.promptCapabilities) or {}
  local dropped = 0
  for _, c in ipairs(context) do
    if c.type == "image" then
      if caps.image then
        table.insert(items, { type = "image", mimeType = c.mimeType, data = c.data })
      else
        dropped = dropped + 1
      end
    else
      table.insert(items, { type = "text", text = c.text })
    end
  end
  if dropped > 0 then
    vim.notify("Dropped " .. dropped .. " image block(s) — agent lacks image capability",
               vim.log.levels.WARN, { title = "acp" })
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

local WT_PCACHE_TTL_MS = 30000
local _wt_pcache    = {}  -- [cwd] = { value = list, ts = ms }
local _wt_pinflight = {}  -- [cwd] = true

local function _parse_wt(stdout)
  if not stdout or stdout == "" then return {} end
  local ok, parsed = pcall(vim.json.decode, stdout)
  if not ok or type(parsed) ~= "table" then return {} end
  local list = {}
  for _, w in ipairs(parsed) do
    if type(w) == "table" and w.path then
      table.insert(list, { path = w.path, branch = w.branch, is_main = w.is_main })
    end
  end
  return list
end

local function _kickoff_wt(cwd, on_done)
  if _wt_pinflight[cwd] then
    if on_done then on_done() end; return
  end
  if vim.fn.executable("wt") == 0 then
    _wt_pcache[cwd] = { value = {}, ts = _uv.now() }
    if on_done then on_done() end; return
  end
  _wt_pinflight[cwd] = true
  vim.system({ "wt", "list", "--format=json" }, { cwd = cwd, text = true }, function(res)
    _wt_pinflight[cwd] = nil
    local list = (res.code == 0) and _parse_wt(res.stdout) or {}
    _wt_pcache[cwd] = { value = list, ts = _uv.now() }
    if on_done then on_done() end
  end)
end

local function _wait_for_worktrees(cwds, timeout_ms)
  local pending = 0
  local function dec() pending = pending - 1 end
  for _, cwd in ipairs(cwds) do
    local entry = _wt_pcache[cwd]
    local fresh = entry and (_uv.now() - entry.ts) < WT_PCACHE_TTL_MS
    if not fresh then
      pending = pending + 1
      _kickoff_wt(cwd, dec)
    end
  end
  if pending > 0 then
    vim.wait(timeout_ms or 800, function() return pending <= 0 end, 10)
  end
end

local _root_lookup_cache = {}  -- [dir] = root | false
local function _git_root(file)
  if not file or file == "" then return nil end
  local dir = vim.fn.fnamemodify(file, ":p:h")
  if _root_lookup_cache[dir] ~= nil then return _root_lookup_cache[dir] or nil end
  local cur = dir
  while cur and cur ~= "/" and cur ~= "" do
    if vim.fn.isdirectory(cur .. "/.git") == 1 or vim.fn.filereadable(cur .. "/.git") == 1 then
      _root_lookup_cache[dir] = cur
      return cur
    end
    local parent = vim.fn.fnamemodify(cur, ":h")
    if not parent or parent == cur then break end
    cur = parent
  end
  _root_lookup_cache[dir] = false
  return nil
end

local _oldfile_roots_cache = nil
local function _oldfile_project_roots()
  if _oldfile_roots_cache then return _oldfile_roots_cache end
  local seen, list = {}, {}
  for _, f in ipairs(vim.v.oldfiles or {}) do
    local root = _git_root(f)
    if root and not seen[root] and vim.fn.isdirectory(root) == 1 then
      seen[root] = true
      table.insert(list, root)
      if #list >= 200 then break end
    end
  end
  _oldfile_roots_cache = list
  return list
end

function M.invalidate_project_cache()
  _oldfile_roots_cache = nil
  _root_lookup_cache   = {}
  _wt_pcache           = {}
end

local function _collect_projects()
  local diff = require("acp.diff")
  local seen, candidates = {}, {}

  local function add(c)
    if c and c ~= "" and not seen[c] and vim.fn.isdirectory(c) == 1 then
      seen[c] = true
      table.insert(candidates, c)
    end
  end
  add(vim.fn.getcwd())
  for _, s in ipairs(require("acp.session").active() or {}) do
    if s and s.cwd then add(s.cwd) end
  end
  for _, p in ipairs(_projects) do add(p) end
  for _, r in ipairs(_oldfile_project_roots()) do add(r) end

  _wait_for_worktrees(candidates, 800)

  local result = {}
  for _, cwd in ipairs(candidates) do
    pcall(diff.load_threads, cwd)
    local threads = diff.get_threads(cwd) or {}
    local entry   = _wt_pcache[cwd]
    local worktrees = (entry and entry.value) or {}
    table.insert(result, { cwd = cwd, threads = threads, worktrees = worktrees })
  end
  return result
end

function M.project_targets()
  local targets = {}
  for _, p in ipairs(_collect_projects()) do
    table.insert(targets, {
      kind = "project",
      cwd = p.cwd,
      label = string.format("📁 %s (%s)",
        vim.fn.fnamemodify(p.cwd, ":t"),
        vim.fn.fnamemodify(p.cwd, ":~")),
    })
    for _, wt in ipairs(p.worktrees) do
      if wt.path ~= p.cwd then
        local branch = (type(wt.branch) == "string" and wt.branch) or vim.fn.fnamemodify(wt.path, ":t")
        table.insert(targets, {
          kind = "worktree",
          cwd = wt.path,
          branch = wt.branch,
          label = "  |_ " .. branch .. "  " .. vim.fn.fnamemodify(wt.path, ":~"),
        })
      end
    end
  end
  return targets
end

local function _open_oil(path)
  if path and path ~= "" and path ~= vim.fn.getcwd() then
    vim.cmd("tcd " .. vim.fn.fnameescape(path))
  end
  vim.cmd("Oil " .. vim.fn.fnameescape(path))
end

local function _open_thread(cwd, file, row)
  local nwb = require("acp.neogit_workbench")
  if cwd and cwd ~= vim.fn.getcwd() then
    pcall(nwb.close)
    vim.cmd("tcd " .. vim.fn.fnameescape(cwd))
  end
  nwb.open({ kind = "vsplit", skip_diff = true })
  nwb.show_thread(file, tonumber(row) or -1, cwd)
end

function M.pick_project()
  local diff     = require("acp.diff")
  local cwd      = vim.fn.getcwd()

  -- If there's no active session for the current directory, create one.
  if not require("acp.session").find_ready_for_cwd(cwd) then
    M.set(cwd); return
  end

  local projects = _collect_projects()
  local items    = {}

  table.insert(items, {
    text = string.format("✨ New thread (%s)", vim.fn.fnamemodify(cwd, ":~")),
    cwd  = cwd,
    kind = "new_thread",
  })
  if #projects > 0 then
    table.insert(items, { text = "  ---", kind = "sep" })
  end

  for _, p in ipairs(projects) do
    table.insert(items, {
      text = string.format("📁 %s (%s)",
        vim.fn.fnamemodify(p.cwd, ":t"),
        vim.fn.fnamemodify(p.cwd, ":~")),
      cwd  = p.cwd,
      kind = "project",
    })
    for _, wt in ipairs(p.worktrees) do
      if wt.path ~= p.cwd then
        local label = (type(wt.branch) == "string" and wt.branch) or vim.fn.fnamemodify(wt.path, ":t")
        table.insert(items, {
          text = "  |_ " .. label .. "  " .. vim.fn.fnamemodify(wt.path, ":~"),
          path = wt.path,
          kind = "worktree",
        })
      end
    end
    if #p.threads > 0 then
      table.insert(items, { text = "  ---", kind = "sep" })
    end
    for _, t in ipairs(p.threads) do
      local title     = (t.thread and (t.thread._title or t.thread.prompt)) or "(empty)"
      title           = tostring(title):gsub("[\r\n]+", " "):sub(1, 80)
      local streaming = diff.is_thread_streaming(t.thread)
      local marker    = streaming and "●" or (diff.is_thread_active(t.thread) and "◉" or "·")
      table.insert(items, {
        text = "  " .. marker .. " " .. title,
        cwd  = p.cwd,
        file = t.file,
        row  = t.row,
        kind = "thread",
      })
    end
  end

  if #items == 0 then
    vim.notify("No ACP projects yet.", vim.log.levels.WARN, { title = "acp" }); return
  end

  local function on_pick(item)
    if not item or item.kind == "sep" then return end
    if item.kind == "new_thread" then
      M.set(item.cwd)
    elseif item.kind == "thread" then
      _open_thread(item.cwd, item.file, item.row)
    elseif item.kind == "worktree" then
      _open_oil(item.path)
    else
      _open_oil(item.cwd)
    end
  end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker.pick({
      source  = "acp_projects",
      items   = items,
      layout  = "select",
      format  = "text",
      confirm = function(picker, item)
        picker:close()
        on_pick(item)
      end,
    })
  else
    vim.ui.select(items, {
      prompt      = "ACP projects",
      format_item = function(it) return it.text end,
    }, on_pick)
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
  vim.wo[vim.api.nvim_get_current_win()].winbar = "%#AcpWinbarText#  comm log (last 500)  %*"
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
