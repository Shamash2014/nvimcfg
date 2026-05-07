local M = {}

local _uv = vim.uv or vim.loop

local NS_DIFF    = vim.api.nvim_create_namespace("acp_diff")
local NS_THREAD  = vim.api.nvim_create_namespace("acp_thread")

local _hls_by_buf = {}
local _expanded_calls = {}
local _line_to_call_id_by_buf = {}
local _decoration_registered = false
local function ensure_decoration_provider()
  if _decoration_registered then return end
  _decoration_registered = true
  vim.api.nvim_set_decoration_provider(NS_THREAD, {
    on_win = function(_, _, buf) return _hls_by_buf[buf] ~= nil end,
    on_line = function(_, _, buf, row)
      local hls = _hls_by_buf[buf]
      if not hls then return end
      local hl = hls[row]
      if hl then
        vim.api.nvim_buf_set_extmark(buf, NS_THREAD, row, 0, {
          line_hl_group = hl,
          ephemeral     = true,
        })
      end
    end,
  })
end
local NS_SEP     = vim.api.nvim_create_namespace("acp_sep")

local subscribe_to_thread -- Forward declaration
local thread_session_key  -- Forward declaration

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
  pcall(function() require("acp.workbench").register_project(cwd) end)
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
  local prev = _threads[cwd][file][row]
  if type(prev) == "table" then
    if prev._unsub then prev._unsub() end
    prev._subscribed = false
    pcall(function()
      require("acp.session").close(cwd .. ":thread:" .. file .. ":" .. row)
    end)
  end
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
  tokens        = nil,
}

local function compute_tokens(t)
  if not t or not t.messages then return nil end
  local tokens = require("acp.tokens")
  return tokens.format(tokens.estimate(t.messages))
end

-- Reconstruct unified diff hunks from difft's semantic alignment data
local function reconstruct_hunks(aligned_lines, chunks)
  local hunks = {}
  if not aligned_lines or #aligned_lines == 0 then return hunks end
  local cur_old, cur_new = 1, 1
  local hunk_adds, hunk_dels, hunk_ctx = {}, {}, {}
  local in_hunk = false

  local function flush_hunk()
    if not in_hunk or (#hunk_adds == 0 and #hunk_dels == 0) then return end
    -- @@ -old_start,len +new_start,len @@
    local old_len = (cur_old - 1) - hunk_first_old + 1
    local new_len = (cur_new - 1) - hunk_first_new + 1
    table.insert(hunks, {
      header = string.format("@@ -%d,%d +%d,%d @@",
        hunk_first_old, old_len, hunk_first_new, new_len),
      lines = vim.list_extend(vim.deepcopy(hunk_ctx), {}),
      _adds = vim.deepcopy(hunk_adds),
      _dels = vim.deepcopy(hunk_dels),
    })
  end

  for _, pair in ipairs(aligned_lines) do
    local old_idx, new_idx = pair[1], pair[2]
    if old_idx ~= nil and new_idx ~= nil then
      -- Matched line: context
      in_hunk = false
      table.insert(hunk_ctx, { type="ctx", text="" })
      cur_old, cur_new = cur_old + 1, cur_new + 1

    elseif old_idx == nil then
      -- New line (insertion)
      if not in_hunk then flush_hunk(); hunk_first_new = new_idx; in_hunk = true end
      table.insert(hunk_adds, { type="add", text="" })
      cur_new = cur_new + 1

    elseif new_idx == nil then
      -- Removed line (deletion)
      if not in_hunk then flush_hunk(); hunk_first_old = old_idx; in_hunk = true end
      table.insert(hunk_dels, { type="del", text="" })
      cur_old = cur_old + 1
    end
  end
  flush_hunk()
  return hunks
end

local function parse_diff(raw)
  local _, json_start = raw[1]:find("{")
  if json_start then
    local ok, data = pcall(vim.json.decode, table.concat(raw))
    if ok and type(data) == "table" then
      -- Handle JSON output from difft --display=json
      local files = {}
      for _, file_data in ipairs(data) do
        if type(file_data) == "table" and type(file_data.path) == "string" then
          local chunks = file_data.chunks or {}
          local hunks = reconstruct_hunks(file_data.aligned_lines, chunks)

          -- Build hunk lines from aligned data + chunk changes
          for _, hunk in ipairs(hunks) do
            hunk.lines = {}
            local old_idx, new_idx = 1, 1
            local ci = 1  -- current chunk index
            local li = 0  -- current line within chunk pair

            while ci <= #chunks or (old_idx < #file_data.aligned_lines and file_data.aligned_lines[ci][1] == nil) do
              local pair = file_data.aligned_lines[ci] or {nil, nil}
              if type(pair) ~= "table" then break end

              local old_ln = pair[1]
              local new_ln = pair[2]
              local chunk_pair = chunks[ci]

              -- Collect text for context line
              local lhs_text, rhs_text = "", ""
              if chunk_pair and type(chunk_pair) == "table" then
                lhs_text = (chunk_pair.lhs and chunk_pair.lhs.content) or ""
                rhs_text = (chunk_pair.rhs and chunk_pair.rhs.content) or ""
              end

              local text = (new_idx ~= nil) and rhs_text or lhs_text
              if new_idx == nil then
                table.insert(hunk.lines, { type="add", text=text })
              elseif old_idx == nil then
                table.insert(hunk.lines, { type="del", text=text })
              else
                table.insert(hunk.lines, { type="ctx", text=text })
              end

              if old_ln ~= nil and new_ln ~= nil then
                old_idx, new_idx = old_idx + 1, new_idx + 1
              elseif old_ln == nil then
                new_idx = new_idx + 1
              else
                old_idx = old_idx + 1
              end

              ci = ci + 1
            end
          end

          table.insert(files, { path=file_data.path, status="M", hunks=hunks })
        end
      end
      return files
    end
  end
  -- Original unified diff parser (for git fallback)
  local files = {}
  local cur_file, cur_hunks, cur_hunk = nil, {}, nil
  local function flush()
    if cur_file and cur_file.path then
      if cur_hunk then table.insert(cur_hunks, cur_hunk) end
      table.insert(files, { path=cur_file.path, status=cur_file.status or "M", hunks=cur_hunks })
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
  local sign = t.resolved and "AcpThreadResolved" or "AcpThreadOpen"
  vim.fn.sign_place(row + 1, "acp_threads", sign, buf, { lnum = row + 1 })
  local hl = sign
  local count = type(t.messages) == "table" and #t.messages or 0
  local label = count > 0 and ("  ▍ thread · " .. count) or "  ▍ thread"
  pcall(vim.api.nvim_buf_set_extmark, buf, NS_THREAD, row, 0, {
    virt_text     = { { label, hl } },
    virt_text_pos = "eol",
    hl_mode       = "combine",
  })
end

local _files_cache  = {}     -- [cwd] = { files = {}, ts = 0 }
local _files_in_flight = {}   -- [cwd] = true
local FILES_TTL_MS  = 5000

local function fetch_head(cwd, path)
  local raw = vim.fn.system({ "git", "-C", cwd, "show", "HEAD:" .. path })
  if vim.v.shell_error ~= 0 then return "" end
  return raw
end

local function write_temp_file(contents)
  local path = vim.fn.tempname()
  local f = io.open(path, "w")
  if not f then return nil end
  f:write(contents or "")
  f:close()
  return path
end

local function spawn_difft(cwd, old_path, new_path, on_done)
  local out = {}
  vim.fn.jobstart({ "difft", "--display=json", old_path, new_path }, {
    cwd             = cwd,
    stdout_buffered = true,
    on_stdout       = function(_, data) if data then vim.list_extend(out, data) end end,
    on_stderr       = function() end,
    on_exit         = function()
      local raw = table.concat(out):gsub("\n$", "")
      if on_done then vim.schedule(function() on_done(raw) end) end
    end,
  })
end

local function async_refresh_files(cwd, on_done)
  if _files_in_flight[cwd] then return end
  _files_in_flight[cwd] = true

  local function finish_with(files)
    _files_cache[cwd] = { files = files or {}, ts = _uv.now() }
    _files_in_flight[cwd] = nil
    if on_done then vim.schedule(on_done) end
  end

  local function fallback_git_diff()
    local raw = {}
    vim.fn.jobstart({ "git", "-C", cwd, "diff", "HEAD" }, {
      cwd             = cwd,
      stdout_buffered = true,
      on_stdout       = function(_, data) if data then vim.list_extend(raw, data) end end,
      on_stderr       = function() end,
      on_exit         = function()
        finish_with((#raw > 0) and parse_diff(raw) or {})
      end,
    })
  end

  local git_out = {}
  vim.fn.jobstart({ "git", "-C", cwd, "diff", "--name-status", "--find-renames", "HEAD" }, {
    cwd             = cwd,
    stdout_buffered = true,
    on_stdout       = function(_, data) if data then vim.list_extend(git_out, data) end end,
    on_stderr       = function() end,
    on_exit         = function()
      local changed_files = {}
      for _, line in ipairs(git_out) do
        local status, path_a, path_b = line:match("^([A-Z]%d*)\t([^\t]+)\t(.+)$")
        if status then
          local code = status:sub(1, 1)
          table.insert(changed_files, {
            status = (code == "A" or code == "D") and code or "M",
            path = (code == "R" or code == "C") and path_b or path_a,
          })
        else
          local simple_status, simple_path = line:match("^([A-Z]%d*)\t(.+)$")
          if simple_status and simple_path then
            local code = simple_status:sub(1, 1)
            table.insert(changed_files, {
              status = (code == "A" or code == "D") and code or "M",
              path = simple_path,
            })
          end
        end
      end

      if #changed_files == 0 then
        finish_with({})
        return
      end

      local pending = #changed_files
      local done = false
      local need_fallback = false
      local parsed_files = {}
      local timer = _uv.new_timer()

      local function finalize_with_difft()
        if done then return end
        done = true
        timer:stop()
        timer:close()
        finish_with(parsed_files)
      end

      local function finalize_with_fallback()
        if done then return end
        done = true
        timer:stop()
        timer:close()
        fallback_git_diff()
      end

      local function on_file_done()
        pending = pending - 1
        if pending == 0 then
          if need_fallback then
            finalize_with_fallback()
          else
            finalize_with_difft()
          end
        end
      end

      timer:start(2000, 0, function()
        vim.schedule(finalize_with_fallback)
      end)

      for _, file in ipairs(changed_files) do
        local cleanup = {}
        local old_path = write_temp_file(fetch_head(cwd, file.path))
        if old_path then table.insert(cleanup, old_path) else need_fallback = true end

        local new_path = file.path
        if file.status == "D" then
          new_path = write_temp_file("")
          if new_path then table.insert(cleanup, new_path) else need_fallback = true end
        end

        if not old_path or not new_path then
          for _, temp_path in ipairs(cleanup) do pcall(os.remove, temp_path) end
          on_file_done()
        else
          spawn_difft(cwd, old_path, new_path, function(raw)
            for _, temp_path in ipairs(cleanup) do pcall(os.remove, temp_path) end
            if raw and #raw > 0 then
              local parsed = parse_diff({ raw })
              if #parsed > 0 then
                for _, entry in ipairs(parsed) do
                  entry.path = file.path
                  entry.status = file.status
                  table.insert(parsed_files, entry)
                end
              else
                need_fallback = true
              end
            else
              need_fallback = true
            end
            on_file_done()
          end)
        end
      end
    end,
  })
end

function M.list_files(cwd)
  local entry = _files_cache[cwd]
  local fresh = entry and (_uv.now() - entry.ts) < FILES_TTL_MS
  if not fresh then
    async_refresh_files(cwd, function()
      pcall(function() require("acp.workbench").render() end)
    end)
  end
  local files = entry and entry.files or {}
  _cur.cwd   = cwd
  _cur.files = files
  return files
end

function M.invalidate_files(cwd)
  _files_cache[cwd] = nil
end

function M.with_files(cwd, cb)
  local entry = _files_cache[cwd]
  local fresh = entry and (_uv.now() - entry.ts) < FILES_TTL_MS
  if fresh then cb(entry.files); return end
  async_refresh_files(cwd, function()
    cb((_files_cache[cwd] or {}).files or {})
  end)
end

function M.attach(buf, file_path, cwd)
  _cur.main_buf = buf
  _cur.sel_file = file_path
  _cur.cwd      = cwd or _cur.cwd or vim.fn.getcwd()
  load_threads(_cur.cwd)
  M._install_main_keymaps(buf)
  
  local cwd_t = _cur.cwd
  if _threads[cwd_t] and _threads[cwd_t][file_path] then
    for row, _ in pairs(_threads[cwd_t][file_path]) do
      redraw_thread(row)
    end
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
  pcall(function() require("acp.neogit_workbench").setup_hl() end)
  _cur.main_win      = main_win
  _cur.main_buf      = main_buf
  _cur.on_winbar     = (function(file, tokens)
    if on_winbar then
      local model = require("acp.agents").current_model_label(_cur.cwd)
      on_winbar(file, tokens, model)
    end
  end)
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
  pcall(function() vim.bo[main_buf].filetype = "NeogitDiffView" end)

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

local _save_timers   = {}
local _render_timers = {}

local function debounce(map, key, ms, fn)
  local existing = map[key]
  if existing then
    existing:stop()
    if not existing:is_closing() then existing:close() end
  end
  local timer = _uv.new_timer()
  map[key] = timer
  timer:start(ms, 0, vim.schedule_wrap(function()
    if map[key] == timer then map[key] = nil end
    if not timer:is_closing() then timer:close() end
    fn()
  end))
end

local function flush(map, key)
  local existing = map[key]
  if existing then
    existing:stop()
    if not existing:is_closing() then existing:close() end
    map[key] = nil
  end
end

local function render_thread_surfaces(cwd, file, row, t)
  redraw_thread(row)
  pcall(function() require("acp.workbench").on_event(file, t) end)
  local needle = string.format("acp-thread-%s-%s", file, row)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if buf_is_visible(b) and vim.api.nvim_buf_get_name(b):find(needle, 1, true) then
      M.render_thread_view(b, cwd, file, row, t)
    end
  end
end

local function normalize_tool_call(u)
  if type(u) ~= "table" then return nil end
  local tc = u.toolCall
  if type(tc) == "table" then return tc end
  if u.toolCallId or u.title or u.kind or u.status or u.rawInput or u.rawOutput then
    return {
      toolCallId = u.toolCallId,
      title      = u.title,
      kind       = u.kind,
      status     = u.status,
      content    = u.content,
      locations  = u.locations,
      rawInput   = u.rawInput,
      rawOutput  = u.rawOutput,
    }
  end
  return nil
end

local function content_block_text(c)
  if type(c) ~= "table" then return "" end
  local t = c.type or "text"
  if t == "text"          then return c.text or ""
  elseif t == "image"     then return "[image" .. (c.mimeType and (" " .. c.mimeType) or "") .. "]"
  elseif t == "audio"     then return "[audio" .. (c.mimeType and (" " .. c.mimeType) or "") .. "]"
  elseif t == "resource_link" then return c.uri or c.name or "[resource_link]"
  elseif t == "resource"  then
    local r = c.resource or {}
    return r.text or ("[resource " .. (r.uri or "") .. "]")
  end
  return c.text or ""
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
  t._stream_offset = nil
  t._stream_parsed = {}
  t._stream_tail = ""
  t._last_token_ts = 0
  t._active_tool = nil

  t._unsub = sess.rpc:subscribe(sess.session_id, function(notif)
    if not t._subscribed then return end
    t.messages = t.messages or {}
    local u = (notif.params or {}).update or {}
    local is_text_update = false
    if (u.sessionUpdate == "text" and u.text) or (u.sessionUpdate == "agent_message_chunk" and u.content) then
      is_text_update = true
      local text = u.text or content_block_text(u.content)
      local last = t.messages[#t.messages]
      if last and last.role == "agent" and last.type == "text" then
        last.text = last.text .. text
      else
        table.insert(t.messages, { role="agent", type="text", text=text })
      end
      local now = vim.uv.now()
      if (now - t._last_token_ts) >= 200 and _cur.on_winbar and _cur.sel_file == file then
        t._last_token_ts = now
        local model = require("acp.agents").current_model_label(cwd)
        _cur.on_winbar(_cur.sel_file, compute_tokens(t), model)
      end
      if not t._stream_started then
        t._stream_started = true
        pcall(function() require("acp.neogit_workbench").refresh() end)
        pcall(vim.cmd, "redrawstatus")
        pcall(function() require("acp.spinner").start(function(frame)
          if _cur.on_winbar and _cur.sel_file == file then
            local label = t._active_tool and (" " .. t._active_tool) or ""
            local model = require("acp.agents").current_model_label(cwd)
            _cur.on_winbar(_cur.sel_file, (compute_tokens(t) or "") .. "  " .. frame .. label, model)
          end
        end) end)
      end
    elseif (u.sessionUpdate == "thought" and u.thought) or (u.sessionUpdate == "agent_thought_chunk" and u.content) then
      local text = u.thought or content_block_text(u.content)
      local last = t.messages[#t.messages]
      if last and last.role == "agent" and last.type == "thought" then
        last.text = last.text .. text
      else
        table.insert(t.messages, { role="agent", type="thought", text=text })
      end
    elseif u.sessionUpdate == "user_message_chunk" and u.content then
      local text = content_block_text(u.content)
      local last = t.messages[#t.messages]
      if last and last.role == "user" and last._streaming then
        last.text = (last.text or "") .. text
      else
        table.insert(t.messages, { role="user", text=text, _streaming=true })
      end
    elseif u.sessionUpdate == "plan" and u.entries then
      for i = #t.messages, 1, -1 do
        if t.messages[i].type == "plan" then table.remove(t.messages, i) end
      end
      table.insert(t.messages, { role="agent", type="plan", entries=u.entries })
    elseif u.sessionUpdate == "tool_call" then
      local tc = normalize_tool_call(u)
      if tc then
        table.insert(t.messages, { role="agent", type="tool_call", call=tc })
        local label = tc.title or tc.kind or "tool"
        local raw   = tc.rawInput
        local args  = raw and (type(raw) == "string" and raw or vim.json.encode(raw)) or ""
        if #args > 30 then args = args:sub(1, 30) .. "…" end
        t._active_tool = label .. (args ~= "" and (": " .. args) or "")
      end
    elseif u.sessionUpdate == "tool_call_update" then
      local tc = normalize_tool_call(u)
      if tc then
        local id = tc.toolCallId
        local found
        if id then
          for i = #t.messages, 1, -1 do
            local m = t.messages[i]
            if m.type == "tool_call" and m.call and m.call.toolCallId == id then
              found = m; break
            end
          end
        end
        if found then
          for k, v in pairs(tc) do
            if k == "content" and type(v) == "table" then
              found.call.content = found.call.content or {}
              for _, c in ipairs(v) do table.insert(found.call.content, c) end
            else
              found.call[k] = v
            end
          end
        else
          table.insert(t.messages, { role="agent", type="tool_call", call=tc })
        end
        if tc.status == "completed" or tc.status == "failed" then
          t._active_tool = nil
        end
      end
    elseif u.sessionUpdate == "tool_result" and u.toolResult then
      table.insert(t.messages, { role="agent", type="tool_result", result=u.toolResult })
      t._active_tool = nil
    elseif u.sessionUpdate == "output" and u.output then
      table.insert(t.messages, { role="agent", type="output", text=tostring(u.output) })
    elseif u.sessionUpdate == "error" and u.error then
      table.insert(t.messages, { role="agent", type="error", text=tostring(u.error) })
    end

    local terminal = false
    if u.sessionUpdate == "turn_complete" or u.sessionUpdate == "session_complete" then
      local reason = u.stopReason or u.reason or "done"
      if reason == "refusal" then
        table.insert(t.messages, { role="system", type="info", text="--- refused ---" })
      elseif reason == "max_tokens" then
        table.insert(t.messages, { role="system", type="info", text="--- max tokens reached ---" })
      elseif reason == "max_turn_requests" then
        table.insert(t.messages, { role="system", type="info", text="--- max turn requests reached ---" })
      elseif reason == "cancelled" then
        table.insert(t.messages, { role="system", type="info", text="--- cancelled ---" })
      elseif reason == "end_turn" then
        -- normal end, no banner
      else
        table.insert(t.messages, { role="agent", type="info", text="Turn ended: " .. reason })
      end
      terminal = true
      pcall(function() require("acp.spinner").stop() end)
      if _cur.on_winbar and _cur.sel_file == file then
        local model = require("acp.agents").current_model_label(cwd)
        _cur.on_winbar(_cur.sel_file, compute_tokens(t), model)
      end
      t._stream_started = false
      pcall(function() require("acp.neogit_workbench").refresh() end)
      pcall(vim.cmd, "redrawstatus")
      t._stream_offset = nil
      t._stream_parsed = {}
      t._stream_tail = ""
      t._active_tool = nil
    elseif u.sessionUpdate == "session_info_update" then
      if u.title      then t._title      = u.title      end
      if u.updatedAt  then t._updated_at = u.updatedAt  end
    end

    local key = thread_session_key(cwd, file, row)
    if terminal then
      flush(_save_timers, key)
      flush(_render_timers, key)
      vim.schedule(function()
        save_thread(cwd, file, row)
        render_thread_surfaces(cwd, file, row, t)
      end)
    else
      debounce(_save_timers, key, 500, function() save_thread(cwd, file, row) end)
      debounce(_render_timers, key, 16, function()
        render_thread_surfaces(cwd, file, row, t)
      end)
    end
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
    local pending = vim.g._acp_visual_text
    if pending then
      visual_text = pending
      vim.g._acp_visual_text = nil
    else
      local l1 = vim.fn.line("'<"); local l2 = vim.fn.line("'>")
      local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
      visual_text = table.concat(lines, "\n")
    end
  end

  require("acp.float").open_comment_float(
    "New comment — " .. vim.fn.fnamemodify(file, ":t"),
    {
      anchor_line = (row >= 0) and (row + 1) or 1,
      win_id      = _cur.main_win or 0,
      diff_buf    = _cur.main_buf or 0,
      on_submit   = function(text)
        local cleaned_text, mention_blocks = require("acp.mentions").parse(text, cwd)
        _threads[cwd] = _threads[cwd] or {}
        _threads[cwd][file] = _threads[cwd][file] or {}
        local thread = {
          prompt   = cleaned_text,
          messages = {{ role = "user", text = cleaned_text }},
          resolved = false,
        }
        _threads[cwd][file][row] = thread
        save_thread(cwd, file, row)
        if row >= 0 then
          vim.schedule(function() redraw_thread(row) end)
        end
        vim.schedule(function()
          require("acp.workbench").render()
          pcall(function() require("acp.neogit_workbench").show_thread(file, row, cwd) end)
        end)

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

        local prompt_items = {}
        for _, b in ipairs(mention_blocks) do table.insert(prompt_items, b) end
        table.insert(prompt_items, { type="text", text =
          "Discussion agent. Context: " .. file .. "\n\n"
          .. prompt_text .. "\n\nComment: " .. cleaned_text
          .. "\n\nRespond concisely."
        })
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
  pcall(function() require("acp.neogit_workbench").setup_hl() end)
  local MAX_WIDTH = 100
  local lines = {}
  local hls   = {}
  local line_to_id = {}
  _line_to_call_id_by_buf[buf] = line_to_id
  local active_id = nil
  local function push(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, hl }) end
    if active_id then line_to_id[#lines] = active_id end
  end
  local function add(s, hl)
    s = s or ""
    if #s <= MAX_WIDTH then push(s, hl); return end
    if not s:find("[\128-\255]") then
      for i = 1, #s, MAX_WIDTH do push(s:sub(i, i + MAX_WIDTH - 1), hl) end
      return
    end
    local total = vim.fn.strchars(s)
    if total <= MAX_WIDTH then push(s, hl); return end
    for i = 0, total - 1, MAX_WIDTH do push(vim.fn.strcharpart(s, i, MAX_WIDTH), hl) end
  end
  local SEP = string.rep("─", 48)

  local meta, msgs = {}, {}
  local has_live = type(t_live) == "table"
    and type(t_live.messages) == "table"
    and #t_live.messages > 0
  if has_live then
    meta = { prompt = t_live.prompt, _title = t_live._title }
    msgs = t_live.messages
  else
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

  local session_mod = require("acp.session")
  local key = thread_session_key(cwd, file, row)
  local sess = session_mod.get(key)
  local mode_label = (require("acp.agents").mode_name_from_session(sess)) or ""

  local model = require("acp.agents").current_model_label(cwd)
  local fname = vim.fn.fnamemodify(file or "", ":t")
  local loc   = (type(row) == "number" and row >= 0) and (fname .. ":" .. (row + 1)) or fname

  local title_raw = meta._title or meta.prompt or "Untitled"
  local title = (title_raw:match("([^\n]+)") or "Untitled"):sub(1, 80)

  local suffix = (mode_label ~= "") and ("  ·  " .. mode_label) or ""
  add(SEP, "AcpThreadPrefix")
  add("  " .. title, "AcpSectionHeader")
  add("  " .. model .. "  ·  " .. loc .. suffix, "Comment")
  add(SEP, "AcpThreadPrefix")
  add("")

  local turn = 0
  local current_role = nil
  local function ensure_role(role)
    if current_role == role then return end
    if current_role then add("") end
    current_role = role
    if role == "user" then
      turn = turn + 1
      add("▌ You  ·  turn " .. turn, "AcpThreadUser")
    else
      add("▌ Agent", "AcpThreadAgent")
    end
  end

  for msg_idx, msg in ipairs(msgs) do
    if msg.role == "user" then
      ensure_role("user")
      for _, l in ipairs(vim.split(msg.text or "", "\n")) do add("  " .. l) end
    elseif msg.type == "thought" then
      ensure_role("agent")
      local tlines = vim.split(msg.text or "", "\n")
      add("  … " .. (tlines[1] or ""), "AcpThreadThought")
      for i = 2, #tlines do add("     " .. tlines[i], "AcpThreadThought") end
    elseif msg.type == "tool_call" then
      ensure_role("agent")
      local call    = msg.call or {}
      local tname   = call.title or call.name or call.kind or "tool"
      local status  = call.status or "pending"
      local KIND    = {
        read = "▤", edit = "✎", delete = "✗", move = "→", search = "⌕",
        execute = "▶", think = "…", fetch = "⤓", switch_mode = "⇄", other = "⚙",
      }
      local STATUS  = { pending = "○", in_progress = "◐", completed = "●", failed = "✗" }
      local glyph   = KIND[call.kind or ""] or STATUS[status] or "○"
      local hl      = ({
        failed      = "Error",
        completed   = "AcpThreadResult",
        in_progress = "AcpThreadAction",
        pending     = "Comment",
      })[status] or "AcpThreadAction"

      local raw = call.rawInput or call.arguments
      local brief = ""
      if type(raw) == "table" then
        local parts = {}
        for k, v in pairs(raw) do
          local s = (type(v) == "string") and v or vim.json.encode(v)
          s = s:gsub("[\r\n]+", " ")
          if #s > 60 then s = s:sub(1, 60) .. "…" end
          table.insert(parts, k .. "=" .. s)
        end
        brief = table.concat(parts, ", ")
        if #brief > 100 then brief = brief:sub(1, 100) .. "…" end
      elseif type(raw) == "string" then
        brief = raw:gsub("[\r\n]+", " ")
        if #brief > 100 then brief = brief:sub(1, 100) .. "…" end
      end

      local id       = call.toolCallId or ("call:" .. msg_idx)
      local expanded = _expanded_calls[id] == true
      local arrow    = expanded and "▾" or "▸"
      local s_mark   = STATUS[status] or "○"
      local header   = "  " .. arrow .. " " .. glyph .. " " .. s_mark .. "  " .. tname
      if brief ~= "" then header = header .. "(" .. brief .. ")" end
      active_id = id
      add(header, hl)

      if expanded then
        if type(call.locations) == "table" then
          for _, loc in ipairs(call.locations) do
            if loc.path then
              local line_suffix = loc.line and (":" .. loc.line) or ""
              add("     @ " .. loc.path .. line_suffix, "Comment")
            end
          end
        end

        local content = call.content or {}
        for _, c in ipairs(content) do
          local ctype = c.type
          if ctype == "content" and c.content then
            local inner = c.content
            if inner.type == "text" and inner.text then
              for _, l in ipairs(vim.split(inner.text, "\n")) do
                add("     " .. l, "AcpThreadResult")
              end
            elseif inner.type == "image" then
              add("     [image" .. (inner.mimeType and (" " .. inner.mimeType) or "") .. "]", "AcpThreadResult")
            elseif inner.type == "audio" then
              add("     [audio" .. (inner.mimeType and (" " .. inner.mimeType) or "") .. "]", "AcpThreadResult")
            elseif inner.type == "resource_link" and inner.uri then
              add("     " .. inner.uri, "AcpThreadResult")
            elseif inner.type == "resource" and inner.resource then
              local r = inner.resource
              if r.text and r.text ~= "" then
                for _, l in ipairs(vim.split(r.text, "\n")) do
                  add("     " .. l, "AcpThreadResult")
                end
              else
                add("     " .. (r.uri or "[resource]"), "AcpThreadResult")
              end
            end
          elseif ctype == "diff" and c.path then
            add("     ⟶ " .. c.path, "AcpThreadAction")
            if c.oldText and c.oldText ~= "" then
              for _, l in ipairs(vim.split(c.oldText, "\n")) do
                add("     - " .. l, "AcpDiffDelete")
              end
            end
            if c.newText and c.newText ~= "" then
              for _, l in ipairs(vim.split(c.newText, "\n")) do
                add("     + " .. l, "AcpDiffAdd")
              end
            end
          elseif ctype == "terminal" and c.terminalId then
            local out = c.output or c.text
            if out and out ~= "" then
              for _, l in ipairs(vim.split(out, "\n")) do
                add("     " .. l, "AcpThreadResult")
              end
            else
              add("     $ terminal " .. c.terminalId, "Comment")
            end
          end
        end

        if (#content == 0) and call.rawOutput then
          local out = (type(call.rawOutput) == "string") and call.rawOutput or vim.json.encode(call.rawOutput)
          for _, l in ipairs(vim.split(out, "\n")) do
            add("     " .. l, "AcpThreadResult")
          end
        end
      end
      active_id = nil
    elseif msg.type == "tool_result" then
      ensure_role("agent")
      local res = msg.result or {}
      local is_err = res.isError
      local hl = is_err and "Error" or "AcpThreadResult"
      local id = "result:" .. msg_idx
      local expanded = _expanded_calls[id] == true
      active_id = id
      local first_line_shown = false
      for _, entry in ipairs(res.content or {}) do
        if entry.type == "text" and entry.text then
          local rlines = vim.split(entry.text, "\n")
          for i = 1, #rlines do
            if not first_line_shown then
              add("  " .. (is_err and "✗" or "✓") .. "  " .. rlines[i], hl)
              first_line_shown = true
            elseif expanded then
              add("     " .. rlines[i], hl)
            end
          end
        elseif entry.type == "image" then
          if not first_line_shown then
            add("  " .. (is_err and "✗" or "✓") .. "  [image]", hl)
            first_line_shown = true
          elseif expanded then
            add("     [image]", hl)
          end
        elseif entry.type == "resource_link" and entry.uri then
          if not first_line_shown then
            add("  " .. (is_err and "✗" or "✓") .. "  " .. entry.uri, hl)
            first_line_shown = true
          elseif expanded then
            add("     " .. entry.uri, hl)
          end
        end
      end
      if not first_line_shown then
        add("  " .. (is_err and "✗" or "✓") .. "  (no content)", hl)
      end
      active_id = nil
    elseif msg.type == "plan" then
      ensure_role("agent")
      add("  ▣ Plan", "AcpSectionHeader")
      for _, e in ipairs(msg.entries or {}) do
        local mark = ({ pending = "○", in_progress = "◐", completed = "●" })[e.status or "pending"] or "○"
        local prio = e.priority and (" [" .. e.priority .. "]") or ""
        add("    " .. mark .. " " .. (e.content or "") .. prio, "AcpThreadAction")
      end
    elseif msg.type == "info" then
      ensure_role("agent")
      add("  ·  " .. (msg.text or ""), "DiagnosticInfo")
    elseif msg.type == "error" then
      ensure_role("agent")
      add("  ✗  " .. (msg.text or ""), "Error")
    elseif msg.role == "agent" then
      ensure_role("agent")
      for _, l in ipairs(vim.split(msg.text or "", "\n")) do add("  " .. l) end
    end
  end
  if current_role then add("") end

  if #msgs == 0 then add("  (no messages yet)", "Comment"); add("") end

  vim.bo[buf].modifiable = true

  local lines_mapped = vim.tbl_map(function(l) return (l:gsub("\n", " ")) end, lines)
  local total_lines = #lines_mapped

  local hl_start = 0
  if t_live and t_live._stream_started then
    if msgs[#msgs] and msgs[#msgs].type == "tool_call" then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_mapped)
      t_live._stream_offset = nil
    elseif t_live._stream_offset == nil then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_mapped)
      local msg_count = #msgs
      local last_msg_idx = msg_count
      local trailing_lines = 0
      if msg_count > 0 then
        local last_msg = msgs[msg_count]
        local last_msg_text = ""
        if last_msg.type == "thought" then
          last_msg_text = last_msg.text or ""
        elseif last_msg.type == "tool_call" then
          last_msg_text = ""
        elseif last_msg.type == "tool_result" then
          last_msg_text = ""
        elseif last_msg.type == "info" or last_msg.type == "error" then
          last_msg_text = last_msg.text or ""
        elseif last_msg.role == "agent" then
          last_msg_text = last_msg.text or ""
        end
        trailing_lines = #vim.split(last_msg_text, "\n")
      end
      if trailing_lines > 0 then
        t_live._stream_offset = total_lines - trailing_lines
      else
        t_live._stream_offset = total_lines
      end
    elseif t_live._stream_offset > total_lines or t_live._stream_offset < 0 then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_mapped)
      t_live._stream_offset = nil
    else
      local suffix_lines = {}
      for i = t_live._stream_offset + 1, total_lines do
        table.insert(suffix_lines, lines_mapped[i])
      end
      vim.api.nvim_buf_set_lines(buf, t_live._stream_offset, -1, false, suffix_lines)
      hl_start = t_live._stream_offset
    end
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_mapped)
    if t_live then
      t_live._stream_offset = nil
      t_live._stream_tail = ""
    end
  end

  vim.bo[buf].modifiable = false
  local hl_map = {}
  for _, h in ipairs(hls) do hl_map[h[1]] = h[2] end
  _hls_by_buf[buf] = hl_map
  ensure_decoration_provider()

  local ns_footer = vim.api.nvim_create_namespace("acp_thread_footer")
  vim.api.nvim_buf_clear_namespace(buf, ns_footer, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns_footer, math.max(0, #lines - 1), 0, {
    virt_lines = {
      { { "" } },
      {
        { " <CR>", "AcpHelpKey" }, { " reply  ", "Comment" },
        { "<Tab>", "AcpHelpKey" }, { " tool  ", "Comment" },
        { "R", "AcpHelpKey" }, { " restart  ", "Comment" },
        { "<S-Tab>", "AcpHelpKey" }, { " mode  ", "Comment" },
        { "M", "AcpHelpKey" }, { " model  ", "Comment" },
        { "i", "AcpHelpKey" }, { " index  ", "Comment" },
        { "q", "AcpHelpKey" }, { " close", "Comment" },
      },
    },
  })
end

function M.toggle_call_at_cursor(buf)
  local map = _line_to_call_id_by_buf[buf]; if not map then return nil end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local id = map[lnum]
  if not id then
    for n = lnum, 1, -1 do
      if map[n] then id = map[n]; break end
    end
  end
  if not id then return nil end
  if _expanded_calls[id] then _expanded_calls[id] = nil else _expanded_calls[id] = true end
  return id
end

function M.find_line_for_call(buf, id)
  local map = _line_to_call_id_by_buf[buf]; if not map then return nil end
  local first
  for lnum, mid in pairs(map) do
    if mid == id and (not first or lnum < first) then first = lnum end
  end
  return first
end


function M.open_thread_view(row, _target_win)
  local cwd  = _cur.cwd or vim.fn.getcwd()
  local file = _cur.sel_file
  reload_threads(cwd)
  local t    = ((_threads[cwd] or {})[file] or {})[row]
  if (not t or type(t) == "userdata") and type(row) == "number" then
    t = ((_threads[cwd] or {})[file] or {})[tostring(row)]
  end
  if type(t) ~= "table" then return end
  require("acp.neogit_workbench").show_thread(file, row, cwd)
end

function thread_session_key(cwd, file, row)
  return cwd .. ":thread:" .. file .. ":" .. row
end
M.thread_session_key = thread_session_key

local function notify_thread_surfaces(cwd, file, row, t)
  redraw_thread(row)
  local needle = string.format("acp-thread-%s-%s", file, row)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):find(needle, 1, true) then
      M.render_thread_view(b, cwd, file, row, t)
    end
  end
  pcall(function() require("acp.workbench").on_event(file, t) end)
end

function M.restart_thread(row, file, explicit_cwd)
  local cwd  = explicit_cwd or _cur.cwd or vim.fn.getcwd()
  file = file or _cur.sel_file
  local t    = ((_threads[cwd] or {})[file] or {})[row]
  if (not t or type(t) == "userdata") and type(row) == "number" then
    t = ((_threads[cwd] or {})[file] or {})[tostring(row)]
  end
  if type(t) ~= "table" then return end

  if t._unsub then t._unsub() end
  t._subscribed = false
  local thread_key = thread_session_key(cwd, file, row)
  require("acp.session").close(thread_key)

  t.messages = {{ role = "user", text = t.prompt }}
  save_thread(cwd, file, row)
  vim.schedule(function() notify_thread_surfaces(cwd, file, row, t) end)

  require("acp.session").get_or_create({ key = thread_key, cwd = cwd }, function(err, sess)
    if err then return end
    subscribe_to_thread(sess, cwd, file, row)
    sess.rpc:request("session/prompt", {
      sessionId = sess.session_id, prompt = {{type="text", text=t.prompt}},
    }, function() end)
  end)
end

function M.reply_at(row, file, explicit_cwd)
  local cwd  = explicit_cwd or _cur.cwd or vim.fn.getcwd()
  file = file or _cur.sel_file
  local t    = ((_threads[cwd] or {})[file] or {})[row]
  if not t then
    vim.notify("No thread here", vim.log.levels.WARN, {title="acp"}); return
  end
  local thread_key = thread_session_key(cwd, file, row)

  local function on_submit(text)
    if vim.trim(text) == "" then return end
    local cleaned_text, mention_blocks = require("acp.mentions").parse(text, cwd)
    table.insert(t.messages, {role="user", text=cleaned_text})
    save_thread(cwd, file, row)
    vim.schedule(function() notify_thread_surfaces(cwd, file, row, t) end)
    require("acp.session").get_or_create({ key = thread_key, cwd = cwd }, function(err, sess)
      if err then
        vim.notify("ACP: " .. err, vim.log.levels.ERROR, { title = "acp" }); return
      end
      subscribe_to_thread(sess, cwd, file, row)
      local prompt_items = {}
      for _, b in ipairs(mention_blocks) do table.insert(prompt_items, b) end
      table.insert(prompt_items, {type="text", text=cleaned_text})
      sess.rpc:request("session/prompt", {
        sessionId = sess.session_id, prompt = prompt_items,
      }, function() end)
    end)
  end

  local has_diff_anchor = _cur.main_win
    and type(_cur.main_win) == "number"
    and vim.api.nvim_win_is_valid(_cur.main_win)

  if not has_diff_anchor then
    require("acp.float").open_composer_float("Reply", { on_submit = on_submit })
    return
  end

  local target_buf = vim.api.nvim_win_get_buf(_cur.main_win)
  local anchor
  if row >= 0 then
    anchor = row + 1
  elseif target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    anchor = math.max(1, vim.api.nvim_buf_line_count(target_buf))
  else
    anchor = 1
  end

  require("acp.float").open_comment_float("Reply", {
    anchor_line = anchor, win_id = _cur.main_win, diff_buf = target_buf,
    on_submit   = on_submit,
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

function M.get_thread(cwd, file, row)
  return ((_threads[cwd] or {})[file] or {})[row]
end

function M.is_thread_active(t)
  if type(t) ~= "table" or not t._subscribed then return false end
  return t._stream_started == true or t._active_tool ~= nil
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
  end, "Open thread or jump to file")

  km("a",  M.add_comment,     "New thread")
  km("i",  M.add_comment,     "New thread")
  km("o",  M.add_comment,     "New thread")
  vim.keymap.set("v", "a", function()
    vim.api.nvim_input("<Esc>")
    vim.schedule(function() M.add_comment(nil, nil, true) end)
  end, {buffer=buf, nowait=true, noremap=true, silent=true, desc="New thread (visual)"})
  vim.keymap.set("v", "i", function()
    vim.api.nvim_input("<Esc>")
    vim.schedule(function() M.add_comment(nil, nil, true) end)
  end, {buffer=buf, nowait=true, noremap=true, silent=true, desc="New thread (visual)"})
  km("r",  function() M.reply_at(vim.api.nvim_win_get_cursor(0)[1] - 1) end, "Reply")
  km("gx", M.toggle_resolve,  "Toggle resolve")
  km("d",  M.delete_thread,   "Delete thread")
  km("gL", function()
    if _cur.sel_file and _cur.sel_file:match("%.nowork/") then
      require("acp.workbench").show_thread(_cur.sel_file, -1)
    end
  end, "Show thread")
  km("gt", function() M.open_thread_view(-1) end, "Open global thread")
  km("gs", M.send,            "Send diff to ACP")
  km("n",  function() require("acp.workbench").set(_cur.cwd) end, "New thread")
  vim.keymap.set("n", "ga", "", { buffer = buf, nowait = false, silent = true })
  km("gan", function()
    local mode = vim.api.nvim_get_mode().mode
    local in_visual = vim.fn.visualmode() ~= "" or mode:find("v") or mode:find("s")
    if in_visual then
      local l1 = vim.fn.line("'<"); local l2 = vim.fn.line("'>")
      local lines = vim.api.nvim_buf_get_lines(0, math.min(l1, l2) - 1, math.max(l1, l2), false)
      vim.g._acp_visual_text = table.concat(lines, "\n")
      vim.api.nvim_input("<Esc>")
      vim.schedule(function() M.add_comment(nil, nil, true) end)
    else
      M.add_comment()
    end
  end, "New thread (with selection)")
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

  local function neogit_op(fn, label)
    pcall(vim.cmd, "packadd neogit")
    local ok, idx = pcall(require, "neogit.lib.git.index")
    if not ok then
      vim.notify("Neogit not available", vim.log.levels.WARN, { title = "acp" }); return
    end
    local res_ok, err = pcall(fn, idx)
    if not res_ok then
      vim.notify("git " .. label .. " failed: " .. tostring(err), vim.log.levels.WARN, { title = "acp" }); return
    end
    M.invalidate_files(_cur.cwd or vim.fn.getcwd())
    if _cur.sel_file then
      M.show_file(_cur.sel_file, _cur.main_win, _cur.main_buf, _cur.on_winbar)
    end
    pcall(function() require("acp.neogit_workbench").refresh() end)
  end

  km("S", function()
    if _cur.sel_file then
      neogit_op(function(idx) idx.add({ _cur.sel_file }) end, "stage")
    end
  end, "Stage file")
  km("U", function()
    if _cur.sel_file then
      neogit_op(function(idx) idx.reset({ _cur.sel_file }) end, "unstage")
    end
  end, "Unstage file")
  km("X", function()
    local file = _cur.sel_file
    if not file then return end
    local choice = vim.fn.confirm("Discard changes to " .. file .. "?", "&Yes\n&No", 2)
    if choice == 1 then
      neogit_op(function(idx) idx.checkout({ file }) end, "discard")
    end
  end, "Discard file")

  local function hunk_at_cursor()
    local row  = vim.api.nvim_win_get_cursor(0)[1] - 1
    local file = _cur.sel_file
    if not file then return end
    local target_header
    for r = row, 0, -1 do
      local meta = _cur.buf_line_meta[r]
      if meta and meta.hunk_header then target_header = meta.hunk_header; break end
    end
    if not target_header then return end
    for _, f in ipairs(_cur.files or {}) do
      if f.path == file then
        for _, h in ipairs(f.hunks or {}) do
          if h.header == target_header then return f, h end
        end
      end
    end
  end

  local function build_patch(file, hunk)
    local parts = {
      "diff --git a/" .. file .. " b/" .. file,
      "--- a/" .. file,
      "+++ b/" .. file,
      hunk.header,
    }
    for _, l in ipairs(hunk.lines) do
      local p = l.type == "add" and "+" or l.type == "del" and "-" or " "
      table.insert(parts, p .. l.text)
    end
    return table.concat(parts, "\n") .. "\n"
  end

  km("s", function()
    local f, h = hunk_at_cursor(); if not f or not h then return end
    local patch = build_patch(f.path, h)
    neogit_op(function(idx) idx.apply(patch, { cached = true }) end, "stage hunk")
  end, "Stage hunk")

  km("u", function()
    local f, h = hunk_at_cursor(); if not f or not h then return end
    local patch = build_patch(f.path, h)
    neogit_op(function(idx) idx.apply(patch, { cached = true, reverse = true }) end, "unstage hunk")
  end, "Unstage hunk")

  km("x", function()
    local f, h = hunk_at_cursor(); if not f or not h then return end
    local choice = vim.fn.confirm("Discard hunk?", "&Yes\n&No", 2)
    if choice == 1 then
      local patch = build_patch(f.path, h)
      neogit_op(function(idx) idx.apply(patch, { reverse = true }) end, "discard hunk")
    end
  end, "Discard hunk")

  km("<BS>", function()
    require("acp.git").open_neogit({ kind = "replace" })
  end, "Back to Neogit")

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

function M.refresh_winbar()
  if _cur and _cur.on_winbar and _cur.sel_file then
    local cwd = _cur.cwd or vim.fn.getcwd()
    local rows = (_threads[cwd] or {})[_cur.sel_file] or {}
    local tokens = ""
    for _, t in pairs(rows) do
      tokens = compute_tokens(t) or ""
      break
    end
    local model = require("acp.agents").current_model_label(cwd)
    _cur.on_winbar(_cur.sel_file, tokens, model)
  end
end

function M._stop_all_timers()
  for k, t in pairs(_save_timers) do
    pcall(function()
      if t then t:stop(); if not t:is_closing() then t:close() end end
    end)
    _save_timers[k] = nil
  end
  for k, t in pairs(_render_timers) do
    pcall(function()
      if t then t:stop(); if not t:is_closing() then t:close() end end
    end)
    _render_timers[k] = nil
  end
end

return M
