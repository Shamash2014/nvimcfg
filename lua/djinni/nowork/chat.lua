local blocks = require("djinni.nowork.blocks")
local input = require("djinni.nowork.input")
local commands = require("djinni.nowork.commands")
local session = require("djinni.acp.session")
local log = require("djinni.nowork.log")
local mcp = require("djinni.nowork.mcp")
local tools = require("djinni.nowork.tools")
local skills = require("djinni.nowork.skills")
local lessons = require("djinni.nowork.lessons")

local ns_id = vim.api.nvim_create_namespace("djinni_chat")

local get_provider

local M = {}

function M._schedule_panel_render()
  local ok, panel = pcall(require, "djinni.nowork.panel")
  if ok and panel and panel.schedule_render then
    panel.schedule_render()
  end
end

_G._djinni_chat_statusline = function()
  local ok, mod = pcall(require, "djinni.nowork.chat")
  if ok and mod and mod.statusline then return mod.statusline() end
  return ""
end

M._streaming = {} -- buf -> true when streaming
M._queue = {} -- buf -> { text1, text2, ... }
M._sessions = {} -- buf -> sessionId (in-memory backup)
M._stream_cleanup = {} -- buf -> cleanup function
M._spinner_frame = 0
M._spinner_chars = { "/", "-", "\\", "|" }
M._modes = {} -- buf -> { {id, name}, ... }
M._current_mode = {} -- buf -> mode_id
M._pending_text = {} -- buf -> accumulated text during streaming
M._assistant_output_seen = {} -- buf -> true once assistant text arrives in current turn
M._scroll_pending = {} -- buf -> true when scroll needed after flush
M._stream_client = {} -- buf -> client ref for watchdog checks
M._global_timer = nil
M._global_timer_scheduled = false
M._last_perm_tool = {} -- buf -> tool description
M._continuation_count = {} -- buf -> number
M._last_tool_failed = {} -- buf -> bool
M._max_continuations = 8
M._plan_path = {} -- buf -> plan file path
M._usage = {} -- buf -> { input_tokens, output_tokens, cost }
M._turn_started_at = {}
M._turn_elapsed_ms = {}
M._turn_usage = {}
M._diff_stats = {}
M._STATUS_DIFF_MAX_BYTES = 512 * 1024
M._STATUS_REDRAW_MIN_MS = 250
M._status_redraw_last = 0
M._status_redraw_pending = false
M._attached = {} -- buf -> true
M._last_code_buf = nil
M._cleanup_deferred = {} -- buf -> true when stream_cleanup was called but blocked by pending permission
M._tool_log = {} -- buf -> list of {name, kind, input, output, images}
M._interrupt_pending = {} -- buf -> true when interrupt fired before session was created
M._hidden_pending = {} -- buf -> list of text chunks not yet rendered (buffer was hidden)
M._timer_scheduled = {} -- buf -> true when a vim.schedule is already pending for the timer
M._pending_images = {} -- buf -> list of { data = base64, media_type = "image/png" }
M._stream_gen = {} -- buf -> generation counter to detect stale callbacks
M._available_commands = {} -- buf -> list of { name, description }

function M.archive_chat_file(filepath)
  if not filepath or filepath == "" then return false end
  local dir = vim.fn.fnamemodify(filepath, ":h")
  local archive_dir = dir .. "/archive"
  vim.fn.mkdir(archive_dir, "p")
  local filename = vim.fn.fnamemodify(filepath, ":t")
  return os.rename(filepath, archive_dir .. "/" .. filename)
end
M._config_options = {} -- buf -> list of config options from ACP
M._creating_session = {} -- buf -> true while create_task_session is in-flight
M._win_configured = {} -- win -> buf when win options + folds already set
M._send_retries = {} -- buf -> number of consecutive send retries
M._waiting_input = {} -- buf -> true when agent stopped with end_turn (waiting for user)
M._max_send_retries = 3
M._active_tool_count = {} -- buf -> number of in-progress tool calls
M._last_event_time = {} -- buf -> uv.now() of last event
M._events_received = {} -- buf -> bool
M._plan_lines = {} -- buf -> { start_line, end_line }
M._last_tool_title = {} -- buf -> string
M._think_fold_start = {} -- buf -> line number where current thinking section started
M._tool_section_start = {} -- buf -> line number where current tool section started
M._last_tool_line = {} -- buf -> line number of last [*] tool line (for per-tool folding)
M._djinni_marker_line = {} -- buf -> line number of @Djinni marker (avoids backwards scan)
M._append_batch = {} -- buf -> list of lines to write in next scheduled flush
M._append_scheduled = {} -- buf -> true when a flush is already scheduled
M._fm_end_cache = {} -- buf -> frontmatter closing line index (1-based)
M._cached_root = {} -- buf -> cached project root (avoids reading frontmatter per event)
M._last_activity_touch = {} -- buf -> last timestamp we called touch_activity
M._stream_tail_row = {} -- buf -> current writable tail row (1-based)
M._stream_tail_text = {} -- buf -> current writable tail text
M._checktime_dirty = false
M._FILE_MUTATING = { edit=true, create=true, write=true, delete=true, move=true }

local LARGE_CHAT_THRESHOLD = 3000

local function _fmt_k(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(n)
end

local function _fmt_elapsed(ms)
  ms = tonumber(ms) or 0
  local seconds = math.floor(ms / 1000)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  seconds = seconds % 60
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, seconds)
  end
  return string.format("%d:%02d", minutes, seconds)
end

local function _split_diff_lines(text)
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines > 0 and lines[#lines] == "" then table.remove(lines) end
  return lines
end

local function _count_diff_lines(old_text, new_text)
  local total_bytes = #(old_text or "") + #(new_text or "")
  if total_bytes > M._STATUS_DIFF_MAX_BYTES then return nil, nil end
  local old_lines = _split_diff_lines(old_text)
  local new_lines = _split_diff_lines(new_text)
  local ok, hunks = pcall(vim.diff, old_text or "", new_text or "", { result_type = "indices" })
  if not ok or type(hunks) ~= "table" then
    return math.max(#new_lines - #old_lines, 0), math.max(#old_lines - #new_lines, 0)
  end
  local added = 0
  local deleted = 0
  for _, hunk in ipairs(hunks) do
    deleted = deleted + (hunk[2] or 0)
    added = added + (hunk[4] or 0)
  end
  return added, deleted
end

local function _redraw_status()
  local now = vim.uv.now()
  local elapsed = now - (M._status_redraw_last or 0)
  if elapsed >= M._STATUS_REDRAW_MIN_MS then
    M._status_redraw_last = now
    pcall(vim.cmd, "redrawstatus")
    return
  end
  if M._status_redraw_pending then return end
  M._status_redraw_pending = true
  vim.defer_fn(function()
    M._status_redraw_pending = false
    M._status_redraw_last = vim.uv.now()
    pcall(vim.cmd, "redrawstatus")
  end, M._STATUS_REDRAW_MIN_MS - elapsed)
end

M._redraw_status = _redraw_status

local function _is_large_chat(buf)
  return vim.api.nvim_buf_line_count(buf) > LARGE_CHAT_THRESHOLD
end

local function _set_stream_tail(buf, row, text)
  M._stream_tail_row[buf] = row
  M._stream_tail_text[buf] = text or ""
end

local function _sync_stream_tail(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil, "" end
  local row = vim.api.nvim_buf_line_count(buf)
  local text = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  _set_stream_tail(buf, row, text)
  return row, text
end

function M._stream_chunk_lines(tail, text)
  local segments = {}
  local start = 1
  while true do
    local nl = text:find("\n", start, true)
    if not nl then break end
    segments[#segments + 1] = text:sub(start, nl - 1)
    start = nl + 1
  end

  if #segments == 0 then
    local merged = (tail or "") .. text
    return { merged }, merged
  end

  local lines = { (tail or "") .. segments[1] }
  for i = 2, #segments do
    lines[#lines + 1] = segments[i]
  end

  local remainder = text:sub(start)
  if text:sub(-1) == "\n" then
    lines[#lines + 1] = ""
  else
    lines[#lines + 1] = remainder
  end

  return lines, lines[#lines]
end

local function _compute_manual_folds(win, buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then return end
  if _is_large_chat(buf) then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ranges = {}
  local fold_start = nil
  for i, line in ipairs(lines) do
    if line:match("^%*%*Thinking") or line:match("^%[%*%]") or line:match("^%[%+%]") or line:match("^%[!%]") then
      if not fold_start then fold_start = i end
    elseif line:match("^@%w") or line:match("^%-%-%-$") or line == "" then
      if fold_start and i - 1 >= fold_start + 1 then
        ranges[#ranges + 1] = { fold_start, i - 1 }
      end
      fold_start = nil
    end
  end
  if fold_start and #lines >= fold_start + 1 then
    ranges[#ranges + 1] = { fold_start, #lines }
  end
  vim.api.nvim_win_call(win, function()
    vim.cmd("noautocmd setlocal foldmethod=manual")
    vim.cmd("noautocmd setlocal foldtext=v:lua.require('djinni.nowork.chat').foldtext()")
    vim.cmd("noautocmd setlocal foldenable")
    vim.cmd("noautocmd setlocal foldlevel=0")
    vim.cmd("noautocmd setlocal foldminlines=1")
    vim.cmd("normal! zE")
    for _, r in ipairs(ranges) do
      pcall(vim.cmd, r[1] .. "," .. r[2] .. "fold")
    end
  end)
end

local function _win_fold_chat(win, buf)
  _compute_manual_folds(win, buf)
end

local function _win_fold_manual(win, buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then return end
  vim.api.nvim_win_call(win, function()
    vim.cmd("noautocmd setlocal foldmethod=manual")
  end)
end

local function _rm_disable(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  pcall(function()
    require("render-markdown.core.manager").set_buf(buf, false)
  end)
end

local function _rm_enable(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  pcall(function()
    require("render-markdown.core.manager").set_buf(buf, true)
  end)
end

local function _win_fold_restore_expr(win, buf)
  _compute_manual_folds(win, buf)
end

function M._invalidate_session(buf)
  local old_sid = M._sessions[buf]
  M._sessions[buf] = nil
  M._waiting_input[buf] = nil
  M._set_frontmatter_field(buf, "session", "")
  if old_sid and old_sid ~= "" then
    local root = M._cached_root[buf] or M.get_project_root(buf)
    pcall(session.close_task_session, root, old_sid, get_provider(buf))
  end
end

local ns_attach = vim.api.nvim_create_namespace("djinni_attach")

function M._update_attach_indicator(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns_attach, 0, -1)
  local imgs = M._pending_images[buf]
  if not imgs or #imgs == 0 then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = #lines, 1, -1 do
    if lines[i] and lines[i]:match("^@You%s*$") then
      vim.api.nvim_buf_set_extmark(buf, ns_attach, i - 1, 0, {
        virt_text = { { " [" .. #imgs .. " image" .. (#imgs > 1 and "s" or "") .. " attached]", "DiagnosticInfo" } },
        virt_text_pos = "eol",
      })
      return
    end
  end
end

function M._paste_image(buf, img)
  local chat_path = vim.api.nvim_buf_get_name(buf)
  local chat_dir = vim.fn.fnamemodify(chat_path, ":h")
  local img_dir = chat_dir .. "/images"
  vim.fn.mkdir(img_dir, "p")
  local ext = img.ext or "png"
  local ts = os.date("%Y%m%d-%H%M%S")
  local filename = ts .. "." .. ext
  local filepath = img_dir .. "/" .. filename
  local f = io.open(filepath, "wb")
  if f then
    f:write(img.raw)
    f:close()
  end
  if not M._pending_images[buf] then M._pending_images[buf] = {} end
  table.insert(M._pending_images[buf], { data = img.data, media_type = img.media_type })
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local insert_row = vim.api.nvim_win_get_cursor(0)[1]
  for i = insert_row, 1, -1 do
    if lines[i] and lines[i]:match("^@You%s*$") then
      for j = i + 1, #lines do
        if lines[j] == "" or lines[j]:match("^%-%-%-$") or lines[j]:match("^@%w+") then
          insert_row = j
          break
        end
        insert_row = j + 1
      end
      break
    end
  end
  local ref = "![image](images/" .. filename .. ")"
  vim.api.nvim_buf_set_lines(buf, insert_row - 1, insert_row - 1, false, { ref })
  M._update_attach_indicator(buf)
  vim.notify("[djinni] Image attached: " .. filename, vim.log.levels.INFO)
end

function M._close_last_tool_fold(buf)
  local start = M._last_tool_line[buf]
  if not start then return end
  M._last_tool_line[buf] = nil
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local win = vim.fn.bufwinid(buf)
    if win == -1 then return end
    local fold_end = vim.api.nvim_buf_line_count(buf)
    if fold_end > start then
      pcall(vim.api.nvim_win_call, win, function()
        vim.cmd(start .. "," .. fold_end .. "foldclose")
      end)
    end
  end, 50)
end

function M._close_tool_fold(buf)
  M._tool_section_start[buf] = nil
  if M._streaming[buf] then return end
  M._close_last_tool_fold(buf)
end

function M._on_session_reconnect(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if M._waiting_input[buf] and not M._streaming[buf] then
    log.info("reconnect skipped — agent waiting for user input buf=" .. tostring(buf))
    return
  end
  if M._streaming[buf] then
    M._stream_gen[buf] = (M._stream_gen[buf] or 0) + 1
    if M._stream_cleanup[buf] then
      M._stream_cleanup[buf](true)
    end
    M._cleanup_empty_djinni(buf)
  end
  local root = M.get_project_root(buf)
  if root then mcp.clear_cache(root) end
  M._invalidate_session(buf)
  M._creating_session[buf] = nil
  M._update_system_block(buf, "Reconnecting...")
  M._ensure_session(buf)
  vim.notify("[djinni] Reconnected — re-establishing session", vim.log.levels.WARN)
end

local function hide_snacks_notif(id)
  if not id then return end
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.notifier then Snacks.notifier.hide(id) end
end

local IMAGE_EXTENSIONS = { png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif", webp = "image/webp", svg = "image/svg+xml" }

local function detect_media_type(raw)
  if not raw or #raw < 4 then return nil end
  local b1, b2, b3, b4 = raw:byte(1, 4)
  if b1 == 0x89 and b2 == 0x50 and b3 == 0x4E and b4 == 0x47 then return "image/png", "png" end
  if b1 == 0xFF and b2 == 0xD8 and b3 == 0xFF then return "image/jpeg", "jpg" end
  if b1 == 0x47 and b2 == 0x49 and b3 == 0x46 then return "image/gif", "gif" end
  if b1 == 0x52 and b2 == 0x49 and b3 == 0x46 and #raw >= 12 then
    local w1, w2, w3, w4 = raw:byte(9, 12)
    if w1 == 0x57 and w2 == 0x45 and w3 == 0x42 and w4 == 0x50 then return "image/webp", "webp" end
  end
  return nil
end

local function encode_base64(raw, callback)
  vim.system({ "base64" }, { stdin = raw, text = true }, function(b64_result)
    vim.schedule(function()
      if b64_result.code ~= 0 or not b64_result.stdout then
        callback(nil)
        return
      end
      local data = b64_result.stdout:gsub("%s+", "")
      if data == "" then
        callback(nil)
        return
      end
      callback(data)
    end)
  end)
end

local function get_clipboard_image(callback)
  local function try_raw(raw)
    if not raw or #raw == 0 then
      callback(nil)
      return
    end
    local media_type, ext = detect_media_type(raw)
    if not media_type then
      callback(nil)
      return
    end
    encode_base64(raw, function(data)
      if not data then
        callback(nil)
        return
      end
      callback({ data = data, media_type = media_type, ext = ext, raw = raw })
    end)
  end

  if vim.fn.has("mac") == 1 then
    local pngpaste = vim.fn.exepath("pngpaste")
    if pngpaste == "" then
      callback(nil)
      return
    end
    vim.system({ pngpaste, "/dev/stdout" }, { text = false }, function(result)
      if result.code ~= 0 or not result.stdout or #result.stdout == 0 then
        vim.schedule(function() callback(nil) end)
        return
      end
      vim.schedule(function() try_raw(result.stdout) end)
    end)
  else
    local wl_paste = vim.fn.exepath("wl-paste")
    local xclip = vim.fn.exepath("xclip")
    if wl_paste ~= "" then
      vim.system({ wl_paste, "--no-newline", "--type", "image/png" }, { text = false }, function(result)
        vim.schedule(function() try_raw(result.code == 0 and result.stdout or nil) end)
      end)
    elseif xclip ~= "" then
      vim.system({ xclip, "-selection", "clipboard", "-t", "image/png", "-o" }, { text = false }, function(result)
        vim.schedule(function() try_raw(result.code == 0 and result.stdout or nil) end)
      end)
    else
      callback(nil)
    end
  end
end

local function file_to_image(filepath, callback)
  local ext = filepath:match("%.(%w+)$")
  if not ext then
    callback(nil)
    return
  end
  ext = ext:lower()
  local media_type = IMAGE_EXTENSIONS[ext]
  if not media_type then
    callback(nil)
    return
  end
  local f = io.open(filepath, "rb")
  if not f then
    callback(nil)
    return
  end
  local raw = f:read("*a")
  f:close()
  if not raw or #raw == 0 then
    callback(nil)
    return
  end
  encode_base64(raw, function(data)
    if not data then
      callback(nil)
      return
    end
    callback({ data = data, media_type = media_type, ext = ext, raw = raw })
  end)
end

local function you_block()
  return { "", "---", "", "@You", "", "", "---", "" }
end

vim.api.nvim_create_autocmd("BufLeave", {
  callback = function(ev)
    local b = ev.buf
    if vim.bo[b].filetype ~= "nowork-chat"
      and vim.bo[b].filetype ~= "nowork-panel"
      and vim.bo[b].buftype == ""
      and vim.api.nvim_buf_get_name(b) ~= "" then
      M._last_code_buf = b
    end
  end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  callback = function(ev)
    local b = ev.buf
    if vim.bo[b].filetype ~= "nowork-chat" then return end
    local win = vim.fn.bufwinid(b)
    if win ~= -1 and M._win_configured[win] ~= b then
      M._win_configured[win] = b
      vim.wo[win].statusline = "%{%v:lua._djinni_chat_statusline()%} %f %m"
      vim.wo[win].wrap = true
      vim.wo[win].linebreak = true
      vim.wo[win].conceallevel = 2
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(b) then return end
        local w = vim.fn.bufwinid(b)
        if w ~= -1 and not _is_large_chat(b) then
          pcall(_win_fold_chat, w, b)
        end
      end)
    end
    local hp = M._hidden_pending[b]
    if hp and #hp > 0 then
      M._hidden_pending[b] = nil
      if vim.api.nvim_buf_is_valid(b) then
        M._apply_stream_chunk(b, table.concat(hp))
      end
    end
    if not M._streaming[b] and not M._creating_session[b] then
      local root = M.get_project_root(b)
      if root then
        local sid = M._sessions[b]
        local s = sid and session.sessions_by_id[sid] or nil
        local client_dead = sid and (not s or not s.client or not s.client:is_alive())
        if sid and client_dead then
          M._sessions[b] = nil
          M._set_frontmatter_field(b, "session", "")
          M._ensure_session(b)
        end
      end
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "nowork-chat",
  callback = function(ev)
    local b = ev.buf
    if M._pre_create_path then
      log.info("FileType: skipping (M.create in progress)")
      return
    end
    log.info("FileType: attach + ensure_session buf=" .. tostring(b))
    M.attach(b)
    M._ensure_session(b)
  end,
})


local function read_frontmatter_field(buf, key)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local line_count = vim.api.nvim_buf_line_count(buf)
  local limit = math.min(20, line_count)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, limit, false)
  if lines[1] ~= "---" then return nil end
  for i = 2, #lines do
    if lines[i] == "---" then return nil end
    local k, v = lines[i]:match("^([%w_]+):%s*(.*)")
    if k == key and v and v ~= "" then return v end
  end
  return nil
end

local function parse_csv(str)
  if not str or str == "" then return {} end
  local result = {}
  for item in str:gmatch("[^,]+") do
    result[#result + 1] = vim.trim(item)
  end
  return result
end

M._cached_provider = {}
get_provider = function(buf)
  local cached = M._cached_provider[buf]
  if cached then return cached end
  cached = read_frontmatter_field(buf, "provider")
  M._cached_provider[buf] = cached
  return cached
end
M.get_provider = get_provider

local function build_session_opts(buf, root)
  local all_servers = mcp.load(root)
  local opts = {}
  if all_servers and next(all_servers) then
    opts.mcpServers = all_servers
  end
  local model = read_frontmatter_field(buf, "model")
  if model and model ~= "" then
    opts.model = model
  end
  local provider = get_provider(buf)
  if provider and provider ~= "" then
    opts.provider = provider
  end
  return opts
end

local function inject_skills(buf, root, prompt)
  local skill_names = parse_csv(read_frontmatter_field(buf, "skills"))
  if #skill_names == 0 then return prompt end
  local prefix = ""
  for _, name in ipairs(skill_names) do
    local content = skills.get(name, root)
    if content then
      prefix = prefix .. "[Skill: " .. name .. "]\n" .. content .. "\n\n"
    end
  end
  if prefix ~= "" then
    return prefix .. prompt
  end
  return prompt
end

local function inject_lessons(buf, root, prompt)
  local toggle = read_frontmatter_field(buf, "lessons")
  if toggle and toggle:lower() == "off" then return prompt end
  local block = lessons.format_for_injection(root)
  if block then return block .. prompt end
  return prompt
end

local function build_history_context(buf, current_text)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local scan_from = math.max(0, line_count - 500)
  local lines = vim.api.nvim_buf_get_lines(buf, scan_from, -1, false)
  local msgs = {}
  local current_type = nil
  local current_lines = {}
  for _, line in ipairs(lines) do
    local header = line:match("^@(%w+)%s*$")
    if header then
      if current_type and #current_lines > 0 then
        local content = table.concat(current_lines, "\n"):match("^%s*(.-)%s*$")
        if content ~= "" then
          msgs[#msgs + 1] = { type = current_type:lower(), content = content }
        end
      end
      current_type = header
      current_lines = {}
    elseif line:match("^%-%-%-$") then
      if current_type and #current_lines > 0 then
        local content = table.concat(current_lines, "\n"):match("^%s*(.-)%s*$")
        if content ~= "" then
          msgs[#msgs + 1] = { type = current_type:lower(), content = content }
        end
      end
      current_type = nil
      current_lines = {}
    elseif current_type then
      current_lines[#current_lines + 1] = line
    end
  end
  if current_type and #current_lines > 0 then
    local content = table.concat(current_lines, "\n"):match("^%s*(.-)%s*$")
    if content ~= "" then
      msgs[#msgs + 1] = { type = current_type:lower(), content = content }
    end
  end
  local filtered = {}
  for _, m in ipairs(msgs) do
    if m.type == "you" or m.type == "djinni" then
      filtered[#filtered + 1] = m
    end
  end
  msgs = filtered
  if #msgs > 0 and msgs[#msgs].type == "you" then
    msgs[#msgs] = nil
  end
  local system_prompt = read_frontmatter_field(buf, "system")
  local root_for_lessons = read_frontmatter_field(buf, "root")
  local lessons_mod = require("djinni.nowork.lessons")
  local has_lessons = root_for_lessons and lessons_mod.has_any(root_for_lessons)
  if #msgs == 0 and not system_prompt and not has_lessons then return current_text end
  local max_msgs = 10
  if #msgs > max_msgs then
    msgs = { unpack(msgs, #msgs - max_msgs + 1) }
  end
  local parts = { "<previous_conversation>" }
  if system_prompt and system_prompt ~= "" then
    parts[#parts + 1] = "<system>\n" .. system_prompt .. "\n</system>"
  end
  if has_lessons then
    local injection = lessons_mod.format_for_injection(root_for_lessons)
    if injection then
      parts[#parts + 1] = injection
    end
  end
  for _, block in ipairs(msgs) do
    local role = block.type == "you" and "user" or "assistant"
    local content = block.content
    if #content > 2000 then
      content = content:sub(1, 2000) .. "\n...(truncated)"
    end
    parts[#parts + 1] = "<" .. role .. ">\n" .. content .. "\n</" .. role .. ">"
  end
  parts[#parts + 1] = "</previous_conversation>\n"
  parts[#parts + 1] = current_text
  return table.concat(parts, "\n")
end

local function slug(text)
  if not text or text == "" then
    return "chat"
  end
  return text:sub(1, 40):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
end

local function iso_timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function project_name(root)
  return vim.fn.fnamemodify(root, ":t")
end

function M.create(project_root, opts)
  opts = opts or {}
  local config = require("djinni").config
  local chat_dir = project_root .. "/" .. config.chat.dir
  vim.fn.mkdir(chat_dir, "p")

  local date = os.date("%Y-%m-%d")
  local title = opts.title or slug(opts.prompt)
  local filename = date .. "-" .. slug(title) .. ".md"
  local filepath = chat_dir .. "/" .. filename

  local context_refs = ""
  if opts.context_file then
    context_refs = context_refs .. "\n@./" .. opts.context_file
  end
  if opts.context_selection then
    context_refs = context_refs .. "\n@./" .. opts.context_selection
  end

  local prompt = opts.prompt or ""

  local auto_mcps = mcp.list(project_root)
  local mcp_value = #auto_mcps > 0 and table.concat(auto_mcps, ", ") or ""

  local content = table.concat({
    "---",
    "project: " .. project_name(project_root),
    "root: " .. project_root,
    "session:",
    "provider: " .. (opts.provider or (config.acp and config.acp.provider) or "claude-code"),
    "model:",
    "mcp: " .. mcp_value,
    "parent: " .. (opts.parent or ""),
    "system: " .. (opts.system or ""),
    "status:",
    "created: " .. iso_timestamp(),
    "---",
    "",
    "@System",
    opts.system or "Session starting...",
    "",
    "---",
    "",
    "@You",
    prompt .. context_refs,
    "",
    "---",
    "",
  }, "\n")

  local f = io.open(filepath, "w")
  if f then
    f:write(content)
    f:close()
  end

  if opts.no_open or opts.silent then
    return filepath
  end

  M._pre_create_path = filepath
  local open_cmd = opts.split and "vsplit" or "edit"
  vim.cmd(open_cmd .. " " .. vim.fn.fnameescape(filepath))
  M._pre_create_path = nil
  local buf = vim.api.nvim_get_current_buf()
  M.attach(buf)

  if opts.no_send then
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i = #lines, 1, -1 do
      if lines[i]:match("^@You%s*$") then
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then
          vim.api.nvim_win_set_cursor(win, { i + 1, 0 })
        end
        break
      end
    end
    return filepath
  end

  M._creating_session[buf] = true
  local sess_opts = build_session_opts(buf, project_root)
  session.create_task_session(project_root, function(err, sid, result)
    M._creating_session[buf] = nil
    if err or not sid then return end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      M._set_frontmatter_field(buf, "session", sid)
      M._sessions[buf] = sid
      M._subscribe_session(buf, project_root, sid)
      M._streaming[buf] = true
      M._start_streaming(buf)
      M._restore_mode(buf, project_root, sid, result)
      local msg = inject_skills(buf, project_root, prompt .. context_refs)
      log.info("sending prompt on sid=" .. tostring(sid) .. " len=" .. tostring(#msg))
      session.send_message(project_root, sid, msg, function(_err, prompt_result)
        log.info("session/prompt callback: " .. (_err and ("err=" .. vim.inspect(_err)) or "ok"))
        if prompt_result then
          log.info("prompt_result: stopReason=" .. tostring(prompt_result.stopReason))
          if prompt_result.usage then log.info("usage: " .. vim.inspect(prompt_result.usage)) end
        end
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          M._accumulate_usage(buf, prompt_result)
          if prompt_result and prompt_result.stopReason == "end_turn" then
            M._waiting_input[buf] = true
          end
          if M._stream_cleanup[buf] then
            M._stream_cleanup[buf]()
          end
        end)
      end, nil, get_provider(buf))
    end)
  end, sess_opts)

  return buf
end

function M._ensure_session(buf)
  if M._sessions[buf] then
    log.info("_ensure_session: skip (session exists) buf=" .. tostring(buf))
    return
  end
  if M._creating_session[buf] then
    log.info("_ensure_session: skip (creating) buf=" .. tostring(buf))
    return
  end

  local root = M.get_project_root(buf)
  if not root then
    log.info("_ensure_session: skip (no root) buf=" .. tostring(buf))
    return
  end

  M._creating_session[buf] = true

  local sid = M.get_session_id(buf)
  local sess_opts = build_session_opts(buf, root)
  log.info("_ensure_session: buf=" .. tostring(buf) .. " sid=" .. tostring(sid) .. " root=" .. root)

  session.create_or_resume_session(root, sid, function(err, new_sid, result)
    M._creating_session[buf] = nil
    if err or not new_sid then
      log.warn("_ensure_session: failed err=" .. tostring(err and (err.message or vim.inspect(err))))
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          M._update_system_block(buf, "Session failed: " .. (err and err.message or "unknown"))
        end
      end)
      return
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local resumed = sid and sid ~= "" and new_sid == sid
      log.info("_ensure_session: " .. (resumed and "resumed" or "created") .. " sid=" .. new_sid)
      M._set_frontmatter_field(buf, "session", new_sid)
      M._sessions[buf] = new_sid
      M._subscribe_session(buf, root, new_sid)
      M._restore_mode(buf, root, new_sid, result)
      M._update_system_block(buf, resumed and "Session reconnected" or "Session ready (ACP)")
      M._process_queue(buf)
    end)
  end, sess_opts)
end

function M.open(file_path, opts)
  opts = opts or {}
  local existing = vim.fn.bufnr(file_path)
  if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
    if opts.split then
      vim.cmd("vsplit")
    end
    vim.api.nvim_set_current_buf(existing)
    return existing
  end
  local cmd = opts.split and "vsplit" or "edit!"
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(file_path))
  local buf = vim.api.nvim_get_current_buf()
  M.attach(buf)
  M._ensure_session(buf)
  return buf
end

M._migrated = {}

local function migrate_unicode(buf)
  if M._migrated[buf] then return end
  M._migrated[buf] = true
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = false
  for i, line in ipairs(lines) do
    local new = line
    new = new:gsub("├─ ", "- ")
    new = new:gsub("│  ✓", "  done:")
    new = new:gsub("│  ✗ error", "  error:")
    new = new:gsub("│  ● running", "  running")
    new = new:gsub("╶", "~")
    new = new:gsub("▎ ", "")
    if new ~= line then
      lines[i] = new
      changed = true
    end
  end
  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

M._keymaps_set = {}

function M._setup_keymaps(buf)
  if M._keymaps_set[buf] then return end
  M._keymaps_set[buf] = true

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = desc })
  end

  map("n", "]]", function()
    M._jump_turn(buf, 1)
  end)
  map("n", "[[", function()
    M._jump_turn(buf, -1)
  end)
  map("n", "G", function()
    M._auto_scroll[buf] = true
    local lc = vim.api.nvim_buf_line_count(buf)
    pcall(vim.api.nvim_win_set_cursor, 0, { lc, 0 })
  end)
  map("n", "<leader><Tab>", "za")
  map("n", "<CR>", function()
    local text = M._get_you_block_at_cursor(buf)
    if not text or text == "" then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local row = vim.api.nvim_win_get_cursor(0)[1]
      for i = row, 1, -1 do
        if lines[i] and lines[i]:match("^@You%s*$") then
          local win = vim.fn.bufwinid(buf)
          if win ~= -1 then
            vim.api.nvim_win_set_cursor(win, { i + 1, 0 })
            vim.cmd("startinsert!")
          end
          return
        end
        if lines[i] and (lines[i]:match("^@%w+%s*$") or lines[i]:match("^%-%-%-$")) then
          break
        end
      end
      return
    end
    M._migrate_you_block(buf)
    if M._streaming[buf] then
      if not M._queue[buf] then M._queue[buf] = {} end
      table.insert(M._queue[buf], text)
    else
      M.send(buf, text)
    end
  end)
  map("i", "<C-CR>", function()
    vim.cmd("stopinsert")
    local text = M._get_you_block_at_cursor(buf)
    if not text or text == "" then return end
    M._migrate_you_block(buf)
    if M._streaming[buf] then
      if not M._queue[buf] then M._queue[buf] = {} end
      table.insert(M._queue[buf], text)
    else
      M.send(buf, text)
    end
  end)
  map("n", "gi", function()
    M.quick_input(buf)
  end)
  map("n", "gp", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("^### Plan") then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        return
      end
    end
    vim.notify("[djinni] No plan section", vim.log.levels.INFO)
  end)
  map("n", "<C-c>", function()
    M.interrupt(buf)
    vim.notify("[djinni] Interrupted", vim.log.levels.WARN)
  end)
  map("n", "gP", function()
    M.select_provider(buf)
  end)
  map("n", "<S-Tab>", function()
    M.pick_mode(buf)
  end)
  map("n", "<C-m>", function()
    M.pick_model(buf)
  end)
  map("n", "<C-r>", function()
    M.restart_session(buf)
  end)
  map("n", "gW", function()
    local branch = read_frontmatter_field(buf, "worktree")
    require("djinni.integrations.worktrunk").pick_op(branch and branch ~= "" and branch or nil)
  end)
  map("n", "<C-w>", function()
    local worktrunk = require("djinni.integrations.worktrunk")
    if not worktrunk.available() then
      vim.notify("[djinni] worktrunk not available", vim.log.levels.WARN)
      return
    end
    local path = vim.api.nvim_buf_get_name(buf)
    local title = vim.fn.fnamemodify(path, ":t:r")
    local branch = title:lower():gsub("[^%w%-]", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
    if branch == "" then branch = "task" end
    vim.ui.select({ "Current branch", "Default branch", "Stacked (from current HEAD)" }, { prompt = "Worktree base:" }, function(choice)
      if not choice then return end
      local opts = (choice:match("Current") or choice:match("Stacked")) and { base = "@" } or {}
      worktrunk.create_for_task(branch, opts, function(path)
        vim.schedule(function()
          if not path then
            vim.notify("[djinni] worktree failed", vim.log.levels.ERROR)
            return
          end
          M._set_frontmatter_field(buf, "worktree", branch)
          vim.api.nvim_buf_call(buf, function() vim.cmd("silent! write") end)
          vim.notify("[djinni] worktree: " .. branch, vim.log.levels.INFO)
        end)
      end)
    end)
  end)
  map("n", "D", function()
    local line = vim.api.nvim_get_current_line()
    local file = line:match("^%- .+%((.-)%)") or line:match("^  .* %((.-)%)")
    if file and file ~= "" then
      file = file:match("^[^,=]+") or file
      if vim.fn.filereadable(file) == 1 then
        vim.cmd("DeltaView " .. vim.fn.fnameescape(file))
      end
    end
  end)
  map("n", "p", function()
    local reg = vim.fn.getreg(vim.v.register)
    local regtype = vim.fn.getregtype(vim.v.register)
    get_clipboard_image(function(img)
      if not img then
        vim.fn.setreg("z", reg, regtype)
        vim.cmd('normal! "zp')
        return
      end
      M._paste_image(buf, img)
    end)
  end)
  map("i", "<C-v>", function()
    get_clipboard_image(function(img)
      if not img then
        local keys = vim.api.nvim_replace_termcodes("<C-r>+", true, false, true)
        vim.api.nvim_feedkeys(keys, "n", false)
        return
      end
      M._paste_image(buf, img)
    end)
  end)
  map("n", "<localleader>a", function()
    local ok, Snacks = pcall(require, "snacks")
    if not ok then
      vim.notify("[djinni] snacks.nvim required for file picker", vim.log.levels.ERROR)
      return
    end
    local root = M.get_project_root(buf) or vim.fn.getcwd()
    Snacks.picker.files({
      cwd = root,
      confirm = function(picker, item)
        picker:close()
        if not item then return end
        local filepath = item._path or (root .. "/" .. item.file)
        local ext = (filepath:match("%.(%w+)$") or ""):lower()
        if IMAGE_EXTENSIONS[ext] then
          file_to_image(filepath, function(img)
            if not img then
              vim.notify("[djinni] Failed to read image: " .. filepath, vim.log.levels.ERROR)
              return
            end
            M._paste_image(buf, img)
          end)
        else
          local rel = vim.fn.fnamemodify(filepath, ":.")
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          local insert_row = #lines
          for i = #lines, 1, -1 do
            if lines[i] and lines[i]:match("^@You%s*$") then
              for j = i + 1, #lines do
                if lines[j] == "" or lines[j]:match("^%-%-%-$") or lines[j]:match("^@%w+") then
                  insert_row = j
                  break
                end
                insert_row = j + 1
              end
              break
            end
          end
          local ref = "@./" .. rel
          vim.api.nvim_buf_set_lines(buf, insert_row - 1, insert_row - 1, false, { ref })
          vim.notify("[djinni] File attached: " .. rel, vim.log.levels.INFO)
        end
      end,
    })
  end)
  map("n", "<localleader>t", function()
    require("djinni.nowork.transcript").open(buf)
  end, "Open transcript loclist")
  map("n", "gA", function()
    local imgs = M._pending_images[buf]
    if not imgs or #imgs == 0 then
      vim.notify("[djinni] No pending attachments", vim.log.levels.INFO)
      return
    end
    local items = {}
    for i, img in ipairs(imgs) do
      local size = math.floor(#img.data * 3 / 4 / 1024)
      table.insert(items, i .. ". " .. img.media_type .. " (" .. size .. " KB)")
    end
    vim.ui.select(items, { prompt = "Remove attachment:" }, function(_, idx)
      if not idx then return end
      table.remove(imgs, idx)
      if #imgs == 0 then M._pending_images[buf] = nil end
      M._update_attach_indicator(buf)
      vim.notify("[djinni] Attachment removed", vim.log.levels.INFO)
    end)
  end)
  map("n", "dS", function()
    M._delete_block(buf)
  end)
  map("n", "<C-q>", function()
    local path = vim.api.nvim_buf_get_name(buf)
    local name = vim.fn.fnamemodify(path, ":t")
    vim.ui.select(
      { "Archive " .. name, "Cancel" },
      { prompt = "Archive this chat file?" },
      function(choice)
        if not choice or choice == "Cancel" then return end
        if M._streaming[buf] and M._stream_cleanup[buf] then
          pcall(M._stream_cleanup[buf], true)
        end
        M._invalidate_session(buf)
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        if path and path ~= "" then
          M.archive_chat_file(path)
        end
      end
    )
  end)
  map("n", "e", function()
    M._edit_block(buf)
  end)
  map("n", "r", function()
    M._retry_block(buf)
  end)
  map("n", "gx", function()
    M._rerun_tool(buf)
  end)
  map("n", "s", function()
    M._permission_action(buf, "select")
  end)
  map("n", "ya", function()
    M._permission_action(buf, "allow")
  end)
  map("n", "yn", function()
    M._permission_action(buf, "deny")
  end)
  map("n", "yA", function()
    M._permission_action(buf, "always")
  end)
  map("n", "?", function()
    M.show_help()
  end)
  map("n", "L", function()
    if M._pending_permission and M._pending_permission[buf] then
      M._permission_action(buf, "allow")
    else
      log.show()
    end
  end)
  map("n", "gt", function()
    M._open_tool_log(buf)
  end)
  local function smart_insert(buf)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local needs_you = false
    for i = row, 1, -1 do
      local l = lines[i]
      if l and l:match("^@Djinni%s*$") then needs_you = true; break end
      if l and l:match("^@System%s*$") then needs_you = true; break end
      if l and l:match("^@You%s*$") then break end
    end
    if needs_you then
      local lc = vim.api.nvim_buf_line_count(buf)
      local last = lines[lc] or ""
      local has_border = last:match("^%-%-%-$")
      if not has_border then
        for i = lc, math.max(1, lc - 2), -1 do
          if lines[i] and lines[i]:match("^%-%-%-$") then has_border = true; break end
          if lines[i] and lines[i] ~= "" then break end
        end
      end
      local new_lines
      if has_border then
        new_lines = { "", "@You", "", "", "---", "" }
      else
        new_lines = you_block()
      end
      vim.api.nvim_buf_set_lines(buf, lc, lc, false, new_lines)
      local you_offset = has_border and 2 or 4
      vim.api.nvim_win_set_cursor(0, { lc + you_offset + 1, 0 })
      vim.cmd("startinsert")
    else
      return false
    end
    return true
  end

  map("n", "i", function()
    if not smart_insert(buf) then
      vim.cmd("startinsert")
    end
  end)
  map("n", "a", function()
    if not smart_insert(buf) then
      vim.cmd("startinsert!")
    end
  end)
  map("n", "o", function()
    if not smart_insert(buf) then
      vim.cmd("normal! o")
      vim.cmd("startinsert")
    end
  end)
  map("n", "I", function()
    input.jump_to_input(buf)
  end)
end

function M.attach(buf)
  if M._attached[buf] then return end
  M._attached[buf] = true
  if vim.bo[buf].filetype ~= "nowork-chat" then
    vim.bo[buf].filetype = "nowork-chat"
  end
  vim.bo[buf].modifiable = true
  vim.bo[buf].buftype = ""
  vim.bo[buf].fileencoding = "utf-8"
  vim.bo[buf].textwidth = 120
  vim.bo[buf].omnifunc = "v:lua.require'djinni.nowork.commands'.omnifunc"

  local line_count = vim.api.nvim_buf_line_count(buf)
  local large = line_count > LARGE_CHAT_THRESHOLD

  if large then
    vim.treesitter.stop(buf)
  end

  local fm_lines = vim.api.nvim_buf_get_lines(buf, 0, math.min(20, line_count), false)
  local parsed = blocks.parse(fm_lines)
  local fm = blocks.get_frontmatter(parsed)
  if fm.plan and fm.plan ~= "" then
    M._plan_path[buf] = fm.plan
  end
  if fm.mode and fm.mode ~= "" then
    M._current_mode[buf] = fm.mode
  end
  if fm.type == "task" then
    local task = require("djinni.nowork.task")
    if not task.is_task_buf(buf) then
      task._task_bufs[buf] = true
      task.setup_keymaps(buf)
      vim.api.nvim_create_autocmd("BufEnter", {
        buffer = buf,
        callback = function()
          if vim.api.nvim_buf_is_valid(buf) then
            task.update_tasks_section(buf)
          end
        end,
      })
      vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = buf,
        once = true,
        callback = function()
          task._task_bufs[buf] = nil
          task._task_lines[buf] = nil
          task._line_to_file[buf] = nil
        end,
      })
      task.update_tasks_section(buf)
    end
  end

  if not large then
    migrate_unicode(buf)
    M._unwrap_paragraphs(buf)
  end

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 and M._win_configured[win] ~= buf then
    M._win_configured[win] = buf
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].statusline = "%{%v:lua._djinni_chat_statusline()%} %f %m"
    vim.wo[win].conceallevel = 2
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local w = vim.fn.bufwinid(buf)
      if w == -1 then return end
      if not large then
        pcall(_win_fold_chat, w, buf)
      end
    end)
  end

  M._setup_keymaps(buf)

  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      M._keymaps_set[buf] = nil
      M._setup_keymaps(buf)
      local root = M.get_project_root(buf)
      if root and root ~= "" then
        pcall(vim.cmd, "lcd " .. vim.fn.fnameescape(root))
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = buf,
    callback = function()
      M._on_save(buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    once = true,
    callback = function()
      local root = M.get_project_root(buf)
      local sid = M.get_session_id(buf) or M._sessions[buf]
      if root then
        if sid and sid ~= "" then
          session.unsubscribe_session(root, sid, get_provider(buf))
          session.close_task_session(root, sid, get_provider(buf))
        end
      end
      M._streaming[buf] = nil
      M._stream_cleanup[buf] = nil
      M._sessions[buf] = nil
      M._usage[buf] = nil
      M._queue[buf] = nil
      M._modes[buf] = nil
      M._current_mode[buf] = nil
      M._plan_path[buf] = nil
      M._continuation_count[buf] = nil
      M._last_tool_failed[buf] = nil
      M._last_perm_tool[buf] = nil
      M._attached[buf] = nil
      M._migrated[buf] = nil
      M._keymaps_set[buf] = nil
      M._hidden_pending[buf] = nil
      M._pending_images[buf] = nil
      M._stream_gen[buf] = nil
      M._send_retries[buf] = nil
      M._pending_text[buf] = nil
      M._assistant_output_seen[buf] = nil
      M._stream_client[buf] = nil
      M._scroll_pending[buf] = nil
      M._active_tool_count[buf] = nil
      M._last_event_time[buf] = nil
      M._events_received[buf] = nil
      M._plan_lines[buf] = nil
      M._last_tool_title[buf] = nil
      M._tool_log[buf] = nil
      M._cleanup_deferred[buf] = nil
      M._think_fold_start[buf] = nil
      M._config_options[buf] = nil
      M._available_commands[buf] = nil
      M._interrupt_pending[buf] = nil
      M._creating_session[buf] = nil
      M._timer_scheduled[buf] = nil
      M._tool_section_start[buf] = nil
      M._auto_scroll[buf] = nil
      M._djinni_marker_line[buf] = nil
      M._fm_end_cache[buf] = nil
      M._append_batch[buf] = nil
      M._append_scheduled[buf] = nil
      M._stream_tail_row[buf] = nil
      M._stream_tail_text[buf] = nil
      M._first_msg_sent[buf] = nil
      M._last_interrupt_time[buf] = nil
      for w, b in pairs(M._win_configured) do
        if b == buf then M._win_configured[w] = nil end
      end
      local ok, panel = pcall(require, "djinni.nowork.panel")
      if ok and panel.render then panel.render() end
    end,
  })
end

local function _is_tool_line(l)
  return l:match("^%[%*%]") or l:match("^%[%+%]") or l:match("^%[!%]")
end

function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("^%*%*Thinking") or _is_tool_line(line) then
    return ">1"
  end
  if line:match("^@%w") or line:match("^%-%-%-$") or line == "" then
    return "0"
  end
  local prev = vim.fn.getline(lnum - 1)
  if prev:match("^%*%*Thinking") or _is_tool_line(prev) then
    return "1"
  end
  return "="
end

function M.foldtext()
  local start = vim.v.foldstart
  local end_line = vim.v.foldend
  local tool_count = 0
  local names = {}
  for i = start, end_line do
    local l = vim.fn.getline(i)
    local name = l:match("^%[.%] (.+)")
    if name then
      tool_count = tool_count + 1
      if #names < 3 then names[#names + 1] = name end
    end
  end
  local lines = end_line - start + 1
  if tool_count > 0 then
    if tool_count <= 3 then
      return table.concat(names, ", ") .. " (" .. lines .. " lines)"
    end
    return names[1] .. " + " .. (tool_count - 1) .. " more (" .. lines .. " lines)"
  end
  local first = vim.fn.getline(start)
  if first:match("^%*%*Thinking") then
    return "Thinking... (" .. lines .. " lines)"
  end
  return first .. " (" .. lines .. " lines)"
end

function M._migrate_you_block(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local you_start = nil
  for i = cursor_row, 1, -1 do
    if lines[i] and lines[i]:match("^@You%s*$") then
      you_start = i
      break
    end
    if lines[i] and lines[i]:match("^@%w+%s*$") and not lines[i]:match("^@You") then return end
    if lines[i] and lines[i]:match("^%-%-%-$") and i > 2 then return end
  end
  if not you_start then return end
  local you_end = #lines
  for i = you_start + 1, #lines do
    if lines[i]:match("^%-%-%-$") or (lines[i]:match("^@%w+%s*$") and not lines[i]:match("^@You")) then
      you_end = i - 1
      break
    end
  end
  local after_you = false
  for i = you_end + 1, #lines do
    if lines[i]:match("^@%w+%s*$") then
      after_you = true
      break
    end
  end
  if not after_you then return end

  local del_from = you_end + 1
  while del_from <= #lines and lines[del_from] == "" do
    del_from = del_from + 1
  end
  if del_from <= #lines and lines[del_from]:match("^%-%-%-$") then
    vim.api.nvim_buf_set_lines(buf, del_from - 1, #lines, false, {})
  else
    vim.api.nvim_buf_set_lines(buf, you_end, #lines, false, {})
  end

  M._invalidate_session(buf)
  M._creating_session[buf] = nil
  M._first_msg_sent = M._first_msg_sent or {}
  M._first_msg_sent[buf] = nil
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_set_cursor(win, { math.min(you_end, vim.api.nvim_buf_line_count(buf)), 0 })
  end
  return true
end

function M._get_you_block_at_cursor(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local block_start = nil
  for i = row, 1, -1 do
    if lines[i] and lines[i]:match("^@You%s*$") then
      block_start = i
      break
    end
    if lines[i] and lines[i]:match("^@%w+%s*$") and not lines[i]:match("^@You") then
      return nil
    end
    if lines[i] and lines[i]:match("^%-%-%-$") and i > 2 then
      return nil
    end
  end

  if not block_start then return nil end

  local block_end = #lines
  for i = block_start + 1, #lines do
    if lines[i]:match("^%-%-%-$") or lines[i]:match("^@%w+%s*$") then
      block_end = i - 1
      break
    end
  end

  local text_lines = {}
  for i = block_start + 1, block_end do
    table.insert(text_lines, lines[i])
  end
  local text = table.concat(text_lines, "\n")
  return text:match("^%s*(.-)%s*$")
end

function M.quick_input_text(buf, text)
  if not text or text == "" then return end
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local you_line = nil
    for i = #lines, 1, -1 do
      local l = lines[i]
      if l:match("^@Djinni") or l:match("^@System") then break end
      if l:match("^@You%s*$") then you_line = i; break end
    end
    if you_line then
      local empty = true
      for i = you_line + 1, #lines do
        if lines[i]:match("^%-%-%-$") then break end
        if lines[i]:match("%S") then empty = false; break end
      end
      if empty then
        local text_lines = vim.split(text, "\n", { plain = true })
        local new = { "@You" }
        vim.list_extend(new, text_lines)
        vim.api.nvim_buf_set_lines(buf, you_line - 1, you_line, false, new)
        if M._streaming[buf] then
          if not M._queue[buf] then M._queue[buf] = {} end
          table.insert(M._queue[buf], text)
        else
          M.send(buf, text)
        end
        return
      end
    end
    local text_lines = vim.split(text, "\n", { plain = true })
    local you_block = { "", "---", "", "@You" }
    vim.list_extend(you_block, text_lines)
    local line_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, you_block)
    if M._streaming[buf] then
      if not M._queue[buf] then M._queue[buf] = {} end
      table.insert(M._queue[buf], text)
    else
      M.send(buf, text)
    end
  end)
end

function M.quick_input(buf)
  vim.ui.input({ prompt = "Message: " }, function(text)
    M.quick_input_text(buf, text)
  end)
end

function M.send(buf, text, images)
  if not text or text == "" then
    return
  end

  if not images then
    images = M._pending_images[buf]
    M._pending_images[buf] = nil
    M._update_attach_indicator(buf)
  end
  M._waiting_input[buf] = nil

  if text ~= "yes, continue" and not text:match("^The previous tool") then
    M._continuation_count[buf] = 0
    M._last_tool_failed[buf] = false
    M._send_retries[buf] = 0
  end

  if text:match("^%s*/") then
    local handled = commands.execute(buf, text)
    if handled then return end
  end

  local root = M.get_project_root(buf)
  if not root then
    return
  end

  local source_buf = M._last_code_buf
  if source_buf and (not vim.api.nvim_buf_is_valid(source_buf) or vim.api.nvim_buf_get_name(source_buf) == "") then
    source_buf = nil
  end
  if not source_buf then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local wb = vim.api.nvim_win_get_buf(win)
      if vim.bo[wb].filetype ~= "nowork-chat" and vim.bo[wb].filetype ~= "nowork-panel"
        and vim.bo[wb].buftype == "" and vim.api.nvim_buf_get_name(wb) ~= "" then
        source_buf = wb
        break
      end
    end
  end
  if source_buf then
    local resolved = M._resolve_refs(text, source_buf)
    if resolved ~= text then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, line in ipairs(lines) do
        local new_line = M._resolve_refs(line, source_buf)
        if new_line ~= line then
          vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { new_line })
        end
      end
    end
    text = resolved
  end

  local sid = M.get_session_id(buf) or M._sessions[buf]
  log.info("send: buf=" .. tostring(buf) .. " sid=" .. tostring(sid) .. " creating=" .. tostring(M._creating_session[buf]) .. " len=" .. tostring(#text))
  if M._streaming[buf] then
    if not M._queue[buf] then M._queue[buf] = {} end
    table.insert(M._queue[buf], { text = text, images = images })
    log.info("send: queuing message (streaming)")
    return
  end
  if not sid or sid == "" then
    if not M._queue[buf] then M._queue[buf] = {} end
    table.insert(M._queue[buf], { text = text, images = images })
    log.info("send: queuing message (no session)")
    if not M._creating_session[buf] then
      M._ensure_session(buf)
    end
    return
  end

  M._stream_gen[buf] = (M._stream_gen[buf] or 0) + 1
  local gen = M._stream_gen[buf]
  M._streaming[buf] = true
  M._start_streaming(buf)
  local msg = text
  if not M._first_msg_sent or not M._first_msg_sent[buf] then
    M._first_msg_sent = M._first_msg_sent or {}
    M._first_msg_sent[buf] = true
    msg = inject_lessons(buf, root, inject_skills(buf, root, build_history_context(buf, text)))
  end
  session.send_message(root, sid, msg, function(err, prompt_result)
    log.info("session/prompt callback: " .. (err and ("err=" .. vim.inspect(err)) or "ok"))
    if prompt_result then
      log.info("prompt_result: stopReason=" .. tostring(prompt_result.stopReason))
      if prompt_result.usage then log.info("usage: " .. vim.inspect(prompt_result.usage)) end
    end
    local function retry_send(reason)
      M._send_retries[buf] = (M._send_retries[buf] or 0) + 1
      if M._send_retries[buf] > M._max_send_retries then
        log.warn("max send retries (" .. M._max_send_retries .. ") reached: " .. reason)
        M._update_system_block(buf, "Failed after " .. M._max_send_retries .. " retries: " .. reason .. ". Send a message to try again.")
        M._send_retries[buf] = 0
        return
      end
      local delay = 1000 * math.pow(2, (M._send_retries[buf] or 1) - 1)
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        M.send(buf, text)
      end, delay)
    end

    local function lightweight_cleanup()
      M._streaming[buf] = nil
      M._stream_cleanup[buf] = nil
      M._cleanup_deferred[buf] = nil
      M._interrupt_pending[buf] = nil
      M._stream_client[buf] = nil
      M._flush_pending(buf)
      M._schedule_panel_render()
    end

    local function invalidate_session()
      M._invalidate_session(buf)
    end

    if err and err.data and err.data.details == "Session not found" then
      vim.schedule(function()
        if M._stream_gen[buf] ~= gen then return end
        if not vim.api.nvim_buf_is_valid(buf) then return end
        lightweight_cleanup()
        M._cleanup_empty_djinni(buf)
        invalidate_session()
        retry_send("Session not found")
      end)
    elseif err then
      vim.schedule(function()
        if M._stream_gen[buf] ~= gen then return end
        if not vim.api.nvim_buf_is_valid(buf) then return end
        lightweight_cleanup()
        M._cleanup_empty_djinni(buf)
        local msg = err.message or (err.data and err.data.details) or vim.inspect(err)
        M._update_system_block(buf, "Error: " .. msg .. " — reconnecting...")
        invalidate_session()
        retry_send(msg)
      end)
    else
      vim.schedule(function()
        if M._stream_gen[buf] ~= gen then return end
        if not vim.api.nvim_buf_is_valid(buf) then return end
        M._accumulate_usage(buf, prompt_result)
        local tok = prompt_result and (prompt_result.tokenUsage or prompt_result.usage) or {}
        local total = (tok.inputTokens or 0) + (tok.outputTokens or 0)
        if total == 0 then
          local sr = prompt_result and prompt_result.stopReason
          if sr == "end_turn" and M._assistant_output_seen[buf] then
            log.info("0-token end_turn — agent waiting for input, keeping session")
            M._waiting_input[buf] = true
            M._send_retries[buf] = 0
            if M._stream_cleanup[buf] then
              M._stream_cleanup[buf]()
            end
            return
          end
          log.warn("0-token response, stopReason=" .. tostring(sr) .. " — invalidating session")
          lightweight_cleanup()
          M._cleanup_empty_djinni(buf)
          invalidate_session()
          M._update_system_block(buf, "Empty response — reconnecting...")
          retry_send("empty response")
          return
        end
        M._send_retries[buf] = 0
        if prompt_result and prompt_result.stopReason == "end_turn" then
          M._waiting_input[buf] = true
        end
        if M._stream_cleanup[buf] then
          M._stream_cleanup[buf]()
        end
        M._maybe_auto_compact(buf)
      end)
    end
  end, images, get_provider(buf))
end

M._last_interrupt_time = {}
local FORCE_KILL_WINDOW = 2

function M.interrupt(buf)
  local now = vim.uv.hrtime() / 1e9
  local last = M._last_interrupt_time[buf]

  if last and (now - last) < FORCE_KILL_WINDOW then
    local root = M.get_project_root(buf)
    local force_sid = M.get_session_id(buf) or M._sessions[buf]
    if root and force_sid and force_sid ~= "" then
      session.close_task_session(root, force_sid, get_provider(buf))
      vim.notify("[djinni] Force-killed process", vim.log.levels.WARN)
    end
    if M._stream_cleanup[buf] then
      M._stream_cleanup[buf](true)
    else
      M._streaming[buf] = nil
      M._schedule_panel_render()
      M._cleanup_empty_djinni(buf)
    end
    M._last_interrupt_time[buf] = nil
    M._sessions[buf] = nil
    M._set_frontmatter_field(buf, "session", "")
    return
  end

  M._last_interrupt_time[buf] = now

  local root = M.get_project_root(buf)
  local sid = M.get_session_id(buf) or M._sessions[buf]
  if root and sid then
    session.interrupt(root, sid, get_provider(buf))
  elseif root then
    M._interrupt_pending[buf] = true
    M._sessions[buf] = nil
    M._set_frontmatter_field(buf, "session", "")
  end
  M._stream_gen[buf] = (M._stream_gen[buf] or 0) + 1
  if M._pending_permission and M._pending_permission[buf] then
    local perm = M._pending_permission[buf]
    hide_snacks_notif(perm.notif_id)
    local reject_id = nil
    if perm.options then
      for _, opt in ipairs(perm.options) do
        if opt.kind == "reject_once" then reject_id = opt.id; break end
      end
    end
    if reject_id and perm.respond then
      pcall(perm.respond, { outcome = { outcome = "selected", optionId = reject_id } })
    end
    M._pending_permission[buf] = nil
  end
  M._cleanup_deferred[buf] = nil
  M._waiting_input[buf] = nil
  M._last_tool_failed[buf] = false
  M._last_perm_tool[buf] = nil
  M._continuation_count[buf] = 0
  M._queue[buf] = nil
  if M._stream_cleanup[buf] then
    M._stream_cleanup[buf](true)
  else
    M._streaming[buf] = nil
    M._schedule_panel_render()
    M._cleanup_empty_djinni(buf)
  end
end

function M.interrupt_all()
  local count = 0
  for buf, _ in pairs(M._streaming) do
    if vim.api.nvim_buf_is_valid(buf) then
      M.interrupt(buf)
      count = count + 1
    end
  end
  if count > 0 then
    vim.notify("[djinni] Interrupted " .. count .. " session(s)", vim.log.levels.WARN)
  else
    local cur = vim.api.nvim_get_current_buf()
    M.interrupt(cur)
    vim.notify("[djinni] Interrupted", vim.log.levels.WARN)
  end
end

function M._cleanup_empty_djinni(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if _is_large_chat(buf) then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = #lines, 1, -1 do
    if lines[i] and lines[i]:match("^@Djinni%s*$") then
      local has_content = false
      for j = i + 1, #lines do
        local l = lines[j]
        if l:match("^@%w+%s*$") or l:match("^%-%-%-$") then break end
        if l:match("%S") then has_content = true; break end
      end
      if not has_content then
        local del_from = i
        local del_to = i
        while del_from > 1 and (lines[del_from - 1] == "" or lines[del_from - 1]:match("^%-%-%-$")) do
          del_from = del_from - 1
        end
        while del_to < #lines and lines[del_to + 1] == "" do
          del_to = del_to + 1
        end
        pcall(vim.api.nvim_buf_set_lines, buf, del_from - 1, del_to, false, {})
        return
      end
    end
  end
end

function M._flush_pending(buf)
  local pt = M._pending_text[buf]
  if not pt or #pt == 0 then return end
  M._text_dirty[buf] = nil
  local pending = table.concat(pt)
  M._pending_text[buf] = {}
  if pending == "" then return end
  if vim.fn.bufwinid(buf) == -1 then
    M._hidden_pending[buf] = M._hidden_pending[buf] or {}
    M._hidden_pending[buf][#M._hidden_pending[buf] + 1] = pending
    return
  end
  local hp = M._hidden_pending[buf]
  if hp then
    M._hidden_pending[buf] = nil
    hp[#hp + 1] = pending
    pending = table.concat(hp)
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lessons_mod = require("djinni.nowork.lessons")
  local extracted, cleaned = lessons_mod.extract_from_text(pending)
  if #extracted > 0 then
    pending = cleaned
    local root = M.get_project_root(buf)
    if root then
      local source = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
      for _, text in ipairs(extracted) do
        lessons_mod.add(root, text, source)
        vim.notify("[djinni] Lesson learned: " .. text, vim.log.levels.INFO)
      end
    end
    if pending:match("^%s*$") then return end
  end
  local MAX_CHUNK = 4096
  if #pending > MAX_CHUNK then
    local cut = pending:sub(1, MAX_CHUNK)
    local nl = cut:find("\n[^\n]*$")
    if nl then
      M._apply_stream_chunk(buf, pending:sub(1, nl - 1))
      local leftover = pending:sub(nl)
      local pt2 = M._pending_text[buf]
      if not pt2 then pt2 = {}; M._pending_text[buf] = pt2 end
      table.insert(pt2, 1, leftover)
    else
      M._apply_stream_chunk(buf, cut)
      local leftover = pending:sub(MAX_CHUNK + 1)
      local pt2 = M._pending_text[buf]
      if not pt2 then pt2 = {}; M._pending_text[buf] = pt2 end
      table.insert(pt2, 1, leftover)
    end
    return
  end
  M._apply_stream_chunk(buf, pending)
end

function M._stop_global_timer()
  if M._global_timer and not M._global_timer:is_closing() then
    M._global_timer:stop()
    M._global_timer:close()
  end
  M._global_timer = nil
  M._global_timer_scheduled = false
end

M._watchdog_tick = 0
M._checktime_tick = 0
M._text_dirty = {}
M._flush_robin = 0

function M._start_global_timer()
  if M._global_timer then return end
  local timer = vim.uv.new_timer()
  M._global_timer = timer
  timer:start(100, 500, function()
    M._spinner_frame = M._spinner_frame + 1
    if M._global_timer_scheduled then return end
    M._global_timer_scheduled = true
    vim.schedule(function()
      M._global_timer_scheduled = false
      M._watchdog_tick = M._watchdog_tick + 1
      local do_watchdog = M._watchdog_tick % 6 == 0

      local any_streaming = false
      local stream_bufs = {}
      for buf, _ in pairs(M._streaming) do
        if not vim.api.nvim_buf_is_valid(buf) then
          M._streaming[buf] = nil
          if M._stream_cleanup[buf] then
            M._stream_cleanup[buf](true)
          end
        else
          any_streaming = true
          stream_bufs[#stream_bufs + 1] = buf
        end
      end

      local MAX_FLUSH = 2
      local n = #stream_bufs
      local flushed = 0
      for i = 1, n do
        local idx = ((M._flush_robin + i - 1) % n) + 1
        local buf = stream_bufs[idx]
        if flushed < MAX_FLUSH and M._text_dirty[buf] and vim.fn.bufwinid(buf) ~= -1 then
          M._flush_pending(buf)
          flushed = flushed + 1
        end

        if do_watchdog then
          if M._pending_permission and M._pending_permission[buf] then
            M._last_event_time[buf] = vim.uv.now()
          else
            local client = M._stream_client[buf]
            local ok_alive, alive = pcall(function() return client and client:is_alive() end)
            local dead = not ok_alive or not alive
            local has_active_tool = (M._active_tool_count[buf] or 0) > 0
            local elapsed = vim.uv.now() - (M._last_event_time[buf] or vim.uv.now())
            local no_events = not M._events_received[buf] and elapsed > 180000
            local tool_stuck = has_active_tool and elapsed > 300000
            local stale = not dead and not has_active_tool and M._events_received[buf] and elapsed > 900000
            if dead or no_events or tool_stuck or stale then
              local exit_info = dead and client and client.exit_code and " (exit " .. tostring(client.exit_code) .. ")" or ""
              local reason = dead and ("Process died" .. exit_info) or no_events and "No events received for 180s" or stale and "No events for 900s" or "Tool stuck for 300s"
              log.warn("watchdog triggered: " .. reason)
              local pt = M._pending_text[buf]
              if not pt then pt = {}; M._pending_text[buf] = pt end
              pt[#pt + 1] = "\n\n**" .. reason .. "**\n"
              M._stream_gen[buf] = (M._stream_gen[buf] or 0) + 1
              M._invalidate_session(buf)
              M._last_tool_failed[buf] = false
              M._continuation_count[buf] = 0
              if M._stream_cleanup[buf] then
                M._stream_cleanup[buf](true)
              end
            end
          end
        end
      end
      M._flush_robin = M._flush_robin + MAX_FLUSH

      if M._checktime_dirty then
        M._checktime_tick = M._checktime_tick + 1
        if M._checktime_tick >= 4 then
          M._checktime_dirty = false
          M._checktime_tick = 0
          vim.cmd("silent! checktime")
        end
      end

      for buf, _ in pairs(M._scroll_pending) do
        M._scroll_pending[buf] = nil
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then
          local line_count = vim.api.nvim_buf_line_count(buf)
          local ok, pos = pcall(vim.api.nvim_win_get_cursor, win)
          if ok and (line_count - pos[1]) > 3 then
            M._auto_scroll[buf] = false
          end
          if M._auto_scroll[buf] ~= false then
            pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })
          end
        end
      end

      if not any_streaming then
        M._stop_global_timer()
      else
        _redraw_status()
      end
    end)
  end)
end

function M._flush_append_batch(buf)
  local batch = M._append_batch[buf]
  M._append_batch[buf] = nil
  M._append_scheduled[buf] = nil
  if not batch or #batch == 0 then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local lc = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, lc, lc, false, batch)
  _set_stream_tail(buf, lc + #batch, batch[#batch])
end

local function _enqueue_append(buf, lines_to_add)
  if vim.fn.bufwinid(buf) == -1 then
    M._hidden_pending[buf] = M._hidden_pending[buf] or {}
    for _, line in ipairs(lines_to_add) do
      M._hidden_pending[buf][#M._hidden_pending[buf] + 1] = "\n" .. line
    end
    return
  end
  local batch = M._append_batch[buf]
  if not batch then
    batch = {}
    M._append_batch[buf] = batch
  end
  for _, l in ipairs(lines_to_add) do
    batch[#batch + 1] = l
  end
  if not M._append_scheduled[buf] then
    M._append_scheduled[buf] = true
    vim.schedule(function()
      M._flush_append_batch(buf)
    end)
  end
end

function M._append_line(buf, line)
  local parts = {}
  if line:find("\n") then
    for part in (line .. "\n"):gmatch("([^\n]*)\n") do
      parts[#parts + 1] = part
    end
  else
    parts[1] = line
  end
  _enqueue_append(buf, parts)
end

function M._append_lines(buf, lines_array)
  local flat = {}
  for _, line in ipairs(lines_array) do
    if line:find("\n") then
      for part in (line .. "\n"):gmatch("([^\n]*)\n") do
        flat[#flat + 1] = part
      end
    else
      flat[#flat + 1] = line
    end
  end
  _enqueue_append(buf, flat)
end

function M._on_session_update(buf, data)
  if not data then return end
  local root = M._cached_root[buf]
  if not root then
    root = M.get_project_root(buf)
    M._cached_root[buf] = root
  end
  local ok, err = pcall(function()
    local now = vim.uv.now()
    M._last_event_time[buf] = now
    M._events_received[buf] = true
    if root and (now - (M._last_activity_touch[buf] or 0)) > 5000 then
      M._last_activity_touch[buf] = now
      session.touch_activity(root, get_provider(buf))
    end

    local update = data.update or data
    local update_type = update.sessionUpdate

    local extra = ""
    if update_type == "tool_call" then
      extra = " title=" .. (update.title or "") .. " kind=" .. (update.kind or "")
    elseif update_type == "tool_call_update" then
      extra = " status=" .. (update.status or "") .. " title=" .. (update.title or "") .. " kind=" .. (update.kind or "")
    end
    log.dbg("event: " .. (update_type or "nil") .. extra)

    if update_type == "agent_message_chunk" or update_type == "agent_thought_chunk" then
      M._last_perm_tool[buf] = nil
      local text = update.content and update.content.text
      if text then
        if text:match("%S") then
          M._assistant_output_seen[buf] = true
        end
        local pt = M._pending_text[buf]
        if not pt then pt = {}; M._pending_text[buf] = pt end
        pt[#pt + 1] = text
        M._text_dirty[buf] = true
      end

    elseif update_type == "tool_call" then
      local kind = update.kind or ""
      local is_think = kind:lower() == "think" or kind:lower() == "thinking"
      M._flush_append_batch(buf)
      local line_count = vim.api.nvim_buf_line_count(buf)
      if is_think then
        M._think_fold_start[buf] = line_count + 1
        M._append_lines(buf, { "", "**Thinking...**" })
      else
        M._active_tool_count[buf] = (M._active_tool_count[buf] or 0) + 1
        M._schedule_panel_render()
        local title = update.title or kind
        if not M._tool_section_start[buf] then
          M._tool_section_start[buf] = line_count + 1
        end
        M._close_last_tool_fold(buf)
        M._append_lines(buf, { "[*] " .. title })
        M._last_tool_line[buf] = line_count + 1
        M._tool_log[buf] = M._tool_log[buf] or {}
        table.insert(M._tool_log[buf], { name = title, kind = kind, input = nil, output = nil, images = {} })
      end

    elseif update_type == "tool_call_update" then
      local kind = update.kind or ""
      local is_think = kind:lower() == "think" or kind:lower() == "thinking"
      local status = update.status or ""
      local title = update.title or ""
      if title ~= "" then M._last_tool_title[buf] = title end
      if status == "failed" then
        M._last_tool_failed[buf] = true
        if not is_think then
          M._active_tool_count[buf] = math.max(0, (M._active_tool_count[buf] or 1) - 1)
          M._schedule_panel_render()
        end
      elseif status == "completed" then
        M._last_tool_failed[buf] = false
        M._last_perm_tool[buf] = nil
        if not is_think then
          M._active_tool_count[buf] = math.max(0, (M._active_tool_count[buf] or 1) - 1)
          M._schedule_panel_render()
        end
        if M._FILE_MUTATING[kind] then
          M._checktime_dirty = true
        end
        if kind == "Agent" then
          local agent_title = title ~= "" and title or "subagent"
          vim.notify("[djinni] Agent done: " .. agent_title, vim.log.levels.INFO)
        end
      end

      if is_think then
        if status == "completed" then
          local text = nil
          if type(update.content) == "table" then
            if update.content.text then
              text = update.content.text
            elseif #update.content > 0 then
              local parts = {}
              for _, c in ipairs(update.content) do
                if c.content and c.content.text then
                  parts[#parts + 1] = c.content.text
                end
              end
              if #parts > 0 then text = table.concat(parts) end
            end
          end
          if text then
            local batch = {}
            for line in text:gmatch("([^\n]+)") do
              batch[#batch + 1] = "> " .. line
            end
            batch[#batch + 1] = ""
            M._append_lines(buf, batch)
          end
          M._think_fold_start[buf] = nil
        end
      else
        local text_parts = {}
        if type(update.content) == "table" then
          if update.content.text then
            text_parts[#text_parts + 1] = tostring(update.content.text)
          elseif #update.content > 0 then
            for _, c in ipairs(update.content) do
              if c.type ~= "diff" and c.type ~= "image" then
                local t = (c.content and c.content.text) or c.text
                if t then text_parts[#text_parts + 1] = tostring(t) end
              end
            end
          end
        end
        local text = #text_parts > 0 and table.concat(text_parts, "\n") or nil
        local output_lines = {}
        if status == "completed" then
          local file_path = nil
          local diff_content = nil
          if type(update.content) == "table" then
            for _, c in ipairs(update.content) do
              if c.type == "diff" then
                file_path = c.path
                if c.oldText and c.newText then
                  diff_content = { old = c.oldText, new = c.newText, path = c.path }
                end
                break
              end
              if c.path then file_path = c.path end
            end
          end
          if not file_path and update.rawInput then
            file_path = update.rawInput.file_path or update.rawInput.filePath
          end
          if not file_path and update.locations and update.locations[1] then
            file_path = update.locations[1].path
          end
          local last_tool_title = M._last_tool_title[buf]
          if not file_path and last_tool_title then
            file_path = last_tool_title:match("(/%S+%.[%w]+)")
          end
          log.dbg("tool completed: path=" .. (file_path or "nil") .. " from_title=" .. (last_tool_title or ""))
          M._last_tool_title[buf] = nil
          if diff_content then
            local added, deleted = _count_diff_lines(diff_content.old, diff_content.new)
            local stats = M._diff_stats[buf] or { files = 0, added = 0, deleted = 0 }
            stats.files = stats.files + 1
            stats.added = stats.added + (added or 0)
            stats.deleted = stats.deleted + (deleted or 0)
            M._diff_stats[buf] = stats
            _redraw_status()
            local codediff = require("djinni.nowork.codediff")
            local diff_lines_out = codediff.compute(diff_content.old, diff_content.new, diff_content.path)
            local diff_batch = {}
            for _, dl in ipairs(diff_lines_out) do
              diff_batch[#diff_batch + 1] = dl.text
            end
            M._append_lines(buf, diff_batch)
            vim.schedule(function()
              if not vim.api.nvim_buf_is_valid(buf) then return end
              local lc = vim.api.nvim_buf_line_count(buf)
              codediff.apply_highlights(buf, lc - #diff_lines_out, diff_lines_out)
            end)
          elseif file_path then
            if file_path:match("plans/") and file_path:match("%.md$") and vim.fn.filereadable(file_path) == 1 then
              M._plan_path[buf] = file_path
              M._set_frontmatter_field(buf, "plan", file_path)
              vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buf) then
                  M._update_plan_section(buf)
                end
              end)
            end
          end
          if file_path and not diff_content then
            output_lines[#output_lines + 1] = "  " .. file_path
          end
          if text then
            for tline in text:gmatch("([^\n]+)") do
              output_lines[#output_lines + 1] = "  " .. tline
            end
          end
        elseif status == "error" then
          output_lines[#output_lines + 1] = "  error: " .. (text or "")
        end
        if #output_lines > 0 then
          M._append_lines(buf, output_lines)
        end
        if status == "completed" or status == "error" or status == "failed" then
          local tlog = M._tool_log[buf]
          if tlog and #tlog > 0 then
            local entry = tlog[#tlog]
            if entry.input == nil and update.rawInput then
              entry.input = update.rawInput
            end
            if entry.output == nil then
              local out_parts = {}
              local imgs = {}
              if type(update.content) == "table" then
                if update.content.text then
                  table.insert(out_parts, update.content.text)
                else
                  for _, c in ipairs(update.content) do
                    if c.type == "image" then
                      local src = c.source or {}
                      table.insert(imgs, { media_type = src.media_type, data = src.data, url = src.url })
                    elseif c.type == "diff" and c.path then
                      table.insert(out_parts, "diff: " .. c.path)
                      if c.oldText then table.insert(out_parts, "--- " .. c.path) end
                      if c.newText then table.insert(out_parts, "+++ " .. c.path) end
                    elseif c.content and c.content.text then
                      table.insert(out_parts, c.content.text)
                    elseif c.text then
                      table.insert(out_parts, c.text)
                    elseif c.path then
                      table.insert(out_parts, c.path)
                    end
                  end
                end
              end
              entry.output = table.concat(out_parts, "\n")
              entry.images = imgs
              entry.status = status
            end
          end
          M._close_last_tool_fold(buf)
          if (M._active_tool_count[buf] or 0) == 0 then
            M._tool_section_start[buf] = nil
          end
        end
      end

    elseif update_type == "modes" then
      M._modes[buf] = update.availableModes or {}
      M._current_mode[buf] = update.currentModeId

    elseif update_type == "current_mode_update" then
      local mode_id = update.modeId or update.currentModeId
      M._current_mode[buf] = mode_id
      if mode_id then M._set_frontmatter_field(buf, "mode", mode_id) end

    elseif update_type == "plan" then
      local entries = update.entries or {}
      if #entries > 0 then
        local plan_lines = { "### Plan" }
        for _, entry in ipairs(entries) do
          local check = "[ ]"
          local st = entry.status or ""
          if st == "completed" then check = "[x]"
          elseif st == "in_progress" then check = "[~]" end
          local text = entry.content or ""
          table.insert(plan_lines, "- " .. check .. " " .. text)
        end
        table.insert(plan_lines, "")

        M._flush_pending(buf)
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          local pl = M._plan_lines[buf]
          if pl and pl.start_line and pl.end_line then
            pcall(vim.api.nvim_buf_set_lines, buf, pl.start_line, pl.end_line, false, plan_lines)
            pl.end_line = pl.start_line + #plan_lines
          else
            local lc = vim.api.nvim_buf_line_count(buf)
            M._plan_lines[buf] = { start_line = lc, end_line = lc + #plan_lines }
            vim.api.nvim_buf_set_lines(buf, lc, lc, false, plan_lines)
          end
        end)
      end

    elseif update_type == "available_commands_update" then
      local cmds = update.availableCommands
      if type(cmds) == "table" then
        M._available_commands[buf] = cmds
      end

    elseif update_type == "config_option_update" then
      local opts = update.configOptions
      if type(opts) == "table" then
        M._config_options[buf] = opts
      end

    elseif update_type == "usage_update" then
      M._accumulate_usage(buf, update)

    elseif update_type == "result" then
      local usage = update.tokenUsage or update.usage
      local cost_val = update.costUSD or update.cost or update.totalCost
      if usage or cost_val then
        M._accumulate_usage(buf, { tokenUsage = usage, cost = cost_val })
      end
      local result_text = update.resultText or update.message
      if result_text and result_text ~= "" then
        local pt = M._pending_text[buf]
        if not pt then pt = {}; M._pending_text[buf] = pt end
        pt[#pt + 1] = "\n" .. result_text
      end

    elseif update_type == "system" or update_type == "system_message" then
      local text = update.message or update.text or update.content
      if text and text ~= "" then
        M._append_lines(buf, { "", "> [system] " .. tostring(text) })
      end

    elseif update_type == "compaction" or update_type == "context_compaction" then
      M._append_lines(buf, { "", "> [compaction] Context compacted" })

    elseif update_type == "retry" or update_type == "agent_retry" then
      local reason = update.reason or update.message or ""
      M._append_lines(buf, { "> [retry] " .. tostring(reason) })

    elseif update_type == "error" or update_type == "agent_error" then
      local msg = update.message or update.error or update.text or ""
      M._append_lines(buf, { "", "> [error] " .. tostring(msg) })

    elseif update_type then
      local silent = { available_commands_update = true, config_option_update = true, usage_update = true, modes = true, current_mode_update = true }
      if not silent[update_type] then
        log.info("unhandled session update: " .. update_type)
        local text = update.message or update.text or update.content
        if type(text) == "string" and text ~= "" then
          M._append_lines(buf, { "> [" .. update_type .. "] " .. text })
        end
      end
    end
  end) -- pcall

  if not ok then
    log.warn("session/update handler error: " .. tostring(err))
  end
end

function M._on_permission(buf, params, respond)
  local kind_labels = {
    allow_once = "Allow",
    allow_always = "Always",
    reject_once = "Deny",
    reject_always = "Never",
  }

  local opts_str = ""
  if params.options then
    for _, o in ipairs(params.options) do
      opts_str = opts_str .. (o.kind or o.id or "?") .. "=" .. (o.label or "") .. " "
    end
  end
  log.info("permission_request: " .. (params.toolCall and (params.toolCall.title or params.toolCall.kind) or "?") .. " opts=[" .. opts_str .. "]")
  log.dbg("perm raw: " .. vim.inspect(params):gsub("\n", " "):sub(1, 500))
  if M._pending_permission and M._pending_permission[buf] then
    log.info("auto-approve (duplicate)")
    local default_id = "allow_once"
    if params.options then
      for _, o in ipairs(params.options) do
        if o.kind == "allow_once" then default_id = o.optionId or o.kind; break end
      end
    end
    respond({ outcome = { outcome = "selected", optionId = default_id } })
    return
  end
  local tool_desc = "tool"
  local tool_kind = ""
  if params.toolCall then
    tool_desc = (params.toolCall.title or params.toolCall.kind or "tool"):gsub("[\n\r]", " ")
    tool_kind = params.toolCall.kind or ""
  end
  local options = {}
  local option_labels = {}
  if params.options then
    for _, opt in ipairs(params.options) do
      local id = opt.optionId or opt.kind or ""
      local kind = opt.kind or ""
      local label = (opt.name or kind_labels[kind] or opt.label or id):gsub("[\n\r]", " ")
      table.insert(options, { id = id, kind = kind, label = label })
      table.insert(option_labels, "[" .. label .. "]")
    end
  end

  M._flush_pending(buf)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local ok_snacks, Snacks = pcall(require, "snacks")
    local notif_id = "djinni_perm_" .. tostring(buf)
    if ok_snacks and Snacks.notify then
      Snacks.notify.warn("Permission: " .. tool_desc, {
        title = "djinni",
        id = notif_id,
        timeout = 0,
        actions = {
          { label = "Allow (ya)", key = "a", fn = function() M._permission_action(buf, "allow") end },
          { label = "Always (yA)", key = "A", fn = function() M._permission_action(buf, "always") end },
          { label = "Deny (yn)", key = "d", fn = function() M._permission_action(buf, "deny") end },
          { label = "Pick (s)", key = "s", fn = function() M._permission_action(buf, "select") end },
        },
      })
    else
      notif_id = nil
      vim.notify("[djinni] Permission: " .. tool_desc, vim.log.levels.WARN)
    end
    local lc = vim.api.nvim_buf_line_count(buf)
    local perm_lines = {
      "",
      "---",
      "",
      "@System",
      "Permission:" .. tool_desc,
      "  " .. table.concat(option_labels, "  ") .. "  (ya/yn/yA or s to pick)",
      "",
    }
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, perm_lines)

    M._pending_permission = M._pending_permission or {}
    M._pending_permission[buf] = { respond = respond, options = options, tool_desc = tool_desc, tool_kind = tool_kind, notif_id = notif_id }
    M._schedule_panel_render()
  end)
end

function M._subscribe_session(buf, root, sid)
  local old_sid = M._sessions[buf]
  if old_sid and old_sid ~= sid and old_sid ~= "" then
    session.unsubscribe_session(root, old_sid, get_provider(buf))
  end
  M._first_msg_sent = M._first_msg_sent or {}
  M._first_msg_sent[buf] = nil
  session.subscribe_session(root, sid, {
    on_update = function(data)
      M._on_session_update(buf, data)
    end,
    on_permission = function(params, respond)
      M._on_permission(buf, params, respond)
    end,
  }, get_provider(buf))
  session.on_reconnect(sid, function()
    vim.schedule(function() M._on_session_reconnect(buf) end)
  end)
end

function M._start_streaming(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local root = M.get_project_root(buf)
  if not root then return end

  local streaming_lines = { "", "---", "", "@Djinni", "" }
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, streaming_lines)

  M._pending_text[buf] = {}
  M._assistant_output_seen[buf] = nil
  M._djinni_marker_line[buf] = line_count + 3
  M._active_tool_count[buf] = 0
  M._tool_section_start[buf] = nil
  M._last_event_time[buf] = vim.uv.now()
  M._turn_started_at[buf] = M._last_event_time[buf]
  M._turn_usage[buf] = { input_tokens = 0, output_tokens = 0, cost = 0 }
  M._events_received[buf] = false
  M._plan_lines[buf] = nil
  M._last_tool_title[buf] = nil
  M._auto_scroll[buf] = true
  _set_stream_tail(buf, line_count + #streaming_lines, streaming_lines[#streaming_lines])

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    pcall(_win_fold_manual, win, buf)
  end

  _rm_disable(buf)

  local function cleanup()
    _rm_enable(buf)
    if M._turn_started_at[buf] then
      M._turn_elapsed_ms[buf] = vim.uv.now() - M._turn_started_at[buf]
      M._turn_started_at[buf] = nil
    end
    M._turn_usage[buf] = nil
    M._streaming[buf] = nil
    M._stream_cleanup[buf] = nil
    M._cleanup_deferred[buf] = nil
    M._interrupt_pending[buf] = nil
    M._stream_client[buf] = nil
    M._scroll_pending[buf] = nil
    M._stream_tail_row[buf] = nil
    M._stream_tail_text[buf] = nil
    M._schedule_panel_render()
  end

  M._stream_cleanup[buf] = function(force)
    if not M._streaming[buf] then return end
    local cleanup_gen = M._stream_gen[buf]
    if not vim.api.nvim_buf_is_valid(buf) then
      cleanup()
      return
    end
    if not force and M._pending_permission and M._pending_permission[buf] then
      M._cleanup_deferred[buf] = true
      return
    end
    M._timer_scheduled[buf] = nil
    log.info("stream_cleanup called force=" .. tostring(force))
    cleanup()
    M._flush_pending(buf)
    M._flush_append_batch(buf)
    M._close_tool_fold(buf)
    M._think_fold_start[buf] = nil
    local usage = M._usage[buf]
    if usage and vim.api.nvim_buf_is_valid(buf) then
      local total = usage.input_tokens + usage.output_tokens
      if total > 0 then
        local tok_str = total >= 1000 and string.format("%.1fk", total / 1000) or tostring(total)
        M._set_frontmatter_field(buf, "tokens", tok_str)
      end
      if usage.cost > 0 then
        M._set_frontmatter_field(buf, "cost", string.format("%.2f", usage.cost))
      end
    end
    if not _is_large_chat(buf) then
      M._cleanup_empty_djinni(buf)
    end
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if M._streaming[buf] then return end
      local cwin = vim.fn.bufwinid(buf)
      if cwin == -1 then return end
      if not _is_large_chat(buf) then
        pcall(_win_fold_restore_expr, cwin, buf)
      end
    end, 300)
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
        pcall(vim.api.nvim_buf_call, buf, function() vim.cmd("silent! write") end)
      end
    end, 500)
    local last_perm = M._last_perm_tool[buf]
    M._last_perm_tool[buf] = nil
    local count = M._continuation_count[buf] or 0
    local tool_failed = M._last_tool_failed[buf]
    M._last_tool_failed[buf] = false

    local function auto_continue(msg)
      if count >= M._max_continuations then
        log.warn("max continuations (" .. M._max_continuations .. ") reached")
        if vim.api.nvim_buf_is_valid(buf) then
          local lc = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
            "", "@System", "Max auto-continuations (" .. M._max_continuations .. ") reached. Send a message to continue.", ""
          })
        end
      elseif vim.api.nvim_buf_is_valid(buf) then
        M._continuation_count[buf] = count + 1
        log.info("auto-continue [" .. (count + 1) .. "/" .. M._max_continuations .. "]: " .. msg)
        vim.defer_fn(function()
          M.send(buf, msg)
        end, 500)
        return true
      end
      return false
    end

    if last_perm and (last_perm.action == "reject_once" or last_perm.action == "reject_always") then
      if vim.api.nvim_buf_is_valid(buf) then
        local lc = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, lc, lc, false, you_block())
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then
          vim.api.nvim_win_set_cursor(win, { lc + 5, 0 })
        end
        vim.cmd("startinsert")
      end
      return
    end

    if last_perm and last_perm.kind ~= "switch_mode" then
      if auto_continue("yes, continue") then return end
    end

    if tool_failed then
      if auto_continue("The previous tool call failed. Please try an alternative approach.") then return end
    end

    if not M._queue[buf] or #M._queue[buf] == 0 then
      vim.defer_fn(function()
        if M._streaming[buf] or M._stream_gen[buf] ~= cleanup_gen then return end
        local task_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
        local project = vim.fn.fnamemodify(M.get_project_root(buf) or "", ":t")
        local label = M._waiting_input[buf] and "Waiting" or "Done"
        vim.notify("[djinni] " .. label .. ": " .. task_name .. " (" .. project .. ")", vim.log.levels.INFO)
        if vim.api.nvim_buf_is_valid(buf) then
          local win = vim.fn.bufwinid(buf)
          local lc = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, lc, lc, false, you_block())
          if win ~= -1 then
            vim.api.nvim_win_set_cursor(win, { lc + 5, 0 })
            if win == vim.api.nvim_get_current_win() then
              vim.cmd("startinsert")
            end
          end
        end
      end, 100)
    end
    M._process_queue(buf)
  end

  local sid = M._sessions[buf]
  local client = sid and session.get_client(sid) or nil
  M._stream_client[buf] = client
  M._start_global_timer()
  M._schedule_panel_render()
end

function M._process_queue(buf)
  if not M._queue[buf] or #M._queue[buf] == 0 then
    log.info("_process_queue: empty buf=" .. tostring(buf))
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    M._queue[buf] = nil
    return
  end
  local entry = table.remove(M._queue[buf], 1)
  if #M._queue[buf] == 0 then M._queue[buf] = nil end
  local text = type(entry) == "table" and entry.text or entry
  local queued_images = type(entry) == "table" and entry.images or nil
  log.info("_process_queue: sending queued message buf=" .. tostring(buf) .. " len=" .. tostring(#text))
  M.send(buf, text, queued_images)
end

local function _is_structural_line(line)
  if line == "" then return true end
  if line:match("^```") then return true end
  if line:match("^#") then return true end
  if line:match("^%s*[-*+]%s") then return true end
  if line:match("^%s*%d+%.%s") then return true end
  if line:match("^>") then return true end
  if line:match("^|") then return true end
  if line:match("^%[[%*%+!]%]") then return true end
  if line:match("^---$") then return true end
  if line:match("^@%w") then return true end
  return false
end

function M._unwrap_paragraphs(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if _is_large_chat(buf) then return end
  local total = vim.api.nvim_buf_line_count(buf)
  local marker_line = M._djinni_marker_line[buf]
  if not marker_line or marker_line >= total then
    marker_line = nil
    local window = 200
    local search_from = math.max(0, total - window)
    while search_from >= 0 do
      local chunk = vim.api.nvim_buf_get_lines(buf, search_from, math.min(search_from + window, total), false)
      for i = #chunk, 1, -1 do
        if (chunk[i] or ""):match("^@Djinni%s*$") then
          marker_line = search_from + i
          break
        end
      end
      if marker_line then break end
      if search_from == 0 then break end
      search_from = math.max(0, search_from - window)
    end
  end
  if not marker_line then return end

  local lines = vim.api.nvim_buf_get_lines(buf, marker_line, total, false)
  local result = {}
  local in_code = false
  for _, line in ipairs(lines) do
    if line:match("^```") then
      in_code = not in_code
      result[#result + 1] = line
    elseif in_code then
      result[#result + 1] = line
    elseif _is_structural_line(line) then
      result[#result + 1] = line
    elseif #result > 0 and not _is_structural_line(result[#result]) and not in_code then
      result[#result] = result[#result] .. " " .. line
    else
      result[#result + 1] = line
    end
  end

  vim.api.nvim_buf_set_lines(buf, marker_line, total, false, result)
end

M._auto_scroll = {}

function M._apply_stream_chunk(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local row = M._stream_tail_row[buf]
  local tail = M._stream_tail_text[buf]
  if not row or row > vim.api.nvim_buf_line_count(buf) then
    row, tail = _sync_stream_tail(buf)
  end

  local lines, new_tail = M._stream_chunk_lines(tail, text)
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, lines)
  _set_stream_tail(buf, row + #lines - 1, new_tail)

  M._scroll_pending[buf] = true
end

function M.get_session_id(buf)
  return read_frontmatter_field(buf, "session")
end

function M.get_project_root(buf)
  return read_frontmatter_field(buf, "root")
end

function M._read_frontmatter_csv(buf, key)
  return parse_csv(read_frontmatter_field(buf, key))
end

function M._get_fm_end(buf)
  local cached = M._fm_end_cache[buf]
  if cached then return cached end
  local limit = math.min(20, vim.api.nvim_buf_line_count(buf))
  local lines = vim.api.nvim_buf_get_lines(buf, 0, limit, false)
  for i = 2, #lines do
    if lines[i] == "---" then
      M._fm_end_cache[buf] = i
      return i
    end
  end
  return nil
end

function M._set_frontmatter_field(buf, key, value)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local fm_end = M._get_fm_end(buf)
  if not fm_end then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, fm_end, false)
  for i = 2, #lines do
    local k = lines[i]:match("^([%w_]+):")
    if k == key then
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { key .. ": " .. value })
      return
    end
  end
  vim.api.nvim_buf_set_lines(buf, fm_end - 1, fm_end - 1, false, { key .. ": " .. value })
  M._fm_end_cache[buf] = fm_end + 1
end

function M._jump_turn(buf, direction)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current = cursor[1]

  local targets = {}
  for i, line in ipairs(lines) do
    if line:match("^@You%s*$") or line:match("^@Djinni%s*$") or line:match("^@System%s*$") then
      targets[#targets + 1] = i
    end
  end

  if #targets == 0 then
    return
  end

  if direction > 0 then
    for _, t in ipairs(targets) do
      if t > current then
        vim.api.nvim_win_set_cursor(0, { t, 0 })
        return
      end
    end
  else
    for i = #targets, 1, -1 do
      if targets[i] < current then
        vim.api.nvim_win_set_cursor(0, { targets[i], 0 })
        return
      end
    end
  end
end

function M._fresh_restart(buf, root)
  M._streaming[buf] = nil
  M._stream_cleanup[buf] = nil
  M._cleanup_deferred[buf] = nil
  M._schedule_panel_render()

  mcp.clear_cache(root)
  local old_sid = M.get_session_id(buf) or M._sessions[buf]
  local sess_opts = build_session_opts(buf, root)

  local history_msg = (function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local parsed = blocks.parse(lines)
    local parts = {}
    for _, b in ipairs(parsed) do
      if (b.type == "you" or b.type == "djinni") and b.content and b.content ~= "" then
        local role = b.type == "you" and "User" or "Assistant"
        local content = b.content
          :gsub("^%- .+\n?", "")
          :gsub("\n%- .+", "")
          :gsub("^%*%*Thinking%.%.%.%*%*.-\n?", "")
          :gsub("\n?> [^\n]*", "")
          :gsub("%s+$", "")
        if content ~= "" then
          parts[#parts + 1] = role .. ": " .. content
        end
      end
    end
    if #parts == 0 then return nil end
    return "[Previous conversation - session restarted]\n\n"
      .. table.concat(parts, "\n\n")
      .. "\n\n[End of context. Continue from here.]"
  end)()

  local prev_sid = M.get_session_id(buf) or M._sessions[buf]
  M._set_frontmatter_field(buf, "session", "")
  M._sessions[buf] = nil
  if prev_sid and prev_sid ~= "" then
    session.close_task_session(root, prev_sid, get_provider(buf))
  end
  local pre_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = #pre_lines, 1, -1 do
    local l = pre_lines[i]
    if l:match("^@You%s*$") then
      local has_content = false
      for j = i + 1, #pre_lines do
        if pre_lines[j]:match("^@%w+%s*$") or pre_lines[j]:match("^%-%-%-$") then break end
        if pre_lines[j]:match("%S") then has_content = true; break end
      end
      if not has_content then
        local del_from = i
        while del_from > 1 and (pre_lines[del_from - 1] == "" or pre_lines[del_from - 1]:match("^%-%-%-$")) do
          del_from = del_from - 1
        end
        local del_to = i
        while del_to < #pre_lines and (pre_lines[del_to + 1] == "" or pre_lines[del_to + 1]:match("^%-%-%-$")) do
          del_to = del_to + 1
        end
        pcall(vim.api.nvim_buf_set_lines, buf, del_from - 1, del_to, false, {})
      end
      break
    end
    if l:match("^@%w+%s*$") and not l:match("^@You") then break end
  end
  local lc = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, lc, lc, false, { "", "---", "", "@System", "Restarting session...", "" })

  session.create_or_resume_session(root, old_sid, function(err, new_sid, result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if err or not new_sid then
        local row = vim.api.nvim_buf_line_count(buf) - 1
        vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { "Session failed: " .. (err and err.message or "unknown") })
        return
      end
      local resumed = old_sid and old_sid ~= "" and new_sid == old_sid
      M._set_frontmatter_field(buf, "session", new_sid)
      M._sessions[buf] = new_sid
      M._subscribe_session(buf, root, new_sid)
      local row = vim.api.nvim_buf_line_count(buf) - 1
      vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { resumed and "Session resumed" or "Session ready" })
      vim.notify("[djinni] Session " .. (resumed and "resumed (context preserved)" or "restarted (fresh)"), vim.log.levels.INFO)
      M._restore_mode(buf, root, new_sid, result)
      local function finish_restart()
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          M._pending_text[buf] = {}
          M._append_batch[buf] = nil
          local rlc = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, rlc, rlc, false, you_block())
          local win = vim.fn.bufwinid(buf)
          if win ~= -1 then
            vim.api.nvim_win_set_cursor(win, { rlc + 5, 0 })
          end
        end)
      end
      if not resumed and history_msg then
        session.send_message(root, new_sid, history_msg, function() finish_restart() end, nil, get_provider(buf))
      else
        finish_restart()
      end
    end)
  end, sess_opts)
end

function M.restart_session(buf)
  local root = M.get_project_root(buf)
  if not root then return end
  M._fresh_restart(buf, root)
end

function M.resume_session(buf, target_session_id)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local root = M.get_project_root(buf)
  if not root then
    vim.notify("[djinni] No project root", vim.log.levels.WARN)
    return
  end

  local provider_name = get_provider(buf)
  local sess_opts = build_session_opts(buf, root)

  local function attach_session(session_id, label)
    if not session_id or session_id == "" then return end
    if M._streaming[buf] and M._stream_cleanup[buf] then
      M._stream_cleanup[buf](true)
    end
    local old_sid = M.get_session_id(buf) or M._sessions[buf]
    if old_sid and old_sid ~= "" and old_sid ~= session_id then
      session.unsubscribe_session(root, old_sid, provider_name)
      session.close_task_session(root, old_sid, provider_name)
    end
    M._set_frontmatter_field(buf, "session", "")
    M._sessions[buf] = nil
    M._waiting_input[buf] = nil
    M._continuation_count[buf] = 0
    M._last_tool_failed[buf] = false
    M._queue[buf] = nil
    M._usage[buf] = nil
    M._available_commands[buf] = nil
    M._modes[buf] = nil
    M._current_mode[buf] = nil
    M._config_options[buf] = nil
    M._pending_text[buf] = {}
    M._append_batch[buf] = nil

    session.load_task_session(root, session_id, function(err, result)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if err then
          vim.notify("[djinni] Resume failed: " .. (err.message or "unknown"), vim.log.levels.WARN)
          return
        end
        M._set_frontmatter_field(buf, "session", session_id)
        M._sessions[buf] = session_id
        M._subscribe_session(buf, root, session_id)
        M._restore_mode(buf, root, session_id, result)
        local lc = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
          "", "---", "", "@System", "Session resumed" .. (label and (": " .. label) or ""), "",
        })
        vim.notify("[djinni] Session resumed", vim.log.levels.INFO)
      end)
    end, sess_opts)
  end

  if target_session_id and target_session_id ~= "" then
    attach_session(target_session_id, target_session_id)
    return
  end

  session.list_task_sessions(root, function(err, sessions)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if err then
        vim.notify("[djinni] /resume not supported: " .. (err.message or "unknown"), vim.log.levels.WARN)
        return
      end
      if not sessions or #sessions == 0 then
        vim.notify("[djinni] No resumable sessions", vim.log.levels.INFO)
        return
      end

      table.sort(sessions, function(a, b)
        local at = a.updatedAt or ""
        local bt = b.updatedAt or ""
        if at == bt then
          return (a.title or a.sessionId or "") < (b.title or b.sessionId or "")
        end
        return at > bt
      end)

      vim.ui.select(sessions, {
        prompt = "Resume session:",
        format_item = function(item)
          local title = item.title or "(untitled)"
          local updated = item.updatedAt or "unknown time"
          return title .. "  [" .. updated .. "]  " .. (item.sessionId or "")
        end,
      }, function(choice)
        if not choice or not choice.sessionId then return end
        vim.schedule(function()
          attach_session(choice.sessionId, choice.title or choice.sessionId)
        end)
      end)
    end)
  end, sess_opts)
end


function M.switch_provider(buf, choice)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local root = M.get_project_root(buf)
  local prov_old_sid = M.get_session_id(buf) or M._sessions[buf]
  if root and prov_old_sid and prov_old_sid ~= "" then
    session.close_task_session(root, prov_old_sid, get_provider(buf))
  end
  M._sessions[buf] = nil
  M._cached_provider[buf] = nil
  M._set_frontmatter_field(buf, "provider", choice)
  M._set_frontmatter_field(buf, "session", "")

  local lines = { "", "---", "", "@System", "Provider changed to " .. choice, "" }
  input.insert_above_separator(buf, lines)

  if root then
    mcp.clear_cache(root)
    local provider_opts = build_session_opts(buf, root)
    session.create_task_session(root, function(err, new_sid)
      if err or not new_sid then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            M._update_system_block(buf, "Session failed: " .. (err and err.message or "unknown"))
          end
        end)
        return
      end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          M._set_frontmatter_field(buf, "session", new_sid)
          M._sessions[buf] = new_sid
          M._subscribe_session(buf, root, new_sid)
        end
      end)
    end, provider_opts)
  end
end

function M.select_provider(buf)
  local Provider = require("djinni.acp.provider")
  local providers = Provider.list()

  vim.schedule(function()
    vim.ui.select(providers, { prompt = "Select provider:" }, function(choice)
      if not choice then return end
      vim.schedule(function() M.switch_provider(buf, choice) end)
    end)
  end)
end

function M.pick_mode(buf)
  local modes = M._modes[buf]
  if not modes or #modes == 0 then
    vim.notify("[djinni] No modes available", vim.log.levels.WARN)
    return
  end

  local current = M._current_mode[buf]
  local current_idx = 1
  for i, m in ipairs(modes) do
    if m.id == current then
      current_idx = i
      break
    end
  end

  local next_idx = (current_idx % #modes) + 1
  local mode = modes[next_idx]

  local root = M.get_project_root(buf)
  local sid = M.get_session_id(buf) or M._sessions[buf]
  if root and sid then
    session.set_mode(root, sid, mode.id, get_provider(buf))
    M._current_mode[buf] = mode.id
    M._set_frontmatter_field(buf, "mode", mode.id)
    local icons = { plan = "📋", spec = "📝", auto = "🤖", code = "💻", chat = "💬", execute = "▶️" }
    local icon = icons[mode.id] or "↻"
    local name = mode.displayName or mode.name or mode.id
    vim.notify(icon .. " " .. name, vim.log.levels.INFO)
  end
end

function M.get_slash_commands(buf)
  return commands.get_slash_commands(buf)
end

function M.pick_command(buf)
  local cmds = M.get_slash_commands(buf)
  if not cmds or #cmds == 0 then
    vim.notify("[djinni] No slash commands available", vim.log.levels.WARN)
    return
  end
  local source_labels = {
    ["local"] = "[local]",
    agent = "[agent]",
    skill = "[skill]",
  }
  local function run_command(cmd, input)
    local text = cmd.slash or ("/" .. cmd.name)
    if input and input ~= "" then
      text = text .. " " .. input
    end
    if cmd.source == "skill" then
      commands.execute(buf, "/skill " .. cmd.name)
      return
    end
    if commands.execute(buf, text) then
      return
    end
    M.send(buf, text)
  end
  vim.ui.select(cmds, {
    prompt = "Slash command:",
    format_item = function(cmd)
      local parts = { cmd.slash or ("/" .. cmd.name) }
      local source = source_labels[cmd.source]
      if source then parts[#parts + 1] = source end
      if cmd.description and cmd.description ~= "" then
        parts[#parts + 1] = cmd.description
      elseif cmd.input and cmd.input.hint then
        parts[#parts + 1] = cmd.input.hint
      end
      return table.concat(parts, "  ")
    end,
  }, function(cmd)
    if not cmd then return end
    if cmd.input and cmd.input.hint then
      vim.ui.input({ prompt = (cmd.slash or ("/" .. cmd.name)) .. " ", }, function(value)
        if value == nil then return end
        vim.schedule(function() run_command(cmd, vim.trim(value)) end)
      end)
      return
    end
    run_command(cmd)
  end)
end

function M.pick_model(buf)
  vim.schedule(function()
    local models = commands.get_models(buf)
    local current = read_frontmatter_field(buf, "model") or ""

    local items = { { kind = "manual", label = "[type manually…]" } }
    for _, m in ipairs(models) do
      items[#items + 1] = {
        kind = "model",
        id = m.id,
        label = m.label or m.id,
      }
    end

    vim.ui.select(items, {
      prompt = "Select model",
      format_item = function(item)
        return item.label or item.id or ""
      end,
    }, function(choice)
      if not choice then return end
      if choice.kind == "manual" then
        vim.ui.input({ prompt = "Model: ", default = current }, function(input)
          if not input or input == "" then return end
          M._set_frontmatter_field(buf, "model", input)
          M.restart_session(buf)
        end)
        return
      end
      local model_id = choice.id or choice.label
      if not model_id or model_id == "" then return end
      M._set_frontmatter_field(buf, "model", model_id)
      M.restart_session(buf)
    end)
  end)
end

function M.show_help()
  local help = {
    "Chat Keybinds",
    "",
    "  <CR>      Send @You block at cursor",
    "  gi        Quick input (queues if streaming)",
    "  <C-c>     Interrupt AI",
    "  I         Jump to input zone",
    "  i         Insert (on separator: input zone)",
    "  ]] / [[   Next / prev turn",
    "  <Tab>     Toggle fold",
    "  <CR>      Context action",
    "  p         Switch provider",
    "  R         Restart session",
    "  D         Delta diff (on tool line)",
    "  dd        Delete block",
    "  e         Edit block",
    "  r         Retry from block",
    "  s         Permission picker",
    "  ya/yn/yA  Allow / deny / always",
    "  ?         This help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = 38
  local height = #help
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = vim.o.lines - height - 4,
    style = "minimal",
    border = "rounded",
    title = " Help ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

function M._update_plan_section(buf)
  local plan_path = M._plan_path[buf]
  if not plan_path then return end

  local f = io.open(plan_path, "r")
  if not f then return end
  local plan_lines = { "", "### Plan" }
  for line in f:lines() do
    table.insert(plan_lines, line)
  end
  f:close()
  table.insert(plan_lines, "")
  table.insert(plan_lines, "---")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local fm_end = nil
  local fm_count = 0
  for i, line in ipairs(lines) do
    if line:match("^%-%-%-$") then
      fm_count = fm_count + 1
      if fm_count == 2 then
        fm_end = i
        break
      end
    end
  end
  if not fm_end then return end

  local plan_start = nil
  local plan_end = nil
  for i = fm_end + 1, #lines do
    if lines[i]:match("^### Plan") then
      plan_start = i
    elseif plan_start and lines[i]:match("^%-%-%-$") then
      plan_end = i
      break
    end
  end

  if plan_start and plan_end then
    vim.api.nvim_buf_set_lines(buf, plan_start - 1, plan_end, false, plan_lines)
  else
    local insert_at = fm_end
    for i = fm_end + 1, #lines do
      if lines[i]:match("^@System") then
        for j = i + 1, #lines do
          if lines[j]:match("^%-%-%-$") or lines[j]:match("^@") then
            insert_at = j - 1
            break
          end
          insert_at = j
        end
        break
      elseif lines[i]:match("^@You") or lines[i]:match("^@Djinni") then
        break
      end
    end
    vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, plan_lines)
  end
end

function M._update_system_block(buf, text)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line == "@System" then
      local next_idx = i
      if next_idx < #lines then
        vim.api.nvim_buf_set_lines(buf, next_idx, next_idx + 1, false, { text })
      end
      return
    end
  end
end

function M._delete_block(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local block_start = nil
  local block_type = nil
  for i = row, 1, -1 do
    local header = lines[i] and lines[i]:match("^@(%w+)%s*$")
    if header then
      block_start = i
      block_type = header
      break
    end
  end

  if not block_start or not block_type then return end

  local block_end = #lines
  for i = block_start + 1, #lines do
    if lines[i]:match("^@%w+%s*$") or (lines[i]:match("^%-%-%-$") and i > block_start + 1) then
      block_end = i - 1
      break
    end
  end

  local del_start = block_start
  if del_start > 1 and lines[del_start - 1]:match("^%-%-%-$") then
    del_start = del_start - 1
  end
  if del_start > 1 and lines[del_start - 1] == "" then
    del_start = del_start - 1
  end

  while block_end < #lines and lines[block_end + 1] == "" do
    block_end = block_end + 1
  end
  if block_end < #lines and lines[block_end + 1]:match("^%-%-%-$") then
    block_end = block_end + 1
  end
  while block_end < #lines and lines[block_end + 1] == "" do
    block_end = block_end + 1
  end

  pcall(vim.api.nvim_buf_set_lines, buf, del_start - 1, block_end, false, {})
end

function M._context_action(_buf) end

function M._open_tool_log(buf)
  local log = M._tool_log[buf]
  if not log or #log == 0 then
    vim.notify("[djinni] No tool calls recorded", vim.log.levels.INFO)
    return
  end

  local lines = {}
  for i, entry in ipairs(log) do
    local status_mark = entry.status == "error" or entry.status == "failed" and " ✗" or " ✓"
    table.insert(lines, ("## [%d] %s%s"):format(i, entry.name or entry.kind or "?", status_mark))
    table.insert(lines, "")

    if entry.input and next(entry.input) then
      table.insert(lines, "### Input")
      local ok, encoded = pcall(vim.fn.json_encode, entry.input)
      if ok then
        local decoded_ok, decoded = pcall(vim.fn.json_decode, encoded)
        if decoded_ok then
          for k, v in pairs(entry.input) do
            local val = type(v) == "table" and vim.fn.json_encode(v) or tostring(v)
            if #val > 2000 then val = val:sub(1, 2000) .. " …" end
            table.insert(lines, ("  %s: %s"):format(k, val))
          end
        end
      end
      table.insert(lines, "")
    end

    table.insert(lines, "### Output")
    if entry.output and entry.output ~= "" then
      for line in (entry.output .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, "  " .. line)
      end
    else
      table.insert(lines, "  (empty)")
    end

    if entry.images and #entry.images > 0 then
      table.insert(lines, "")
      table.insert(lines, "### Images")
      for j, img in ipairs(entry.images) do
        if img.url then
          table.insert(lines, ("  [image %d] url: %s"):format(j, img.url))
        elseif img.data then
          local kb = math.floor(#img.data * 3 / 4 / 1024)
          table.insert(lines, ("  [image %d] %s ~%d KB"):format(j, img.media_type or "image", kb))
        end
      end
    end

    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")
  end

  local vw = vim.o.columns
  local vh = vim.o.lines
  local w = math.floor(vw * 0.88)
  local h = math.floor(vh * 0.85)
  local row = math.floor((vh - h) / 2)
  local col = math.floor((vw - w) / 2)

  local fbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)
  vim.bo[fbuf].filetype = "markdown"
  vim.bo[fbuf].modifiable = false
  vim.bo[fbuf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(fbuf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = w,
    height = h,
    style = "minimal",
    border = "rounded",
    title = " Tool Log ",
    title_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 0

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = fbuf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = fbuf, silent = true, nowait = true })
end

function M._edit_block(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local block_start = nil
  for i = row, 1, -1 do
    if lines[i] and lines[i]:match("^@You%s*$") then
      block_start = i
      break
    end
    if lines[i] and lines[i]:match("^@%w+%s*$") and not lines[i]:match("^@You") then
      return
    end
    if lines[i] and lines[i]:match("^%-%-%-$") and i > 2 then
      return
    end
  end
  if not block_start then return end

  local block_end = #lines
  for i = block_start + 1, #lines do
    if lines[i]:match("^%-%-%-$") or lines[i]:match("^@%w+%s*$") then
      block_end = i - 1
      break
    end
  end

  local text_lines = {}
  for i = block_start + 1, block_end do
    table.insert(text_lines, lines[i])
  end
  local text = table.concat(text_lines, "\n"):match("^%s*(.-)%s*$")
  if not text or text == "" then return end

  local next_block = nil
  for i = block_end + 1, #lines do
    if lines[i]:match("^@%w+%s*$") then
      next_block = i
      break
    end
  end
  if not next_block then return end

  local del_from = next_block
  if del_from > 1 and lines[del_from - 1]:match("^%-%-%-$") then
    del_from = del_from - 1
  end
  if del_from > 1 and lines[del_from - 1] == "" then
    del_from = del_from - 1
  end

  pcall(vim.api.nvim_buf_set_lines, buf, del_from - 1, #lines, false, {})

  M._invalidate_session(buf)
  M._creating_session[buf] = nil
  M._first_msg_sent[buf] = nil

  M.send(buf, text)
end

function M._rerun_tool(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local tool = tools.extract_tool_at_cursor(lines, row)
  if not tool then return end
  local prompt = "Run " .. tool.name
  if tool.args ~= "" then
    prompt = prompt .. " with: " .. tool.args
  end
  M.send(buf, prompt)
end

function M._retry_block(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local djinni_start = nil
  for i = row, 1, -1 do
    if lines[i] and lines[i]:match("^@Djinni%s*$") then
      djinni_start = i
      break
    end
    if lines[i] and lines[i]:match("^@You%s*$") then
      break
    end
  end

  if not djinni_start then
    return
  end

  local you_text = nil
  for i = djinni_start - 1, 1, -1 do
    if lines[i] and lines[i]:match("^@You%s*$") then
      local text_lines = {}
      for j = i + 1, djinni_start - 1 do
        if lines[j]:match("^%-%-%-$") or lines[j]:match("^@%w+%s*$") then
          break
        end
        table.insert(text_lines, lines[j])
      end
      you_text = table.concat(text_lines, "\n"):match("^%s*(.-)%s*$")
      break
    end
  end

  if not you_text or you_text == "" then
    return
  end

  local del_from = djinni_start
  if del_from > 1 and lines[del_from - 1]:match("^%-%-%-$") then
    del_from = del_from - 1
  end
  if del_from > 1 and lines[del_from - 1] == "" then
    del_from = del_from - 1
  end
  pcall(vim.api.nvim_buf_set_lines, buf, del_from - 1, #lines, false, {})

  M._invalidate_session(buf)
  M._creating_session[buf] = nil
  M._first_msg_sent = M._first_msg_sent or {}
  M._first_msg_sent[buf] = nil

  M.send(buf, you_text)
end

function M._permission_action(buf, action)
  if not M._pending_permission or not M._pending_permission[buf] then
    vim.notify("[djinni] No pending permission", vim.log.levels.WARN)
    return
  end

  local perm = M._pending_permission[buf]

  hide_snacks_notif(perm.notif_id)

  if action == "select" then
    local labels = {}
    for _, opt in ipairs(perm.options) do
      table.insert(labels, opt.label)
    end
    vim.schedule(function()
      vim.ui.select(labels, { prompt = "Permission:" }, function(choice, idx)
        if not choice or not idx then return end
        M._pending_permission[buf] = nil
        local deferred = M._cleanup_deferred[buf]
        M._cleanup_deferred[buf] = nil
        local ok_resp, resp_err = pcall(perm.respond, { outcome = { outcome = "selected", optionId = perm.options[idx].id } })
        if not ok_resp then
          log.err("respond failed (select): " .. tostring(resp_err))
        elseif deferred and M._stream_cleanup[buf] then
          vim.schedule(function()
            if M._stream_cleanup[buf] then M._stream_cleanup[buf]() end
          end)
        end
        local lc = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, lc, lc, false, { "", "@System", "OK:" .. choice, "" })
        M._schedule_panel_render()
      end)
    end)
    return
  end

  M._pending_permission[buf] = nil
  local deferred = M._cleanup_deferred[buf]
  M._cleanup_deferred[buf] = nil

  local action_to_kind = {
    allow = "allow_once",
    deny = "reject_once",
    always = "allow_always",
  }
  local target_kind = action_to_kind[action]
  local option_id = nil
  if perm.options and #perm.options > 0 then
    for _, opt in ipairs(perm.options) do
      if opt.kind == target_kind then
        option_id = opt.id
        break
      end
    end
  end

  if not option_id then
    M._pending_permission[buf] = perm
    M._permission_action(buf, "select")
    return
  end

  local selected_kind = target_kind
  local kind_labels = {
    allow_once = "Allowed",
    allow_always = "Always allowed",
    reject_once = "Denied",
    reject_always = "Never allowed",
  }

  local function send_perm_response(reason)
    M._last_perm_tool[buf] = { desc = perm.tool_desc, kind = perm.tool_kind, action = selected_kind }
    log.info("permission response: " .. option_id .. " tool=" .. (perm.tool_desc or "?") .. " kind=" .. (perm.tool_kind or "?") .. (reason and (" reason=" .. reason) or ""))
    local response = {
      outcome = {
        outcome = "selected",
        optionId = option_id,
      },
    }
    if reason and reason ~= "" then
      response.outcome.message = reason
    end
    local ok_resp, resp_err = pcall(perm.respond, response)
    if not ok_resp then
      log.err("respond failed: " .. tostring(resp_err))
      if M._stream_cleanup[buf] then
        M._stream_cleanup[buf](true)
      else
        M._streaming[buf] = nil
      end
      M._continuation_count[buf] = nil
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(buf) then
          M.send(buf, "yes, continue")
        end
      end, 100)
    else
      log.info("respond sent OK")
      if deferred and M._stream_cleanup[buf] then
        vim.schedule(function()
          if M._stream_cleanup[buf] then M._stream_cleanup[buf]() end
        end)
      end
    end

    local suffix = reason and reason ~= "" and (" (" .. reason .. ")") or ""
    local lc = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
      "",
      "@System",
      "OK:" .. (kind_labels[selected_kind] or option_id) .. suffix,
      "",
    })
    M._schedule_panel_render()

  end

  if selected_kind == "reject_once" or selected_kind == "reject_always" then
    local ok_snacks, Snacks = pcall(require, "snacks")
    local input_fn = (ok_snacks and Snacks.input) and Snacks.input or vim.ui.input
    input_fn({ prompt = "Rejection reason (optional): " }, function(input)
      vim.schedule(function()
        send_perm_response(input)
      end)
    end)
  else
    send_perm_response(nil)
  end
end

function M._on_save(buf)
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! zR")
    end)
  end
end

function M._extract_modes(buf, result)
  if not result then log.dbg("_extract_modes: no result"); return end
  log.dbg("_extract_modes keys: " .. vim.inspect(vim.tbl_keys(result)):gsub("\n", " "))
  if result.modes then
    local modes = result.modes
    if type(modes.availableModes) == "table" then
      M._modes[buf] = modes.availableModes
      log.info("modes received: " .. #modes.availableModes .. " modes")
    end
    if modes.currentModeId then
      M._current_mode[buf] = modes.currentModeId
      M._set_frontmatter_field(buf, "mode", modes.currentModeId)
    end
  end
end

function M._restore_mode(buf, root, sid, result)
  local saved_mode = M._current_mode[buf]
  M._extract_modes(buf, result)
  if saved_mode then
    local current = result and result.modes and result.modes.currentModeId
    local modes = M._modes[buf] or {}
    if #modes > 0 then
      local supported = false
      for _, mode in ipairs(modes) do
        if mode.id == saved_mode then
          supported = true
          break
        end
      end
      if not supported then
        if current then
          M._current_mode[buf] = current
          M._set_frontmatter_field(buf, "mode", current)
        end
        return
      end
    end
    M._current_mode[buf] = saved_mode
    M._set_frontmatter_field(buf, "mode", saved_mode)
    if saved_mode ~= current and root and sid then
      session.set_mode(root, sid, saved_mode, get_provider(buf))
    end
  end
end

function M._resolve_refs(text, source_buf)
  local bufname = vim.api.nvim_buf_get_name(source_buf)
  if bufname == "" then
    return text
  end
  local rel = vim.fn.fnamemodify(bufname, ":.")
  text = text:gsub("@{file}", "@./" .. rel)
  text = text:gsub("@{selection}", function()
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    if start_line > 0 and end_line > 0 then
      return "@./" .. rel .. ":" .. start_line .. "-" .. end_line
    end
    return "@./" .. rel
  end)
  text = text:gsub("@{file:(%d+%-?%d*)}", function(range)
    return "@./" .. rel .. ":" .. range
  end)
  text = text:gsub("%[#file%]%((.-)%)", function(path)
    return "@./" .. path
  end)
  return text
end

function M._accumulate_usage(buf, result)
  if not result then return end
  local u = M._usage[buf] or { input_tokens = 0, output_tokens = 0, cost = 0, context_used = 0, context_size = 0 }
  local tok = result.tokenUsage or result.usage or {}
  local input_tokens = tok.inputTokens or tok.input_tokens or 0
  local output_tokens = tok.outputTokens or tok.output_tokens or 0
  local has_token_fields = tok.inputTokens ~= nil or tok.input_tokens ~= nil or tok.outputTokens ~= nil or tok.output_tokens ~= nil
  local cost = nil
  if result.costUSD then
    cost = tonumber(result.costUSD) or 0
  elseif result.cost then
    local c = result.cost
    if type(c) == "table" then
      cost = tonumber(c.amount) or 0
    else
      cost = tonumber(c) or 0
    end
  elseif result.totalCost then
    cost = tonumber(result.totalCost) or 0
  end
  local turn = M._turn_usage[buf]
  if turn and has_token_fields then
    local input_delta = math.max(0, input_tokens - (turn.input_tokens or 0))
    local output_delta = math.max(0, output_tokens - (turn.output_tokens or 0))
    u.input_tokens = u.input_tokens + input_delta
    u.output_tokens = u.output_tokens + output_delta
    turn.input_tokens = math.max(turn.input_tokens or 0, input_tokens)
    turn.output_tokens = math.max(turn.output_tokens or 0, output_tokens)
  else
    u.input_tokens = u.input_tokens + input_tokens
    u.output_tokens = u.output_tokens + output_tokens
  end
  if result.used then u.context_used = result.used end
  if result.size then u.context_size = result.size end
  if cost then
    if turn then
      local cost_delta = math.max(0, cost - (turn.cost or 0))
      u.cost = u.cost + cost_delta
      turn.cost = math.max(turn.cost or 0, cost)
    else
      u.cost = u.cost + cost
    end
  end
  M._usage[buf] = u
  _redraw_status()
end

M._auto_compact_threshold = 0.80

function M._maybe_auto_compact(buf)
  local u = M._usage[buf]
  if not u or u.context_size == 0 or u.context_used == 0 then return end
  local ratio = u.context_used / u.context_size
  if ratio < M._auto_compact_threshold then return end
  if M._streaming[buf] then return end
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    M.send(buf, "/compact")
  end)
end

function M.statusline()
  local ok, result = pcall(function()
    local buf = vim.api.nvim_get_current_buf()
    local parts = { "djinni" }
    local mode = M._current_mode[buf]
    if mode then parts[#parts + 1] = "[" .. tostring(mode) .. "]" end
    if M._streaming[buf] then
      local idx = (M._spinner_frame % #M._spinner_chars) + 1
      parts[#parts + 1] = M._spinner_chars[idx]
    end
    local started = M._turn_started_at[buf]
    local elapsed = started and (vim.uv.now() - started) or M._turn_elapsed_ms[buf]
    if elapsed and elapsed > 0 then
      parts[#parts + 1] = _fmt_elapsed(elapsed)
    end
    local usage = M._usage[buf]
    if usage then
      local input_tokens = usage.input_tokens or 0
      local output_tokens = usage.output_tokens or 0
      if input_tokens + output_tokens > 0 then
        parts[#parts + 1] = "↓" .. _fmt_k(input_tokens) .. " ↑" .. _fmt_k(output_tokens)
      end
    end
    local diff = M._diff_stats[buf]
    if diff and ((diff.files or 0) > 0 or (diff.added or 0) > 0 or (diff.deleted or 0) > 0) then
      parts[#parts + 1] = "Δ" .. _fmt_k(diff.files or 0) .. " +" .. _fmt_k(diff.added or 0) .. " -" .. _fmt_k(diff.deleted or 0)
    end
    if usage and usage.cost and usage.cost > 0 then
      parts[#parts + 1] = string.format("$%.2f", usage.cost)
    end
    if #parts == 1 and not M._streaming[buf] then return "" end
    return table.concat(parts, " ")
  end)
  if ok then return result end
  return "djinni"
end

function M.global_statusline()
  local ok, result = pcall(function()
    local hive_ok, hive = pcall(require, "djinni.nowork.hive")
    if hive_ok and hive.statusline then
      local hive_status = hive.statusline()
      if hive_status ~= "" then
        local total_cost = 0
        for _, usage in pairs(M._usage or {}) do
          if usage.cost and usage.cost > 0 then total_cost = total_cost + usage.cost end
        end
        local cost_str = total_cost > 0 and (" $" .. string.format("%.2f", total_cost)) or ""
        return hive_status .. cost_str
      end
    end
    local running = 0
    local total_cost = 0
    for buf in pairs(M._streaming or {}) do
      if vim.api.nvim_buf_is_valid(buf) then running = running + 1 end
    end
    for _, usage in pairs(M._usage or {}) do
      if usage.cost and usage.cost > 0 then total_cost = total_cost + usage.cost end
    end
    if running == 0 and total_cost == 0 then return "" end
    local parts = "djinni:"
    if running > 0 then parts = parts .. " " .. running .. "●" end
    if total_cost > 0 then parts = parts .. " $" .. string.format("%.2f", total_cost) end
    return parts
  end)
  if ok then return result end
  return ""
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    for buf, fn in pairs(M._stream_cleanup) do
      pcall(fn, true)
    end
    session.shutdown_all()
  end,
})

function M.show_tree(buf)
  local root = M.get_project_root(buf)
  if not root then
    vim.notify("[djinni] No project root", vim.log.levels.WARN)
    return
  end

  local config = require("djinni").config
  local chat_dir = root .. "/" .. config.chat.dir
  local current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")

  local handle = vim.loop.fs_scandir(chat_dir)
  if not handle then
    vim.notify("[djinni] No chat directory", vim.log.levels.WARN)
    return
  end

  local files = {}
  local parents = {}
  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if ftype == "file" and name:match("%.md$") and name ~= "TASK.md" then
      files[#files + 1] = name
      local f = io.open(chat_dir .. "/" .. name, "r")
      if f then
        local in_fm = false
        local fm_count = 0
        for line in f:lines() do
          if line:match("^%-%-%-$") then
            fm_count = fm_count + 1
            if fm_count == 1 then in_fm = true
            elseif fm_count == 2 then break end
          elseif in_fm then
            local k, v = line:match("^(%w+):%s*(.+)$")
            if k == "parent" then
              parents[name] = v
              break
            end
          end
        end
        f:close()
      end
    end
  end

  local children = {}
  for child, parent in pairs(parents) do
    if not children[parent] then children[parent] = {} end
    children[parent][#children[parent] + 1] = child
  end
  for _, kids in pairs(children) do
    table.sort(kids)
  end

  local function find_root_ancestor(name)
    local seen = {}
    while parents[name] do
      if seen[name] then break end
      seen[name] = true
      name = parents[name]
    end
    return name
  end

  local ancestor = find_root_ancestor(current_file)

  local tree_lines = {}
  local tree_files = {}
  local current_line = 0

  local function render(name, prefix, is_last)
    local connector = is_last and "└─ " or "├─ "
    local marker = name == current_file and "  ◀" or ""
    local line = prefix .. connector .. name:gsub("%.md$", "") .. marker
    tree_lines[#tree_lines + 1] = line
    tree_files[#tree_files + 1] = name
    if name == current_file then current_line = #tree_lines end

    local kids = children[name]
    if kids then
      local child_prefix = prefix .. (is_last and "   " or "│  ")
      for i, child in ipairs(kids) do
        render(child, child_prefix, i == #kids)
      end
    end
  end

  local root_label = ancestor:gsub("%.md$", "")
  local marker = ancestor == current_file and "  ◀" or ""
  tree_lines[#tree_lines + 1] = root_label .. marker
  tree_files[#tree_files + 1] = ancestor
  if ancestor == current_file then current_line = 1 end

  local kids = children[ancestor]
  if kids then
    for i, child in ipairs(kids) do
      render(child, "", i == #kids)
    end
  end

  if #tree_lines <= 1 and not children[ancestor] then
    vim.notify("[djinni] No forks found", vim.log.levels.INFO)
    return
  end

  local width = 0
  for _, l in ipairs(tree_lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.max(width + 4, 30)
  local height = math.min(#tree_lines + 2, 20)

  local title = " Chat Tree "
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, tree_lines)

  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local win = vim.api.nvim_open_win(float_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((ui.width - width) / 2),
    row = math.floor((ui.height - height) / 2),
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  vim.bo[float_buf].buftype = "nofile"
  vim.bo[float_buf].bufhidden = "wipe"
  vim.bo[float_buf].modifiable = false

  local tree_ns = vim.api.nvim_create_namespace("djinni_tree")
  for i, line in ipairs(tree_lines) do
    if line:find("◀") then
      vim.api.nvim_buf_add_highlight(float_buf, tree_ns, "CursorLine", i - 1, 0, -1)
    end
    local conn_end = line:find("[^│├└─ ]")
    if conn_end and conn_end > 1 then
      vim.api.nvim_buf_add_highlight(float_buf, tree_ns, "Comment", i - 1, 0, conn_end - 1)
    end
  end

  if current_line > 0 then
    vim.api.nvim_win_set_cursor(win, { current_line, 0 })
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function open_at_cursor()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local fname = tree_files[row]
    if fname then
      close()
      M.open(chat_dir .. "/" .. fname)
    end
  end

  vim.keymap.set("n", "<CR>", open_at_cursor, { buffer = float_buf, nowait = true })
  vim.keymap.set("n", "q", close, { buffer = float_buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = float_buf, nowait = true })
end

return M
