local M = {}

M._bufs = {}
M._roots = {}
M._last_refresh = {}
M._line_index = {}
M._fold_state = M._fold_state or {}
M._last_data = M._last_data or {}
M._filter = M._filter or {}
M._hidden_sessions = M._hidden_sessions
M._expanded = M._expanded or {}

function M._foldtext()
  local v = vim.v
  local line = vim.fn.getline(v.foldstart)
  local hidden = (v.foldend or v.foldstart) - v.foldstart
  if hidden <= 0 then return line end
  return line .. "  (" .. hidden .. " hidden)"
end

local ns
local function get_ns()
  if not ns then ns = require("neowork.highlight").ns end
  return ns
end

local STATUS_ORDER = { running = 1, awaiting = 2, review = 3, ready = 4, done = 5 }

local status_markers = {
  running  = "R",
  awaiting = "!",
  review   = "V",
  ready    = ".",
  done     = "-",
}

local status_sign_hl = {
  running  = "NeoworkIdxSignRunning",
  awaiting = "NeoworkIdxSignAwaiting",
  review   = "NeoworkIdxSignReview",
  ready    = "NeoworkIdxSignReady",
  done     = "NeoworkIdxSignDone",
}

local function hidden_path()
  local dir = vim.fn.stdpath("state") .. "/neowork"
  vim.fn.mkdir(dir, "p")
  return dir .. "/hidden.json"
end

local function load_hidden()
  if M._hidden_sessions then return M._hidden_sessions end
  local f = io.open(hidden_path(), "r")
  if not f then M._hidden_sessions = {}; return M._hidden_sessions end
  local data = f:read("*a"); f:close()
  local ok, decoded = pcall(vim.json.decode, data)
  M._hidden_sessions = (ok and type(decoded) == "table") and decoded or {}
  return M._hidden_sessions
end

local function save_hidden()
  local f = io.open(hidden_path(), "w"); if not f then return end
  f:write(vim.json.encode(M._hidden_sessions or {})); f:close()
end

local function normalize_status(raw)
  if raw == "idle" then return "ready" end
  if raw == "connecting" then return "running" end
  if raw == "submitting" then return "running" end
  if raw == "streaming" then return "running" end
  if raw == "tool" then return "running" end
  if raw == "interrupted" then return "review" end
  if raw == "error" then return "review" end
  if raw == "archived" then return "done" end
  if STATUS_ORDER[raw] then return raw end
  return "done"
end

local _bridge_cache
local function get_bridge_mod()
  if _bridge_cache ~= nil then return _bridge_cache or nil end
  local ok, bridge = pcall(require, "neowork.bridge")
  _bridge_cache = ok and bridge or false
  return _bridge_cache or nil
end

local function resolve_runtime_status(s)
  local filepath = s._filepath
  if filepath and filepath ~= "" then
    local buf = vim.fn.bufnr(filepath)
    if buf > 0 and vim.api.nvim_buf_is_valid(buf) then
      local bridge = get_bridge_mod()
      if bridge then
        if bridge.get_status_bucket then
          local status, meta = bridge.get_status_bucket(buf)
          return status, meta
        end
        if bridge.has_pending_permission and bridge.has_pending_permission(buf) then
          local perm = bridge.get_pending_permission and bridge.get_pending_permission(buf) or {}
          return "awaiting", { kind = "perm", title = perm.title, tool_kind = perm.tool_kind, tool_desc = perm.tool_desc }
        end
        if bridge.is_streaming and bridge.is_streaming(buf) then
          return "running", { kind = "streaming" }
        end
      end
    end
  end
  return normalize_status(s.status), nil
end

local function pad_l(s, w)
  s = s or ""
  if #s > w then return s:sub(1, w - 1) .. "~" end
  return s .. string.rep(" ", w - #s)
end

local function pad_r(s, w)
  s = s or ""
  if #s > w then return s:sub(1, w - 1) .. "~" end
  return string.rep(" ", w - #s) .. s
end

local function time_ago(iso_date)
  if not iso_date or iso_date == "" then return "" end
  local y, mo, d, h, mi, s = iso_date:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h) or 0, min = tonumber(mi) or 0, sec = tonumber(s) or 0,
  })
  local diff = os.time() - t
  if diff < 60 then return diff .. "s"
  elseif diff < 3600 then return math.floor(diff / 60) .. "m"
  elseif diff < 86400 then return math.floor(diff / 3600) .. "h"
  else return math.floor(diff / 86400) .. "d"
  end
end

local function sort_sessions(sessions)
  local copy = vim.list_slice(sessions, 1, #sessions)
  table.sort(copy, function(a, b)
    local oa = STATUS_ORDER[a.status] or 99
    local ob = STATUS_ORDER[b.status] or 99
    if oa ~= ob then return oa < ob end
    if (a._project_name or "") ~= (b._project_name or "") then
      return (a._project_name or "") < (b._project_name or "")
    end
    if (a._slug or "") ~= (b._slug or "") then
      return (a._slug or "") < (b._slug or "")
    end
    return (a.created or "") > (b.created or "")
  end)
  return copy
end

local function get_known_roots(home)
  local ok, projects = pcall(require, "djinni.integrations.projects")
  local roots
  if ok then roots = projects.get() else roots = { home or vim.fn.getcwd() } end
  local seen, out = {}, {}
  if home then seen[home] = true; out[#out + 1] = home end
  for _, r in ipairs(roots) do
    if not seen[r] then seen[r] = true; out[#out + 1] = r end
  end
  return out
end

local function collect_sessions(home)
  local store = require("neowork.store")
  local hidden = load_hidden()
  local all = {}
  local seen_path, seen_sid = {}, {}
  local total_cost = 0
  for _, root in ipairs(get_known_roots(home)) do
    local project = vim.fn.fnamemodify(root, ":t")
    for _, s in ipairs(store.scan_sessions(root)) do
      local path_key = s._filepath or ""
      local sid = s.session or ""
      if not seen_path[path_key] and not (sid ~= "" and seen_sid[sid]) and not hidden[path_key] then
        seen_path[path_key] = true
        if sid ~= "" then seen_sid[sid] = true end
        s._project_root = root
        s._project_name = project
        local st, req = resolve_runtime_status(s)
        s.status = st
        s._required = req
        if s.session and s.session ~= "" then
          s._last_turn = store.get_last_agent_turn(s.session, root)
          s._last_action = store.get_last_action(s.session, root)
        end
        total_cost = total_cost + (tonumber(s.cost or 0) or 0)
        all[#all + 1] = s
      end
    end
  end
  return sort_sessions(all), total_cost
end

local COL_PROJ, COL_AGE, COL_CTX, COL_COST = 14, 4, 5, 7

local STATUS_SIGIL = {
  running  = "●",
  awaiting = "!",
  review   = "◐",
  ready    = "○",
  done     = "·",
}
local STATUS_TOKEN_HL = {
  running  = "NeoworkIdxStatusRun",
  awaiting = "NeoworkIdxStatusPerm",
  review   = "NeoworkIdxStatusRvw",
  ready    = "NeoworkIdxStatusRdy",
  done     = "NeoworkIdxStatusEnd",
}

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
        local id = entry.type == "section" and entry.id or entry.root
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

function M._render(buf, sessions, total_cost)
  local prev_folds = capture_fold_state(buf)

  local lines = {}
  local hl_marks = {}
  local sign_marks = {}
  local fold_ranges = {}
  M._line_index[buf] = {}

  local function add(text) lines[#lines + 1] = text or "" end
  local function ln() return #lines end
  local function hl(row, col_s, col_e, group)
    hl_marks[#hl_marks + 1] = { row, col_s, col_e, group }
  end

  local function window_width_for(b)
    local wins = vim.fn.win_findbuf(b)
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) then
        local w = vim.api.nvim_win_get_width(win)
        local info = vim.fn.getwininfo(win)[1] or {}
        local tw = tonumber(info.textoff) or 0
        return math.max(20, w - tw)
      end
    end
    return vim.o.columns
  end
  local panel_w = math.max(60, window_width_for(buf) - 4)
  local open_ranges = {}

  local function render_session(s, indent)
    indent = indent or "  "
    local slug = s._slug or "unnamed"
    local show_project = (#indent <= 2)
    local name_field
    if show_project and s._project_name and s._project_name ~= "" then
      name_field = s._project_name .. "/" .. slug
    else
      name_field = slug
    end

    local sigil = STATUS_SIGIL[s.status] or STATUS_SIGIL.done
    local sigil_bytes = #sigil

    local required_text, required_hl
    if s._required and s._required.kind == "perm" then
      required_text = "[PERM " .. (s._required.tool_kind or "req") .. "] !/~/A"
      required_hl = "NeoworkIdxRequiredPerm"
    elseif s._required and s._required.kind == "streaming" then
      required_text = "[streaming]"
      required_hl = "NeoworkIdxRequiredRun"
    else
      local bits = {}
      local age = time_ago(s.created)
      if age ~= "" then bits[#bits + 1] = age end
      if s.context_pct and s.context_pct > 0 then bits[#bits + 1] = s.context_pct .. "%" end
      if s.cost and tonumber(s.cost or 0) > 0 then bits[#bits + 1] = "$" .. s.cost end
      required_text = table.concat(bits, " · ")
      required_hl = "NeoworkIdxMuted"
    end

    local action_text = ""
    if s._last_action and s._last_action.summary then
      action_text = s._last_action.summary
    elseif s._last_turn and s._last_turn ~= "" then
      action_text = "» " .. s._last_turn
    end

    local right_w = vim.api.nvim_strwidth(required_text)
    local name_w_disp = vim.api.nvim_strwidth(name_field)
    local sigil_disp = vim.api.nvim_strwidth(sigil)
    local fixed = #indent + sigil_disp + 2 + name_w_disp + 2
    local avail = math.max(4, panel_w - fixed - right_w - 2)
    local action_disp = vim.api.nvim_strwidth(action_text)
    if action_disp > avail then
      local keep = math.max(1, avail - 1)
      local byte_len = vim.fn.byteidx(action_text, keep)
      if byte_len and byte_len > 0 then
        action_text = action_text:sub(1, byte_len) .. "…"
        action_disp = vim.api.nvim_strwidth(action_text)
      end
    end

    local pad = panel_w - fixed - action_disp - right_w
    if pad < 2 then pad = 2 end
    local text = indent .. sigil .. "  " .. name_field .. "  " .. action_text .. string.rep(" ", pad) .. required_text
    add(text)
    local i = ln()
    M._line_index[buf][i] = { type = "session", session = s }
    local r = i - 1

    local pos = #indent
    hl(r, pos, pos + sigil_bytes, STATUS_TOKEN_HL[s.status] or "NeoworkIdxStatusEnd")
    pos = pos + sigil_bytes + 2
    hl(r, pos, pos + #name_field, "NeoworkIdxSession")
    pos = pos + #name_field + 2
    if action_text ~= "" then
      local prefix_len = 0
      if s._last_action and s._last_action.kind then
        for _, p in ipairs({ "→ ", "✎ ", "» ", "… ", "⚠ " }) do
          if action_text:sub(1, #p) == p then prefix_len = #p; break end
        end
      elseif action_text:sub(1, #"» ") == "» " then
        prefix_len = #"» "
      end
      if prefix_len > 0 then
        hl(r, pos, pos + prefix_len, "NeoworkIdxActionKind")
      end
      hl(r, pos + prefix_len, pos + #action_text, "NeoworkIdxMuted")
    end
    if required_text ~= "" then
      local rpos = #text - #required_text
      hl(r, rpos, rpos + #required_text, required_hl)
    end

    if s._required and s._required.kind == "perm" then
      local prefix = indent .. "     ↳ "
      local title = s._required.title or "permission request"
      local desc = s._required.tool_desc and s._required.tool_desc ~= title and (" — " .. s._required.tool_desc) or ""
      local max_w = math.max(20, panel_w - #prefix - 2)
      local body = title .. desc .. "  (!/~/A)"
      if #body > max_w then body = body:sub(1, max_w - 1) .. "…" end
      local line = prefix .. body
      add(line)
      local ti = ln()
      M._line_index[buf][ti] = { type = "activity", session = s }
      hl(ti - 1, #prefix, #line, "NeoworkIdxMuted")
    end

    local exp = M._expanded[buf] or {}
    if exp[s._filepath or ""] then
      local detail_prefix = indent .. "     │ "
      local function add_detail(text, caption_len, extra_marks)
        local max_w = math.max(20, panel_w - #detail_prefix - 2)
        local t = tostring(text or "")
        if #t > max_w then t = t:sub(1, max_w - 1) .. "…" end
        local line = detail_prefix .. t
        add(line)
        local di = ln()
        M._line_index[buf][di] = { type = "detail", session = s }
        local row = di - 1
        hl(row, 0, #detail_prefix, "NeoworkIdxRule")
        if caption_len and caption_len > 0 then
          hl(row, #detail_prefix, #detail_prefix + caption_len, "NeoworkIdxSection")
          hl(row, #detail_prefix + caption_len, #line, "NeoworkIdxMuted")
        else
          hl(row, #detail_prefix, #line, "NeoworkIdxMuted")
        end
        if extra_marks then
          for _, m in ipairs(extra_marks) do
            hl(row, #detail_prefix + m[1], #detail_prefix + m[2], m[3])
          end
        end
      end

      local sb = s._filepath and vim.fn.bufnr(s._filepath) or -1
      if sb > 0 and vim.api.nvim_buf_is_valid(sb) then
        local bridge = get_bridge_mod()
        if bridge and bridge.get_pending_permission then
          local p = bridge.get_pending_permission(sb)
          if p then
            add_detail("PERM  " .. (p.tool_kind or "?"), 4)
            if p.tool_desc and p.tool_desc ~= p.title then add_detail("      " .. p.tool_desc) end
            if type(p.raw_input) == "table" then
              for k, v in pairs(p.raw_input) do
                local val = type(v) == "table" and vim.json.encode(v) or tostring(v)
                add_detail("      " .. tostring(k) .. ": " .. val)
              end
            end
            if p.locations and #p.locations > 0 then
              for _, loc in ipairs(p.locations) do
                add_detail("      @ " .. (loc.path or vim.inspect(loc)))
              end
            end
          end
        end
      end

      if s.session and s.session ~= "" then
        local entries = require("neowork.store").get_current_plan(s.session, s._project_root or s.root)
        if entries and #entries > 0 then
          add_detail("PLAN  " .. #entries .. " steps", 4)
          for _, e in ipairs(entries) do
            local mark, mark_hl
            local status = e.status or ""
            if status == "completed" then mark, mark_hl = "✓", "NeoworkIdxStatusRun"
            elseif status == "in_progress" then mark, mark_hl = "→", "NeoworkIdxActionKind"
            else mark, mark_hl = "·", "NeoworkIdxMuted" end
            local prefix = "  " .. mark .. " "
            add_detail(prefix .. (e.content or e.title or ""), 0, { { #"  ", #"  " + #mark, mark_hl } })
          end
        end
      end

      if s._last_turn and s._last_turn ~= "" then
        add_detail("LAST  » " .. s._last_turn, 4)
      end
    end
  end

  local function open_range(id)
    open_ranges[#open_ranges + 1] = { id = id, start = ln(), stop = ln() }
  end
  local function close_range()
    local range = table.remove(open_ranges)
    if range then
      range.stop = ln()
      fold_ranges[#fold_ranges + 1] = range
    end
  end


  do
    local hdr = string.format("  NEOWORK · %d active · $%.2f", #sessions, total_cost or 0)
    add(hdr)
    hl(ln() - 1, 2, #"  NEOWORK", "NeoworkIdxTitle")
    hl(ln() - 1, #"  NEOWORK", #hdr, "NeoworkIdxMuted")
    local rule_w = math.max(20, panel_w - 2)
    local rule = "  " .. string.rep("─", rule_w)
    add(rule)
    hl(ln() - 1, 0, #rule, "NeoworkIdxRule")
    add("")
  end

  local buckets = { awaiting = {}, running = {}, review = {}, ready = {}, ended = {} }
  for _, s in ipairs(sessions) do
    if s.status == "awaiting" then table.insert(buckets.awaiting, s)
    elseif s.status == "running" then table.insert(buckets.running, s)
    elseif s.status == "review" then table.insert(buckets.review, s)
    elseif s.status == "ready" then table.insert(buckets.ready, s)
    else table.insert(buckets.ended, s) end
  end

  local secs = {
    { id = "awaiting", title = "Awaiting input", items = buckets.awaiting },
    { id = "running",  title = "Running",        items = buckets.running },
    { id = "review",   title = "In review",      items = buckets.review },
    { id = "ready",    title = "Ready",          items = buckets.ready },
    { id = "ended",    title = "Ended",          items = buckets.ended },
  }

  local filter = M._filter[buf]
  if filter then
    local map_id = { awaiting = "awaiting", running = "running", review = "review", ready = "ready", done = "ended", ended = "ended" }
    local keep = map_id[filter]
    local kept = {}
    for _, sec in ipairs(secs) do
      if sec.id == keep then kept[#kept + 1] = sec end
    end
    secs = kept
  end

  for _, sec in ipairs(secs) do
    if #sec.items > 0 then
      local chev = prev_folds[sec.id] and "▸ " or "▾ "
      local count = "(" .. #sec.items .. ")"
      local header = chev .. sec.title .. " " .. count
      add(header)
      local i = ln()
      M._line_index[buf][i] = { type = "section", id = sec.id }
      local chev_bytes = #chev
      hl(i - 1, 0, chev_bytes, "NeoworkIdxChevron")
      hl(i - 1, chev_bytes, chev_bytes + #sec.title, "NeoworkIdxSection")
      hl(i - 1, chev_bytes + #sec.title + 1, #header, "NeoworkIdxCount")
      open_range(sec.id)
      for _, s in ipairs(sec.items) do render_session(s, "  ") end
      close_range()
      add("")
    end
  end

  local by_root = {}
  local root_order = {}
  for _, s in ipairs(sessions) do
    local root = s._project_root or ""
    if not by_root[root] then
      by_root[root] = { root = root, name = s._project_name or vim.fn.fnamemodify(root, ":t"), sessions = {} }
      root_order[#root_order + 1] = by_root[root]
    end
    table.insert(by_root[root].sessions, s)
  end
  local function has_active(r)
    for _, s in ipairs(r.sessions) do
      if s.status == "running" or s.status == "awaiting" or s.status == "review" then return true end
    end
    return false
  end
  table.sort(root_order, function(a, b)
    local aa, ba = has_active(a), has_active(b)
    if aa ~= ba then return aa end
    if #a.sessions ~= #b.sessions then return #a.sessions > #b.sessions end
    return (a.name or "") < (b.name or "")
  end)

  if #root_order > 0 then
    local pchev = prev_folds["__projects__"] and "▸ " or "▾ "
    local pcount = "(" .. #root_order .. ")"
    local header = pchev .. "Projects " .. pcount
    add(header)
    local i = ln()
    M._line_index[buf][i] = { type = "section", id = "__projects__" }
    local pchev_bytes = #pchev
    hl(i - 1, 0, pchev_bytes, "NeoworkIdxChevron")
    hl(i - 1, pchev_bytes, pchev_bytes + #"Projects", "NeoworkIdxSection")
    hl(i - 1, pchev_bytes + #"Projects" + 1, #header, "NeoworkIdxCount")
    open_range("__projects__")
    for _, rd in ipairs(root_order) do
      local n_live = 0
      for _, s in ipairs(rd.sessions) do
        if s.status == "running" or s.status == "awaiting" or s.status == "review" then n_live = n_live + 1 end
      end
      local rchev = prev_folds[rd.root] and "▸ " or "▾ "
      local rcount = "(" .. n_live .. " live · " .. (#rd.sessions - n_live) .. " idle)"
      local phdr = "  " .. rchev .. rd.name .. " " .. rcount
      add(phdr)
      local pi = ln()
      M._line_index[buf][pi] = { type = "project", root = rd.root }
      local rchev_bytes = #rchev
      hl(pi - 1, 2, 2 + rchev_bytes, "NeoworkIdxChevron")
      hl(pi - 1, 2 + rchev_bytes, 2 + rchev_bytes + #rd.name, "NeoworkIdxProject")
      hl(pi - 1, 2 + rchev_bytes + #rd.name + 1, #phdr, "NeoworkIdxCount")
      open_range(rd.root)
      for _, s in ipairs(sort_sessions(rd.sessions)) do render_session(s, "    ") end
      close_range()
    end
    close_range()
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local nns = get_ns()
  vim.api.nvim_buf_clear_namespace(buf, nns, 0, -1)
  for _, m in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, nns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  for _, sg in ipairs(sign_marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, nns, sg.row, 0, {
      sign_text = sg.text,
      sign_hl_group = sg.hl,
    })
  end

  M._fold_state[buf] = prev_folds
  apply_folds(buf, fold_ranges, prev_folds)

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    pcall(function() vim.wo[win].winbar = "" end)
  end
end

local function entry_at_cursor(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return M._line_index[buf] and M._line_index[buf][row]
end

local function session_at_cursor(buf)
  local e = entry_at_cursor(buf)
  if e and (e.type == "session" or e.type == "activity" or e.type == "detail") then return e.session end
  return nil
end

local function project_at_cursor(buf)
  local e = entry_at_cursor(buf)
  if e and e.type == "project" then return e.root end
  return nil
end

local function nth_session_row(buf, n)
  local idx = M._line_index[buf] or {}
  local count = 0
  for i = 1, vim.api.nvim_buf_line_count(buf) do
    local e = idx[i]
    if e and e.type == "session" then
      count = count + 1
      if count == n then return i end
    end
  end
  return nil
end

function M._show_help()
  local help = {
    " Neowork Index",
    "",
    " <CR>              Open session / toggle fold (▾ open · ▸ collapsed)",
    " <count><CR>       Jump+open Nth session (e.g. 3<CR>)",
    " o, v, t           Open in hsplit / vsplit / new tab",
    " n / T             New session (vsplit / new tab)",
    " za zc zo zM zR    Native folds",
    " [[ ]]             Prev/next section",
    " gf                Follow session file (vsplit)",
    " <C-g>             Session info in cmdline",
    " <Tab>             Toggle inline details (permission, plan, last turn)",
    " !  ~  A           Permission: allow / deny / always",
    " R                 Refresh",
    " q                 Close",
    " ?                 This help",
    "",
    " Ex commands (buffer-local):",
    " :NeoworkNew[!] [name]        New session (vsplit; ! = tab)",
    " :NeoworkNewTab / NewSplit    New session in tab / hsplit",
    " :NeoworkRename {name}        Rename session at cursor",
    " :NeoworkDelete[!]            Delete (! skips confirm)",
    " :NeoworkArchive              Archive",
    " :NeoworkInterrupt            Interrupt running",
    " :NeoworkAllow / Deny / AllowAlways",
    " :NeoworkHide / UnhideAll",
    " :NeoworkAddProject [path]",
    " :NeoworkRemoveProject",
    " :NeoworkQuickfix             Populate quickfix",
    " :NeoworkRefresh",
    " :Neowork [status]            Filter buckets (running/awaiting/…)",
    " :'<,'>NeoworkArchive | Delete[!] | Hide  Batch over visual range",
  }
  vim.cmd("belowright " .. #help .. "new")
  local fbuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, help)
  vim.bo[fbuf].buftype = "nofile"
  vim.bo[fbuf].bufhidden = "wipe"
  vim.bo[fbuf].swapfile = false
  vim.bo[fbuf].modifiable = false
  vim.bo[fbuf].filetype = "neowork-help"
  vim.keymap.set("n", "q", "<Cmd>bd<CR>", { buffer = fbuf, nowait = true, silent = true })
end

local function pick_project(home, callback)
  local roots = get_known_roots(home)
  if #roots == 1 then callback(roots[1]); return end
  local labels = {}
  for _, r in ipairs(roots) do
    labels[#labels + 1] = vim.fn.fnamemodify(r, ":t") .. "  " .. r
  end
  vim.ui.select(labels, { prompt = "Project:" }, function(_, idx)
    if idx then callback(roots[idx]) end
  end)
end

local function require_bridge()
  local ok, bridge = pcall(require, "neowork.bridge")
  if not ok then return nil end
  return bridge
end

local function session_buf(s)
  if not s or not s._filepath then return nil end
  local b = vim.fn.bufnr(s._filepath)
  if b > 0 and vim.api.nvim_buf_is_valid(b) then return b end
  return nil
end

local function teardown_session(s)
  local sb = session_buf(s)
  if not sb then return end
  local bridge = require_bridge()
  if bridge and bridge.detach then pcall(bridge.detach, sb) end
  pcall(vim.api.nvim_buf_delete, sb, { force = true })
end

local function do_new_session(buf, name, split)
  split = split or "vsplit"
  pick_project(M._roots[buf], function(target)
    vim.schedule(function()
      require("neowork.util").new_session_interactive(target, {
        name = name,
        prompt = "Session name (" .. vim.fn.fnamemodify(target, ":t") .. "): ",
      }, function(filepath)
        if filepath then
          require("neowork.document").open(filepath, { split = split })
        else
          vim.notify("neowork: failed to create session file", vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

local function do_rename(buf, new_name)
  local s = session_at_cursor(buf); if not s then return end
  local apply = function(nm)
    if not nm or nm == "" then return end
    require("neowork.store").rename_session(s._project_root or s.root, s._slug, require("neowork.util").slug(nm))
    M._last_refresh[buf] = nil; M.refresh(buf)
  end
  if new_name and new_name ~= "" then apply(new_name)
  else vim.ui.input({ prompt = "New name: ", default = s._slug }, apply) end
end

local function do_delete(buf, force)
  local s = session_at_cursor(buf); if not s then return end
  if not force then
    if vim.fn.confirm("Delete " .. s._slug .. "?", "&Yes\n&No", 2) ~= 1 then return end
  end
  teardown_session(s)
  require("neowork.store").delete_session(s._project_root or s.root, s._slug)
  M._last_refresh[buf] = nil; M.refresh(buf)
end

local function do_archive(buf)
  local s = session_at_cursor(buf); if not s then return end
  require("neowork.store").archive_session(s._project_root or s.root, s._slug)
  M._last_refresh[buf] = nil; M.refresh(buf)
end

local function do_interrupt(buf)
  local s = session_at_cursor(buf); local sb = session_buf(s); local bridge = require_bridge()
  if sb and bridge and bridge.interrupt then
    bridge.interrupt(sb); M._last_refresh[buf] = nil; M.refresh(buf)
  end
end

local function do_perm(buf, action)
  local s = session_at_cursor(buf); local sb = session_buf(s); local bridge = require_bridge()
  if sb and bridge and bridge.permission_action then
    bridge.permission_action(sb, action); M._last_refresh[buf] = nil; M.refresh(buf)
  end
end

local function do_hide(buf)
  local s = session_at_cursor(buf); if not s or not s._filepath then return end
  load_hidden()[s._filepath] = true; save_hidden()
  M._last_refresh[buf] = nil; M.refresh(buf)
end

local function do_unhide_all(buf)
  M._hidden_sessions = {}; save_hidden()
  M._last_refresh[buf] = nil; M.refresh(buf)
end

local function do_add_project(buf, path)
  local apply = function(p)
    if not p or p == "" then return end
    local abs = vim.fn.fnamemodify(p, ":p"):gsub("/$", "")
    local ok, projects = pcall(require, "djinni.integrations.projects")
    if ok then projects.add(abs) end
    M._last_refresh[buf] = nil; M.refresh(buf)
  end
  if path and path ~= "" then apply(path)
  else vim.ui.input({ prompt = "Project root: ", default = vim.fn.getcwd(), completion = "dir" }, apply) end
end

local function do_remove_project(buf)
  local root = project_at_cursor(buf)
  if not root then
    local s = session_at_cursor(buf)
    root = s and s._project_root or nil
  end
  if not root then return end
  if vim.fn.confirm("Remove project " .. root .. "?", "&Yes\n&No", 2) ~= 1 then return end
  local ok, projects = pcall(require, "djinni.integrations.projects")
  if ok then projects.remove(root) end
  M._last_refresh[buf] = nil; M.refresh(buf)
end

local function sessions_in_range(buf, line1, line2)
  local out = {}
  local idx = M._line_index[buf] or {}
  for i = line1, line2 do
    local e = idx[i]
    if e and e.type == "session" then out[#out + 1] = e.session end
  end
  return out
end

local function for_each_in_range(buf, args, fn)
  local line1, line2 = args.line1, args.line2
  local is_range = args.range and args.range > 0
  local targets = is_range and sessions_in_range(buf, line1, line2) or nil
  if targets and #targets > 0 then
    for _, s in ipairs(targets) do fn(s) end
  else
    local s = session_at_cursor(buf)
    if s then fn(s) end
  end
  M._last_refresh[buf] = nil; M.refresh(buf)
end

local function do_quickfix(buf)
  local items = {}
  local idx = M._line_index[buf] or {}
  for i = 1, vim.api.nvim_buf_line_count(buf) do
    local e = idx[i]
    if e and e.type == "session" and e.session._filepath then
      local s = e.session
      items[#items + 1] = {
        filename = s._filepath,
        lnum = 1,
        text = string.format("[%s] %s  %s", s.status, s._project_name or "", s._slug or ""),
      }
    end
  end
  vim.fn.setqflist({}, " ", { title = "Neowork Sessions", items = items })
  vim.cmd("copen")
end

function M._setup_buffer(buf)
  local function map(key, fn, desc)
    vim.keymap.set("n", key, fn, { buffer = buf, desc = desc, nowait = true, silent = true })
  end

  map("<CR>", function()
    local count = vim.v.count
    if count > 0 then
      local row = nth_session_row(buf, count)
      if row then
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        local s = session_at_cursor(buf)
        if s then require("neowork.document").open(s._filepath, { split = "vsplit" }) end
      end
      return
    end
    local s = session_at_cursor(buf)
    if s then
      require("neowork.document").open(s._filepath, { split = "vsplit" })
      return
    end
    local e = entry_at_cursor(buf)
    if e and (e.type == "section" or e.type == "project") then
      pcall(vim.cmd, "normal! za")
      M._rerender_cached(buf)
    end
  end, "Open / toggle fold")

  local function rerender_after(cmd_str)
    return function()
      pcall(vim.cmd, cmd_str)
      M._rerender_cached(buf)
    end
  end
  map("zM", rerender_after("normal! zM"), "Close all folds")
  map("zR", rerender_after("normal! zR"), "Open all folds")
  map("za", rerender_after("normal! za"), "Toggle fold")
  map("zc", rerender_after("normal! zc"), "Close fold")
  map("zo", rerender_after("normal! zo"), "Open fold")

  map("v", function()
    local s = session_at_cursor(buf)
    if s then require("neowork.document").open(s._filepath, { split = "vsplit" }) end
  end, "Open in vsplit")

  map("o", function()
    local s = session_at_cursor(buf)
    if s then require("neowork.document").open(s._filepath, { split = "split" }) end
  end, "Open in split")

  map("t", function()
    local s = session_at_cursor(buf)
    if s then require("neowork.document").open(s._filepath, { split = "tabedit" }) end
  end, "Open in new tab")

  map("T", function() do_new_session(buf, nil, "tabedit") end, "New session in new tab")

  local function jump_section(dir)
    local idx = M._line_index[buf] or {}
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local target
    if dir > 0 then
      for i = row + 1, vim.api.nvim_buf_line_count(buf) do
        local e = idx[i]
        if e and (e.type == "section" or e.type == "project") then target = i; break end
      end
    else
      for i = row - 1, 1, -1 do
        local e = idx[i]
        if e and (e.type == "section" or e.type == "project") then target = i; break end
      end
    end
    if target then vim.api.nvim_win_set_cursor(0, { target, 0 }) end
  end
  map("[[", function() jump_section(-1) end, "Previous section")
  map("]]", function() jump_section(1)  end, "Next section")

  map("gf", function()
    local s = session_at_cursor(buf)
    if s then require("neowork.document").open(s._filepath, { split = "vsplit" }) end
  end, "Follow session file")

  map("<C-g>", function()
    local s = session_at_cursor(buf)
    if not s then return end
    vim.api.nvim_echo({
      { s._filepath or "", "Directory" },
      { "  [" .. (s.status or "?") .. "]", "Comment" },
      { "  " .. (s._project_name or ""), "Identifier" },
      { "  " .. (s.created or ""), "Comment" },
    }, false, {})
  end, "Session info")

  map("R", function() M._last_refresh[buf] = nil; M.refresh(buf) end, "Refresh")
  map("q", function() vim.api.nvim_win_close(0, false) end, "Close")
  map("?", function() M._show_help() end, "Help")

  local function cmd(name, fn, opts)
    opts = opts or {}
    opts.force = true
    vim.api.nvim_buf_create_user_command(buf, name, fn, opts)
  end
  cmd("NeoworkNew",           function(a) do_new_session(buf, a.args, a.bang and "tabedit" or "vsplit") end, { nargs = "?", bang = true })
  cmd("NeoworkNewTab",        function(a) do_new_session(buf, a.args, "tabedit") end, { nargs = "?" })
  cmd("NeoworkNewSplit",      function(a) do_new_session(buf, a.args, "split") end,   { nargs = "?" })
  cmd("NeoworkRename",        function(a) do_rename(buf, a.args) end,      { nargs = "?" })
  cmd("NeoworkDelete", function(a)
    local targets = (a.range and a.range > 0) and sessions_in_range(buf, a.line1, a.line2) or nil
    if targets and #targets > 0 then
      if not a.bang and vim.fn.confirm("Delete " .. #targets .. " sessions?", "&Yes\n&No", 2) ~= 1 then return end
      for _, s in ipairs(targets) do
        teardown_session(s)
        require("neowork.store").delete_session(s._project_root or s.root, s._slug)
      end
      M._last_refresh[buf] = nil; M.refresh(buf)
    else
      do_delete(buf, a.bang)
    end
  end, { bang = true, range = true })
  cmd("NeoworkArchive", function(a)
    for_each_in_range(buf, a, function(s)
      require("neowork.store").archive_session(s._project_root or s.root, s._slug)
    end)
  end, { range = true })
  cmd("NeoworkInterrupt",     function() do_interrupt(buf) end,            {})
  cmd("NeoworkAllow",         function() do_perm(buf, "allow") end,        {})
  cmd("NeoworkDeny",          function() do_perm(buf, "deny") end,         {})
  cmd("NeoworkAllowAlways",   function() do_perm(buf, "always") end,       {})
  cmd("NeoworkHide", function(a)
    for_each_in_range(buf, a, function(s)
      if s._filepath then load_hidden()[s._filepath] = true end
    end)
    save_hidden()
  end, { range = true })
  cmd("NeoworkUnhideAll",     function() do_unhide_all(buf) end,           {})
  cmd("NeoworkAddProject",    function(a) do_add_project(buf, a.args) end, { nargs = "?", complete = "dir" })
  cmd("NeoworkRemoveProject", function() do_remove_project(buf) end,       {})
  cmd("NeoworkQuickfix",      function() do_quickfix(buf) end,             {})
  cmd("NeoworkRefresh",       function() M._last_refresh[buf] = nil; M.refresh(buf) end, {})
  cmd("NeoworkHelp",          function() M._show_help() end,               {})
  cmd("Neowork", function(a)
    local arg = vim.trim(a.args or "")
    if arg == "" then M._filter[buf] = nil
    else M._filter[buf] = arg end
    M._last_refresh[buf] = nil; M._last_data[buf] = nil; M.refresh(buf)
  end, {
    nargs = "?",
    complete = function() return { "awaiting", "running", "review", "ready", "ended" } end,
  })

  map("n", function() do_new_session(buf) end,     "New session")
  map("a", function() do_archive(buf) end,         "Archive")
  map("d", function() do_delete(buf, false) end,   "Delete")
  map("r", function() do_rename(buf) end,          "Rename")
  map("x", function() do_interrupt(buf) end,       "Interrupt")
  map("<Tab>", function()
    local s = session_at_cursor(buf); if not s or not s._filepath then return end
    M._expanded[buf] = M._expanded[buf] or {}
    M._expanded[buf][s._filepath] = not M._expanded[buf][s._filepath]
    M._last_data[buf] = nil; M._last_refresh[buf] = nil; M.refresh(buf)
  end, "Toggle details")
  map("!", function() do_perm(buf, "allow") end,   "Permission: allow")
  map("~", function() do_perm(buf, "deny") end,    "Permission: deny")
  map("A", function() do_perm(buf, "always") end,  "Permission: always")
  map("h", function() do_hide(buf) end,            "Hide")
  map("H", function() do_unhide_all(buf) end,      "Unhide all")
  map("p", function() do_add_project(buf) end,     "Add project")
  map("P", function() do_remove_project(buf) end,  "Remove project")
  map("Q", function() do_quickfix(buf) end,        "Populate quickfix")
end

function M._setup_autocmds(buf)
  local group = vim.api.nvim_create_augroup("NeoworkIndex_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf, group = group,
    callback = function() M.refresh(buf) end,
  })
  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = group,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
        M._last_refresh[buf] = nil
        M._last_data[buf] = nil
        M.refresh(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
        vim.schedule(function() M._rerender_cached(buf) end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local resized = vim.v.event and vim.v.event.windows or {}
      local bufwins = vim.fn.win_findbuf(buf)
      local hit = false
      for _, rwin in ipairs(resized) do
        for _, bwin in ipairs(bufwins) do
          if rwin == bwin then hit = true; break end
        end
        if hit then break end
      end
      if hit then
        vim.schedule(function() M._rerender_cached(buf) end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf, group = group, once = true,
    callback = function()
      local root = M._roots[buf]
      if root then M._bufs[root] = nil end
      M._roots[buf] = nil
      M._last_refresh[buf] = nil
      M._line_index[buf] = nil
      M._fold_state[buf] = nil
      M._last_data[buf] = nil
      M._filter[buf] = nil
      M._expanded[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_name, "NeoworkIndex_" .. buf)
    end,
  })
end

local function sessions_signature(sessions, total_cost, expanded)
  local parts = { string.format("%.4f", total_cost or 0), tostring(#sessions) }
  if expanded then
    local keys = {}
    for k, v in pairs(expanded) do if v then keys[#keys + 1] = k end end
    table.sort(keys)
    parts[#parts + 1] = "exp:" .. table.concat(keys, ",")
  end
  for _, s in ipairs(sessions) do
    parts[#parts + 1] = table.concat({
      s._filepath or "",
      s.status or "",
      tostring(s.tokens or ""),
      tostring(s.cost or ""),
      tostring(s.context_pct or ""),
      tostring(s.summary or ""),
      tostring(s._last_turn or ""),
      tostring(s._last_action and (s._last_action.kind .. "|" .. (s._last_action.summary or "")) or ""),
      tostring(s._required and (s._required.kind .. "|" .. (s._required.tool_kind or "") .. "|" .. (s._required.title or "")) or ""),
    }, "\t")
  end
  return table.concat(parts, "\n")
end

function M.refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local now = vim.uv.now()
  if M._last_refresh[buf] and (now - M._last_refresh[buf]) < 2000 then return end
  M._last_refresh[buf] = now
  local sessions, total_cost = collect_sessions(M._roots[buf])
  local sig = sessions_signature(sessions, total_cost, M._expanded[buf])
  local prev = M._last_data[buf]
  if prev and prev.sig == sig then return end
  M._last_data[buf] = { sessions = sessions, total_cost = total_cost, sig = sig }
  M._render(buf, sessions, total_cost)
end

function M._rerender_cached(buf)
  local data = M._last_data[buf]
  if data then M._render(buf, data.sessions, data.total_cost) end
end

function M.refresh_all()
  for _, buf in pairs(M._bufs) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      M._last_refresh[buf] = nil
      M._last_data[buf] = nil
      local scheduled_buf = buf
      vim.schedule(function() M.refresh(scheduled_buf) end)
    end
  end
end

local function apply_window_style(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].cursorline = true
  pcall(function() vim.wo[win].cursorlineopt = "line" end)
  vim.wo[win].wrap = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].foldmethod = "manual"
  vim.wo[win].foldenable = true
  vim.wo[win].foldtext = "v:lua.require'neowork.index'._foldtext()"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].fillchars = "fold: ,foldopen:▾,foldclose:▸,foldsep: ,eob: "
  vim.wo[win].statuscolumn = ""
  vim.wo[win].winhighlight = "Normal:NeoworkIdxNormal,CursorLine:NeoworkIdxCursorLine,Folded:NeoworkIdxSection"
end

function M.open(opts)
  opts = opts or {}
  local root = opts.root or vim.fn.getcwd()
  local as_tab = opts.tab ~= false

  if M._bufs[root] and vim.api.nvim_buf_is_valid(M._bufs[root]) then
    local existing = M._bufs[root]
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        if vim.api.nvim_win_get_buf(win) == existing then
          vim.api.nvim_set_current_tabpage(tp)
          vim.api.nvim_set_current_win(win)
          M._last_refresh[existing] = nil
          M.refresh(existing)
          return
        end
      end
    end
    if as_tab then vim.cmd("tabnew") end
    vim.api.nvim_set_current_buf(existing)
    apply_window_style(vim.api.nvim_get_current_win())
    M._last_refresh[existing] = nil
    M.refresh(existing)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "neowork-index"

  M._bufs[root] = buf
  M._roots[buf] = root

  M._setup_buffer(buf)
  M._setup_autocmds(buf)

  if as_tab then vim.cmd("tabnew") end
  vim.api.nvim_set_current_buf(buf)
  apply_window_style(vim.api.nvim_get_current_win())

  M.refresh(buf)
end

function M.close(root)
  root = root or vim.fn.getcwd()
  local buf = M._bufs[root]
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

function M.toggle(opts)
  opts = opts or {}
  local root = opts.root or vim.fn.getcwd()
  local buf = M._bufs[root]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        pcall(vim.api.nvim_win_close, win, true)
        return
      end
    end
  end
  M.open(opts)
end

return M
