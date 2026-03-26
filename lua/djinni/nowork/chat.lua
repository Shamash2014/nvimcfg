local blocks = require("djinni.nowork.blocks")
local input = require("djinni.nowork.input")
local commands = require("djinni.nowork.commands")
local session = require("djinni.acp.session")
local log = require("djinni.nowork.log")
local mcp = require("djinni.nowork.mcp")
local skills = require("djinni.nowork.skills")

local M = {}
M._streaming = {} -- buf -> true when streaming
M._queue = {} -- buf -> { text1, text2, ... }
M._sessions = {} -- buf -> sessionId (in-memory backup)
M._stream_cleanup = {} -- buf -> cleanup function
M._spinner_frame = 0
M._spinner_chars = { "/", "-", "\\", "|" }
M._modes = {} -- buf -> { {id, name}, ... }
M._current_mode = {} -- buf -> mode_id
M._event_handler = {} -- buf -> handler fn
M._perm_handler = {} -- buf -> handler fn
M._last_perm_tool = {} -- buf -> tool description
M._continuation_count = {} -- buf -> number
M._last_tool_failed = {} -- buf -> bool
M._max_continuations = 8
M._plan_path = {} -- buf -> plan file path
M._usage = {} -- buf -> { input_tokens, output_tokens, cost }
M._attached = {} -- buf -> true
M._last_code_buf = nil

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

local function build_session_opts(buf, root)
  local mcp_names = parse_csv(read_frontmatter_field(buf, "mcp"))
  local resolved = mcp.resolve(root, mcp_names)
  local opts = {}
  if next(resolved) then
    opts.mcpServers = resolved
  end
  local model = read_frontmatter_field(buf, "model")
  if model and model ~= "" then
    opts.model = model
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
    "provider: claude-code",
    "model:",
    "mcp: " .. mcp_value,
    "status:",
    "created: " .. iso_timestamp(),
    "---",
    "",
    "@System",
    "Session starting...",
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

  if opts.no_open then
    return filepath
  end

  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  local buf = vim.api.nvim_get_current_buf()
  M.attach(buf)

  local sess_opts = build_session_opts(buf, project_root)
  session.create_task_session(project_root, function(err, sid, result)
    if err or not sid then return end
    M._extract_modes(buf, result)
    M._set_frontmatter_field(buf, "session", sid)
    M._sessions[buf] = sid
    M._streaming[buf] = true
    M._start_streaming(buf)
    local msg = inject_skills(buf, project_root, prompt .. context_refs)
    session.send_message(project_root, sid, msg, function(_err, prompt_result)
      log.info("session/prompt callback: " .. (_err and ("err=" .. vim.inspect(_err)) or "ok"))
      if prompt_result then
        local keys = {}
        for k, _ in pairs(prompt_result) do keys[#keys + 1] = k end
        log.info("prompt_result keys: " .. table.concat(keys, ", "))
        if prompt_result.usage then log.info("usage: " .. vim.inspect(prompt_result.usage)) end
      end
      vim.schedule(function()
        M._accumulate_usage(buf, prompt_result)
        if M._stream_cleanup[buf] then
          M._stream_cleanup[buf]()
        end
      end)
    end)
  end, sess_opts)

  return buf
end

function M.open(file_path)
  local existing = vim.fn.bufnr(file_path)
  if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
    vim.api.nvim_set_current_buf(existing)
    return existing
  end
  vim.cmd("edit! " .. vim.fn.fnameescape(file_path))
  local buf = vim.api.nvim_get_current_buf()
  M.attach(buf)

  local root = M.get_project_root(buf)
  if not root then
    return buf
  end

  local sid = M.get_session_id(buf)
  if sid and sid ~= "" then
    session.get_or_create(root)
  else
    local sess_opts = build_session_opts(buf, root)
    session.create_task_session(root, function(err, new_sid)
      if err or not new_sid then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            M._update_system_block(buf, "Session failed: " .. (err and err.message or "unknown error"))
          end
        end)
        return
      end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        M._set_frontmatter_field(buf, "session", new_sid)
        M._sessions[buf] = new_sid
        local saved_mode = M._current_mode[buf]
        if saved_mode then session.set_mode(root, new_sid, saved_mode) end
        M._update_system_block(buf, "Session ready (ACP)")
      end)
    end, sess_opts)
  end

  return buf
end

local function migrate_unicode(buf)
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

function M.attach(buf)
  if M._attached[buf] then return end
  M._attached[buf] = true
  if vim.bo[buf].filetype ~= "nowork-chat" then
    vim.bo[buf].filetype = "nowork-chat"
  end
  vim.bo[buf].buftype = ""
  vim.bo[buf].fileencoding = "utf-8"
  vim.bo[buf].textwidth = 120
  vim.bo[buf].omnifunc = "v:lua.require'djinni.nowork.commands'.omnifunc"

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = blocks.parse(lines)
  local fm = blocks.get_frontmatter(parsed)
  if fm.plan and fm.plan ~= "" then
    M._plan_path[buf] = fm.plan
  end
  if fm.mode and fm.mode ~= "" then
    M._current_mode[buf] = fm.mode
  end

  migrate_unicode(buf)

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.wo[win].foldmethod = "expr"
    vim.wo[win].foldexpr = "v:lua.require('djinni.nowork.chat').foldexpr(v:lnum)"
    vim.wo[win].foldenable = true
    vim.wo[win].foldlevel = 0
    vim.wo[win].foldminlines = 1
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].statusline = "%{%v:lua.require('djinni.nowork.chat').statusline()%} %f %m"
    vim.wo[win].conceallevel = 2
    local ok, rm = pcall(require, "render-markdown")
    if ok then rm.enable() end
  end

  local function map(mode, lhs, rhs)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, nowait = true })
  end

  map("n", "]]", function()
    M._jump_turn(buf, 1)
  end)
  map("n", "[[", function()
    M._jump_turn(buf, -1)
  end)
  map("n", "<Tab>", "za")
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
  end)
  map("n", "P", function()
    M.select_provider(buf)
  end)
  map("n", "<S-Tab>", function()
    M.pick_mode(buf)
  end)
  map("n", "<C-r>", function()
    M.restart_session(buf)
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
  map("n", "dd", function()
    M._delete_block(buf)
  end)
  map("n", "e", function()
    M._edit_block(buf)
  end)
  map("n", "r", function()
    M._retry_block(buf)
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
    log.show()
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
        new_lines = { "", "---", "", "@You", "", "", "---", "" }
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

  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = buf,
    callback = function()
      M._on_save(buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      local root = M.get_project_root(buf)
      local sid = M.get_session_id(buf) or M._sessions[buf]
      if root then
        if M._event_handler[buf] or M._perm_handler[buf] then
          local ok, client = pcall(session.get_or_create, root)
          if ok and client then
            if M._event_handler[buf] then client:off("session/update", M._event_handler[buf]) end
            if M._perm_handler[buf] then client:off("permission_request", M._perm_handler[buf]) end
          end
        end
        if sid and sid ~= "" then
          session.close_task_session(root, sid)
        end
      end
      M._event_handler[buf] = nil
      M._perm_handler[buf] = nil
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
    end,
  })
end

function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("^- %[") then return "0" end
  if line:match("^- ") then return ">1" end
  if line:match("^  %S") then return "1" end
  if line:match("^> ") then return "1" end
  return "0"
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

function M.quick_input(buf)
  vim.ui.input({ prompt = "Message: " }, function(text)
    if not text or text == "" then return end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local line_count = vim.api.nvim_buf_line_count(buf)
      local you_block = { "", "---", "", "@You", text }
      vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, you_block)

      if M._streaming[buf] then
        if not M._queue[buf] then M._queue[buf] = {} end
        table.insert(M._queue[buf], text)
      else
        M.send(buf, text)
      end
    end)
  end)
end

function M.send(buf, text)
  if not text or text == "" then
    return
  end

  if text ~= "yes, continue" and not text:match("^The previous tool") then
    M._continuation_count[buf] = 0
    M._last_tool_failed[buf] = false
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
  if not sid or sid == "" then
    local sess_opts = build_session_opts(buf, root)
    session.create_task_session(root, function(err, new_sid, result)
      if err or not new_sid then
        vim.schedule(function()
          vim.notify("[djinni] Session failed", vim.log.levels.ERROR)
        end)
        return
      end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        M._extract_modes(buf, result)
        local saved_mode = M._current_mode[buf]
        if saved_mode then session.set_mode(root, new_sid, saved_mode) end
        M._set_frontmatter_field(buf, "session", new_sid)
        M._sessions[buf] = new_sid
        vim.notify("[djinni] Session ready", vim.log.levels.INFO)
        M._streaming[buf] = true
        M._start_streaming(buf)
        local msg = inject_skills(buf, root, text)
        session.send_message(root, new_sid, msg, function(_err, prompt_result)
          vim.schedule(function()
            M._accumulate_usage(buf, prompt_result)
            if M._stream_cleanup[buf] then
              M._stream_cleanup[buf]()
            end
          end)
        end)
      end)
    end, sess_opts)
    return
  end

  M._streaming[buf] = true
  M._start_streaming(buf)
  session.send_message(root, sid, text, function(err, prompt_result)
    log.info("session/prompt callback: " .. (err and ("err=" .. vim.inspect(err)) or "ok"))
    if prompt_result then
      local keys = {}
      for k, _ in pairs(prompt_result) do keys[#keys + 1] = k end
      log.info("prompt_result keys: " .. table.concat(keys, ", "))
      if prompt_result.usage then log.info("usage: " .. vim.inspect(prompt_result.usage)) end
    end
    if err and err.data and err.data.details == "Session not found" then
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if M._stream_cleanup[buf] then
          M._stream_cleanup[buf]()
        end
        M._cleanup_empty_djinni(buf)
        M._sessions[buf] = nil
        M._set_frontmatter_field(buf, "session", "")
        M.send(buf, text)
      end)
    else
      vim.schedule(function()
        M._accumulate_usage(buf, prompt_result)
        if M._stream_cleanup[buf] then
          M._stream_cleanup[buf]()
        end
      end)
    end
  end)
end

function M.interrupt(buf)
  local root = M.get_project_root(buf)
  local sid = M.get_session_id(buf) or M._sessions[buf]
  if root and sid then
    session.interrupt(root, sid)
  end
  if M._stream_cleanup[buf] then
    M._stream_cleanup[buf]()
  else
    M._streaming[buf] = nil
    M._cleanup_empty_djinni(buf)
  end
end

function M._cleanup_empty_djinni(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
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

function M._start_streaming(buf)
  local streaming_lines = { "", "---", "", "@Djinni", "" }
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, streaming_lines)

  local root = M.get_project_root(buf)
  local sid = M.get_session_id(buf) or M._sessions[buf]
  local client = session.get_or_create(root)

  if M._event_handler[buf] then
    client:off("session/update", M._event_handler[buf])
    M._event_handler[buf] = nil
  end
  if M._perm_handler[buf] then
    client:off("permission_request", M._perm_handler[buf])
    M._perm_handler[buf] = nil
  end

  local pending = ""
  local timer = vim.uv.new_timer()
  local handler

  local function cleanup()
    M._streaming[buf] = nil
    M._stream_cleanup[buf] = nil
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if M._event_handler[buf] then
      client:off("session/update", M._event_handler[buf])
      M._event_handler[buf] = nil
    end
    if M._perm_handler[buf] then
      client:off("permission_request", M._perm_handler[buf])
      M._perm_handler[buf] = nil
    end
  end

  local function flush()
    if pending == "" then return end
    local chunk = pending
    pending = ""
    if not vim.api.nvim_buf_is_valid(buf) then
      cleanup()
      return
    end
    M._apply_stream_chunk(buf, chunk)
  end

  M._stream_cleanup[buf] = function()
    if not M._streaming[buf] then return end
    if M._pending_permission and M._pending_permission[buf] then return end
    log.info("stream_cleanup called")
    cleanup()
    flush()
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
    M._cleanup_empty_djinni(buf)
    local last_perm = M._last_perm_tool[buf]
    M._last_perm_tool[buf] = nil
    local count = M._continuation_count[buf] or 0
    local tool_failed = M._last_tool_failed[buf]
    M._last_tool_failed[buf] = false

    local function auto_continue(msg)
      if count >= M._max_continuations then
        log.warn("max continuations (" .. M._max_continuations .. ") reached")
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
        vim.api.nvim_buf_set_lines(buf, lc, lc, false, { "", "---", "", "@You", "", "", "---", "" })
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
        local task_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
        local project = vim.fn.fnamemodify(M.get_project_root(buf) or "", ":t")
        vim.notify("[djinni] Done: " .. task_name .. " (" .. project .. ")", vim.log.levels.INFO)
        if vim.api.nvim_buf_is_valid(buf) then
          local lc = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, lc, lc, false, { "", "---", "", "@You", "", "", "---", "" })
          local win = vim.fn.bufwinid(buf)
          if win ~= -1 then
            vim.api.nvim_win_set_cursor(win, { lc + 5, 0 })
          end
        end
      end, 100)
    end
    M._process_queue(buf)
  end

  timer:start(100, 100, function()
    M._spinner_frame = M._spinner_frame + 1
    vim.schedule(flush)
  end)

  local plan_start_line = nil
  local plan_end_line = nil
  local last_tool_title = nil

  local function append_line(line)
    flush()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local lc = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_buf_set_lines(buf, lc, lc, false, { line })
    end)
  end

  handler = function(data)
    local ok, err = pcall(function()
      if not data then return end
      if data.sessionId and sid and data.sessionId ~= sid then return end

      local update = data.update or data
      local update_type = update.sessionUpdate

      local extra = ""
      if update_type == "tool_call" then
        extra = " title=" .. (update.title or "") .. " kind=" .. (update.kind or "")
      elseif update_type == "tool_call_update" then
        extra = " status=" .. (update.status or "") .. " title=" .. (update.title or "") .. " kind=" .. (update.kind or "")
      end
      log.dbg("event: " .. (update_type or "nil") .. extra)

      if update_type == "agent_message_chunk" then
        local text = update.content and update.content.text
        if text then
          pending = pending .. text
        end

      elseif update_type == "agent_thought_chunk" then
        local text = update.content and update.content.text
        if text then
          pending = pending .. text
        end

      elseif update_type == "tool_call" then
        local kind = update.kind or ""
        local is_think = kind:lower() == "think" or kind:lower() == "thinking"
        if is_think then
          append_line("")
          append_line("**Thinking...**")
        else
          local title = update.title or kind
          append_line("- " .. title)
        end

      elseif update_type == "tool_call_update" then
        local kind = update.kind or ""
        local is_think = kind:lower() == "think" or kind:lower() == "thinking"
        local status = update.status or ""
        local title = update.title or ""
        if title ~= "" then last_tool_title = title end
        if status == "failed" then
          M._last_tool_failed[buf] = true
        elseif status == "completed" then
          M._last_tool_failed[buf] = false
        end

        if is_think then
          if status == "completed" then
            local text = nil
            if type(update.content) == "table" then
              if update.content.text then
                text = update.content.text
              elseif #update.content > 0 then
                for _, c in ipairs(update.content) do
                  if c.content and c.content.text then
                    text = (text or "") .. c.content.text
                  end
                end
              end
            end
            if text then
              for line in text:gmatch("([^\n]+)") do
                append_line("> " .. line)
              end
              append_line("")
            end
          end
        else
          local text = nil
          if type(update.content) == "table" then
            if update.content.text then
              text = tostring(update.content.text):gsub("\n", " "):sub(1, 80)
            elseif #update.content > 0 then
              for _, c in ipairs(update.content) do
                if c.content and c.content.text then
                  text = tostring(c.content.text):gsub("\n", " "):sub(1, 80)
                  break
                end
              end
            end
          end
          if status == "completed" then
            local file_path = nil
            if type(update.content) == "table" then
              for _, c in ipairs(update.content) do
                if c.path then file_path = c.path; break end
              end
            end
            if not file_path and update.rawInput then
              file_path = update.rawInput.file_path or update.rawInput.filePath
            end
            if not file_path and update.locations and update.locations[1] then
              file_path = update.locations[1].path
            end
            if not file_path and last_tool_title then
              file_path = last_tool_title:match("(/%S+%.[%w]+)")
            end
            log.dbg("tool completed: path=" .. (file_path or "nil") .. " from_title=" .. (last_tool_title or ""))
            last_tool_title = nil
            if file_path then
              if file_path:match("plans/") and file_path:match("%.md$") and vim.fn.filereadable(file_path) == 1 then
                M._plan_path[buf] = file_path
                M._set_frontmatter_field(buf, "plan", file_path)
                vim.schedule(function()
                  if vim.api.nvim_buf_is_valid(buf) then
                    M._update_plan_section(buf)
                  end
                end)
              else
                append_line("  " .. file_path)
              end
            elseif text and text ~= "" then
              append_line("  " .. text)
            elseif last_tool_title then
              append_line("  done")
            end
          elseif status == "error" then
            append_line("  error: " .. (text or ""))
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

        flush()
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          if plan_start_line and plan_end_line then
            pcall(vim.api.nvim_buf_set_lines, buf, plan_start_line, plan_end_line, false, plan_lines)
            plan_end_line = plan_start_line + #plan_lines
          else
            local lc = vim.api.nvim_buf_line_count(buf)
            plan_start_line = lc
            vim.api.nvim_buf_set_lines(buf, lc, lc, false, plan_lines)
            plan_end_line = lc + #plan_lines
          end
        end)
      end

    elseif update_type == "usage_update" then
      log.info("usage_update: " .. vim.inspect(update))
      M._accumulate_usage(buf, update)

    elseif update_type == "result" then
      local usage = update.tokenUsage or update.usage
      local cost_val = update.costUSD or update.cost or update.totalCost
      if usage or cost_val then
        M._accumulate_usage(buf, { tokenUsage = usage, cost = cost_val })
      end
    end
    end) -- pcall

    if not ok then
      vim.schedule(function()
        -- handler error silenced
      end)
    end

    -- Completion is handled by session/prompt callback, not by session/update events
  end

  M._event_handler[buf] = handler
  session.on_event(root, "session/update", handler)

  local kind_labels = {
    allow_once = "Allow",
    allow_always = "Always",
    reject_once = "Deny",
    reject_always = "Never",
  }

  local perm_handler = function(params, respond)
    if params.sessionId and sid and params.sessionId ~= sid then return end
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
      tool_desc = params.toolCall.title or params.toolCall.kind or "tool"
      tool_kind = params.toolCall.kind or ""
    end
    local options = {}
    local option_labels = {}
    if params.options then
      for _, opt in ipairs(params.options) do
        local id = opt.optionId or opt.kind or ""
        local kind = opt.kind or ""
        local label = opt.name or kind_labels[kind] or opt.label or id
        table.insert(options, { id = id, kind = kind, label = label })
        table.insert(option_labels, "[" .. label .. "]")
      end
    end

    flush()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      vim.notify("[djinni] Permission: " .. tool_desc, vim.log.levels.WARN)
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
      M._pending_permission[buf] = { respond = respond, options = options, tool_desc = tool_desc, tool_kind = tool_kind }
    end)
  end
  M._perm_handler[buf] = perm_handler
  session.on_event(root, "permission_request", perm_handler)
end

function M._process_queue(buf)
  if not M._queue[buf] or #M._queue[buf] == 0 then return end
  if not vim.api.nvim_buf_is_valid(buf) then
    M._queue[buf] = nil
    return
  end
  local text = table.remove(M._queue[buf], 1)
  if #M._queue[buf] == 0 then M._queue[buf] = nil end
  M.send(buf, text)
end

function M._apply_stream_chunk(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ""

  local new_lines = {}
  for line in (last_line .. text):gmatch("([^\n]*)") do
    new_lines[#new_lines + 1] = line
  end

  if #new_lines > 0 then
    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, new_lines)
  end

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_count = vim.api.nvim_buf_line_count(buf)
    if cursor[1] >= line_count - 5 then
      vim.api.nvim_win_set_cursor(win, { line_count, 0 })
    end
  end
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

function M._set_frontmatter_field(buf, key, value)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local closing_idx = nil
  for i, line in ipairs(lines) do
    if i == 1 and line == "---" then
      goto continue
    end
    if line == "---" then
      closing_idx = i
      break
    end
    local k = line:match("^([%w_]+):")
    if k == key then
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { key .. ": " .. value })
      return
    end
    ::continue::
  end
  if closing_idx then
    vim.api.nvim_buf_set_lines(buf, closing_idx - 1, closing_idx - 1, false, { key .. ": " .. value })
  end
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

function M.restart_session(buf)
  local root = M.get_project_root(buf)
  if not root then
    return
  end

  local old_sid = M.get_session_id(buf) or M._sessions[buf]
  mcp.clear_cache(root)
  session.shutdown_project(root)

  local sess_opts = build_session_opts(buf, root)
  local msg = old_sid and old_sid ~= "" and "Restarting process (resuming session)..." or "Restarting session..."
  local lines = { "", "---", "", "@System", msg, "" }
  input.insert_above_separator(buf, lines)

  if old_sid and old_sid ~= "" then
    session.load_task_session(root, old_sid, function(err, _result)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if err then
          M._set_frontmatter_field(buf, "session", "")
          M._sessions[buf] = nil
          M._update_system_block(buf, "Resume failed, creating new session...")
          session.create_task_session(root, function(err2, new_sid)
            vim.schedule(function()
              if not vim.api.nvim_buf_is_valid(buf) then return end
              if err2 or not new_sid then
                M._update_system_block(buf, "Session failed: " .. (err2 and err2.message or "unknown"))
                return
              end
              M._set_frontmatter_field(buf, "session", new_sid)
              M._sessions[buf] = new_sid
              M._update_system_block(buf, "Session ready (ACP)")
              vim.notify("[djinni] Session ready", vim.log.levels.INFO)
            end)
          end, sess_opts)
          return
        end
        M._update_system_block(buf, "Session resumed (ACP)")
        vim.notify("[djinni] Session resumed", vim.log.levels.INFO)
      end)
    end)
  else
    session.create_task_session(root, function(err, new_sid)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if err or not new_sid then
          M._update_system_block(buf, "Session failed: " .. (err and err.message or "unknown"))
          return
        end
        M._set_frontmatter_field(buf, "session", new_sid)
        M._sessions[buf] = new_sid
        M._update_system_block(buf, "Session ready (ACP)")
        vim.notify("[djinni] Session ready", vim.log.levels.INFO)
      end)
    end, sess_opts)
  end
end

function M.select_provider(buf)
  local Provider = require("djinni.acp.provider")
  local providers = Provider.list()

  vim.ui.select(providers, { prompt = "Select provider:" }, function(choice)
    if not choice then return end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local root = M.get_project_root(buf)
      if root then
        session.shutdown_project(root)
      end
      M._set_frontmatter_field(buf, "provider", choice)
      M._set_frontmatter_field(buf, "session", "")

      local lines = { "", "---", "", "@System", "Provider changed to " .. choice, "" }
      input.insert_above_separator(buf, lines)

      if root then
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
            end
          end)
        end)
      end
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
    session.set_mode(root, sid, mode.id)
    M._current_mode[buf] = mode.id
    M._set_frontmatter_field(buf, "mode", mode.id)
    local icons = { plan = "📋", spec = "📝", auto = "🤖", code = "💻", chat = "💬", execute = "▶️" }
    local icon = icons[mode.id] or "↻"
    local name = mode.displayName or mode.name or mode.id
    vim.notify(icon .. " " .. name, vim.log.levels.INFO)
  end
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

function M._edit_block(_buf) end

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

  M.send(buf, you_text)
end

function M._permission_action(buf, action)
  if not M._pending_permission or not M._pending_permission[buf] then
    vim.notify("[djinni] No pending permission", vim.log.levels.WARN)
    return
  end

  local perm = M._pending_permission[buf]

  if action == "select" then
    local labels = {}
    for _, opt in ipairs(perm.options) do
      table.insert(labels, opt.label)
    end
    vim.ui.select(labels, { prompt = "Permission:" }, function(choice, idx)
      if not choice or not idx then return end
      M._pending_permission[buf] = nil
      perm.respond({ outcome = { outcome = "selected", optionId = perm.options[idx].id } })
      local lc = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_buf_set_lines(buf, lc, lc, false, { "", "@System", "OK:" .. choice, "" })
    end)
    return
  end

  M._pending_permission[buf] = nil

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

  M._last_perm_tool[buf] = { desc = perm.tool_desc, kind = perm.tool_kind, action = selected_kind }
  log.info("permission response: " .. option_id .. " tool=" .. (perm.tool_desc or "?") .. " kind=" .. (perm.tool_kind or "?"))
  local ok_resp, resp_err = pcall(perm.respond, {
    outcome = {
      outcome = "selected",
      optionId = option_id,
    },
  })
  if not ok_resp then
    log.err("respond failed: " .. tostring(resp_err))
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        M.send(buf, "yes, continue")
      end
    end, 100)
  else
    log.info("respond sent OK")
  end

  local lc = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
    "",
    "@System",
    "OK:" .. (kind_labels[selected_kind] or option_id),
    "",
  })

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then
      M.send(buf, "yes, continue")
    end
  end, 500)
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
    if modes.availableModes then
      M._modes[buf] = modes.availableModes
      log.info("modes received: " .. #modes.availableModes .. " modes")
    end
    if modes.currentModeId then
      M._current_mode[buf] = modes.currentModeId
      M._set_frontmatter_field(buf, "mode", modes.currentModeId)
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
  return text
end

function M._accumulate_usage(buf, result)
  if not result then return end
  local u = M._usage[buf] or { input_tokens = 0, output_tokens = 0, cost = 0 }
  local tok = result.tokenUsage or result.usage or {}
  u.input_tokens = u.input_tokens + (tok.inputTokens or tok.input_tokens or 0)
  u.output_tokens = u.output_tokens + (tok.outputTokens or tok.output_tokens or 0)
  if result.costUSD then
    u.cost = u.cost + (tonumber(result.costUSD) or 0)
  elseif result.cost then
    u.cost = u.cost + (tonumber(result.cost) or 0)
  elseif result.totalCost then
    u.cost = u.cost + (tonumber(result.totalCost) or 0)
  end
  M._usage[buf] = u
end

function M.statusline()
  local buf = vim.api.nvim_get_current_buf()
  local mode = M._current_mode[buf]
  local mode_str = mode and (" [" .. mode .. "]") or ""
  local usage = M._usage[buf]
  local usage_str = ""
  if usage and usage.cost and usage.cost > 0 then
    usage_str = string.format(" $%.2f", usage.cost)
  elseif usage and (usage.input_tokens + usage.output_tokens) > 0 then
    local total_k = (usage.input_tokens + usage.output_tokens) / 1000
    usage_str = string.format(" %.1fk", total_k)
  end
  if not M._streaming[buf] then
    if mode or usage_str ~= "" then return "djinni" .. mode_str .. usage_str end
    return ""
  end
  local idx = (M._spinner_frame % #M._spinner_chars) + 1
  return "djinni" .. mode_str .. " " .. M._spinner_chars[idx] .. usage_str
end

return M
