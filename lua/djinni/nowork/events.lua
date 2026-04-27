local M = {}
local mode_switch = require("djinni.nowork.mode_switch")
local tool_call = require("djinni.nowork.tool_call")
local strutil = require("djinni.nowork.status_text")

M._counter = 0
M._buf = nil
M._win = nil
M._entries_on_screen = nil

local HELP_ENTRIES = {
  { key = "<CR>", desc = "open full option picker" },
  { key = "a",    desc = "allow_once" },
  { key = "A",    desc = "allow_always (sticky)" },
  { key = "r",    desc = "reject_once (opens compose)" },
  { key = "R",    desc = "reject_always (sticky + compose)" },
  { key = "p",    desc = "preview exact command / payload" },
  { key = "m",    desc = "switch droid mode (explore/routine/autorun)" },
  { key = "g",    desc = "go to droid log" },
  { key = "d",    desc = "dismiss (no response)" },
  { key = "q",    desc = "close events" },
  { key = "<Esc>", desc = "close events" },
  { key = "?",    desc = "this help" },
}

local function next_id()
  M._counter = M._counter + 1
  return M._counter
end

local function resolve_droid(droid_id)
  local droid_mod = require("djinni.nowork.droid")
  return droid_mod.active[droid_id]
end

local function entry_kind(e)
  return e.kind or ((e.tool_kind or e.options) and "permission") or "unknown"
end

function M.events_for(droid)
  if not droid or not droid.state then return {} end
  return droid.state.pending_events or {}
end

function M.permissions_for(droid)
  local out = {}
  for _, e in ipairs(M.events_for(droid)) do
    if entry_kind(e) == "permission" and not e.resolved then
      out[#out + 1] = e
    end
  end
  return out
end

function M.permission_count(droid)
  return #M.permissions_for(droid)
end

function M.permission_count_for_state(state)
  if not state or not state.pending_events then return 0 end
  local n = 0
  for _, e in ipairs(state.pending_events) do
    if entry_kind(e) == "permission" and not e.resolved then n = n + 1 end
  end
  return n
end

local function collect_entries()
  local droid_mod = require("djinni.nowork.droid")
  local entries = {}
  for _, d in pairs(droid_mod.active) do
    if d.state and d.state.pending_events then
      for _, e in ipairs(d.state.pending_events) do
        if not e.resolved then
          entries[#entries + 1] = e
        end
      end
    end
  end
  table.sort(entries, function(a, b) return a.received_at < b.received_at end)
  return entries
end

function M.count()
  return #collect_entries()
end

local format_elapsed = strutil.format_elapsed
local one_line = strutil.one_line

local function render_line(e)
  local now = os.time()
  local droid = resolve_droid(e.droid_id)
  local mode = (droid and droid.mode) or e.droid_mode or "?"

  local cmd = e.tool_command and one_line(e.tool_command, 120) or nil
  if cmd and cmd ~= "" then
    return string.format("[%s] %s · %s · %s · %s",
      e.droid_id, mode, one_line(e.tool_kind or "?", 16), cmd,
      format_elapsed(now - (e.received_at or now)))
  end
  return string.format("[%s] %s · %s · \"%s\" · %s",
    e.droid_id,
    mode,
    one_line(e.tool_kind or "?", 24),
    one_line(e.tool_title or "tool", 80),
    format_elapsed(now - (e.received_at or now))
  )
end

local function preview_entry(e)
  local lines = {
    "# permission request [" .. e.droid_id .. "]",
    "",
    "kind:  " .. (e.tool_kind or "?"),
    "title: " .. (e.tool_title or "tool"),
    "",
    "## exact",
  }
  local cmd = e.tool_command or "(none)"
  for _, l in ipairs(vim.split(cmd, "\n", { plain = true })) do
    lines[#lines + 1] = "  " .. l
  end
  if e.tool_raw_input and type(e.tool_raw_input) == "table" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## rawInput"
    local ok, encoded = pcall(vim.json.encode, e.tool_raw_input)
    if ok and encoded then
      for _, l in ipairs(vim.split(encoded, "\n", { plain = true })) do
        lines[#lines + 1] = "  " .. l
      end
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = math.min(120, math.floor(vim.o.columns * 0.8))
  local height = math.min(30, math.max(#lines + 2, 8))
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col,
    width = width, height = height,
    style = "minimal", border = "rounded",
    title = " permission preview · " .. (e.tool_kind or "?") .. " ",
    title_pos = "center",
    footer = " q close ",
    footer_pos = "left",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  local kopts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", function() pcall(vim.api.nvim_win_close, win, true) end, kopts)
  vim.keymap.set("n", "<Esc>", function() pcall(vim.api.nvim_win_close, win, true) end, kopts)
end

local function find_option(entry, option_kind)
  for _, opt in ipairs(entry.options or {}) do
    if opt.kind == option_kind then return opt end
  end
  return nil
end

local function finish_entry(entry, option)
  if entry.resolved then return end
  entry.resolved = true
  local droid = resolve_droid(entry.droid_id)

  if droid and droid.state and droid.state.pending_events then
    local list = droid.state.pending_events
    for i = #list, 1, -1 do
      if list[i].id == entry.id then
        table.remove(list, i)
      end
    end
  end

  if option then
    local outcome = { outcome = { outcome = "selected", optionId = option.optionId } }
    if droid and droid._sink then
      droid._sink:respond(entry, outcome)
    else
      pcall(entry.respond, outcome)
    end
  end

  local kind = entry.tool_kind
  if droid and kind and option and option.kind == "allow_always" then
    droid.state.sticky_permissions[kind] = "allow"
  elseif droid and kind and option and option.kind == "reject_always" then
    droid.state.sticky_permissions[kind] = "deny"
  end

  if droid and droid.log_buf then
    droid.log_buf:append(string.format("[perm] %s · %s", option and option.kind or "dismissed", kind or "?"))
  end

  require("djinni.nowork.status_panel").update()
end

local function open_reject_compose(entry)
  local droid = resolve_droid(entry.droid_id)
  if not droid then return end
  vim.schedule(function()
    require("djinni.nowork.compose").open(droid, {
      initial = "Rejected " .. (entry.tool_title or "tool") .. ". ",
      alt_buf = vim.fn.bufnr("#"),
      on_submit = function(text)
        require("djinni.nowork.droid").stage_append(droid, text)
      end,
    })
  end)
end

local function resolve_by_kind(entry, option_kind)
  local opt = find_option(entry, option_kind)
  if not opt then
    vim.notify("events: option kind '" .. option_kind .. "' not offered", vim.log.levels.WARN)
    return false
  end
  finish_entry(entry, opt)
  if option_kind == "reject_once" or option_kind == "reject_always" then
    open_reject_compose(entry)
  end
  return true
end

local function pick_full(entry)
  local labels = {}
  for i, opt in ipairs(entry.options or {}) do
    labels[i] = ("[%s] %s"):format(opt.kind or "?", opt.name or opt.optionId or "")
  end
  Snacks.picker.select(labels, {
    prompt = "permission · " .. (entry.tool_title or "tool"),
  }, function(_, idx)
    if not idx then return end
    local chosen = entry.options[idx]
    finish_entry(entry, chosen)
    if chosen and (chosen.kind == "reject_once" or chosen.kind == "reject_always") then
      open_reject_compose(entry)
    end
    M._refresh()
  end)
end

local function switch_mode_and_redispatch(entry)
  local droid = resolve_droid(entry.droid_id)
  if not droid then return end
  local kind = entry_kind(entry)

  if kind ~= "permission" then
    vim.notify("nowork: mode switch only works on permission entries", vim.log.levels.INFO)
    return
  end

  mode_switch.select(droid, {
    modes = { "explore", "routine", "autorun" },
    prompt = "switch " .. droid.id .. " mode",
    after_switch = function(_, _, policy)
      local list = droid.state.pending_events or {}
      for i = #list, 1, -1 do
        if list[i].id == entry.id then table.remove(list, i) end
      end
      entry.resolved = true
      vim.schedule(function()
        policy.on_permission(entry.params, entry.respond, droid)
        M._refresh()
      end)
    end,
  })
end

local function close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    pcall(vim.api.nvim_win_close, M._win, true)
  end
  M._win = nil
  M._entries_on_screen = nil
end

local function render(entries)
  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then
    M._buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M._buf].buftype = "nofile"
    vim.bo[M._buf].bufhidden = "wipe"
    vim.bo[M._buf].swapfile = false
  end

  local lines = { "# Events · <CR> picker · a/A allow · r/R reject · p preview · m mode · g log · d dismiss · q close" }
  if #entries == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  (empty)"
  else
    for i, e in ipairs(entries) do
      lines[#lines + 1] = string.format("%d. %s", i, render_line(e))
    end
  end
  vim.bo[M._buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false
  vim.bo[M._buf].filetype = "markdown"
  M._entries_on_screen = entries
end

local function current_entry()
  if not M._entries_on_screen or #M._entries_on_screen == 0 then return nil end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  local idx = row - 1
  if idx < 1 or idx > #M._entries_on_screen then return nil end
  return M._entries_on_screen[idx]
end

function M._refresh()
  if not (M._win and vim.api.nvim_win_is_valid(M._win)) then return end
  local entries = collect_entries()
  if #entries == 0 then
    close()
    return
  end
  render(entries)
end

local function open_window(entries)
  render(entries)
  local width = math.min(100, math.floor(vim.o.columns * 0.7))
  local height = math.min(math.max(#entries + 2, 5), math.floor(vim.o.lines * 0.5))
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)
  M._win = vim.api.nvim_open_win(M._buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " nowork events ",
    title_pos = "center",
    footer = " <CR>/e/a/A/r/R/y/n/p/m/g/d/q ",
    footer_pos = "left",
  })
  vim.wo[M._win].cursorline = true
  vim.wo[M._win].wrap = false
  if #entries > 0 then
    vim.api.nvim_win_set_cursor(M._win, { 2, 0 })
  end

  local opts = { buffer = M._buf, nowait = true, silent = true }
  local function on(key, fn)
    vim.keymap.set("n", key, fn, opts)
  end

  on("<CR>", function()
    local e = current_entry()
    if not e then return end
    pick_full(e)
  end)

  on("a", function()
    local e = current_entry()
    if not e then return end
    local kind = entry_kind(e)
    if kind == "permission" then
      if resolve_by_kind(e, "allow_once") then M._refresh() end
    else
      vim.notify("nowork: 'a' only works on permission entries", vim.log.levels.INFO)
    end
  end)

  on("A", function()
    local e = current_entry()
    if not e then return end
    local kind = entry_kind(e)
    if kind == "permission" then
      if resolve_by_kind(e, "allow_always") then M._refresh() end
    else
      vim.notify("nowork: 'A' only works on permission entries", vim.log.levels.INFO)
    end
  end)

  on("r", function()
    local e = current_entry()
    if not e then return end
    local kind = entry_kind(e)
    if kind == "permission" then
      if resolve_by_kind(e, "reject_once") then M._refresh() end
    else
      vim.notify("nowork: 'r' only works on permission entries", vim.log.levels.INFO)
    end
  end)

  on("R", function()
    local e = current_entry()
    if not e then return end
    local kind = entry_kind(e)
    if kind == "permission" then
      if resolve_by_kind(e, "reject_always") then M._refresh() end
    else
      vim.notify("nowork: 'R' only works on permission entries", vim.log.levels.INFO)
    end
  end)

  on("p", function()
    local e = current_entry()
    if not e then return end
    local kind = entry_kind(e)
    if kind == "permission" then
      preview_entry(e)
    else
      vim.notify("nowork: 'p' only works on permission entries", vim.log.levels.INFO)
    end
  end)

  on("m", function()
    local e = current_entry()
    if not e then return end
    switch_mode_and_redispatch(e)
  end)

  on("g", function()
    local e = current_entry()
    if not e then return end
    local droid = resolve_droid(e.droid_id)
    if droid and droid.log_buf and droid.log_buf.show then
      close()
      droid.log_buf:show()
    end
  end)

  on("d", function()
    local e = current_entry()
    if not e then return end
    e.resolved = true
    M._refresh()
  end)

  on("q", close)
  on("<Esc>", close)
  on("?", function()
    require("djinni.nowork.help").show("events", HELP_ENTRIES)
  end)
end

function M.enqueue(droid, params, respond)
  droid.state.pending_events = droid.state.pending_events or {}
  local tc = params and params.toolCall or nil
  local raw_input = tc and (tc.rawInput or tc.raw_input or tc.input) or nil
  local entry = {
    kind = "permission",
    id = next_id(),
    droid_id = droid.id,
    droid_mode = droid.mode,
    params = params,
    tool_title = tc and tc.title or "tool",
    tool_kind = tc and tc.kind,
    tool_raw_input = raw_input,
    tool_command = tool_call.render_command(raw_input, tc),
    options = params and params.options or {},
    respond = respond,
    received_at = os.time(),
    resolved = false,
  }
  table.insert(droid.state.pending_events, entry)
  if droid.log_buf then
    local label = entry.tool_command and ((entry.tool_kind or "tool") .. " · " .. entry.tool_command) or entry.tool_title
    droid.log_buf:append(string.format("[permission] %s (<leader>ap to resolve)", label))
  end
  vim.notify(
    string.format("nowork %s: permission needed — %s (<leader>ap)",
      droid.id,
      entry.tool_command or entry.tool_title),
    vim.log.levels.WARN
  )
  require("djinni.nowork.status_panel").update()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    M._refresh()
  end
end

function M.drain_droid(droid, outcome)
  if not droid or not droid.state then return end
  local events = droid.state.pending_events
  if events and #events > 0 then
    for _, e in ipairs(events) do
      if not e.resolved then
        e.resolved = true
        if entry_kind(e) == "permission" and e.respond then
          local payload = { outcome = { outcome = outcome or "cancelled" } }
          if droid._sink then
            droid._sink:respond(e, payload)
          else
            pcall(e.respond, payload)
          end
        end
      end
    end
    droid.state.pending_events = {}
  end
  require("djinni.nowork.status_panel").update()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    M._refresh()
  end
end

function M.open()
  local entries = collect_entries()
  if #entries == 0 then
    vim.notify("nowork: no pending events", vim.log.levels.INFO)
    return
  end
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_set_current_win(M._win)
    return
  end
  open_window(entries)
end

return M
