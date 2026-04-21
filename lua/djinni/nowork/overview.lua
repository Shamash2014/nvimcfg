local M = {}

M._bufs = {}
M._state = {}
M._line_index = {}
M._fold_state = M._fold_state or {}
M._expanded = M._expanded or {}

local ns

local function get_ns()
  if not ns then ns = require("neowork.highlight").ns end
  return ns
end

local function key_for(opts)
  local scope = opts.all_projects and "__all__" or (opts.cwd or vim.fn.getcwd())
  return table.concat({
    scope,
    opts.mode or "*",
    opts.label or "",
  }, "::")
end

function M._foldtext()
  local v = vim.v
  local line = vim.fn.getline(v.foldstart)
  local hidden = (v.foldend or v.foldstart) - v.foldstart
  if hidden <= 0 then return line end
  return line .. "  (" .. hidden .. " hidden)"
end

local function format_elapsed(seconds)
  if not seconds or seconds < 0 then return "?" end
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

local function humanize_bytes(n)
  n = tonumber(n or 0) or 0
  if n < 1024 then return n .. " B" end
  if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
  return string.format("%.2f MB", n / (1024 * 1024))
end

local function dir_size(path)
  local total = 0
  if vim.fn.isdirectory(path) == 0 then return 0 end
  local function walk(dir)
    for _, name in ipairs(vim.fn.readdir(dir) or {}) do
      local full = dir .. "/" .. name
      local stat = vim.uv.fs_stat(full)
      if stat then
        if stat.type == "directory" then
          walk(full)
        else
          total = total + (stat.size or 0)
        end
      end
    end
  end
  walk(path)
  return total
end

local function short_root(path)
  if not path or path == "" then return "?" end
  return vim.fn.fnamemodify(path, ":t")
end

local function project_label(path)
  if not path or path == "" then return "?" end
  return short_root(path) .. "  " .. path
end

local function open_project_root(root, opts)
  if not root or root == "" then return end
  opts = opts or {}
  if opts.split == "vsplit" then
    vim.cmd("botright vsplit")
  end
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  vim.cmd("edit " .. vim.fn.fnameescape(root))
end

local function known_roots()
  local archive = require("djinni.nowork.archive")
  local droid_mod = require("djinni.nowork.droid")
  local roots = {}

  local function add(path)
    if path and path ~= "" then
      roots[vim.fn.fnamemodify(path, ":p"):gsub("/$", "")] = true
    end
  end

  add(vim.fn.getcwd())

  local ok_projects, projects = pcall(require, "djinni.integrations.projects")
  if ok_projects and projects and projects.get then
    for _, root in ipairs(projects.get() or {}) do
      add(root)
    end
  end

  for _, d in pairs(droid_mod.active or {}) do
    add(d.opts and d.opts.cwd)
  end

  for _, h in ipairs(droid_mod.history or {}) do
    add(h.cwd)
    if h.archive_path then
      add(h.archive_path:match("^(.*)/%.nowork/logs/"))
    end
  end

  for _, a in ipairs(archive.list(30) or {}) do
    add(a.cwd)
  end

  local list = vim.tbl_keys(roots)
  table.sort(list)
  return list
end

local function collect_stats(root, mode_filter)
  local archive = require("djinni.nowork.archive")
  local droid_mod = require("djinni.nowork.droid")
  local active = {}
  local archived = {}
  local active_by_status = {}
  local resumable = 0

  for _, d in pairs(droid_mod.active or {}) do
    local cwd = d.opts and d.opts.cwd
    if cwd == root and ((not mode_filter) or d.mode == mode_filter) then
      active[#active + 1] = d
      local status = d.status or "idle"
      active_by_status[status] = (active_by_status[status] or 0) + 1
    end
  end

  for _, a in ipairs(archive.list(30, { root }) or {}) do
    if ((not mode_filter) or a.mode == mode_filter) and a.cwd == root then
      archived[#archived + 1] = a
      if a.has_state then resumable = resumable + 1 end
    end
  end

  table.sort(active, function(a, b)
    local sa = a.started_at or 0
    local sb = b.started_at or 0
    if sa ~= sb then return sa > sb end
    return (a.id or "") < (b.id or "")
  end)

  table.sort(archived, function(a, b)
    if a.date == b.date then return a.stamp > b.stamp end
    return a.date > b.date
  end)

  return {
    root = root,
    name = short_root(root),
    active = active,
    archived = archived,
    active_by_status = active_by_status,
    resumable = resumable,
    disk = dir_size(root .. "/.nowork/logs"),
  }
end

local function collect(opts)
  local roots = opts.all_projects and known_roots() or { opts.cwd or vim.fn.getcwd() }
  local projects = {}
  local active = {}
  local archived = {}
  local active_by_status = {}
  local total_disk = 0
  local total_resumable = 0

  for _, root in ipairs(roots) do
    local stats = collect_stats(root, opts.mode)
    projects[#projects + 1] = stats
    total_disk = total_disk + (stats.disk or 0)
    total_resumable = total_resumable + (stats.resumable or 0)
    for _, d in ipairs(stats.active) do
      active[#active + 1] = d
    end
    for _, a in ipairs(stats.archived) do
      archived[#archived + 1] = a
    end
    for status, count in pairs(stats.active_by_status) do
      active_by_status[status] = (active_by_status[status] or 0) + count
    end
  end

  table.sort(projects, function(a, b)
    local alive_a = #a.active > 0
    local alive_b = #b.active > 0
    if alive_a ~= alive_b then return alive_a end
    local total_a = #a.active + #a.archived
    local total_b = #b.active + #b.archived
    if total_a ~= total_b then return total_a > total_b end
    return (a.name or "") < (b.name or "")
  end)

  table.sort(active, function(a, b)
    local acwd = a.opts and a.opts.cwd or ""
    local bcwd = b.opts and b.opts.cwd or ""
    if acwd ~= bcwd then return acwd < bcwd end
    return (a.started_at or 0) > (b.started_at or 0)
  end)

  table.sort(archived, function(a, b)
    local acwd = a.cwd or ""
    local bcwd = b.cwd or ""
    if acwd ~= bcwd then return acwd < bcwd end
    if a.date == b.date then return a.stamp > b.stamp end
    return a.date > b.date
  end)

  return {
    opts = opts,
    roots = roots,
    projects = projects,
    active = active,
    archived = archived,
    active_by_status = active_by_status,
    total_disk = total_disk,
    total_resumable = total_resumable,
  }
end

local STATUS_ORDER = {
  running = 1,
  idle = 2,
  blocked = 3,
  cancelled = 4,
  done = 5,
}

local STATUS_SIGIL = {
  running = "●",
  idle = "○",
  blocked = "!",
  cancelled = "×",
  done = "·",
}

local function droid_line(d)
  local root = short_root(d.opts and d.opts.cwd)
  local mode = d.mode or "?"
  local phase = d.mode == "autorun" and d.state and d.state.phase and (":" .. d.state.phase) or ""
  local status = d.status or "idle"
  local prompt = (d.initial_prompt or ""):gsub("\n", " ")
  if #prompt > 56 then prompt = prompt:sub(1, 55) .. "…" end
  local age = format_elapsed(os.time() - (d.started_at or os.time()))
  return string.format("%s %s %-16s %-10s %-8s %s", STATUS_SIGIL[status] or "·", root, (d.id or "?") .. " " .. mode .. phase, status, age, prompt)
end

local function archive_line(a)
  local root = short_root(a.cwd)
  local hh = a.stamp and (a.stamp:sub(1, 2) .. ":" .. a.stamp:sub(3, 4)) or "??:??"
  local badge = a.has_state and "↻" or "·"
  local prompt = a.prompt_hint or ""
  if prompt == "" then
    prompt = require("djinni.nowork.archive").prompt_hint(a.path) or ""
    a.prompt_hint = prompt
  end
  prompt = prompt:gsub("\n", " ")
  if #prompt > 56 then prompt = prompt:sub(1, 55) .. "…" end
  return string.format("%s %s %s  %-10s %-10s %s", badge, a.date or "?", hh, root, a.mode or "?", prompt)
end

local function entry_root(entry)
  if not entry then return nil end
  if entry.type == "project" then return entry.root end
  if entry.type == "droid" then
    local d = entry.droid
    return d and d.opts and d.opts.cwd or nil
  end
  if entry.type == "archive" then
    local a = entry.archive
    return a and a.cwd or nil
  end
  return nil
end

local function capture_fold_state(buf)
  local prev = M._fold_state[buf] or {}
  local idx = M._line_index[buf] or {}
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then return prev end
  local win = wins[1]
  local state = {}
  vim.api.nvim_win_call(win, function()
    for lnum, entry in pairs(idx) do
      if entry.type == "section" or entry.type == "project" then
        local id = entry.id or entry.root
        state[id] = vim.fn.foldclosed(lnum) ~= -1
      end
    end
  end)
  for k, v in pairs(prev) do
    if state[k] == nil then state[k] = v end
  end
  return state
end

local function apply_folds(buf, ranges, state)
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then return end
  local win = wins[1]
  vim.api.nvim_win_call(win, function()
    vim.cmd("silent! normal! zE")
    for _, r in ipairs(ranges) do
      if r.stop > r.start then
        vim.cmd(string.format("silent! %d,%dfold", r.start, r.stop))
      end
    end
    for _, r in ipairs(ranges) do
      if state[r.id] then
        pcall(vim.cmd, string.format("silent! %dfoldclose", r.start))
      else
        pcall(vim.cmd, string.format("silent! %dfoldopen", r.start))
      end
    end
  end)
end

local function apply_window_style(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].cursorline = true
  pcall(function() vim.wo[win].cursorlineopt = "line" end)
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldmethod = "manual"
  vim.wo[win].foldenable = true
  vim.wo[win].foldtext = "v:lua.require'djinni.nowork.overview'._foldtext()"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].fillchars = "fold: ,foldopen:▾,foldclose:▸,foldsep: ,eob: "
  vim.wo[win].statuscolumn = ""
  vim.wo[win].winhighlight = "Normal:NeoworkIdxNormal,CursorLine:NeoworkIdxCursorLine,Folded:NeoworkIdxSection"
end

local function title_for(state)
  local scope = state.opts.all_projects and "all projects" or short_root(state.opts.cwd or vim.fn.getcwd())
  local label = state.opts.label or state.opts.mode or "overview"
  return string.format(" nowork %s — %s ", label, scope)
end

local function render(buf, state)
  local lines = {}
  local row_index = {}
  local fold_ranges = {}
  local open_ranges = {}
  local prev_folds = capture_fold_state(buf)
  local hl_marks = {}

  local function byte_col(text, char_idx)
    local max_chars = vim.str_utfindex(text)
    if char_idx < 0 then char_idx = 0 end
    if char_idx > max_chars then char_idx = max_chars end
    return vim.str_byteindex(text, char_idx) or #text
  end

  local function hl(row, start_char, end_char, group)
    hl_marks[#hl_marks + 1] = { row = row, start_col = start_char, end_col = end_char, group = group }
  end

  local function add(line, entry)
    lines[#lines + 1] = line or ""
    if entry then row_index[#lines] = entry end
  end

  local function open_range(id)
    open_ranges[#open_ranges + 1] = { id = id, start = #lines, stop = #lines }
  end

  local function close_range()
    local range = table.remove(open_ranges)
    if range then
      range.stop = #lines
      fold_ranges[#fold_ranges + 1] = range
    end
  end

  local label = state.opts.label or state.opts.mode or (state.opts.all_projects and "projects" or "overview")
  local scope = state.opts.all_projects and "all projects" or (state.opts.cwd or vim.fn.getcwd())
  local status_bits = {}
  for status, count in pairs(state.active_by_status or {}) do
    status_bits[#status_bits + 1] = { status = status, count = count }
  end
  table.sort(status_bits, function(a, b)
    local oa = STATUS_ORDER[a.status] or 99
    local ob = STATUS_ORDER[b.status] or 99
    if oa ~= ob then return oa < ob end
    return a.status < b.status
  end)
  local status_text = {}
  for _, bit in ipairs(status_bits) do
    status_text[#status_text + 1] = bit.status .. "=" .. bit.count
  end

  local function add_meta(label_text, value, label_hl)
    local line = string.format("  %-8s %s", label_text, value)
    add(line)
    hl(#lines - 1, 2, 2 + #label_text, label_hl or "NeoworkIdxSection")
    hl(#lines - 1, 11, #line, "NeoworkIdxMuted")
  end

  do
    local header = "  Nowork Status"
    add(header)
    hl(#lines - 1, 2, #header, "NeoworkIdxTitle")
  end
  add_meta("Head", label, "NeoworkIdxTitle")
  add_meta("Root", scope)
  add_meta("Sessions", string.format("%d live, %d archived, %d resumable", #state.active, #state.archived, state.total_resumable), "NeoworkIdxSession")
  add_meta("Disk", humanize_bytes(state.total_disk), "NeoworkIdxSession")
  add_meta("Status", #status_text > 0 and table.concat(status_text, " · ") or "none")
  do
    local rule = "  " .. string.rep("─", 70)
    add(rule)
    hl(#lines - 1, 0, #rule, "NeoworkIdxRule")
  end
  add("")

  local buckets = {}
  for _, d in ipairs(state.active) do
    local status = d.status or "idle"
    buckets[status] = buckets[status] or {}
    buckets[status][#buckets[status] + 1] = d
  end

  local bucket_order = { "running", "idle", "blocked", "cancelled", "done" }
  for _, status in ipairs(bucket_order) do
    local items = buckets[status] or {}
    if #items > 0 then
      local section_id = "active:" .. status
      local chev = prev_folds[section_id] and "▸" or "▾"
      local title = string.format("%s Active %s (%d)", chev, status, #items)
      add(title, { type = "section", id = section_id })
      hl(#lines - 1, 0, 1, "NeoworkIdxChevron")
      hl(#lines - 1, 2, 8, "NeoworkIdxSection")
      hl(#lines - 1, 9, 9 + #status, ({
        running = "NeoworkIdxStatusRun",
        idle = "NeoworkIdxStatusRdy",
        blocked = "NeoworkIdxStatusPerm",
        cancelled = "NeoworkIdxStatusEnd",
        done = "NeoworkIdxStatusEnd",
      })[status] or "NeoworkIdxMuted")
      hl(#lines - 1, #title - (#tostring(#items) + 1), #title, "NeoworkIdxCount")
      open_range(section_id)
      for _, d in ipairs(items) do
        local line = "  " .. droid_line(d)
        add(line, { type = "droid", droid = d })
        do
          local status_name = d.status or "idle"
          local project = short_root(d.opts and d.opts.cwd)
          local mode = d.mode or "?"
          local phase = d.mode == "autorun" and d.state and d.state.phase and (":" .. d.state.phase) or ""
          local id_and_mode = (d.id or "?") .. " " .. mode .. phase
          local sigil_end = byte_col(line, 3)
          hl(#lines - 1, byte_col(line, 2), sigil_end, ({
            running = "NeoworkIdxStatusRun",
            idle = "NeoworkIdxStatusRdy",
            blocked = "NeoworkIdxStatusPerm",
            cancelled = "NeoworkIdxStatusEnd",
            done = "NeoworkIdxStatusEnd",
          })[status_name] or "NeoworkIdxMuted")
          local project_start = line:find(project, 1, true)
          if project_start then
            hl(#lines - 1, project_start - 1, project_start - 1 + #project, "NeoworkIdxProject")
          end
          local ident_start = line:find(id_and_mode, 1, true)
          if ident_start then
            hl(#lines - 1, ident_start - 1, ident_start - 1 + #id_and_mode, "NeoworkIdxSession")
          end
          local status_start = line:find(status_name, 1, true)
          if status_start then
            hl(#lines - 1, status_start - 1, status_start - 1 + #status_name, "NeoworkIdxMuted")
          end
        end
        local expanded = M._expanded[buf] and M._expanded[buf]["droid:" .. (d.id or "")]
        if expanded then
          local tokens = d.state and d.state.tokens or {}
          local detail = string.format("     root     %s", d.opts and d.opts.cwd or "?")
          add(detail, { type = "detail", droid = d })
          hl(#lines - 1, 0, 5, "NeoworkIdxRule")
          hl(#lines - 1, 5, 13, "NeoworkIdxSection")
          hl(#lines - 1, 13, #detail, "NeoworkIdxMuted")
          detail = string.format("     runtime  provider %s  queue %d  mode %s", d.provider_name or "?", #(d.state and d.state.queue or {}), d.mode or "?")
          add(detail, { type = "detail", droid = d })
          hl(#lines - 1, 0, 5, "NeoworkIdxRule")
          hl(#lines - 1, 5, 13, "NeoworkIdxSection")
          hl(#lines - 1, 13, #detail, "NeoworkIdxMuted")
          detail = string.format("     usage    in %s  out %s  read %s  write %s  cost %s",
            tokens.input or 0, tokens.output or 0, tokens.cache_read or 0, tokens.cache_write or 0, tokens.cost or 0)
          add(detail, { type = "detail", droid = d })
          hl(#lines - 1, 0, 5, "NeoworkIdxRule")
          hl(#lines - 1, 5, 13, "NeoworkIdxSection")
          hl(#lines - 1, 13, #detail, "NeoworkIdxMuted")
        end
      end
      close_range()
      add("")
    end
  end

  local recent_count = math.min(#state.archived, 18)
  local recent = {}
  for i = 1, recent_count do
    recent[#recent + 1] = state.archived[i]
  end
  do
    local section_id = "archive:recent"
    local chev = prev_folds[section_id] and "▸" or "▾"
    local title = string.format("%s Recent archive (%d)", chev, #recent)
    add(title, { type = "section", id = section_id })
    hl(#lines - 1, 0, 1, "NeoworkIdxChevron")
    hl(#lines - 1, 2, 16, "NeoworkIdxSection")
    hl(#lines - 1, #title - (#tostring(#recent) + 1), #title, "NeoworkIdxCount")
    open_range(section_id)
  end
  if #recent == 0 then
    add("  (none)")
  else
    for _, a in ipairs(recent) do
      local line = "  " .. archive_line(a)
      add(line, { type = "archive", archive = a })
      do
        local badge_hl = a.has_state and "NeoworkIdxStatusRun" or "NeoworkIdxMuted"
        local project = short_root(a.cwd)
        local mode = a.mode or "?"
        hl(#lines - 1, byte_col(line, 2), byte_col(line, 3), badge_hl)
        local project_start = line:find(project, 1, true)
        if project_start then
          hl(#lines - 1, project_start - 1, project_start - 1 + #project, "NeoworkIdxProject")
        end
        local mode_start = line:find(mode, 1, true)
        if mode_start then
          hl(#lines - 1, mode_start - 1, mode_start - 1 + #mode, "NeoworkIdxSession")
        end
      end
      local expanded = M._expanded[buf] and M._expanded[buf]["archive:" .. (a.path or "")]
      if expanded then
        local detail = "     path     " .. (a.path or "?")
        add(detail, { type = "detail", archive = a })
        hl(#lines - 1, 0, 5, "NeoworkIdxRule")
        hl(#lines - 1, 5, 13, "NeoworkIdxSection")
        hl(#lines - 1, 13, #detail, "NeoworkIdxMuted")
        if a.has_state then
          detail = "     state    " .. (require("djinni.nowork.archive").state_path(a.path) or "?")
          add(detail, { type = "detail", archive = a })
          hl(#lines - 1, 0, 5, "NeoworkIdxRule")
          hl(#lines - 1, 5, 13, "NeoworkIdxSection")
          hl(#lines - 1, 13, #detail, "NeoworkIdxMuted")
        end
      end
    end
  end
  close_range()
  add("")

  do
    local section_id = "projects"
    local chev = prev_folds[section_id] and "▸" or "▾"
    local title = string.format("%s Projects (%d)", chev, #state.projects)
    add(title, { type = "section", id = section_id })
    hl(#lines - 1, 0, 1, "NeoworkIdxChevron")
    hl(#lines - 1, 2, 10, "NeoworkIdxSection")
    hl(#lines - 1, #title - (#tostring(#state.projects) + 1), #title, "NeoworkIdxCount")
    open_range(section_id)
  end
  for _, project in ipairs(state.projects) do
    local project_id = "project:" .. project.root
    local chev = prev_folds[project_id] and "▸" or "▾"
    local header = string.format("  %s %s (%d live · %d archived · %d resumable · %s)",
      chev,
      project.name, #project.active, #project.archived, project.resumable, humanize_bytes(project.disk))
    add(header, { type = "project", root = project.root, id = project_id })
    hl(#lines - 1, 2, 3, "NeoworkIdxChevron")
    hl(#lines - 1, 4, 4 + #project.name, "NeoworkIdxProject")
    hl(#lines - 1, 4 + #project.name + 1, #header, "NeoworkIdxCount")
    open_range(project_id)
    local root_line = "    root " .. project.root
    add(root_line, { type = "project_root", root = project.root })
    hl(#lines - 1, 4, 8, "NeoworkIdxSection")
    hl(#lines - 1, 9, #root_line, "NeoworkIdxMuted")
    if #project.active == 0 and #project.archived == 0 then
      add("    (empty)")
    else
      for _, d in ipairs(project.active) do
        add("    " .. droid_line(d), { type = "droid", droid = d })
      end
      local limit = math.min(#project.archived, 8)
      for i = 1, limit do
        local a = project.archived[i]
        add("    " .. archive_line(a), { type = "archive", archive = a })
      end
      if #project.archived > limit then
        local more = string.format("    … %d more archived", #project.archived - limit)
        add(more)
        hl(#lines - 1, 4, #more, "NeoworkIdxMuted")
      end
    end
    close_range()
  end
  close_range()
  add("")
  do
    local rule = "  " .. string.rep("─", 70)
    add(rule)
    hl(#lines - 1, 0, #rule, "NeoworkIdxRule")
  end
  do
    local footer = "  Commands <CR> visit  <Tab> details  . actions  i compose  x cancel  r restart  d delete  n new  R refresh  q quit"
    add(footer)
    hl(#lines - 1, 2, 10, "NeoworkIdxSection")
    hl(#lines - 1, 11, #footer, "NeoworkIdxMuted")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local nns = get_ns()
  vim.api.nvim_buf_clear_namespace(buf, nns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, nns, mark.row, byte_col(lines[mark.row + 1] or "", mark.start_col), {
      end_col = byte_col(lines[mark.row + 1] or "", mark.end_col),
      hl_group = mark.group,
    })
  end
  M._line_index[buf] = row_index
  M._fold_state[buf] = prev_folds
  apply_folds(buf, fold_ranges, prev_folds)
end

local function entry_at_cursor(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return M._line_index[buf] and M._line_index[buf][row] or nil
end

local function choose_project(default_root, callback)
  local roots = known_roots()
  if #roots == 0 then
    callback(nil)
    return
  end
  if default_root then
    callback(default_root)
    return
  end
  local labels = {}
  for _, root in ipairs(roots) do
    labels[#labels + 1] = project_label(root)
  end
  vim.ui.select(labels, { prompt = "nowork project" }, function(_, idx)
    callback(idx and roots[idx] or nil)
  end)
end

local function open_item(buf, entry)
  if not entry then return end
  local state = M._state[buf] or {}
  local opts = state.opts or {}
  if entry.type == "droid" then
    local d = entry.droid
    if d and d.log_buf and d.log_buf.show then d.log_buf:show() end
    return
  end
  if entry.type == "archive" then
    require("djinni.nowork.archive").open(entry.archive.path, { cwd = entry.archive.cwd })
    return
  end
  if entry.type == "project_root" then
    open_project_root(entry.root, { split = opts.project_visit_split })
    return
  end
  if entry.type == "project" then
    open_project_root(entry.root, { split = opts.project_visit_split })
    return
  end
  if entry.type == "section" then
    pcall(vim.cmd, "normal! za")
  end
end

local function run_action(entry)
  if not entry then return end
  if entry.type == "droid" then
    require("djinni.nowork.picker").run_action(entry.droid)
    return
  end
  if entry.type == "archive" then
    require("djinni.nowork.picker").run_archive_action(entry.archive.path, entry.archive.has_state)
  end
end

local function click_open(buf)
  local pos = vim.fn.getmousepos()
  if pos.winid and pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid) then
    vim.api.nvim_set_current_win(pos.winid)
  end
  if pos.line and pos.line > 0 then
    pcall(vim.api.nvim_win_set_cursor, 0, { pos.line, math.max((pos.column or 1) - 1, 0) })
  end
  local entry = entry_at_cursor(buf)
  local state = M._state[buf] or {}
  local opts = state.opts or {}
  if entry and (entry.type == "project" or entry.type == "project_root") then
    open_project_root(entry.root, { split = opts.project_visit_split })
    return
  end
  open_item(buf, entry)
end

local function click_project_root(buf)
  local pos = vim.fn.getmousepos()
  if pos.winid and pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid) then
    vim.api.nvim_set_current_win(pos.winid)
  end
  if pos.line and pos.line > 0 then
    pcall(vim.api.nvim_win_set_cursor, 0, { pos.line, math.max((pos.column or 1) - 1, 0) })
  end
  local entry = entry_at_cursor(buf)
  local state = M._state[buf] or {}
  local opts = state.opts or {}
  if entry and (entry.type == "project" or entry.type == "project_root") then
    open_project_root(entry.root, { split = opts.project_visit_split })
  end
end

local function delete_archive(entry)
  if not entry or entry.type ~= "archive" then
    vim.notify("nowork: cursor is not on an archive row", vim.log.levels.WARN)
    return
  end
  local path = entry.archive.path
  local name = vim.fn.fnamemodify(path, ":t")
  if vim.fn.confirm("Delete worklog " .. name .. "?", "&Delete\n&Cancel", 2) ~= 1 then return end
  os.remove(path)
  local sidecar = require("djinni.nowork.archive").state_path(path)
  if sidecar then os.remove(sidecar) end
  vim.notify("nowork: deleted " .. name, vim.log.levels.INFO)
end

function M.refresh(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local state = M._state[buf]
  if not state then return end
  state.data = collect(state.opts)
  render(buf, state.data)
end

function M.refresh_all()
  for _, buf in pairs(M._bufs) do
    if buf and vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
      vim.schedule(function()
        M.refresh(buf)
      end)
    end
  end
end

local function setup_autocmds(buf, key)
  local group = vim.api.nvim_create_augroup("NoworkOverview_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    group = group,
    callback = function() M.refresh(buf) end,
  })
  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = group,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
        M.refresh(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
        vim.schedule(function() M.refresh(buf) end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    group = group,
    once = true,
    callback = function()
      M._bufs[key] = nil
      M._state[buf] = nil
      M._line_index[buf] = nil
      M._fold_state[buf] = nil
      M._expanded[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_name, "NoworkOverview_" .. buf)
    end,
  })
end

local function setup_buffer(buf)
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = "nowork overview: " .. desc })
  end

  map("<CR>", function()
    open_item(buf, entry_at_cursor(buf))
    M.refresh(buf)
  end, "open")

  map("<LeftMouse>", function()
    click_project_root(buf)
    M.refresh(buf)
  end, "mouse project root")

  map("<2-LeftMouse>", function()
    click_open(buf)
    M.refresh(buf)
  end, "mouse open")

  map(".", function()
    run_action(entry_at_cursor(buf))
    M.refresh(buf)
  end, "actions")

  map("i", function()
    local entry = entry_at_cursor(buf)
    if not entry or entry.type ~= "droid" then
      vim.notify("nowork: cursor is not on an active droid", vim.log.levels.WARN)
      return
    end
    require("djinni.nowork.compose").open(entry.droid, { alt_buf = vim.fn.bufnr("#") })
  end, "compose")

  map("a", function()
    local entry = entry_at_cursor(buf)
    if not entry or entry.type ~= "droid" then
      vim.notify("nowork: cursor is not on an active droid", vim.log.levels.WARN)
      return
    end
    require("djinni.nowork.compose").open(entry.droid, { alt_buf = vim.fn.bufnr("#") })
  end, "compose")

  map("x", function()
    local entry = entry_at_cursor(buf)
    if not entry or entry.type ~= "droid" then
      vim.notify("nowork: cursor is not on an active droid", vim.log.levels.WARN)
      return
    end
    require("djinni.nowork.droid").cancel(entry.droid)
    M.refresh(buf)
  end, "cancel")

  map("r", function()
    local entry = entry_at_cursor(buf)
    if not entry or entry.type ~= "archive" or not entry.archive.has_state then
      vim.notify("nowork: cursor is not on a resumable archive", vim.log.levels.WARN)
      return
    end
    require("djinni.nowork.droid").restart_from_archive(entry.archive.path)
    M.refresh(buf)
  end, "restart archive")

  map("d", function()
    delete_archive(entry_at_cursor(buf))
    M.refresh(buf)
  end, "delete archive")

  map("<Tab>", function()
    local entry = entry_at_cursor(buf)
    if not entry or (entry.type ~= "droid" and entry.type ~= "archive") then return end
    local prefix = entry.type == "droid" and "droid:" or "archive:"
    local id = prefix .. (entry.type == "droid" and (entry.droid.id or "") or (entry.archive.path or ""))
    M._expanded[buf] = M._expanded[buf] or {}
    M._expanded[buf][id] = not M._expanded[buf][id]
    M.refresh(buf)
  end, "toggle details")

  map("R", function() M.refresh(buf) end, "refresh")
  map("q", function() vim.api.nvim_win_close(0, false) end, "close")
  map("<Esc>", function() vim.api.nvim_win_close(0, false) end, "close")
  map("?", function()
    require("djinni.nowork.help").show("nowork overview", {
      { key = "<CR>",      desc = "open droid log / archive split / project root / toggle fold" },
      { key = "click project", desc = "open the project root directory" },
      { key = ".",         desc = "actions menu for droid or archive" },
      { key = "i / a",     desc = "compose to active droid" },
      { key = "x",         desc = "cancel active droid" },
      { key = "r",         desc = "restart archive from saved state" },
      { key = "d",         desc = "delete archive (+ sidecar)" },
      { key = "<Tab>",     desc = "toggle details" },
      { key = "n",         desc = "new routine/autorun for project under cursor" },
      { key = "za zc zo",  desc = "native folds" },
      { key = "R",         desc = "refresh" },
      { key = "q / <Esc>", desc = "close" },
    })
  end, "help")

  map("n", function()
    local root = entry_root(entry_at_cursor(buf))
    choose_project(root, function(chosen_root)
      if not chosen_root then return end
      Snacks.picker.select({ "routine", "autorun" }, { prompt = "new nowork" }, function(choice)
        if choice == "routine" then
          require("djinni.nowork").routine("", { cwd = chosen_root })
        elseif choice == "autorun" then
          require("djinni.nowork").auto("", { cwd = chosen_root })
        end
        M.refresh_all()
      end)
    end)
  end, "new")
end

function M.open(opts)
  opts = opts or {}
  local key = key_for(opts)
  local existing = M._bufs[key]

  if existing and vim.api.nvim_buf_is_valid(existing) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == existing then
        vim.api.nvim_set_current_win(win)
        apply_window_style(win)
        pcall(function() vim.wo[win].winbar = title_for(M._state[existing]) end)
        M.refresh(existing)
        return
      end
    end
    vim.cmd("botright vsplit")
    vim.api.nvim_set_current_buf(existing)
    apply_window_style(vim.api.nvim_get_current_win())
    pcall(function() vim.wo[0].winbar = title_for(M._state[existing]) end)
    vim.api.nvim_win_set_width(0, math.min(88, math.max(64, math.floor(vim.o.columns * 0.42))))
    M.refresh(existing)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "nowork-overview"
  if opts.cwd and opts.cwd ~= "" then
    vim.b[buf].nowork_cwd = opts.cwd
  end

  M._bufs[key] = buf
  M._state[buf] = { opts = vim.tbl_extend("force", {}, opts) }

  setup_buffer(buf)
  setup_autocmds(buf, key)

  vim.cmd("botright vsplit")
  vim.api.nvim_set_current_buf(buf)
  if opts.cwd and opts.cwd ~= "" then
    vim.cmd("lcd " .. vim.fn.fnameescape(opts.cwd))
  end
  vim.api.nvim_buf_set_name(buf, "nowork://overview/" .. key:gsub("[^%w_.%-]+", "_"))
  vim.api.nvim_win_set_width(0, math.min(88, math.max(64, math.floor(vim.o.columns * 0.42))))
  apply_window_style(vim.api.nvim_get_current_win())
  pcall(function() vim.wo[0].winbar = title_for(M._state[buf]) end)

  M.refresh(buf)
end

return M
