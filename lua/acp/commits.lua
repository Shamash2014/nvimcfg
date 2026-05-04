local M = {}

local function thread_jsonl(cwd, file, row)
  local safe = (file:gsub("[/\\:*?\"<>|%s]", "_"))
  return cwd .. "/.nowork/threads/" .. safe .. "@" .. tostring(row) .. ".jsonl"
end

local function harvest_paths(t)
  local seen, out = {}, {}
  local function add(p)
    if type(p) ~= "string" or p == "" or seen[p] then return end
    seen[p] = true
    table.insert(out, p)
  end
  for _, m in ipairs((t and t.messages) or {}) do
    if m.type == "tool_call" or m.type == "tool_call_update" then
      local call = m.call or {}
      for _, loc in ipairs(call.locations or {}) do add(loc.path) end
      local raw = call.rawInput or call.arguments
      if type(raw) == "table" then
        add(raw.path); add(raw.file_path); add(raw.filePath)
        add(raw.target); add(raw.targetPath); add(raw.source); add(raw.sourcePath)
        if type(raw.paths) == "table" then for _, p in ipairs(raw.paths) do add(p) end end
      end
    end
    local txt = m.text
    if type(txt) == "string" then
      for p in txt:gmatch("[%w_%./%-]+%.[%w]+") do
        if p:find("/") then add(p) end
      end
    end
  end
  return out
end

local function iso(ts) return os.date("!%Y-%m-%dT%H:%M:%SZ", ts) end

local function commits_since(cwd, mtime)
  local out = vim.fn.systemlist({ "git", "-C", cwd, "rev-list", "--count",
                                  "HEAD", "--since=" .. iso(mtime) })
  if vim.v.shell_error ~= 0 then return 0 end
  return tonumber(out[1] or "0") or 0
end

function M.thread_age(cwd, file, row)
  local mt = vim.fn.getftime(thread_jsonl(cwd, file, row))
  if not mt or mt <= 0 then return { is_past = false, n_since = 0, mtime = nil } end
  local n = commits_since(cwd, mt)
  return { is_past = n > 0, n_since = n, mtime = mt }
end

local function thread_window(cwd, file, row, t)
  local lo, hi
  if t and t.created_at then lo = t.created_at end
  if t and t.updated_at then hi = t.updated_at end
  if not (lo and hi) then
    local mt = vim.fn.getftime(thread_jsonl(cwd, file, row))
    if mt and mt > 0 then
      hi = hi or iso(mt + 3600)
      lo = lo or iso(mt - 86400)
    end
  end
  return lo, hi
end

local function list_commits(cwd, since, until_, paths)
  local cmd = { "git", "-C", cwd, "log",
    "--pretty=format:%h%x09%cI%x09%s",
    "--no-merges", "-n", "200" }
  if since   then table.insert(cmd, "--since=" .. since)   end
  if until_  then table.insert(cmd, "--until=" .. until_)  end
  if paths and #paths > 0 then
    table.insert(cmd, "--")
    for _, p in ipairs(paths) do table.insert(cmd, p) end
  end
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then return {} end
  local commits = {}
  for _, line in ipairs(out) do
    local sha, ts, subj = line:match("^(%w+)\t(%S+)\t(.*)$")
    if sha then table.insert(commits, { sha = sha, ts = ts, subject = subj or "" }) end
  end
  return commits
end

local function show_buf(cwd, sha)
  local name = "acp-commit-" .. sha
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):find(name, 1, true) then return b end
  end
  local out = vim.fn.systemlist({ "git", "-C", cwd, "show", "--stat", "-p", sha })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile  = false
  vim.bo[buf].filetype  = "diff"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable = false
  return buf
end

function M.open_log(cwd, file, row, opts)
  opts = opts or {}
  local diff = require("acp.diff")
  local t    = diff.get_thread(cwd, file, row)
  local age  = M.thread_age(cwd, file, row)
  if opts.auto and not age.is_past then return end
  if opts.auto and diff.is_thread_active and diff.is_thread_active(t) then return end
  local since, until_ = thread_window(cwd, file, row, t)
  local paths   = harvest_paths(t)
  local commits = list_commits(cwd, since, until_, paths)
  if #commits == 0 and #paths > 0 then
    commits = list_commits(cwd, since, until_, nil)
  end
  if #commits == 0 then
    if not opts.auto then
      vim.notify("No commits in thread window", vim.log.levels.INFO, { title = "acp" })
    end
    return
  end

  local lines, sha_at = {}, {}
  for i, c in ipairs(commits) do
    local short_ts = c.ts:sub(1, 16):gsub("T", " ")
    lines[i]  = string.format("%s  %s  %s", c.sha, short_ts, c.subject)
    sha_at[i] = c.sha
  end

  local log_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(log_buf, "acp-commits-" .. file .. "@" .. tostring(row))
  vim.bo[log_buf].buftype   = "nofile"
  vim.bo[log_buf].bufhidden = "wipe"
  vim.bo[log_buf].swapfile  = false
  vim.bo[log_buf].filetype  = "git"
  vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, lines)
  vim.bo[log_buf].modifiable = false

  vim.cmd("topleft vsplit")
  vim.api.nvim_set_current_buf(log_buf)
  vim.api.nvim_win_set_width(0, 64)
  local log_win = vim.api.nvim_get_current_win()
  local age = M.thread_age(cwd, file, row)
  local past_tag = age.is_past
    and ("%#WarningMsg# from past · " .. age.n_since .. " commit" ..
         (age.n_since == 1 and "" or "s") .. " since ")
    or ""
  vim.wo[log_win].winbar = "%#AcpWinbarText#  commits  " .. past_tag .. "%*"

  local diff_win
  local function render_current()
    local lnum = vim.api.nvim_win_get_cursor(log_win)[1]
    local sha  = sha_at[lnum]
    if not sha then return end
    local dbuf = show_buf(cwd, sha)
    if not (diff_win and vim.api.nvim_win_is_valid(diff_win)) then
      vim.api.nvim_set_current_win(log_win)
      vim.cmd("rightbelow vsplit")
      diff_win = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_win_set_buf(diff_win, dbuf)
    vim.wo[diff_win].winbar = "%#AcpWinbarText#  diff  " .. past_tag ..
                              "%#Comment#" .. sha .. " %*"
    vim.api.nvim_set_current_win(log_win)
  end

  local function step(delta)
    local cur = vim.api.nvim_win_get_cursor(log_win)[1]
    local n   = vim.api.nvim_buf_line_count(log_buf)
    local nxt = math.max(1, math.min(n, cur + delta))
    vim.api.nvim_win_set_cursor(log_win, { nxt, 0 })
    render_current()
  end

  local function km(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = log_buf, nowait = true, silent = true, noremap = true })
  end
  km("<CR>", render_current)
  km("j",    function() step( 1) end)
  km("k",    function() step(-1) end)
  km("]c",   function() step( 1) end)
  km("[c",   function() step(-1) end)
  km("q", function()
    if diff_win and vim.api.nvim_win_is_valid(diff_win) then
      pcall(vim.api.nvim_win_close, diff_win, true)
    end
    pcall(vim.api.nvim_win_close, log_win, true)
  end)

  render_current()
end

return M
