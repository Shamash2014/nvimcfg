local M = {}

local STATE_SCHEMA_VERSION = 1

local function logs_dir_for(cwd)
  cwd = cwd or vim.fn.getcwd()
  return cwd .. "/.nowork/logs"
end

local function logs_dir()
  return logs_dir_for(vim.fn.getcwd())
end

local function sidecar_path(log_path)
  if not log_path then return nil end
  if log_path:match("%.log$") then
    return (log_path:gsub("%.log$", ".state.json"))
  end
  return log_path .. ".state.json"
end

local function fs_exists(path)
  if not path then return false end
  local ok, stat = pcall(vim.loop.fs_stat, path)
  return ok and stat ~= nil
end

local function archive_root(path)
  if not path or path == "" then return nil end
  local root = path:match("^(.-)/%.nowork/")
  if not root or root == "" then return nil end
  return vim.uv.fs_realpath(root) or vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
end

local function as_object(tbl)
  if tbl == nil then return vim.empty_dict() end
  if type(tbl) ~= "table" then return vim.empty_dict() end
  if next(tbl) == nil then return vim.empty_dict() end
  return tbl
end

local function serialize_state(droid)
  local st = droid.state or {}
  local opts = droid.opts or {}
  local tasks_copy = {}
  for id, t in pairs(st.tasks or {}) do
    tasks_copy[id] = {
      id = t.id or id,
      desc = t.desc,
      deps = t.deps or {},
      subtasks = t.subtasks or {},
      acceptance = t.acceptance or {},
      status = t.status or "open",
    }
  end
  return {
    v = STATE_SCHEMA_VERSION,
    id = droid.id,
    mode = droid.mode,
    initial_prompt = droid.initial_prompt,
    started_at = droid.started_at,
    status = droid.status,
    phase = st.phase,
    current_task_id = st.current_task_id,
    turns_on_task = st.turns_on_task or 0,
    tasks = as_object(tasks_copy),
    topo_order = st.topo_order or {},
    sprint_retries = as_object(st.sprint_retries),
    eval_feedback = as_object(st.eval_feedback),
    sticky_permissions = as_object(st.sticky_permissions),
    opts = {
      cwd = opts.cwd,
      provider_name = droid.provider_name,
      allow_kinds = opts.allow_kinds or {},
      turns_per_task_cap = opts.turns_per_task_cap,
      sprint_retry_cap = opts.sprint_retry_cap,
      grade_threshold = opts.grade_threshold,
      test_cmd = opts.test_cmd,
      skills = opts.skills or {},
    },
  }
end

function M.write_state(droid)
  if not droid or not droid._log_path then return nil end
  local path = sidecar_path(droid._log_path)
  if not path then return nil end
  local ok_enc, encoded = pcall(vim.json.encode, serialize_state(droid))
  if not ok_enc or type(encoded) ~= "string" then return nil end
  local tmp = path .. ".tmp"
  local fh = io.open(tmp, "w")
  if not fh then return nil end
  local ok = pcall(function()
    fh:write(encoded)
    fh:close()
  end)
  if not ok then pcall(function() fh:close() end); os.remove(tmp); return nil end
  if not os.rename(tmp, path) then
    os.remove(tmp)
    return nil
  end
  return path
end

function M.state_path(log_path)
  return sidecar_path(log_path)
end

function M.read_state(log_path)
  local path = sidecar_path(log_path)
  if not path or not fs_exists(path) then return nil, "missing" end
  local fh = io.open(path, "r")
  if not fh then return nil, "open failed" end
  local raw = fh:read("*a") or ""
  fh:close()
  if raw == "" then return nil, "empty" end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then return nil, "decode failed" end
  if decoded.v ~= STATE_SCHEMA_VERSION then
    return nil, "schema v" .. tostring(decoded.v) .. " unsupported (expected v" .. STATE_SCHEMA_VERSION .. ")"
  end
  return decoded, nil
end

function M.write(droid)
  if not droid or not droid.log_buf or not droid.log_buf.buf then return end
  if not vim.api.nvim_buf_is_valid(droid.log_buf.buf) then return end
  local lines = vim.api.nvim_buf_get_lines(droid.log_buf.buf, 0, -1, false)
  if #lines == 0 then return end
  local ts = os.time()
  local date = os.date("%Y-%m-%d", ts)
  local stamp = os.date("%H%M%S", ts)
  local base = logs_dir_for(droid.opts and droid.opts.cwd)
  local dir = base .. "/" .. date
  vim.fn.mkdir(dir, "p")
  local safe_mode = (droid.mode or "unknown"):gsub("[^%w_]", "_")
  local safe_id = tostring(droid.id or "unknown"):gsub("[^%w_]", "_")
  local path = ("%s/%s-%s-%s.log"):format(dir, stamp, safe_id, safe_mode)
  local fh = io.open(path, "w")
  if not fh then return end
  fh:write(table.concat(lines, "\n"))
  fh:close()
  return path
end

local function collect_from(root, max_days, seen, out)
  if vim.fn.isdirectory(root) == 0 then return end
  local dates = vim.fn.readdir(root) or {}
  table.sort(dates, function(a, b) return a > b end)
  for i, date in ipairs(dates) do
    if i > max_days then break end
    local dir = root .. "/" .. date
    for _, fname in ipairs(vim.fn.readdir(dir) or {}) do
      local stamp, id, mode = fname:match("^(%d+)-(.-)-(.-)%.log$")
      if stamp then
        local path = dir .. "/" .. fname
        if not seen[path] then
          seen[path] = true
          out[#out + 1] = {
            path = path,
            date = date,
            stamp = stamp,
            id = id,
            mode = mode,
            cwd = root:gsub("/%.nowork/logs$", ""),
            has_state = fs_exists(sidecar_path(path)),
          }
        end
      end
    end
  end
end

function M.list(max_days, extra_roots)
  max_days = max_days or 14
  local out, seen = {}, {}
  collect_from(logs_dir(), max_days, seen, out)
  if extra_roots then
    for _, cwd in ipairs(extra_roots) do
      if cwd and cwd ~= "" then
        collect_from(logs_dir_for(cwd), max_days, seen, out)
      end
    end
  end
  return out
end

function M.prompt_hint(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local hint = nil
  for _ = 1, 20 do
    local line = fh:read("*l")
    if not line then break end
    local p = line:match("^%[prompt%] (.*)$")
    if p then hint = p; break end
  end
  fh:close()
  return hint
end

local function send_to_qflist(buf, path, mode, l1, l2)
  local parser = require("djinni.nowork.parser")
  local qfix = require("djinni.nowork.qfix")
  local cwd = vim.b[buf].nowork_cwd
  if not cwd or cwd == "" then
    cwd = path:match("^(.-)/%.nowork/logs/")
  end
  local base_line = 0
  local lines
  if l1 and l2 then
    lines = vim.api.nvim_buf_get_lines(buf, l1 - 1, l2, false)
    base_line = l1 - 1
  else
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  local items = parser.parse_with_sections(table.concat(lines, "\n"), { filename = path, cwd = cwd })
  if base_line > 0 then
    for _, it in ipairs(items) do
      if it.filename == path then it.lnum = (it.lnum or 1) + base_line end
    end
  end
  if #items == 0 then
    vim.notify("nowork: no sections or locations parsed from log", vim.log.levels.WARN)
    return
  end
  qfix.set(items, {
    mode = mode or "replace",
    open = true,
    title = "nowork log: " .. vim.fn.fnamemodify(path, ":t"),
  })
end

local HELP_ENTRIES = {
  { key = "a / <CR>",       desc = "actions menu" },
  { key = "R",              desc = "restart (resume from saved state)" },
  { key = "<localleader>d", desc = "delete worklog (+ sidecar)" },
  { key = "gq",             desc = "log → qflist (replace)" },
  { key = "gq (visual)",    desc = "selected range → qflist" },
  { key = "<localleader>q", desc = "log → qflist (replace)" },
  { key = "<localleader>Q", desc = "log → qflist (append)" },
  { key = "?",              desc = "this help" },
}

local function delete_worklog(buf, path)
  local sidecar = sidecar_path(path)
  local name = vim.fn.fnamemodify(path, ":t")
  local ok, choice = pcall(vim.fn.confirm, "Delete worklog " .. name .. "?", "&Delete\n&Cancel", 2)
  if not ok or choice ~= 1 then return end
  local ok_log = os.remove(path)
  local ok_side = sidecar and os.remove(sidecar)
  if ok_log then
    vim.notify("nowork: deleted " .. name, vim.log.levels.INFO)
  else
    vim.notify("nowork: failed to delete " .. path, vim.log.levels.ERROR)
  end
  if ok_side then
    vim.notify("nowork: deleted sidecar " .. vim.fn.fnamemodify(sidecar, ":t"), vim.log.levels.INFO)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

local function open_actions_menu(buf, path)
  local has_state = fs_exists(sidecar_path(path))
  local actions = {}
  if has_state then
    actions[#actions + 1] = {
      label = "restart (resume from saved state)",
      fn = function()
        require("djinni.nowork.droid").restart_from_archive(path)
      end,
    }
  end
  actions[#actions + 1] = {
    label = "log → qflist (replace)",
    fn = function() send_to_qflist(buf, path, "replace") end,
  }
  actions[#actions + 1] = {
    label = "log → qflist (append)",
    fn = function() send_to_qflist(buf, path, "append") end,
  }
  actions[#actions + 1] = {
    label = "delete worklog (+ sidecar)",
    fn = function() delete_worklog(buf, path) end,
  }
  actions[#actions + 1] = {
    label = "close",
    fn = function()
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end,
  }
  local labels = vim.tbl_map(function(a) return a.label end, actions)
  local prompt = "archive: " .. vim.fn.fnamemodify(path, ":t") .. " ▸ "
  Snacks.picker.select(labels, { prompt = prompt }, function(chosen)
    if not chosen then return end
    for _, a in ipairs(actions) do
      if a.label == chosen then a.fn() return end
    end
  end)
end

function M.bind_qflist_keys(buf, path)
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "a", function()
    open_actions_menu(buf, path)
  end, vim.tbl_extend("force", opts, { desc = "nowork: archive actions" }))
  vim.keymap.set("n", "<CR>", function()
    open_actions_menu(buf, path)
  end, vim.tbl_extend("force", opts, { desc = "nowork: archive actions" }))
  vim.keymap.set("n", "R", function()
    if not fs_exists(sidecar_path(path)) then
      vim.notify("nowork: no saved state to restart from", vim.log.levels.WARN)
      return
    end
    require("djinni.nowork.droid").restart_from_archive(path)
  end, vim.tbl_extend("force", opts, { desc = "nowork: restart from archive" }))
  vim.keymap.set("n", "<localleader>d", function()
    delete_worklog(buf, path)
  end, vim.tbl_extend("force", opts, { desc = "nowork: delete worklog" }))
  vim.keymap.set("n", "<localleader>q", function()
    send_to_qflist(buf, path, "replace")
  end, vim.tbl_extend("force", opts, { desc = "nowork: log → qflist" }))
  vim.keymap.set("n", "<localleader>Q", function()
    send_to_qflist(buf, path, "append")
  end, vim.tbl_extend("force", opts, { desc = "nowork: log → qflist (append)" }))
  vim.keymap.set("n", "gq", function()
    send_to_qflist(buf, path, "replace")
  end, vim.tbl_extend("force", opts, { desc = "nowork: log → qflist" }))
  vim.keymap.set("x", "gq", function()
    local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
    if l1 > l2 then l1, l2 = l2, l1 end
    vim.cmd("normal! \27")
    send_to_qflist(buf, path, "replace", l1, l2)
  end, vim.tbl_extend("force", opts, { desc = "nowork: log range → qflist" }))
  vim.keymap.set("n", "?", function()
    require("djinni.nowork.help").show("nowork log", HELP_ENTRIES)
  end, vim.tbl_extend("force", opts, { desc = "nowork: log keys help" }))
end

function M.open(path, opts)
  opts = opts or {}
  local cwd = opts.cwd
  if not cwd or cwd == "" then
    cwd = archive_root(path)
  else
    cwd = vim.uv.fs_realpath(cwd) or vim.fn.fnamemodify(cwd, ":p"):gsub("/$", "")
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "nowork"
  if cwd and cwd ~= "" then
    vim.b[buf].nowork_cwd = cwd
  end
  local fh = io.open(path, "r")
  if fh then
    local content = fh:read("*a") or ""
    fh:close()
    local lines = vim.split(content, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  vim.bo[buf].modifiable = false
  vim.cmd("below 15split")
  vim.api.nvim_win_set_buf(0, buf)
  if cwd and cwd ~= "" then
    vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  end
  pcall(vim.api.nvim_buf_set_name, buf, "nowork://archive/" .. vim.fn.fnamemodify(path, ":t"))
  M.bind_qflist_keys(buf, path)
end

return M
