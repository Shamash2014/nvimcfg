local droid_mod = require("djinni.nowork.droid")
local lifecycle = require("djinni.nowork.state")
local mode_switch = require("djinni.nowork.mode_switch")

local M = {}

pcall(vim.api.nvim_set_hl, 0, "NoworkPickerSkill", { bold = true, link = "Special" })

local function derive_cwd_from_archive(path)
  if not path or path == "" then return nil end
  local ok, archive = pcall(require, "djinni.nowork.archive")
  if ok and archive and archive.read_state then
    local state = archive.read_state(path)
    if state and state.opts and state.opts.cwd and vim.fn.isdirectory(state.opts.cwd) == 1 then
      return state.opts.cwd
    end
  end
  local guess = path:match("^(.-)/%.nowork/logs/")
  if guess and vim.fn.isdirectory(guess) == 1 then
    return guess
  end
  return nil
end

local function split_skills(text)
  local parts = {}
  local i = 1
  while i <= #text do
    local s, e = text:find("/[%w][%w_:-]*", i)
    if not s then
      parts[#parts + 1] = { text:sub(i), "SnacksPickerLabel" }
      break
    end
    if s > i then
      parts[#parts + 1] = { text:sub(i, s - 1), "SnacksPickerLabel" }
    end
    parts[#parts + 1] = { text:sub(s, e), "NoworkPickerSkill" }
    i = e + 1
  end
  return parts
end

local function format_item(item)
  if item.header then
    return { { item.text, "Title" } }
  end
  if item.history_entry then
    local h = item.history_entry
    local head = ("[%s] %s (%s)"):format(h.id, h.mode, h.status or "done")
    local parts = { { head, "SnacksPickerLabel" } }
    if h.initial_prompt and h.initial_prompt ~= "" then
      local trunc = h.initial_prompt:sub(1, 50)
      parts[#parts + 1] = { " — ", "SnacksPickerLabel" }
      for _, seg in ipairs(split_skills(trunc)) do
        parts[#parts + 1] = seg
      end
    end
    return parts
  end
  if item.archive then
    local a = item.archive
    local hh = a.stamp:sub(1, 2) .. ":" .. a.stamp:sub(3, 4)
    local badge = a.has_state and "↻" or " "
    local head = ("[arch %s %s %s] %s"):format(badge, a.date, hh, a.mode or "?")
    local parts = { { head, "SnacksPickerLabel" } }
    if a.prompt_hint and a.prompt_hint ~= "" then
      local trunc = a.prompt_hint:sub(1, 50)
      parts[#parts + 1] = { " — ", "SnacksPickerLabel" }
      for _, seg in ipairs(split_skills(trunc)) do
        parts[#parts + 1] = seg
      end
    end
    return parts
  end
  local d = item.droid_id and droid_mod.active[item.droid_id]
  if not d then return { { item.text or "", "SnacksPickerLabel" } } end
  local phase = d.mode == "autorun" and d.state and d.state.phase and (":" .. d.state.phase) or ""
  local head = ("[%s] %s%s (%s)"):format(d.id, d.mode, phase, d.status)
  local parts = { { head, "SnacksPickerLabel" } }
  if d.initial_prompt and d.initial_prompt ~= "" then
    local trunc = d.initial_prompt:sub(1, 50)
    parts[#parts + 1] = { " — ", "SnacksPickerLabel" }
    for _, seg in ipairs(split_skills(trunc)) do
      parts[#parts + 1] = seg
    end
  end
  if (d.mode == "explore" or d.mode == "planner") and d.state and d.state.qfix_items and #d.state.qfix_items > 0 then
    parts[#parts + 1] = { " [" .. #d.state.qfix_items .. " results]", "SnacksPickerLabel" }
  end
  local perm_count = require("djinni.nowork.events").permission_count(d)
  if perm_count > 0 then
    parts[#parts + 1] = { " perm!" .. perm_count, "DiagnosticWarn" }
  end
  return parts
end

local function mode_matches(mode, filter)
  if not filter then return true end
  if type(filter) == "string" then return mode == filter end
  if type(filter) == "table" then
    for _, allowed in ipairs(filter) do
      if mode == allowed then return true end
    end
    return false
  end
  return true
end

local function build_items(opts)
  opts = opts or {}
  local items = {}
  local filter = opts.mode_filter

  local active = {}
  for id, d in pairs(droid_mod.active) do
    if mode_matches(d.mode, filter) then
      active[#active + 1] = { id = id, text = id, droid_id = id, _sort = d.started_at or 0 }
    end
  end
  table.sort(active, function(a, b) return a._sort > b._sort end)

  if opts.include_history or opts.include_archive then
    if #active > 0 then
      items[#items + 1] = { header = true, text = "── Active ──" }
    end
  end
  for _, it in ipairs(active) do items[#items + 1] = it end

  if opts.include_history then
    local history = {}
    for _, h in ipairs(droid_mod.history or {}) do
      if mode_matches(h.mode, filter) then
        history[#history + 1] = h
      end
    end
    if #history > 0 then
      items[#items + 1] = { header = true, text = "── Recent (this session) ──" }
      for _, h in ipairs(history) do
        items[#items + 1] = { id = "h:" .. h.id, text = h.id, history_entry = h }
      end
    end
  end

  if opts.include_archive then
    local archive = require("djinni.nowork.archive")
    local extra_roots_set = {}
    for _, d in pairs(droid_mod.active) do
      local c = d.opts and d.opts.cwd
      if c then extra_roots_set[c] = true end
    end
    for _, h in ipairs(droid_mod.history or {}) do
      if h.archive_path then
        local root = h.archive_path:match("^(.*)/%.nowork/logs/")
        if root then extra_roots_set[root] = true end
      end
    end
    local extra_roots = vim.tbl_keys(extra_roots_set)
    local list = archive.list(7, extra_roots)
    local by_date = {}
    for _, a in ipairs(list) do
      if mode_matches(a.mode, filter) and not droid_mod.active[a.id] then
        by_date[a.date] = by_date[a.date] or {}
        table.insert(by_date[a.date], a)
      end
    end
    local dates = vim.tbl_keys(by_date)
    table.sort(dates, function(a, b) return a > b end)
    for _, date in ipairs(dates) do
      local entries = by_date[date]
      table.sort(entries, function(x, y) return x.stamp > y.stamp end)
      items[#items + 1] = { header = true, text = "── " .. date .. " ──" }
      for _, a in ipairs(entries) do
        a.prompt_hint = archive.prompt_hint(a.path)
        items[#items + 1] = { id = "a:" .. a.path, text = a.path, archive = a }
      end
    end
  end

  return items
end

local function spawn(picker, mode)
  local pattern = picker:filter() and picker:filter().pattern or ""
  picker:close()
  local nw = require("djinni.nowork")
  if mode == "routine" or mode == "auto" then
    nw[mode](pattern or "", {})
    return
  end
  if pattern ~= "" then
    nw[mode](pattern, {})
    return
  end
  local labels = { explore = "explore", routine = "routine", auto = "autorun" }
  require("djinni.nowork.compose").open(nil, {
    title = " nowork " .. (labels[mode] or mode) .. " ",
    alt_buf = vim.fn.bufnr("#"),
    on_submit = function(text)
      if text and text ~= "" then nw[mode](text, {}) end
    end,
  })
end

local function build_action_items(d)
  local items = {}
  local function add(label, fn) items[#items + 1] = { text = label, fn = fn } end

  local perm_count = require("djinni.nowork.events").permission_count(d)
  if perm_count > 0 then
    add(("resolve %d permission%s"):format(perm_count, perm_count == 1 and "" or "s"), function()
      require("djinni.nowork.events").open()
    end)
  end

  local pending = d.state and d.state.pending_prompt
  if pending and pending.show then
    add("answer question", function()
      pending.show()
    end)
  end

  add("show log", function()
    if d.log_buf and d.log_buf.show then d.log_buf:show() end
  end)

  if d.mode == "routine" or d.mode == "autorun" then
    add("compose", function()
      require("djinni.nowork.compose").open(d, { alt_buf = vim.fn.bufnr("#") })
    end)
  end

  add("switch model", function()
    require("djinni.nowork.model_picker").pick(d)
  end)
  add("switch ACP mode", function()
    require("djinni.nowork.acp_mode").pick(d)
  end)
  add("switch mode", function()
    if d.status == "running" then
      vim.notify("nowork: cannot switch mode while running", vim.log.levels.WARN)
      return
    end
    mode_switch.select(d, { prompt = "switch mode" })
  end)

  add("populate qfix", function()
    require("djinni.nowork.qfix_share").populate(d)
  end)
  add("shadow review", function()
    require("djinni.nowork.shadow").review(d)
  end)

  local plan_cwd = d.opts and d.opts.cwd
  if plan_cwd and vim.fn.isdirectory(plan_cwd .. "/.nowork/plans") == 1 then
    add("review plan", function()
      require("djinni.nowork.plans").pick(plan_cwd)
    end)
  end

  if lifecycle.is_finished(d) then
    add("restart (resume from saved state)", function()
      droid_mod.restart(d)
    end)
  end
  add("cancel", function() droid_mod.cancel(d) end)
  add("done",   function() droid_mod.done(d) end)
  return items
end

local function open_numbered_actions(title, actions)
  local lines = {}
  local extra = {}
  for i, action in ipairs(actions) do
    if i > 9 then break end
    lines[#lines + 1] = ("  [%d] %s"):format(i, action.text)
    extra[tostring(i)] = function(close)
      close()
      action.fn()
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "# Press 1–9 to pick, <C-c>/q to cancel."
  require("djinni.nowork.plan_buffer").open({
    title = " " .. title .. " ",
    footer = " 1-9 pick · <C-c>/q cancel ",
    content = table.concat(lines, "\n"),
    filetype = "markdown",
    readonly = true,
    on_submit = function() return true end,
    extra_keys = extra,
  })
end

local function build_archive_actions(path, has_state)
  local archive = require("djinni.nowork.archive")
  local sidecar = archive.state_path(path)
  if has_state == nil then
    has_state = sidecar and vim.loop.fs_stat(sidecar) ~= nil
  end
  local actions = {}
  if has_state then
    actions[#actions + 1] = {
      text = "restart (resume from saved state)",
      fn = function() droid_mod.restart_from_archive(path) end,
    }
  end
  actions[#actions + 1] = {
    text = "fork (new droid from this worklog)",
    fn = function() droid_mod.fork_from_archive(path) end,
  }
  actions[#actions + 1] = {
    text = "open log (read-only)",
    fn = function() archive.open(path) end,
  }
  local plan_cwd = derive_cwd_from_archive(path)
  if plan_cwd and vim.fn.isdirectory(plan_cwd .. "/.nowork/plans") == 1 then
    actions[#actions + 1] = {
      text = "review plan",
      fn = function()
        require("djinni.nowork.plans").pick(plan_cwd)
      end,
    }
  end
  actions[#actions + 1] = {
    text = "copy log path",
    fn = function()
      vim.fn.setreg("+", path)
      vim.fn.setreg('"', path)
      vim.notify("nowork: copied " .. path, vim.log.levels.INFO)
    end,
  }
  actions[#actions + 1] = {
    text = "delete archive (+ sidecar)",
    fn = function()
      Snacks.picker.select({ "no, keep", "yes, delete" }, {
        prompt = "delete " .. vim.fn.fnamemodify(path, ":t") .. "? ",
      }, function(choice)
        if not choice or not choice:match("^yes") then return end
        local ok_log = os.remove(path)
        local ok_state = sidecar and os.remove(sidecar)
        local msg = ok_log and ("nowork: deleted " .. vim.fn.fnamemodify(path, ":t")) or ("nowork: failed to delete " .. path)
        vim.notify(msg, ok_log and vim.log.levels.INFO or vim.log.levels.ERROR)
        if ok_state then
          vim.notify("nowork: deleted sidecar " .. vim.fn.fnamemodify(sidecar, ":t"), vim.log.levels.INFO)
        end
      end)
    end,
  }
  return actions
end

local function build_history_action_items(history_entry)
  local archive = require("djinni.nowork.archive")
  local actions = {}
  local function add(label, fn) actions[#actions + 1] = { text = label, fn = fn } end

  local archive_path = history_entry and history_entry.archive_path or nil
  local sidecar = archive_path and archive.state_path(archive_path) or nil
  local has_state = sidecar and vim.loop.fs_stat(sidecar) ~= nil
  local log_buf = history_entry and history_entry.log_buf or nil
  local log_buf_valid = log_buf and log_buf.buf and vim.api.nvim_buf_is_valid(log_buf.buf)

  if archive_path then
    local archive_actions = build_archive_actions(archive_path, has_state)
    for _, action in ipairs(archive_actions) do
      actions[#actions + 1] = action
    end
    return actions
  end
  if log_buf and log_buf.show and log_buf_valid then
    add("show log", function()
      log_buf:show()
    end)
  else
    add("show missing log warning", function()
      vim.notify("nowork: log buffer gone and no archive for " .. (history_entry.id or "?"), vim.log.levels.WARN)
    end)
  end

  local plan_cwd = history_entry and history_entry.cwd or nil
  if plan_cwd and vim.fn.isdirectory(plan_cwd .. "/.nowork/plans") == 1 then
    add("review plan", function()
      require("djinni.nowork.plans").pick(plan_cwd)
    end)
  end

  return actions
end

function M.run_action(d)
  local actions = build_action_items(d)
  open_numbered_actions(d.id .. " ▸", actions)
end

function M.run_history_action(history_entry)
  local id = history_entry and history_entry.id or "history"
  local actions = build_history_action_items(history_entry or {})
  open_numbered_actions(id .. " ▸", actions)
end

function M.run_archive_action(path, has_state)
  local actions = build_archive_actions(path, has_state)
  open_numbered_actions("archive: " .. vim.fn.fnamemodify(path, ":t") .. " ▸", actions)
end

function M.count(opts)
  return #build_items(opts or {})
end

function M.pick(opts)
  opts = opts or {}
  local items = build_items(opts)
  if #items == 0 then
    local hint = "nowork: no droids"
    if opts.include_archive then hint = hint .. " or archived logs" end
    hint = hint .. " (cwd: " .. vim.fn.getcwd() .. ")"
    vim.notify(hint, vim.log.levels.WARN)
    return
  end
  Snacks.picker({
    title = "nowork droids",
    items = items,
    format = format_item,
    confirm = function(picker, item)
      local pattern = picker:filter() and picker:filter().pattern or ""
      if item and item.header then
        return
      end
      if item and item.droid_id then
        local d = droid_mod.active[item.droid_id]
        picker:close()
        if not d then
          vim.notify("nowork: droid " .. item.droid_id .. " no longer active", vim.log.levels.WARN)
          return
        end
        if opts.on_droid then
          opts.on_droid(d)
        else
          vim.schedule(function() M.run_action(d) end)
        end
        return
      end
      if item and item.history_entry then
        picker:close()
        local h = item.history_entry
        vim.schedule(function()
          M.run_history_action(h)
        end)
        return
      end
      if item and item.archive then
        picker:close()
        local path = item.archive.path
        local has_state = item.archive.has_state
        vim.schedule(function()
          M.run_archive_action(path, has_state)
        end)
        return
      end
      picker:close()
      local nw = require("djinni.nowork")
      if pattern ~= "" then
        nw.explore(pattern, {})
      else
        require("djinni.nowork.compose").open(nil, {
          title = " nowork explore ",
          alt_buf = vim.fn.bufnr("#"),
          on_submit = function(text)
            if text and text ~= "" then nw.explore(text, {}) end
          end,
        })
      end
    end,
    actions = {
      nowork_explore = function(picker) spawn(picker, "explore") end,
      nowork_routine = function(picker) spawn(picker, "routine") end,
      nowork_autorun = function(picker) spawn(picker, "auto") end,
      nowork_cancel  = function(picker, item)
        if item and item.droid_id then
          local d = droid_mod.active[item.droid_id]
          picker:close()
          if d then droid_mod.cancel(d) end
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<c-s>"] = { "nowork_explore", mode = { "i", "n" } },
          ["<c-w>"] = { "nowork_routine", mode = { "i", "n" } },
          ["<c-a>"] = { "nowork_autorun", mode = { "i", "n" } },
          ["q"]     = { "nowork_cancel",  mode = { "n" } },
        },
      },
    },
  })
end

return M
