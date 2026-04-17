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
