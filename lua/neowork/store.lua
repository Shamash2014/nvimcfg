local M = {}

local config = require("neowork.config")
local const = require("neowork.const")

function M.ensure_dirs(root)
  local neowork_dir = config.get_neowork_dir(root)
  local transcripts_dir = config.get_transcripts_dir(root)
  local archive_dir = config.get_archive_dir(root)
  vim.fn.mkdir(neowork_dir, "p")
  vim.fn.mkdir(transcripts_dir, "p")
  vim.fn.mkdir(archive_dir, "p")
end

function M.append_event(session_id, root, event)
  if not session_id or session_id == "" then
    return
  end
  local transcripts_dir = config.get_transcripts_dir(root)
  local path = transcripts_dir .. "/" .. session_id .. ".jsonl"
  event.ts = event.ts or os.date("!%Y-%m-%dT%H:%M:%SZ")
  local line = vim.json.encode(event)
  local fd = io.open(path, "a")
  if not fd then return end
  fd:write(line .. "\n")
  fd:close()
end

function M.read_transcript(session_id, root)
  local transcripts_dir = config.get_transcripts_dir(root)
  local path = transcripts_dir .. "/" .. session_id .. ".jsonl"
  local fd = io.open(path, "r")
  if not fd then
    return {}
  end
  local events = {}
  for line in fd:lines() do
    if line ~= "" then
      local ok, event = pcall(vim.json.decode, line)
      if ok then
        table.insert(events, event)
      end
    end
  end
  fd:close()
  return events
end

function M.clear_transcript(session_id, root)
  if not session_id or session_id == "" then return false end
  local transcripts_dir = config.get_transcripts_dir(root)
  local path = transcripts_dir .. "/" .. session_id .. ".jsonl"
  return vim.fn.delete(path) == 0
end

function M.transcript_exists(session_id, root)
  local transcripts_dir = config.get_transcripts_dir(root)
  local path = transcripts_dir .. "/" .. session_id .. ".jsonl"
  return vim.fn.filereadable(path) == 1
end

M._scan_cache = {}
M._last_turn_cache = {}
M._last_action_cache = {}

local function first_line(text)
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then return trimmed end
  end
  return ""
end

function M.get_last_agent_turn(session_id, root)
  if not session_id or session_id == "" then return nil end
  local transcripts_dir = config.get_transcripts_dir(root)
  local path = transcripts_dir .. "/" .. session_id .. ".jsonl"
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil end
  local key = path
  local cached = M._last_turn_cache[key]
  if cached and cached.mtime == stat.mtime.sec then return cached.turn end
  local fd = io.open(path, "r")
  if not fd then return nil end
  local last_line = nil
  for line in fd:lines() do
    if line ~= "" and (line:find('"type":"assistant"', 1, true) or line:find('"type":"agent_message"', 1, true)) then
      last_line = line
    end
  end
  fd:close()
  local turn
  if last_line then
    local ok, ev = pcall(vim.json.decode, last_line)
    if ok and ev and (ev.type == "assistant" or ev.type == "agent_message") then
      turn = first_line(ev.content)
    end
  end
  M._last_turn_cache[key] = { mtime = stat.mtime.sec, turn = turn }
  return turn
end

local function short(text, n)
  n = n or 80
  local s = first_line(text)
  if #s > n then s = s:sub(1, n - 1) .. "…" end
  return s
end

local function derive_action(ev)
  local t = ev.type or ev.sessionUpdate or ""
  if t == "tool_call" or t == "tool_call_update" then
    local name = ev.title or ev.name or (ev.tool and (ev.tool.name or ev.tool.kind)) or ev.kind or "tool"
    local sum = short(ev.rawInput and (ev.rawInput.command or ev.rawInput.path or ev.rawInput.description)
      or ev.content or ev.title or name)
    return { kind = "tool", summary = "→ " .. tostring(name) .. (sum ~= "" and sum ~= name and ("  " .. sum) or "") }
  end
  if t == "plan" then
    local entries = ev.entries or ev.plan or {}
    local pending = 0
    for _, e in ipairs(entries) do
      if (e.status or "") ~= "completed" then pending = pending + 1 end
    end
    return { kind = "plan", summary = "✎ plan · " .. tostring(#entries) .. " steps (" .. pending .. " pending)" }
  end
  if t == "assistant" or t == "agent_message" or t == "agent_message_chunk" then
    return { kind = "message", summary = "» " .. short(ev.content) }
  end
  if t == "agent_thought_chunk" or t == "thinking" then
    return { kind = "thinking", summary = "… " .. short(ev.content) }
  end
  if t == "error" then
    return { kind = "error", summary = "⚠ " .. short(ev.content or ev.message) }
  end
  return nil
end

function M.get_last_action(session_id, root)
  if not session_id or session_id == "" then return nil end
  local transcripts_dir = config.get_transcripts_dir(root)
  local path = transcripts_dir .. "/" .. session_id .. ".jsonl"
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil end
  local key = path
  local cached = M._last_action_cache[key]
  if cached and cached.mtime == stat.mtime.sec then return cached.action end
  local fd = io.open(path, "r")
  if not fd then return nil end
  local lines = {}
  for line in fd:lines() do
    if line ~= "" then lines[#lines + 1] = line end
  end
  fd:close()
  local action
  for i = #lines, 1, -1 do
    local ok, ev = pcall(vim.json.decode, lines[i])
    if ok and ev and ev.type ~= "user" and ev.type ~= "result" then
      local a = derive_action(ev)
      if a then action = a; break end
    end
  end
  M._last_action_cache[key] = { mtime = stat.mtime.sec, action = action }
  return action
end

function M.get_current_plan(session_id, root)
  if not session_id or session_id == "" then return nil end
  local transcripts_dir = config.get_transcripts_dir(root)
  local path = transcripts_dir .. "/" .. session_id .. ".jsonl"
  local fd = io.open(path, "r")
  if not fd then return nil end
  local lines = {}
  for line in fd:lines() do
    if line ~= "" then lines[#lines + 1] = line end
  end
  fd:close()
  for i = #lines, 1, -1 do
    local ok, ev = pcall(vim.json.decode, lines[i])
    if ok and ev and (ev.type == "plan" or ev.sessionUpdate == "plan") then
      return ev.entries or ev.plan or {}
    end
  end
  return nil
end

function M.scan_sessions(root)
  local neowork_dir = config.get_neowork_dir(root)
  local files = vim.fn.glob(neowork_dir .. "/*.md", false, true)
  local sessions = {}
  local seen = {}
  for _, filepath in ipairs(files) do
    local stat = vim.uv.fs_stat(filepath)
    if stat then
      local mtime = stat.mtime.sec
      local cached = M._scan_cache[filepath]
      local meta
      if cached and cached.mtime == mtime then
        meta = cached.meta
      else
        meta = M.read_frontmatter(filepath)
        if meta then
          meta._filepath = vim.fn.fnamemodify(filepath, ":p")
          meta._slug = vim.fn.fnamemodify(filepath, ":t:r")
          M._scan_cache[filepath] = { mtime = mtime, meta = meta }
        end
      end
      if meta then
        sessions[#sessions + 1] = meta
        seen[filepath] = true
      end
    end
  end
  for path in pairs(M._scan_cache) do
    if not seen[path] then M._scan_cache[path] = nil end
  end
  return sessions
end

function M.read_frontmatter(filepath)
  return require("neowork.frontmatter").read_file(filepath)
end

function M.write_session_file(root, slug, meta)
  M.ensure_dirs(root)
  local neowork_dir = config.get_neowork_dir(root)
  local filepath = neowork_dir .. "/" .. slug .. ".md"
  local lines = {
    "---",
    "project: " .. (meta.project or ""),
    "root: " .. (meta.root or root),
    "session: " .. (meta.session or ""),
    "provider: " .. (meta.provider or config.get("provider")),
    "model: " .. (meta.model or config.get("model")),
    "status: " .. (meta.status or const.session_status.idle),
    "created: " .. (meta.created or os.date("!%Y-%m-%dT%H:%M:%SZ")),
    "tokens: " .. (meta.tokens or "0"),
    "cost: " .. (meta.cost or "0.00"),
    "summary: " .. (meta.summary or ""),
    "parent: " .. (meta.parent or ""),
    "schedule_enabled: " .. (meta.schedule_enabled or "false"),
    "schedule_interval: " .. (meta.schedule_interval or ""),
    "schedule_command: " .. (meta.schedule_command or ""),
    "schedule_next_run: " .. (meta.schedule_next_run or ""),
    "schedule_last_run: " .. (meta.schedule_last_run or ""),
    "schedule_run_count: " .. (meta.schedule_run_count or "0"),
    "schedule_last_error: " .. (meta.schedule_last_error or ""),
    "---",
    "",
    const.role.system,
    meta.system or "Session starting...",
    "",
    "---",
    "",
    const.role.user,
    "",
    "---",
  }
  local fd = io.open(filepath, "w")
  if not fd then return nil end
  fd:write(table.concat(lines, "\n") .. "\n")
  fd:close()
  return filepath
end

function M.archive_session(root, slug)
  local src = config.get_neowork_dir(root) .. "/" .. slug .. ".md"
  local dst = config.get_archive_dir(root) .. "/" .. slug .. ".md"
  return vim.fn.rename(src, dst) == 0
end

function M.delete_session(root, slug)
  local filepath = config.get_neowork_dir(root) .. "/" .. slug .. ".md"
  return vim.fn.delete(filepath) == 0
end

function M.rename_session(root, old_slug, new_slug)
  local neowork_dir = config.get_neowork_dir(root)
  local dst = neowork_dir .. "/" .. new_slug .. ".md"
  if vim.fn.filereadable(dst) == 1 then return false end
  return vim.fn.rename(neowork_dir .. "/" .. old_slug .. ".md", dst) == 0
end

return M
