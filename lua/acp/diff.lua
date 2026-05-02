local M = {}

local NS_DIFF    = vim.api.nvim_create_namespace("acp_diff")
local NS_THREAD  = vim.api.nvim_create_namespace("acp_thread")
local NS_SEP     = vim.api.nvim_create_namespace("acp_sep")

local subscribe_to_thread -- Forward declaration

local STATUS_WORDS = { A = "new file  ", M = "modified  ", D = "deleted   " }

local _threads = {}

local function threads_path(cwd) return cwd .. "/.nowork/threads.json" end

local function save_threads(cwd)
  if not cwd then return end
  vim.fn.mkdir(cwd .. "/.nowork", "p")
  local f = io.open(threads_path(cwd), "w")
  if f then
    f:write(vim.json.encode(_threads[cwd] or {}))
    f:close()
  end
end

local function load_threads(cwd)
  if not cwd then return end
  local f = io.open(threads_path(cwd), "r")
  if f then
    local content = f:read("*a")
    f:close()
    if content ~= "" then
      local ok, data = pcall(vim.json.decode, content)
      if ok then _threads[cwd] = data end
    end
  end
end
M.load_threads = load_threads

local _cur = {
  cwd           = nil,
  files         = {},
  sel_file      = nil,
  buf_line_meta = {},
  main_win      = nil,
  main_buf      = nil,
  on_winbar     = nil,
}

local function parse_diff(raw)
  local files = {}
  local cur_file, cur_hunks, cur_hunk = nil, {}, nil
  local function flush()
    if cur_file and cur_file.path then
      if cur_hunk then table.insert(cur_hunks, cur_hunk) end
      table.insert(files, { path=cur_file.path, status=cur_file.status, hunks=cur_hunks })
    end
    cur_hunks, cur_hunk = {}, nil
  end
  for _, line in ipairs(raw) do
    if     line:match("^diff %-%-git")  then flush(); cur_file={path=nil,status="M"}
    elseif line:match("^new file")      then if cur_file then cur_file.status="A" end
    elseif line:match("^deleted file")  then if cur_file then cur_file.status="D" end
    elseif line:match("^%+%+%+ ")       then
      if cur_file then
        local p = line:match("^%+%+%+ b/(.+)$") or ""
        if p ~= "/dev/null" and p ~= "" then cur_file.path = p end
      end
    elseif line:match("^@@") then
      if cur_hunk then table.insert(cur_hunks, cur_hunk) end
      cur_hunk = { header = line, lines = {} }
    elseif cur_hunk then
      local t = line:sub(1,1)
      if     t=="+" then table.insert(cur_hunk.lines,{type="add",text=line:sub(2)})
      elseif t=="-" then table.insert(cur_hunk.lines,{type="del",text=line:sub(2)})
      elseif t==" " then table.insert(cur_hunk.lines,{type="ctx",text=line:sub(2)})
      end
    end
  end
  flush()
  return files
end

local function apply_line_hl(buf, row, hl_group)
  vim.api.nvim_buf_set_extmark(buf, NS_DIFF, row, 0,
    { line_hl_group = hl_group, priority = 50 })
end
M.apply_line_hl = apply_line_hl

local function format_agent_msg(msg)
  if msg.type == "info" then
    return "ℹ " .. (msg.text or "")
  elseif msg.text then
    return msg.text
  elseif msg.call then
    return "Call: " .. (msg.call.name or "?")
  elseif msg.result then
    local out = msg.result.content and msg.result.content[1] and msg.result.content[1].text or ""
    return "Result: " .. (msg.result.isError and "ERROR" or "OK") .. " — " .. out
  end
  return ""
end

local function thread_virt(t)
  if type(t) ~= "table" then return {} end
  local u_hl = t.resolved and "AcpThreadResolved" or "AcpThreadOpen"
  local virt = {
    {
      { "  ╭─ ", "AcpThreadPrefix" },
      { t.resolved and "✓ " or "· ", u_hl },
      { t.prompt, u_hl },
    },
  }
  local msgs = t.messages or {}
  for i = #msgs, 1, -1 do
    local msg = msgs[i]
    if msg.role == "agent" then
      local raw  = format_agent_msg(msg)
      local text = raw:gsub("\n", " "):sub(1, 80)
      if #raw > 80 then text = text .. "…" end
      table.insert(virt, {
        { "  │  ", "AcpThreadPrefix" },
        { text,    "AcpThreadAgent"  },
      })
      break
    end
  end
  table.insert(virt, {
    { "  ╰─ ", "AcpThreadPrefix" },
    { t.resolved and "[resolved]" or "[open]", u_hl },
    { "  <CR>=open  r=reply  x=toggle  d=del", "AcpThreadPrefix" },
  })
  return virt
end

local function redraw_thread(row)
  local buf = _cur.main_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local cwd  = _cur.cwd or vim.fn.getcwd()
  local file = _cur.sel_file
  local marks = vim.api.nvim_buf_get_extmarks(buf, NS_THREAD, {row,0}, {row,-1}, {})
  for _, m in ipairs(marks) do vim.api.nvim_buf_del_extmark(buf, NS_THREAD, m[1]) end
  vim.fn.sign_unplace("acp_threads", { buffer = buf, id = row + 1 })
  local t = ((_threads[cwd] or {})[file] or {})[row]
  if type(t) ~= "table" then return end
  vim.api.nvim_buf_set_extmark(buf, NS_THREAD, row, 0, { virt_lines = thread_virt(t) })
  local sign = t.resolved and "AcpThreadResolved" or "AcpThreadOpen"
  vim.fn.sign_place(row + 1, "acp_threads", sign, buf, { lnum = row + 1 })
end

function M.list_files(cwd)
  local raw = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " diff HEAD")
  if vim.v.shell_error ~= 0 or #raw == 0 then
    raw = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " diff")
  end
  if #raw == 0 then return {} end
  local files = parse_diff(raw)
  _cur.cwd   = cwd
  _cur.files = files
  return files
end

function M.attach(buf, file_path, cwd)
  _cur.main_buf = buf
  _cur.sel_file = file_path
  _cur.cwd      = cwd or _cur.cwd or vim.fn.getcwd()
  load_threads(_cur.cwd)
  M._install_main_keymaps(buf)
  
  -- Redraw and subscribe to existing threads for this file
  local cwd_t = _cur.cwd
  if _threads[cwd_t] and _threads[cwd_t][file_path] then
    for row, _ in pairs(_threads[cwd_t][file_path]) do
      redraw_thread(row)
    end
    -- Try to subscribe if session is already active
    require("acp.session").get_or_create(cwd_t, function(err, sess)
      if not err and sess then
        for row, _ in pairs(_threads[cwd_t][file_path]) do
          subscribe_to_thread(sess, cwd_t, file_path, row)
        end
      end
    end)
  end

  -- Add footer via virt_lines at the end
  vim.api.nvim_buf_clear_namespace(buf, NS_SEP, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_extmark(buf, NS_SEP, line_count - 1, 0, {
    virt_lines = {
      { { "" } },
      { { "  <CR> open/jump  a comment  s send  ]c next  [c prev  R refresh", "AcpFooter" } },
    }
  })
end

function M.show_file(file_path, main_win, main_buf, on_winbar)
  _cur.main_win      = main_win
  _cur.main_buf      = main_buf
  _cur.on_winbar     = on_winbar
  _cur.sel_file      = file_path
  _cur.buf_line_meta = {}
  _cur.cwd           = _cur.cwd or vim.fn.getcwd()
  load_threads(_cur.cwd)
  if #_cur.files == 0 then _cur.files = M.list_files(_cur.cwd) end

  if main_win and vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_win_set_buf(main_win, main_buf)
  end

  local file_data
  for _, f in ipairs(_cur.files) do
    if f.path == file_path then file_data = f; break end
  end
  if not file_data then
    vim.notify("Not in diff: " .. file_path, vim.log.levels.WARN, {title="acp"}); return
  end

  local ls = {}
  local pending_hls = {}
  local function addh(s, hl, meta)
    local row = #ls; table.insert(ls, s or "")
    if hl   then table.insert(pending_hls, {row, hl}) end
    if meta then _cur.buf_line_meta[row] = meta end
  end

  addh((STATUS_WORDS[file_data.status] or "modified  ") .. file_path, "AcpDiffFile")
  addh("")
  for _, hunk in ipairs(file_data.hunks) do
    addh(hunk.header, "AcpDiffHunk")
    -- Parse @@ -start,len +start,len @@
    local start_line = tonumber(hunk.header:match("%+(%d+)")) or 1
    local current_real_line = start_line

    for _, dl in ipairs(hunk.lines) do
      local px = dl.type=="add" and "+" or dl.type=="del" and "-" or " "
      local hl = dl.type=="add" and "AcpDiffAdd" or dl.type=="del" and "AcpDiffDelete" or nil
      local meta = { type=dl.type, file=file_path, hunk_header=hunk.header, real_line = current_real_line }
      addh(px .. dl.text, hl, meta)
      
      if dl.type ~= "del" then
        current_real_line = current_real_line + 1
      end
    end
    addh("")
  end
  vim.bo[main_buf].modifiable = true
  vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, ls)
  vim.bo[main_buf].modifiable = false

  local ok_diffs, diffs_mod = pcall(require, "diffs")
  if ok_diffs then
    diffs_mod.attach(main_buf)
    diffs_mod.refresh(main_buf)
  end

  vim.api.nvim_buf_clear_namespace(main_buf, NS_DIFF,   0, -1)
  vim.api.nvim_buf_clear_namespace(main_buf, NS_THREAD, 0, -1)
  vim.fn.sign_unplace("acp_threads", { buffer = main_buf })
  for _, h in ipairs(pending_hls) do
    vim.api.nvim_buf_set_extmark(main_buf, NS_DIFF, h[1], 0,
      { line_hl_group = h[2], priority = 50 })
  end

  M.attach(main_buf, file_path, _cur.cwd)
  if on_winbar then on_winbar(file_path) end
end

subscribe_to_thread = function(sess, cwd, file, row)
  local t = ((_threads[cwd] or {})[file] or {})[row]
  if not t and type(row) == "number" then
    -- Try string key (JSON keys are always strings)
    t = ((_threads[cwd] or {})[file] or {})[tostring(row)]
  end
  if type(t) ~= "table" then return end
  if t._unsub then t._unsub() end
  t._subscribed = true

  t._unsub = sess.rpc:subscribe(sess.session_id, function(notif)
    if not t._subscribed then return end
    local u = (notif.params or {}).update or {}
    if (u.sessionUpdate == "text" and u.text) or (u.sessionUpdate == "agent_message_chunk" and u.content) then
      local text = u.text or (u.content and u.content.text) or ""
      local last = t.messages[#t.messages]
      if last and last.role == "agent" and last.type == "text" then
        last.text = last.text .. text
      else
        table.insert(t.messages, { role="agent", type="text", text=text })
      end
    elseif (u.sessionUpdate == "thought" and u.thought) or (u.sessionUpdate == "agent_thought_chunk" and u.content) then
      local text = u.thought or (u.content and u.content.text) or ""
      local last = t.messages[#t.messages]
      if last and last.role == "agent" and last.type == "thought" then
        last.text = last.text .. text
      else
        table.insert(t.messages, { role="agent", type="thought", text=text })
      end
    elseif u.sessionUpdate == "tool_call" and u.toolCall then
      table.insert(t.messages, { role="agent", type="tool_call", call=u.toolCall })
    elseif u.sessionUpdate == "tool_result" and u.toolResult then
      table.insert(t.messages, { role="agent", type="tool_result", result=u.toolResult })
    elseif u.sessionUpdate == "session_info_update" and u.title then
      t._title = u.title
    end
    vim.schedule(function()
      redraw_thread(row)
      save_threads(cwd)
      -- If thread view is open for this thread, refresh it
      local bufname = string.format("acp-thread-%s-%s", file, row)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local bname = vim.api.nvim_buf_get_name(b)
        if bname:find(bufname, 1, true) then
          M.render_thread_view(b, t)
        end
      end
    end)
  end)
end

function M.add_comment(file, row, visual)
  local cwd  = _cur.cwd or vim.fn.getcwd()
  file = file or _cur.sel_file
  row  = row  or (vim.api.nvim_win_is_valid(0) and vim.api.nvim_win_get_cursor(0)[1] - 1) or -1
  local meta = _cur.buf_line_meta[row]

  if not file then
    vim.notify("No file context", vim.log.levels.WARN, {title="acp"}); return
  end

  local visual_text = ""
  if visual then
    local l1 = vim.fn.line("'<"); local l2 = vim.fn.line("'>")
    local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
    visual_text = table.concat(lines, "\n")
  end

  require("acp.float").open_comment_float(
    "New comment — " .. vim.fn.fnamemodify(file, ":t"),
    {
      anchor_line = (row >= 0) and (row + 1) or 1,
      win_id      = _cur.main_win or 0,
      diff_buf    = _cur.main_buf or 0,
      on_submit   = function(text)
        _threads[cwd] = _threads[cwd] or {}
        _threads[cwd][file] = _threads[cwd][file] or {}
        local thread = {
          prompt   = text,
          messages = {{ role = "user", text = text }},
          resolved = false,
        }
        _threads[cwd][file][row] = thread
        save_threads(cwd)
        if row >= 0 then
          vim.schedule(function() redraw_thread(row) end)
        end

        local thread_key = cwd .. ":thread:" .. file .. ":" .. row
        local prompt_text = "General comment"
        if visual_text ~= "" then
          prompt_text = "Context:\n```\n" .. visual_text .. "\n```"
        elseif row >= 0 then
          local line_text = vim.api.nvim_buf_get_lines(_cur.main_buf, row, row+1, false)[1] or ""
          prompt_text = (meta and meta.hunk_header or "") .. "\n"
            .. (meta and (meta.type=="add" and "+" or meta.type=="del" and "-" or " ") or " ")
            .. line_text
        end

        local prompt_items = {{ type="text", text =
          "Discussion agent. Context: " .. file .. "\n\n"
          .. prompt_text .. "\n\nComment: " .. text
          .. "\n\nRespond concisely."
        }}
        require("acp.session").get_or_create({ key = thread_key, cwd = cwd }, function(err, sess)
          if err then
            vim.notify("ACP: "..err, vim.log.levels.ERROR, {title="acp"}); return
          end
          subscribe_to_thread(sess, cwd, file, row)
          sess.rpc:request("session/prompt", {
            sessionId = sess.session_id, prompt = prompt_items,
          }, function(e, res)
            if res and res.stopReason then
              table.insert(t.messages, { role="agent", type="info", text="Turn ended: " .. res.stopReason })
              vim.schedule(function() redraw_thread(row) end)
            end
          end)
        end)
      end,
    }
  )
end

function M.render_thread_view(buf, t)
  local lines = {}
  local hls   = {}
  local function add(s, hl)
    table.insert(lines, s or "")
    if hl then table.insert(hls, { #lines - 1, hl }) end
  end

  local model = require("acp.agents").current_model_label(_cur.cwd)
  add("Thread: " .. (t.prompt or "Untitled") .. "  [" .. model .. "]", "AcpSectionHeader")
  add("")

  for _, msg in ipairs(t.messages) do
    if msg.role == "user" then
      add("─ User ──────────────────────────────────", "Comment")
      for _, l in ipairs(vim.split(msg.text or "", "\n")) do add(l) end
    else
      local title = "─ Agent (" .. (msg.type or "text") .. ") ──────────────"
      local hl    = msg.type == "thought" and "Comment" or msg.type == "tool_call" and "Special" or "Function"
      add(title, hl)
      local text = format_agent_msg(msg)
      for _, l in ipairs(vim.split(text, "\n")) do add(l) end
    end
    add("")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(buf, -1, h[2], h[1], 0, -1)
  end
end

function M.open_thread_view(row)
  local cwd  = _cur.cwd or vim.fn.getcwd()
  local file = _cur.sel_file
  local t    = ((_threads[cwd] or {})[file] or {})[row]
  if (not t or type(t) == "userdata") and type(row) == "number" then
    t = ((_threads[cwd] or {})[file] or {})[tostring(row)]
  end
  if type(t) ~= "table" then return end

  local bufname = string.format("acp-thread-%s-%s", file, row)
  local buf = nil
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name:find(bufname, 1, true) then buf = b; break end
  end
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, bufname)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].filetype = "markdown"
  end

  M.render_thread_view(buf, t)
  vim.keymap.set("n", "<CR>", function() M.reply_at(row, file) end,
    { buffer = buf, nowait = true, silent = true, desc = "Reply" })
  vim.cmd("botright vsplit")
  vim.api.nvim_set_current_buf(buf)
end

function M.reply_at(row, file)
  local cwd  = _cur.cwd or vim.fn.getcwd()
  file = file or _cur.sel_file
  local t    = ((_threads[cwd] or {})[file] or {})[row]
  if not t then
    vim.notify("No thread here", vim.log.levels.WARN, {title="acp"}); return
  end
  local thread_key = cwd .. ":thread:" .. file .. ":" .. row
  require("acp.float").open_comment_float("Reply", {
    anchor_line = row + 1, win_id = _cur.main_win, diff_buf = _cur.main_buf,
    on_submit   = function(text)
      table.insert(t.messages, {role="user", text=text})
      vim.schedule(function() redraw_thread(row) end)
      require("acp.session").get_or_create({ key = thread_key, cwd = cwd }, function(err, sess)
        if err then return end
        subscribe_to_thread(sess, cwd, file, row)
        sess.rpc:request("session/prompt", {
          sessionId = sess.session_id, prompt = {{type="text", text=text}},
        }, function() end)
      end)
    end,
  })
end

function M.toggle_resolve()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cwd = _cur.cwd or vim.fn.getcwd()
  local t   = ((_threads[cwd] or {})[_cur.sel_file] or {})[row]
  if not t then return end
  t.resolved = not t.resolved
  redraw_thread(row)
end

function M.get_threads(cwd)
  local result = {}
  for file, rows in pairs((_threads[cwd] or {})) do
    for row, t in pairs(rows) do
      table.insert(result, { file = file, row = row, thread = t })
    end
  end
  table.sort(result, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    return a.row < b.row
  end)
  return result
end

function M.delete_thread(file, row)
  local cwd = _cur.cwd or vim.fn.getcwd()
  file = file or _cur.sel_file
  row = row or (vim.api.nvim_win_is_valid(0) and vim.api.nvim_win_get_cursor(0)[1] - 1) or -1
  local t = ((_threads[cwd] or {})[file] or {})[row]
  if t then
    if t._unsub then t._unsub() end
    t._subscribed = false
    local thread_key = cwd .. ":thread:" .. file .. ":" .. row
    require("acp.session").close(thread_key)
    _threads[cwd][file][row] = nil
    save_threads(cwd)
  end
  if file == _cur.sel_file then redraw_thread(row) end
  require("acp.workbench").render()
end

function M.send()
  local cwd   = _cur.cwd or vim.fn.getcwd()
  local parts = {"Review this diff. Inline comments are marked [COMMENT].\n"}
  for _, f in ipairs(_cur.files) do
    table.insert(parts, "--- " .. f.path .. " (" .. f.status .. ") ---")
    local row = 2
    for _, hunk in ipairs(f.hunks) do
      table.insert(parts, hunk.header); row = row + 1
      for _, dl in ipairs(hunk.lines) do
        local px = dl.type=="add" and "+" or dl.type=="del" and "-" or " "
        table.insert(parts, px .. dl.text)
        local t = ((_threads[cwd] or {})[f.path] or {})[row]
        if t then
          table.insert(parts, "  [COMMENT] " .. t.prompt)
          if t.resolved then table.insert(parts, "  [RESOLVED]") end
        end
        row = row + 1
      end
      table.insert(parts, ""); row = row + 1
    end
  end
  local ctx = require("acp.workbench").drain_context()
  table.insert(ctx, {type="text", text=table.concat(parts, "\n")})
  require("acp.session").get_or_create(cwd, function(err, sess)
    if err then vim.notify("ACP: "..err, vim.log.levels.ERROR, {title="acp"}); return end
    sess.rpc:request("session/prompt", {
      sessionId = sess.session_id, prompt = ctx,
    }, function(req_err, res)
      local reason = (res and res.stopReason) or (req_err and "error") or "unknown"
      vim.schedule(function()
        vim.notify("ACP done ("..reason..")", vim.log.levels.INFO, {title="acp"})
      end)
    end)
    vim.notify("ACP review sent", vim.log.levels.INFO, {title="acp"})
  end)
end

local _km_installed = {}
function M._install_main_keymaps(buf)
  if _km_installed[buf] then return end
  _km_installed[buf] = true
  local function km(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn,
      {buffer=buf, nowait=true, noremap=true, silent=true, desc=desc})
  end

  km("<CR>", function()
    local row  = vim.api.nvim_win_get_cursor(0)[1] - 1
    local cwd  = _cur.cwd or vim.fn.getcwd()
    local file = _cur.sel_file
    local meta = _cur.buf_line_meta[row]
    
    if ((_threads[cwd] or {})[file] or {})[row] then
      M.open_thread_view(row)
    elseif meta and meta.real_line then
      local path = (cwd .. "/" .. file):gsub("//+", "/")
      require("acp.workbench").close()
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      vim.api.nvim_win_set_cursor(0, { meta.real_line, 0 })
    end
  end, "Open thread worklog or jump to file")

  km("a",  M.add_comment,     "New thread")
  vim.keymap.set("v", "a", function()
    vim.api.nvim_input("<Esc>")
    vim.schedule(function() M.add_comment(nil, nil, true) end)
  end, {buffer=buf, nowait=true, noremap=true, silent=true, desc="New thread (visual)"})
  km("r",  function() M.reply_at(vim.api.nvim_win_get_cursor(0)[1] - 1) end, "Reply")
  km("x",  M.toggle_resolve,  "Toggle resolve")
  km("d",  M.delete_thread,   "Delete thread")
  km("gL", function()
    if _cur.sel_file and _cur.sel_file:match("%.nowork/") then
      require("acp.workbench").show_log(_cur.sel_file)
    end
  end, "Show plan worklog")
  km("gt", function() M.open_thread_view(-1) end, "Open global thread")
  km("s",  M.send,            "Send diff to ACP")
  km("n",  function() require("acp.workbench").set(_cur.cwd) end, "New work item")
  km("m", function() require("acp.workbench").pick_mode() end, "Pick mode")
  km("M", function() require("acp").pick_model() end,         "Pick model")
  km("?",  function() require("acp.workbench").show_help() end, "Help")
  km("g?", function() require("acp.workbench").show_help() end, "Help")
  km("R",  function()
    if _cur.sel_file then
      M.show_file(_cur.sel_file, _cur.main_win, _cur.main_buf, _cur.on_winbar)
    end
  end, "Refresh")

  km("]c", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    for r = row+1, vim.api.nvim_buf_line_count(buf) do
      if (vim.api.nvim_buf_get_lines(buf,r-1,r,false)[1] or ""):match("^@@") then
        vim.api.nvim_win_set_cursor(0,{r,0}); return
      end
    end
  end, "Next hunk")

  km("[c", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    for r = row-1, 1, -1 do
      if (vim.api.nvim_buf_get_lines(buf,r-1,r,false)[1] or ""):match("^@@") then
        vim.api.nvim_win_set_cursor(0,{r,0}); return
      end
    end
  end, "Prev hunk")
end

return M
