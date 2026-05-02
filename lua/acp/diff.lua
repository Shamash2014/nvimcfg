local M = {}

local NS_DIFF    = vim.api.nvim_create_namespace("acp_diff")
local NS_THREAD  = vim.api.nvim_create_namespace("acp_thread")
local NS_SEP     = vim.api.nvim_create_namespace("acp_sep")

local subscribe_to_thread -- Forward declaration

local STATUS_WORDS = { A = "new file  ", M = "modified  ", D = "deleted   " }

local _threads = {}

local function thread_dir(cwd) return cwd .. "/.nowork/threads" end

local function thread_path(cwd, file, row)
  local safe = (file:gsub("[/\\:*?\"<>|%s]", "_"))
  return thread_dir(cwd) .. "/" .. safe .. "@" .. tostring(row) .. ".jsonl"
end

local function save_thread(cwd, file, row)
  if not cwd then return end
  local t = ((_threads[cwd] or {})[file] or {})[row]
  if type(t) ~= "table" then return end
  vim.fn.mkdir(thread_dir(cwd), "p")
  local f = io.open(thread_path(cwd, file, row), "w")
  if not f then return end
  local meta = { type = "meta", prompt = t.prompt, file = file, row = row }
  for k, v in pairs(t) do
    if k ~= "messages" and type(v) ~= "function" and not k:match("^_") then
      meta[k] = v
    end
  end
  f:write(vim.json.encode(meta) .. "\n")
  for _, msg in ipairs(t.messages or {}) do
    local cm = {}
    for k, v in pairs(msg) do if type(v) ~= "function" then cm[k] = v end end
    f:write(vim.json.encode(cm) .. "\n")
  end
  f:close()
end

local function load_threads(cwd)
  if not cwd then return end
  if _threads[cwd] then return end
  _threads[cwd] = {}
  local paths = vim.fn.glob(thread_dir(cwd) .. "/*.jsonl", false, true)
  for _, path in ipairs(paths) do
    local f = io.open(path, "r")
    if f then
      local first = f:read("*l")
      local ok, meta = pcall(vim.json.decode, first or "")
      if ok and type(meta) == "table" and meta.type == "meta" then
        local tf, tr = meta.file, tonumber(meta.row)
        if tf and tr ~= nil then
          local msgs = {}
          for line in f:lines() do
            if line ~= "" then
              local ok2, msg = pcall(vim.json.decode, line)
              if ok2 and type(msg) == "table" then table.insert(msgs, msg) end
            end
          end
          local t = {}
          for k, v in pairs(meta) do
            if k ~= "type" and k ~= "file" and k ~= "row" then t[k] = v end
          end
          t.messages = msgs
          _threads[cwd][tf] = _threads[cwd][tf] or {}
          _threads[cwd][tf][tr] = t
        end
      end
      f:close()
    end
  end
  -- Migrate from legacy threads.json
  if vim.tbl_isempty(_threads[cwd]) then
    local lp = cwd .. "/.nowork/threads.json"
    local lf = io.open(lp, "r")
    if lf then
      local content = lf:read("*a"); lf:close()
      if content ~= "" then
        local ok, data = pcall(vim.json.decode, content)
        if ok and type(data) == "table" then
          for lfile, rows in pairs(data) do
            for row_str, t in pairs(rows) do
              local rn = tonumber(row_str)
              if rn ~= nil and type(t) == "table" then
                _threads[cwd][lfile] = _threads[cwd][lfile] or {}
                _threads[cwd][lfile][rn] = t
                save_thread(cwd, lfile, rn)
              end
            end
          end
        end
      end
    end
  end
end
M.load_threads = load_threads

local function reload_threads(cwd)
  _threads[cwd] = nil
  load_threads(cwd)
end
M.reload_threads = reload_threads

function M.upsert_thread(cwd, file, row, t)
  load_threads(cwd)
  _threads[cwd] = _threads[cwd] or {}
  _threads[cwd][file] = _threads[cwd][file] or {}
  _threads[cwd][file][row] = t
  save_thread(cwd, file, row)
end

function M.append_thread_msg(cwd, file, row, msg)
  load_threads(cwd)
  local t = ((_threads[cwd] or {})[file] or {})[row]
  if type(t) ~= "table" then return end
  t.messages = t.messages or {}
  if msg.type == "text" or msg.type == "thought" then
    local last = t.messages[#t.messages]
    if last and last.role == "agent" and last.type == msg.type then
      last.text = (last.text or "") .. (msg.text or "")
      save_thread(cwd, file, row)
      return
    end
  end
  table.insert(t.messages, msg)
  save_thread(cwd, file, row)
end

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
    return (msg.text or "")
  elseif msg.type == "thought" then
    return (msg.text or "")
  elseif msg.call or msg.type == "tool_call" then
    local call = msg.call or msg
    local args = call.arguments and vim.json.encode(call.arguments) or "{}"
    if #args > 200 then args = args:sub(1, 200) .. "..." end
    return "Tool: " .. (call.name or "?") .. "\nArgs: " .. args
  elseif msg.result or msg.type == "tool_result" then
    local res = msg.result or msg
    local out = res.content and res.content[1] and res.content[1].text or ""
    if #out > 1000 then out = out:sub(1, 1000) .. "..." end
    local status = res.isError and "ERROR" or "OK"
    return status .. " — " .. out
  elseif msg.text then
    return msg.text
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

local function buf_is_visible(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return false end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then return true end
  end
  return false
end

local function redraw_thread(row)
  row = tonumber(row)
  if not row or row < 0 then return end
  row = math.floor(row)
  local buf = _cur.main_buf
  if not buf_is_visible(buf) then return end
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
  t.messages = t.messages or {}
  if t._unsub then t._unsub() end
  t._subscribed = true

  t._unsub = sess.rpc:subscribe(sess.session_id, function(notif)
    if not t._subscribed then return end
    t.messages = t.messages or {}
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
    elseif u.sessionUpdate == "output" and u.output then
      table.insert(t.messages, { role="agent", type="output", text=tostring(u.output) })
    elseif u.sessionUpdate == "error" and u.error then
      table.insert(t.messages, { role="agent", type="error", text=tostring(u.error) })
    elseif u.sessionUpdate == "turn_complete" or u.sessionUpdate == "session_complete" then
      local reason = u.stopReason or u.reason or "done"
      table.insert(t.messages, { role="agent", type="info", text="Turn ended: " .. reason })
    elseif u.sessionUpdate == "session_info_update" and u.title then
      t._title = u.title
    end
    vim.schedule(function()
      save_thread(cwd, file, row)
      redraw_thread(row)
      require("acp.workbench").on_event(file, t)
      local bufname = string.format("acp-thread-%s-%s", file, row)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if buf_is_visible(b) then
          local bname = vim.api.nvim_buf_get_name(b)
          if bname:find(bufname, 1, true) then
            M.render_thread_view(b, cwd, file, row, t)
          end
        end
      end
    end)
  end)
end
M.subscribe_to_thread = subscribe_to_thread

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
        save_thread(cwd, file, row)
        if row >= 0 then
          vim.schedule(function() redraw_thread(row) end)
        end
        vim.schedule(function() require("acp.workbench").render() end)

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
              thread.messages = thread.messages or {}
              table.insert(thread.messages, { role="agent", type="info", text="Turn ended: " .. res.stopReason })
              vim.schedule(function() redraw_thread(row) end)
            end
          end)
        end)
      end,
    }
  )
end

function M.render_thread_view(buf, cwd, file, row, t_live)
  local lines = {}
  local hls   = {}
  local function add(s, hl)
    table.insert(lines, s or "")
    if hl then table.insert(hls, { #lines - 1, hl }) end
  end
  local SEP = string.rep("─", 48)

  local meta, msgs = {}, {}
  if type(t_live) == "table" then
    -- Fast path during streaming: use in-memory table directly
    meta = { prompt = t_live.prompt, _title = t_live._title }
    msgs = t_live.messages or {}
  else
    -- Read from JSONL file (open_thread_view / restart)
    local path = thread_path(cwd, file, row)
    local f = io.open(path, "r")
    if f then
      local first = f:read("*l")
      local ok, m = pcall(vim.json.decode, first or "")
      if ok and type(m) == "table" then meta = m end
      for line in f:lines() do
        if line ~= "" then
          local ok2, msg = pcall(vim.json.decode, line)
          if ok2 and type(msg) == "table" then table.insert(msgs, msg) end
        end
      end
      f:close()
    else
      local t = ((_threads[cwd] or {})[file] or {})[row]
      if type(t) == "table" then meta = { prompt = t.prompt }; msgs = t.messages or {} end
    end
  end

  local model = require("acp.agents").current_model_label(cwd)
  local fname = vim.fn.fnamemodify(file or "", ":t")
  local loc   = (type(row) == "number" and row >= 0) and (fname .. ":" .. (row + 1)) or fname

  local title_raw = meta._title or meta.prompt or "Untitled"
  local title = (title_raw:match("([^\n]+)") or "Untitled"):sub(1, 80)

  add(SEP, "AcpThreadPrefix")
  add("  " .. title, "AcpSectionHeader")
  add("  " .. model .. "  ·  " .. loc, "Comment")
  add(SEP, "AcpThreadPrefix")
  add("")

  local turn = 0
  for _, msg in ipairs(msgs) do
    if msg.role == "user" then
      turn = turn + 1
      add("User  (turn " .. turn .. ")", "AcpSectionHeader")
      for _, l in ipairs(vim.split(msg.text or "", "\n")) do add("  " .. l) end
      add("")
    elseif msg.type == "thought" then
      local tlines = vim.split(msg.text or "", "\n")
      local show = math.min(#tlines, 3)
      add("  💭 " .. (tlines[1] or ""):sub(1, 80), "AcpThreadThought")
      for i = 2, show do add("     " .. tlines[i]:sub(1, 80), "AcpThreadThought") end
      if #tlines > show then add("     … (" .. #tlines .. " lines)", "Comment") end
    elseif msg.type == "tool_call" then
      local call = msg.call or {}
      local args = call.arguments and vim.json.encode(call.arguments) or "{}"
      if #args > 100 then args = args:sub(1, 100) .. "…" end
      add("  ⚙ " .. (call.name or "?") .. "  " .. args, "AcpThreadAction")
    elseif msg.type == "tool_result" then
      local res = msg.result or {}
      local is_err = res.isError
      local out = res.content and res.content[1] and res.content[1].text or ""
      local rlines = vim.split(out, "\n")
      local show = math.min(#rlines, 4)
      local hl = is_err and "Error" or "AcpThreadResult"
      add("  " .. (is_err and "✗" or "✓") .. "  " .. (rlines[1] or ""):sub(1, 100), hl)
      for i = 2, show do add("     " .. rlines[i]:sub(1, 100), hl) end
      if #rlines > show then add("     … (" .. #rlines .. " lines)", "Comment") end
    elseif msg.type == "info" then
      add("  ·  " .. (msg.text or ""), "DiagnosticInfo")
    elseif msg.type == "error" then
      add("  ✗  " .. (msg.text or ""), "Error")
    elseif msg.role == "agent" then
      for _, l in ipairs(vim.split(msg.text or "", "\n")) do add("  " .. l) end
      add("")
    end
  end

  if #msgs == 0 then add("  (no messages yet)", "Comment"); add("") end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false,
    vim.tbl_map(function(l) return (l:gsub("\n", " ")) end, lines))
  vim.bo[buf].modifiable = false
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(buf, -1, h[2], h[1], 0, -1)
  end

  local ns_footer = vim.api.nvim_create_namespace("acp_thread_footer")
  vim.api.nvim_buf_clear_namespace(buf, ns_footer, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns_footer, math.max(0, #lines - 1), 0, {
    virt_lines = {
      { { "" } },
      {
        { " <CR>", "AcpHelpKey" }, { " reply  ", "Comment" },
        { "R", "AcpHelpKey" }, { " restart  ", "Comment" },
        { "<S-Tab>", "AcpHelpKey" }, { " mode  ", "Comment" },
        { "M", "AcpHelpKey" }, { " model  ", "Comment" },
        { "q", "AcpHelpKey" }, { " close", "Comment" },
      },
    },
  })
end


function M.open_thread_view(row, target_win)
  local cwd  = _cur.cwd or vim.fn.getcwd()
  local file = _cur.sel_file
  reload_threads(cwd)
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

  M.render_thread_view(buf, cwd, file, row)

  local thread_key = cwd .. ":thread:" .. file .. ":" .. row

  local active_sess = require("acp.session").get(thread_key)
  if active_sess then
    subscribe_to_thread(active_sess, cwd, file, row)
  end

  local function km(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  km("<CR>", function() M.reply_at(row, file) end, "Reply")
  km("R",   function() M.restart_thread(row, file) end, "Restart thread")
  km("q",   function() vim.api.nvim_win_close(0, true) end, "Close")
  km("m",   function()
    require("acp.workbench").pick_mode(thread_key)
  end, "Pick mode")
  km("M",   function()
    require("acp").pick_model(cwd)
  end, "Pick model")
  km("<S-Tab>", function()
    require("acp.workbench").pick_mode(thread_key)
  end, "Switch mode")

  local existing_win = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      existing_win = w; break
    end
  end
  if existing_win then
    vim.api.nvim_set_current_win(existing_win)
  elseif target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_set_buf(target_win, buf)
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd("botright vsplit")
    vim.api.nvim_set_current_buf(buf)
  end
end

function M.restart_thread(row, file)
  local cwd  = _cur.cwd or vim.fn.getcwd()
  file = file or _cur.sel_file
  local t    = ((_threads[cwd] or {})[file] or {})[row]
  if (not t or type(t) == "userdata") and type(row) == "number" then
    t = ((_threads[cwd] or {})[file] or {})[tostring(row)]
  end
  if type(t) ~= "table" then return end

  local thread_key = cwd .. ":thread:" .. file .. ":" .. row
  require("acp.session").close(thread_key) -- Kill old session

  t.messages = {{ role = "user", text = t.prompt }}
  save_thread(cwd, file, row)
  redraw_thread(row)

  -- Refresh the thread view buffer if visible
  local bufname = string.format("acp-thread-%s-%s", file, row)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):find(bufname, 1, true) then
      M.render_thread_view(b, cwd, file, row)
      break
    end
  end

  require("acp.session").get_or_create({ key = thread_key, cwd = cwd }, function(err, sess)
    if err then return end
    subscribe_to_thread(sess, cwd, file, row)
    sess.rpc:request("session/prompt", {
      sessionId = sess.session_id, prompt = {{type="text", text=t.prompt}},
    }, function() end)
  end)
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
    os.remove(thread_path(cwd, file, row))
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
  km("<S-Tab>", function() require("acp.workbench").pick_mode() end, "Switch mode")
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
