local M = {}

local config = require("neowork.config")
local store = require("neowork.store")

M._timer = nil
M._roots = M._roots or {}
M._running = M._running or {}
M._configured = M._configured or false

local function now_epoch()
  return os.time(os.date("!*t"))
end

local function iso_at(epoch)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

local function parse_iso(iso)
  if not iso or iso == "" then return nil end
  local y, mo, d, h, mi, s = iso:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z$")
  if not y then return nil end
  return os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s),
    isdst = false,
  })
end

function M.parse_interval(text)
  local amount, unit = tostring(text or ""):lower():match("^%s*(%d+)%s*([smhdw])%s*$")
  amount = tonumber(amount)
  if not amount or amount <= 0 then
    return nil, "invalid interval"
  end
  local mult = {
    s = 1,
    m = 60,
    h = 3600,
    d = 86400,
    w = 604800,
  }
  return amount * mult[unit]
end

local function schedule_enabled(meta)
  return tostring(meta.schedule_enabled or "") == "true"
end

local function write_fields(buf, fields)
  local document = require("neowork.document")
  document.set_frontmatter_fields(buf, fields)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent! write")
  end)
end

local function ensure_buf(filepath)
  local buf = vim.fn.bufnr(filepath)
  if buf < 0 then
    buf = vim.fn.bufadd(filepath)
  end
  if vim.fn.bufloaded(buf) == 0 then
    vim.fn.bufload(buf)
  end
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  if not vim.b[buf].neowork_chat then
    require("neowork.document").attach(buf)
    require("neowork.keymaps").setup_document_keymaps(buf)
    require("neowork.highlight").apply(buf)
  end
  return buf
end

local function buffer_busy(buf)
  local bridge = require("neowork.bridge")
  local status = bridge.get_status_bucket and select(1, bridge.get_status_bucket(buf)) or nil
  return status == "running" or status == "awaiting"
end

local function update_after_run(buf, interval_seconds, err)
  local fields = {
    schedule_next_run = iso_at(now_epoch() + interval_seconds),
  }
  if err then
    fields.schedule_last_error = tostring(err)
  else
    local document = require("neowork.document")
    local current = tonumber(document.read_frontmatter_field(buf, "schedule_run_count") or "0") or 0
    fields.schedule_last_run = iso_at(now_epoch())
    fields.schedule_run_count = tostring(current + 1)
    fields.schedule_last_error = ""
  end
  write_fields(buf, fields)
end

function M.enable(buf, interval_text, command)
  local seconds, err = M.parse_interval(interval_text)
  if not seconds then return nil, err end
  command = vim.trim(command or "")
  if command == "" then
    return nil, "missing command"
  end
  write_fields(buf, {
    schedule_enabled = "true",
    schedule_interval = vim.trim(interval_text),
    schedule_command = command,
    schedule_next_run = iso_at(now_epoch() + seconds),
    schedule_last_error = "",
  })
  return true
end

function M.disable(buf)
  write_fields(buf, {
    schedule_enabled = "false",
    schedule_next_run = "",
    schedule_last_error = "",
  })
  return true
end

function M.clear(buf)
  write_fields(buf, {
    schedule_enabled = "false",
    schedule_interval = "",
    schedule_command = "",
    schedule_next_run = "",
    schedule_last_run = "",
    schedule_run_count = "0",
    schedule_last_error = "",
  })
  return true
end

function M.run_now(buf)
  local document = require("neowork.document")
  local interval_text = document.read_frontmatter_field(buf, "schedule_interval") or ""
  local command = document.read_frontmatter_field(buf, "schedule_command") or ""
  local seconds, err = M.parse_interval(interval_text)
  if not seconds then return nil, err end
  command = vim.trim(command)
  if command == "" then
    return nil, "missing command"
  end
  if buffer_busy(buf) then
    return nil, "session busy"
  end
  pcall(require("neowork.bridge").reset_session, buf)
  local ok, exec_err = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd(command)
    end)
  end)
  update_after_run(buf, seconds, ok and nil or exec_err)
  if not ok then
    return nil, tostring(exec_err)
  end
  return true
end

function M.run_meta(_, meta)
  if not meta or not schedule_enabled(meta) then return false end
  local filepath = meta._filepath
  if not filepath or filepath == "" or M._running[filepath] then return false end
  local seconds = M.parse_interval(meta.schedule_interval)
  if not seconds then return false end
  local due_at = parse_iso(meta.schedule_next_run)
  if due_at and due_at > now_epoch() then return false end

  local buf = ensure_buf(filepath)
  if not buf or buffer_busy(buf) then return false end

  M._running[filepath] = true
  local ok, err = pcall(function()
    local command = vim.trim(meta.schedule_command or "")
    if command == "" then error("missing command") end
    require("neowork.bridge").reset_session(buf)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd(command)
    end)
  end)
  update_after_run(buf, seconds, ok and nil or err)
  M._running[filepath] = nil
  return ok
end

function M.tick()
  for root in pairs(M._roots) do
    for _, meta in ipairs(store.scan_sessions(root)) do
      pcall(M.run_meta, root, meta)
    end
  end
end

function M.register_root(root)
  root = root and vim.fn.fnamemodify(root, ":p"):gsub("/+$", "") or nil
  if not root or root == "" then return end
  M._roots[root] = true
end

function M.stop()
  if M._timer then
    M._timer:stop()
    M._timer:close()
    M._timer = nil
  end
end

function M.start()
  if M._timer then return end
  local interval = tonumber(config.get("schedule_poll_ms")) or 30000
  M._timer = vim.uv.new_timer()
  M._timer:start(interval, interval, vim.schedule_wrap(function()
    M.tick()
  end))
end

function M.setup()
  if M._configured then return end
  M._configured = true
  M.register_root(vim.fn.getcwd())
  M.start()
end

return M
