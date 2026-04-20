local M = {}

M._buf = nil
M._win = nil

local function format_elapsed(seconds)
  if not seconds or seconds < 0 then return "?" end
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

local function humanize_bytes(n)
  if n < 1024 then return n .. " B" end
  if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
  return string.format("%.2f MB", n / (1024 * 1024))
end

local function dir_size(path)
  local total = 0
  if vim.fn.isdirectory(path) == 0 then return 0 end
  local function walk(dir)
    for _, name in ipairs(vim.fn.readdir(dir) or {}) do
      local p = dir .. "/" .. name
      local stat = vim.loop.fs_stat(p)
      if stat then
        if stat.type == "directory" then walk(p)
        else total = total + (stat.size or 0) end
      end
    end
  end
  walk(path)
  return total
end

local function gather(cwd, mode_filter)
  local droid_mod = require("djinni.nowork.droid")
  local archive = require("djinni.nowork.archive")

  local active, active_by_mode = {}, {}
  for _, d in pairs(droid_mod.active) do
    local droid_cwd = d.opts and d.opts.cwd
    if (not cwd) or droid_cwd == cwd then
      if (not mode_filter) or d.mode == mode_filter then
        active[#active + 1] = d
        active_by_mode[d.mode] = (active_by_mode[d.mode] or 0) + 1
      end
    end
  end

  local archived = archive.list(30, cwd and { cwd } or nil) or {}
  local arch_scoped, arch_by_mode, resumable = {}, {}, 0
  for _, a in ipairs(archived) do
    if (not cwd) or a.cwd == cwd then
      if (not mode_filter) or a.mode == mode_filter then
        arch_scoped[#arch_scoped + 1] = a
        arch_by_mode[a.mode] = (arch_by_mode[a.mode] or 0) + 1
        if a.has_state then resumable = resumable + 1 end
      end
    end
  end
  table.sort(arch_scoped, function(a, b)
    if a.date == b.date then return a.stamp > b.stamp end
    return a.date > b.date
  end)

  local disk = dir_size((cwd or vim.fn.getcwd()) .. "/.nowork/logs")

  return {
    cwd = cwd or vim.fn.getcwd(),
    active = active,
    active_by_mode = active_by_mode,
    archived = arch_scoped,
    arch_by_mode = arch_by_mode,
    resumable = resumable,
    disk = disk,
  }
end

local function render_line_for_archive(a)
  local hh = a.stamp:sub(1, 2) .. ":" .. a.stamp:sub(3, 4)
  local badge = a.has_state and "↻" or " "
  local prompt = a.prompt_hint or ""
  if prompt == "" then
    prompt = require("djinni.nowork.archive").prompt_hint(a.path) or ""
    a.prompt_hint = prompt
  end
  if #prompt > 60 then prompt = prompt:sub(1, 59) .. "…" end
  return string.format("%s %s %s · %s · %s", badge, a.date, hh, a.mode or "?", prompt)
end

local function render_line_for_droid(d)
  local phase = d.mode == "autorun" and d.state and d.state.phase and (":" .. d.state.phase) or ""
  local prompt = (d.initial_prompt or ""):gsub("\n", " ")
  if #prompt > 60 then prompt = prompt:sub(1, 59) .. "…" end
  return string.format("● %s %s%s · %s · %s", d.id, d.mode or "?", phase, d.status or "?", prompt)
end

local function build_lines(stats, mode_label)
  local lines = {}
  local label = mode_label or "routine"
  table.insert(lines, "# nowork " .. label .. " overview")
  table.insert(lines, "")
  table.insert(lines, "cwd: " .. stats.cwd)
  table.insert(lines, string.format("active: %d · archived: %d · resumable: %d · disk: %s",
    #stats.active, #stats.archived, stats.resumable, humanize_bytes(stats.disk)))
  if next(stats.active_by_mode) then
    local bits = {}
    for m, c in pairs(stats.active_by_mode) do bits[#bits + 1] = m .. "=" .. c end
    table.insert(lines, "active by mode: " .. table.concat(bits, " · "))
  end
  if next(stats.arch_by_mode) then
    local bits = {}
    for m, c in pairs(stats.arch_by_mode) do bits[#bits + 1] = m .. "=" .. c end
    table.insert(lines, "archived by mode: " .. table.concat(bits, " · "))
  end
  table.insert(lines, "")
  table.insert(lines, "## Active (" .. #stats.active .. ")")
  local row_map = {}
  if #stats.active == 0 then
    table.insert(lines, "  (none)")
  else
    for _, d in ipairs(stats.active) do
      table.insert(lines, render_line_for_droid(d))
      row_map[#lines] = { kind = "droid", droid_id = d.id }
    end
  end
  table.insert(lines, "")
  table.insert(lines, "## Archived (" .. #stats.archived .. ")")
  if #stats.archived == 0 then
    table.insert(lines, "  (none)")
  else
    for _, a in ipairs(stats.archived) do
      table.insert(lines, render_line_for_archive(a))
      row_map[#lines] = { kind = "archive", path = a.path, has_state = a.has_state }
    end
  end
  table.insert(lines, "")
  table.insert(lines, "keys: <CR> open · r restart · d delete · n new " .. label .. " · R refresh · q close · ?")
  return lines, row_map
end

local function close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    pcall(vim.api.nvim_win_close, M._win, true)
  end
  M._win = nil
end

function M.open(opts)
  opts = opts or {}
  local mode_filter = opts.mode or "routine"
  local cwd = opts.cwd or vim.fn.getcwd()

  local stats = gather(cwd, mode_filter)
  local lines, row_map = build_lines(stats, mode_filter)

  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then
    M._buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M._buf].buftype = "nofile"
    vim.bo[M._buf].bufhidden = "hide"
    vim.bo[M._buf].swapfile = false
    vim.bo[M._buf].filetype = "markdown"
  end
  vim.bo[M._buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false

  local width = math.min(120, math.floor(vim.o.columns * 0.8))
  local height = math.min(30, math.max(#lines + 2, 12))
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_set_current_win(M._win)
  else
    M._win = vim.api.nvim_open_win(M._buf, true, {
      relative = "editor",
      row = row, col = col,
      width = width, height = height,
      style = "minimal", border = "rounded",
      title = " nowork " .. mode_filter .. " overview — " .. vim.fn.fnamemodify(cwd, ":t") .. " ",
      title_pos = "center",
      footer = " <CR> open · r restart · d delete · n new · R refresh · q close · ? ",
      footer_pos = "left",
    })
    vim.wo[M._win].cursorline = true
    vim.wo[M._win].wrap = false
  end

  local function current_row()
    if not M._win or not vim.api.nvim_win_is_valid(M._win) then return nil end
    local r = vim.api.nvim_win_get_cursor(M._win)[1]
    return row_map[r]
  end

  local kopts = { buffer = M._buf, nowait = true, silent = true }
  local function bind(k, fn) vim.keymap.set("n", k, fn, kopts) end

  bind("q", close)
  bind("<Esc>", close)
  bind("R", function() close(); vim.schedule(function() M.open({ mode = mode_filter, cwd = cwd }) end) end)
  bind("n", function()
    close()
    local nw = require("djinni.nowork")
    local entry = nw[mode_filter == "autorun" and "auto" or mode_filter]
    if entry then entry("", { cwd = cwd }) end
  end)
  bind("<CR>", function()
    local info = current_row()
    if not info then return end
    if info.kind == "droid" then
      close()
      local d = require("djinni.nowork.droid").active[info.droid_id]
      if d and d.log_buf and d.log_buf.show then d.log_buf:show() end
    elseif info.kind == "archive" then
      close()
      local picker = require("djinni.nowork.picker")
      vim.schedule(function() picker.run_archive_action(info.path, info.has_state) end)
    end
  end)
  bind("r", function()
    local info = current_row()
    if info and info.kind == "archive" and info.has_state then
      close()
      require("djinni.nowork.droid").restart_from_archive(info.path)
    else
      vim.notify("nowork: cursor is not on a resumable archive", vim.log.levels.WARN)
    end
  end)
  bind("d", function()
    local info = current_row()
    if not (info and info.kind == "archive") then
      vim.notify("nowork: cursor is not on an archive row", vim.log.levels.WARN)
      return
    end
    local ok, choice = pcall(vim.fn.confirm, "Delete worklog " .. vim.fn.fnamemodify(info.path, ":t") .. "?", "&Delete\n&Cancel", 2)
    if not ok or choice ~= 1 then return end
    os.remove(info.path)
    local sidecar = require("djinni.nowork.archive").state_path(info.path)
    if sidecar then os.remove(sidecar) end
    vim.notify("nowork: deleted " .. vim.fn.fnamemodify(info.path, ":t"), vim.log.levels.INFO)
    close()
    vim.schedule(function() M.open({ mode = mode_filter, cwd = cwd }) end)
  end)
  bind("?", function()
    require("djinni.nowork.help").show("nowork overview", {
      { key = "<CR>",     desc = "open (droid log / archive menu)" },
      { key = "r",        desc = "restart from archive (needs ↻)" },
      { key = "d",        desc = "delete archive (+ sidecar)" },
      { key = "n",        desc = "new " .. mode_filter .. " in this cwd" },
      { key = "R",        desc = "refresh" },
      { key = "q / <Esc>",desc = "close" },
    })
  end)
end

return M
