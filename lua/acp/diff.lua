local M = {}

local NS_DIFF    = vim.api.nvim_create_namespace("acp_diff")
local NS_THREAD  = vim.api.nvim_create_namespace("acp_thread")
local NS_SEP     = vim.api.nvim_create_namespace("acp_sep")

local STATUS_WORDS = { A = "new file  ", M = "modified  ", D = "deleted   " }

local _threads = {}

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

local function thread_virt(t)
  local u_hl = t.resolved and "AcpThreadResolved" or "AcpThreadOpen"
  local virt = {
    {
      { "  ╭─ ", "AcpThreadPrefix" },
      { t.resolved and "✓ " or "· ", u_hl },
      { t.prompt, u_hl },
    },
  }
  for i = #t.messages, 1, -1 do
    local msg = t.messages[i]
    if msg.role == "agent" then
      local text = msg.text:gsub("\n", " "):sub(1, 80)
      if #msg.text > 80 then text = text .. "…" end
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
  if not t then return end
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

function M.show_file(file_path, main_win, main_buf, on_winbar)
  _cur.main_win      = main_win
  _cur.main_buf      = main_buf
  _cur.on_winbar     = on_winbar
  _cur.sel_file      = file_path
  _cur.buf_line_meta = {}
  _cur.cwd           = _cur.cwd or vim.fn.getcwd()
  if #_cur.files == 0 then _cur.files = M.list_files(_cur.cwd) end

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
    for _, dl in ipairs(hunk.lines) do
      local px = dl.type=="add" and "+" or dl.type=="del" and "-" or " "
      addh(px .. dl.text, nil, { type=dl.type, file=file_path, hunk_header=hunk.header })
    end
    addh("")
  end
  addh("  a new comment  s send to ACP  ]c/[c hunk  R refresh", "AcpDiffHunk")

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

  for row, _ in pairs((_threads[_cur.cwd] or {})[file_path] or {}) do
    redraw_thread(row)
  end

  if on_winbar then on_winbar(file_path) end
  M._install_main_keymaps(main_buf)
end

function M.add_comment()
  local row  = vim.api.nvim_win_get_cursor(0)[1] - 1
  local meta = _cur.buf_line_meta[row]
  local cwd  = _cur.cwd or vim.fn.getcwd()
  local file = _cur.sel_file
  if not meta then
    vim.notify("Not on a diff line", vim.log.levels.WARN, {title="acp"}); return
  end

  require("acp.float").open_comment_float(
    "New comment — " .. vim.fn.fnamemodify(file, ":t"),
    {
      anchor_line = row + 1,
      win_id      = _cur.main_win,
      diff_buf    = _cur.main_buf,
      on_submit   = function(text)
        _threads[cwd] = _threads[cwd] or {}
        _threads[cwd][file] = _threads[cwd][file] or {}
        local thread = {
          prompt   = text,
          messages = {{ role = "user", text = text }},
          resolved = false,
        }
        _threads[cwd][file][row] = thread
        vim.schedule(function() redraw_thread(row) end)

        local thread_key = cwd .. ":thread:" .. file .. ":" .. row
        local line_text  = vim.api.nvim_buf_get_lines(_cur.main_buf, row, row+1, false)[1] or ""
        local prompt_items = {{ type="text", text =
          "Code review agent. File: " .. file .. "\n\n"
          .. (meta.hunk_header or "") .. "\n"
          .. (meta.type=="add" and "+" or meta.type=="del" and "-" or " ")
          .. line_text .. "\n\nReview comment: " .. text
          .. "\n\nRespond concisely (2-3 sentences)."
        }}
        require("acp.session").get_or_create(thread_key, function(err, sess)
          if err then
            vim.notify("ACP: "..err, vim.log.levels.ERROR, {title="acp"}); return
          end
          sess.rpc:subscribe(sess.session_id, function(notif)
            local u = (notif.params or {}).update or {}
            if u.sessionUpdate == "text" and u.text then
              thread.messages[#thread.messages+1] = {role="agent", text=u.text}
              vim.schedule(function() redraw_thread(row) end)
            end
          end)
          sess.rpc:request("session/prompt", {
            sessionId = sess.session_id, prompt = prompt_items,
          }, function() end)
        end)
      end,
    }
  )
end

function M.reply_at(row)
  local cwd  = _cur.cwd or vim.fn.getcwd()
  local file = _cur.sel_file
  local t    = ((_threads[cwd] or {})[file] or {})[row]
  if not t then
    vim.notify("No thread here", vim.log.levels.WARN, {title="acp"}); return
  end
  local thread_key = cwd .. ":thread:" .. file .. ":" .. row
  require("acp.float").open_comment_float(
    "Reply",
    {
      anchor_line = row + 1,
      win_id      = _cur.main_win,
      diff_buf    = _cur.main_buf,
      on_submit   = function(text)
        table.insert(t.messages, {role="user", text=text})
        vim.schedule(function() redraw_thread(row) end)
        require("acp.session").get_or_create(thread_key, function(err, sess)
          if err then return end
          sess.rpc:subscribe(sess.session_id, function(notif)
            local u = (notif.params or {}).update or {}
            if u.sessionUpdate == "text" and u.text then
              t.messages[#t.messages+1] = {role="agent", text=u.text}
              vim.schedule(function() redraw_thread(row) end)
            end
          end)
          sess.rpc:request("session/prompt", {
            sessionId = sess.session_id,
            prompt    = {{type="text", text=text}},
          }, function() end)
        end)
      end,
    }
  )
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

function M.delete_thread()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cwd = _cur.cwd or vim.fn.getcwd()
  if (_threads[cwd] or {})[_cur.sel_file] then
    _threads[cwd][_cur.sel_file][row] = nil
  end
  redraw_thread(row)
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
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local cwd = _cur.cwd or vim.fn.getcwd()
    if ((_threads[cwd] or {})[_cur.sel_file] or {})[row] then
      M.reply_at(row)
    end
  end, "Open thread")

  km("a",  M.add_comment,     "New thread")
  km("r",  function() M.reply_at(vim.api.nvim_win_get_cursor(0)[1] - 1) end, "Reply")
  km("x",  M.toggle_resolve,  "Toggle resolve")
  km("d",  M.delete_thread,   "Delete thread")
  km("s",  M.send,            "Send diff to ACP")
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
