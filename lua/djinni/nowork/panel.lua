local M = {}

M._buf = nil
M._win = nil
M._tab = nil
M._source_tab = nil
M._view = "sessions"
M._cursor_idx = 1
M._tasks = {}
M._line_index = {}
M._collapsed = {}
M._projects_hidden = false
M._current_buf = nil
M._session_history = {}
M._numbered_sessions = {}
M._separator_line = nil

-- Hive section state
M._line_hive = {} -- line_nr -> { type = "section"|"agent"|"permission", data = ... }
M._hive_fold = {} -- section_id -> bool (true = folded)
M._hive_project_filter = "current" -- "current" | "all"

local status_icons = {
  running = "●",
  input = "⚠",
  idle = "◆",
  done = "✓",
}

local status_hl = {
  running = "DiagnosticOk",
  input = "DiagnosticWarn",
  idle = "Comment",
  done = "DiagnosticHint",
}

local status_order = { running = 1, input = 2, idle = 3, done = 4 }

local ns = vim.api.nvim_create_namespace("nowork_panel")

local _wt_stats = {}
local _wt_stats_ttl = 30
local _wt_info_cache = {}
local _wt_info_cache_at = {}
local _root_stats = {}
local _root_stats_ttl = 30
local _tasks_dirty = true
local _render_timer = nil

local function _detect_worktree_info(root)
  if _wt_info_cache[root] ~= nil and _wt_info_cache_at[root] and (os.time() - _wt_info_cache_at[root]) < 30 then
    return _wt_info_cache[root]
  end
  local function cache_false()
    _wt_info_cache[root] = false
    _wt_info_cache_at[root] = os.time()
    return false
  end
  local git_path = root .. "/.git"
  local stat = vim.loop.fs_stat(git_path)
  if not stat or stat.type ~= "file" then return cache_false() end
  local f = io.open(git_path, "r")
  if not f then return cache_false() end
  local content = f:read("*a")
  f:close()
  local gitdir = content:match("gitdir:%s*(.+)")
  if not gitdir then return cache_false() end
  gitdir = gitdir:gsub("%s+$", "")
  if not vim.startswith(gitdir, "/") then
    gitdir = root .. "/" .. gitdir
  end
  gitdir = vim.fn.fnamemodify(gitdir, ":p"):gsub("/$", "")
  local main_git = gitdir:match("^(.+)/worktrees/[^/]+$")
  if not main_git then return cache_false() end
  local parent = vim.fn.fnamemodify(main_git, ":h")
  local head_file = gitdir .. "/HEAD"
  local hf = io.open(head_file, "r")
  local branch = nil
  if hf then
    local head = hf:read("*l")
    hf:close()
    branch = head and head:match("ref: refs/heads/(.+)")
  end
  if not branch then
    branch = gitdir:match("/worktrees/([^/]+)$")
  end
  local info = { parent = parent, branch = branch }
  _wt_info_cache[root] = info
  _wt_info_cache_at[root] = os.time()
  return info
end

local _wt_branches_cache = {}
local _wt_branches_cache_at = {}
local _wt_branches_ttl = 30

local function _discover_worktrees(root)
  if _wt_branches_cache[root] and _wt_branches_cache_at[root] and (os.time() - _wt_branches_cache_at[root]) < _wt_branches_ttl then
    return _wt_branches_cache[root]
  end
  local wt_dir = root .. "/.git/worktrees"
  local handle = vim.loop.fs_scandir(wt_dir)
  if not handle then
    _wt_branches_cache[root] = {}
    return {}
  end
  local branches = {}
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if type == "directory" then
      local head_file = wt_dir .. "/" .. name .. "/HEAD"
      local hf = io.open(head_file, "r")
      if hf then
        local head = hf:read("*l")
        hf:close()
        local branch = head and head:match("ref: refs/heads/(.+)")
        if branch then
          table.insert(branches, branch)
        else
          table.insert(branches, name)
        end
      end
    end
  end
  _wt_branches_cache[root] = branches
  _wt_branches_cache_at[root] = os.time()
  return branches
end

local function write_frontmatter_to_file(file_path, key, value)
  local chat = require("djinni.nowork.chat")
  local bufnr = vim.fn.bufnr(file_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
    chat._set_frontmatter_field(bufnr, key, value)
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write") end)
    return
  end
  bufnr = vim.fn.bufadd(file_path)
  vim.bo[bufnr].buflisted = false
  vim.fn.bufload(bufnr)
  chat._set_frontmatter_field(bufnr, key, value)
  vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write") end)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

local _wt_stats_busy = false

local function _refresh_wt_stats(tasks)
  local worktrunk = require("djinni.integrations.worktrunk")
  if not worktrunk.available() then return end
  if _wt_stats_busy then return end

  local needs_refresh = false
  for _, task in ipairs(tasks) do
    local branch = task.worktree
    if branch and branch ~= "" then
      local entry = _wt_stats[branch]
      if not entry or (os.time() - entry.at) >= _wt_stats_ttl then
        needs_refresh = true
        break
      end
    end
  end
  if not needs_refresh then return end

  _wt_stats_busy = true
  worktrunk.list({ full = true }, function(entries)
    _wt_stats_busy = false
    if not entries then return end
    for _, e in ipairs(entries) do
      if e.branch then
        local wt = e.working_tree or {}
        local diff = wt.diff or {}
        local uncommitted = 0
        if wt.staged then uncommitted = uncommitted + 1 end
        if wt.modified then uncommitted = uncommitted + 1 end
        if wt.untracked then uncommitted = uncommitted + 1 end
        local dirty = wt.staged or wt.modified or wt.untracked or false
        _wt_stats[e.branch] = {
          added = diff.added or 0,
          deleted = diff.deleted or 0,
          uncommitted = uncommitted,
          ahead = e.main and e.main.ahead or 0,
          behind = e.main and e.main.behind or 0,
          dirty = dirty,
          at = os.time(),
        }
      end
    end
    vim.schedule(function()
      if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
        M.schedule_render()
      end
    end)
  end)
end

local function _refresh_root_stats(roots)
  for _, root in ipairs(roots) do
    local entry = _root_stats[root]
    if entry and (os.time() - entry.at) < _root_stats_ttl then goto next_root end

    local stats = { added = 0, deleted = 0, uncommitted = 0, at = os.time() }
    _root_stats[root] = stats

    vim.fn.jobstart({ "git", "diff", "--shortstat" }, {
      cwd = root,
      stdout_buffered = true,
      on_stdout = function(_, data)
        for _, line in ipairs(data or {}) do
          local ins = line:match("(%d+) insertion")
          local del = line:match("(%d+) deletion")
          if ins then stats.added = tonumber(ins) end
          if del then stats.deleted = tonumber(del) end
        end
      end,
      on_exit = function()
        vim.fn.jobstart({ "git", "status", "--porcelain" }, {
          cwd = root,
          stdout_buffered = true,
          on_stdout = function(_, data)
            local count = 0
            for _, line in ipairs(data or {}) do
              if line ~= "" then count = count + 1 end
            end
            stats.uncommitted = count
          end,
          on_exit = function()
            vim.schedule(function()
              if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
                M.schedule_render()
              end
            end)
          end,
        })
      end,
    })
    ::next_root::
  end
end

function M.refresh()
  _wt_stats = {}
  _root_stats = {}
  _wt_info_cache = {}
  _wt_info_cache_at = {}
  _wt_branches_cache = {}
  _wt_branches_cache_at = {}
  _tasks_dirty = true
  M.render()
end

function M.schedule_render()
  _tasks_dirty = true
  if _render_timer then
    _render_timer:stop()
  end
  _render_timer = vim.defer_fn(function()
    _render_timer = nil
    M.render()
  end, 50)
end

local function get_config()
  local ok, djinni = pcall(require, "djinni")
  if ok and djinni.config then
    return djinni.config
  end
  return { panel = { width = 40 }, chat = { dir = ".chat" } }
end

local function get_assoc_win()
  if M._source_tab and vim.api.nvim_get_tabvar(M._source_tab, "") then
    local wins = vim.api.nvim_tabpage_list_wins(M._source_tab)
    if #wins > 0 then
      return wins[1]
    end
  end
  vim.cmd("rightbelow vsplit enew")
  local new_win = vim.api.nvim_get_current_win()
  if M._tab and vim.api.nvim_get_tabvar(M._tab, "") then
    vim.cmd(M._tab .. "tabnext")
  end
  return new_win
end

M._line_tasks = {}
M._line_projects = {}
M._line_sessions = {}
M._hidden_sessions = {}

local function session_at_cursor()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return nil end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  return M._line_sessions[row]
end

local function task_at_cursor()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return nil end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  return M._line_tasks[row]
end

local function project_at_cursor()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return nil end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  return M._line_projects[row]
end

function M._get_grouped_tasks()
  local groups = {}
  local group_map = {}

  local projects = require("djinni.integrations.projects")
  for _, root in ipairs(projects.get()) do
    if root ~= "." then
      local actual_root = root
      local info = _detect_worktree_info(root)
      if info then actual_root = info.parent end
      if not group_map[actual_root] then
        local name = vim.fn.fnamemodify(actual_root, ":t")
        group_map[actual_root] = { name = name, root = actual_root, subgroups = {}, _sub_map = {} }
        table.insert(groups, group_map[actual_root])
      end
      if info and info.branch then
        local grp = group_map[actual_root]
        if not grp._sub_map[info.branch] then
          grp._sub_map[info.branch] = {
            name = info.branch,
            worktree = info.branch,
            tasks = {},
          }
          table.insert(grp.subgroups, grp._sub_map[info.branch])
        end
      end
    end
  end

  for _, task in ipairs(M._tasks) do
    local task_root = task.root or task.file_path:match("^(.-)/%.[^/]+/[^/]+$") or ""
    if task_root ~= "." then
      local wt_key = task.worktree and task.worktree ~= "" and task.worktree or nil
      local info = _detect_worktree_info(task_root)
      if info and not wt_key then
        wt_key = info.branch
        task_root = info.parent
      end
      wt_key = wt_key or "_main"
      if not group_map[task_root] then
        local name = vim.fn.fnamemodify(task_root, ":t")
        group_map[task_root] = { name = name, root = task_root, subgroups = {}, _sub_map = {} }
        table.insert(groups, group_map[task_root])
      end
      local grp = group_map[task_root]
      if not grp._sub_map[wt_key] then
        grp._sub_map[wt_key] = {
          name = wt_key == "_main" and "main" or wt_key,
          worktree = wt_key ~= "_main" and wt_key or nil,
          tasks = {},
        }
        table.insert(grp.subgroups, grp._sub_map[wt_key])
      end
      table.insert(grp._sub_map[wt_key].tasks, task)
    end
  end

  local function group_has_active(g)
    for _, sg in ipairs(g.subgroups) do
      for _, t in ipairs(sg.tasks) do
        if t.status == "running" or t.status == "input" then return true end
      end
    end
    return false
  end

  local function group_task_count(g)
    local c = 0
    for _, sg in ipairs(g.subgroups) do c = c + #sg.tasks end
    return c
  end

  table.sort(groups, function(a, b)
    local aa, ba = group_has_active(a), group_has_active(b)
    if aa ~= ba then return aa end
    local ac, bc = group_task_count(a), group_task_count(b)
    if ac ~= bc then return ac > bc end
    return a.name < b.name
  end)

  for _, grp in ipairs(groups) do
    table.sort(grp.subgroups, function(a, b)
      local function sub_active(sg)
        for _, t in ipairs(sg.tasks) do
          if t.status == "running" or t.status == "input" then return true end
        end
        return false
      end
      local aa, ba = sub_active(a), sub_active(b)
      if aa ~= ba then return aa end
      if (a.worktree ~= nil) ~= (b.worktree ~= nil) then return a.worktree ~= nil end
      if #a.tasks ~= #b.tasks then return #a.tasks > #b.tasks end
      return a.name < b.name
    end)
  end

  return groups
end

function M._scan_tasks()
  if not _tasks_dirty and #M._tasks > 0 then
    local chat = require("djinni.nowork.chat")
    for _, task in ipairs(M._tasks) do
      local bufnr = vim.fn.bufnr(task.file_path)
      if bufnr ~= -1 then
        local usage = chat._usage[bufnr]
        if usage then
          local total = usage.input_tokens + usage.output_tokens
          if total > 0 then
            task.tokens = total >= 1000 and string.format("%.1fk", total / 1000) or tostring(total)
          end
          if usage.cost > 0 then
            task.cost = string.format("%.2f", usage.cost)
          end
          if usage.context_size and usage.context_size > 0 then
            task.context_pct = math.floor((usage.context_used or 0) / usage.context_size * 100)
          end
        end
        if chat._streaming[bufnr] then
          task.status = "running"
        end
        local is_visible = vim.fn.bufwinid(bufnr) ~= -1
        if is_visible then
          if chat._streaming[bufnr] then
            task.activity = (chat._last_tool_title and chat._last_tool_title[bufnr]) or "streaming…"
          elseif chat._last_perm_tool and chat._last_perm_tool[bufnr] then
            task.activity = "⚠ " .. chat._last_perm_tool[bufnr]
          else
            task.activity = nil
          end
        end
      end
    end
    return
  end
  _tasks_dirty = false

  local cfg = get_config()
  local chat_dir = cfg.chat and cfg.chat.dir or ".chat"
  local tasks = {}

  local projects = require("djinni.integrations.projects")
  local known = projects.discover()

  for _, root in ipairs(known) do
    local dir = root .. "/" .. chat_dir
    local handle = vim.loop.fs_scandir(dir)
    if handle then
      while true do
        local name, type = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if type == "file" and name:match("%.md$") and name ~= "TASK.md" then
          local path = dir .. "/" .. name
          local f = io.open(path, "r")
          if f then
            local title = name:gsub("%.md$", "")
            local status = "idle"
            local time = ""
            local model = ""
            local provider = ""
            local tokens = ""
            local cost = ""
            local task_skills = ""
            local task_mcp = ""
            local task_worktree = ""
            local line_num = 0
            local in_frontmatter = false
            local fm_count = 0
            for line in f:lines() do
              line_num = line_num + 1
              if line_num > 25 then break end
              if line:match("^%-%-%-") then
                fm_count = fm_count + 1
                if fm_count == 1 then
                  in_frontmatter = true
                elseif fm_count == 2 then
                  break
                end
              elseif in_frontmatter then
                local k, v = line:match("^(%w+):%s*(.+)$")
                if k == "title" then title = v end
                if k == "status" then status = v end
                if k == "time" then time = v end
                if k == "model" then model = v end
                if k == "provider" then provider = v end
                if k == "tokens" then tokens = v end
                if k == "cost" then cost = v end
                if k == "skills" then task_skills = v end
                if k == "mcp" then task_mcp = v end
                if k == "worktree" then task_worktree = v end
              end
            end
            f:close()
            local project_name = vim.fn.fnamemodify(root, ":t")
            table.insert(tasks, {
              project = project_name,
              root = root,
              title = title,
              status = status,
              time = time,
              model = model,
              provider = provider,
              tokens = tokens,
              cost = cost,
              skills = task_skills,
              mcp = task_mcp,
              worktree = task_worktree,
              file_path = path,
            })
          end
        end
      end
    end
  end

  table.sort(tasks, function(a, b)
    local oa = status_order[a.status] or 99
    local ob = status_order[b.status] or 99
    if oa ~= ob then return oa < ob end
    return a.title < b.title
  end)

  local chat = require("djinni.nowork.chat")
  for _, task in ipairs(tasks) do
    local bufnr = vim.fn.bufnr(task.file_path)
    if bufnr ~= -1 then
      local usage = chat._usage[bufnr]
      if usage then
        local total = usage.input_tokens + usage.output_tokens
        if total > 0 then
          task.tokens = total >= 1000 and string.format("%.1fk", total / 1000) or tostring(total)
        end
        if usage.cost > 0 then
          task.cost = string.format("%.2f", usage.cost)
        end
        if usage.context_size and usage.context_size > 0 then
          task.context_pct = math.floor((usage.context_used or 0) / usage.context_size * 100)
        end
      end
      if chat._streaming[bufnr] then
        task.status = "running"
      end
      local is_visible = vim.fn.bufwinid(bufnr) ~= -1
      if is_visible then
        if chat._streaming[bufnr] then
          task.activity = (chat._last_tool_title and chat._last_tool_title[bufnr]) or "streaming…"
        elseif chat._last_perm_tool and chat._last_perm_tool[bufnr] then
          task.activity = "⚠ " .. chat._last_perm_tool[bufnr]
        end
      end
    end
  end

  M._tasks = tasks
  _refresh_wt_stats(tasks)

  local roots_without_wt = {}
  local seen_roots = {}
  for _, task in ipairs(tasks) do
    if (not task.worktree or task.worktree == "") and not seen_roots[task.root] then
      seen_roots[task.root] = true
      table.insert(roots_without_wt, task.root)
    end
  end
  if #roots_without_wt > 0 then
    _refresh_root_stats(roots_without_wt)
  end
end

local function format_model(model)
  if not model or model == "" then return "" end
  return model:gsub("^claude%-", ""):gsub("^anthropic/", "")
end

local function root_from_key(key)
  if not key then return nil end
  return key:match("^(.+):") or key
end

local function render_ai_virt(task)
  local vt = {}
  if task.context_pct then
    local pct_hl = task.context_pct >= 80 and "DiagnosticError" or task.context_pct >= 50 and "DiagnosticWarn" or "Comment"
    table.insert(vt, { task.context_pct .. "%", pct_hl })
  end
  local model_str = format_model(task.model)
  if model_str ~= "" then
    if #vt > 0 then table.insert(vt, { " │ ", "NonText" }) end
    table.insert(vt, { model_str, "Comment" })
  end
  if task.tokens ~= "" then
    if #vt > 0 then table.insert(vt, { " │ ", "NonText" }) end
    table.insert(vt, { task.tokens, "Number" })
  end
  if task.cost ~= "" then
    if #vt > 0 then table.insert(vt, { " │ ", "NonText" }) end
    table.insert(vt, { "$" .. task.cost, "String" })
  end
  return vt
end

local function render_stats_virt(stats)
  local vt = {}
  if not stats then return vt end
  if stats.added > 0 or stats.deleted > 0 then
    table.insert(vt, { "+" .. stats.added .. " ", "String" })
    table.insert(vt, { "-" .. stats.deleted, "DiagnosticError" })
  end
  if stats.uncommitted > 0 then
    if #vt > 0 then table.insert(vt, { "  ", "NonText" }) end
    table.insert(vt, { stats.uncommitted .. "U", "DiagnosticWarn" })
  end
  return vt
end

local function render_session_virt(s)
  local vt = {}
  if s.context ~= "" then
    local pct = tonumber(s.context:match("(%d+)")) or 0
    local pct_hl = pct >= 80 and "DiagnosticError" or pct >= 50 and "DiagnosticWarn" or "Comment"
    table.insert(vt, { s.context, pct_hl })
  end
  if s.tokens ~= "" then
    if #vt > 0 then table.insert(vt, { " │ ", "NonText" }) end
    table.insert(vt, { s.tokens, "Number" })
  end
  if s.cost ~= "" then
    if #vt > 0 then table.insert(vt, { " │ ", "NonText" }) end
    table.insert(vt, { s.cost, "String" })
  end
  return vt
end

local function _fmt_k(n)
  if not n or n <= 0 then return "0" end
  return n >= 1000 and string.format("%.1fk", n / 1000) or tostring(n)
end

function M._collect_sessions()
  local chat = require("djinni.nowork.chat")
  local result = {}
  local seen = {}
  local candidates = {}
  for buf in pairs(chat._sessions or {})  do candidates[buf] = true end
  for buf in pairs(chat._streaming or {}) do candidates[buf] = true end

  for buf in pairs(candidates) do
    if not vim.api.nvim_buf_is_valid(buf) then goto continue end
    if M._hidden_sessions[buf] then goto continue end
    local name_full = vim.api.nvim_buf_get_name(buf)
    if name_full == "" or vim.api.nvim_get_option_value("buftype", { buf = buf }) == "nofile" then goto continue end

    local sid = chat._sessions[buf] or ""
    if sid ~= "" and seen[sid] then goto continue end
    if sid ~= "" then seen[sid] = true end

    local short = vim.fn.fnamemodify(name_full, ":t:r")
    if short == "" then short = "[buf " .. buf .. "]" end

    local title = short
    pcall(function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, 15, false)
      local in_fm = false
      for _, line in ipairs(lines) do
        if line:match("^%-%-%-") then
          if in_fm then break end
          in_fm = true
        elseif in_fm then
          local k, v = line:match("^(%w+):%s*(.+)$")
          if k == "title" and v and v ~= "" then title = v break end
        end
      end
    end)

    local root = chat.get_project_root(buf)
    local project = root and vim.fn.fnamemodify(root, ":t") or name_full:match("([^/]+)/[^/]+/[^/]+$") or ""
    local usage = chat._usage[buf]

    local status
    if chat._streaming[buf] then status = "running"
    elseif chat._last_perm_tool[buf] then status = "input"
    elseif chat._waiting_input and chat._waiting_input[buf] then status = "input"
    elseif chat._sessions[buf] then status = "idle"
    else status = "done" end

    local activity = ""
    if chat._streaming[buf] then
      local tool_title = chat._last_tool_title[buf]
      activity = tool_title or "streaming…"
    elseif chat._last_perm_tool[buf] then
      activity = "⚠ " .. chat._last_perm_tool[buf]
    elseif chat._waiting_input and chat._waiting_input[buf] then
      activity = "⚠ waiting for input"
    end

    local tokens = ""
    if usage then
      local inp = usage.input_tokens or 0
      local out = usage.output_tokens or 0
      if inp + out > 0 then tokens = "↓" .. _fmt_k(inp) .. " ↑" .. _fmt_k(out) end
    end

    local cost = ""
    if usage and usage.cost and usage.cost > 0 then
      cost = string.format("$%.2f", usage.cost)
    end

    local context = ""
    if usage and (usage.context_size or 0) > 0 then
      context = tostring(math.floor((usage.context_used or 0) / usage.context_size * 100)) .. "%"
    end

    table.insert(result, {
      buf      = buf,
      name     = short,
      title    = title,
      project  = project,
      root     = root,
      status   = status,
      activity = activity,
      tokens   = tokens,
      cost     = cost,
      context  = context,
    })
    ::continue::
  end

  table.sort(result, function(a, b)
    local order = { running = 1, input = 2, idle = 3, done = 4 }
    local oa = order[a.status] or 9
    local ob = order[b.status] or 9
    if oa ~= ob then return oa < ob end
    if a.project ~= b.project then return a.project < b.project end
    return a.title < b.title
  end)
  return result
end

function M._collect_all_sessions()
  local hive = require("djinni.nowork.hive")
  local chat = require("djinni.nowork.chat")
  local result = {}
  local seen = {}

  for _, agent in ipairs(hive.list()) do
    if vim.api.nvim_buf_is_valid(agent.buf) then
      local name_full = vim.api.nvim_buf_get_name(agent.buf)
      local short = vim.fn.fnamemodify(name_full, ":t:r")
      if short == "" then short = "[" .. agent.letter .. "]" end

      local title = short
      pcall(function()
        local lines = vim.api.nvim_buf_get_lines(agent.buf, 0, 15, false)
        local in_fm = false
        for _, line in ipairs(lines) do
          if line:match("^%-%-%-") then
            if in_fm then break end
            in_fm = true
          elseif in_fm then
            local k, v = line:match("^(%w+):%s*(.+)$")
            if k == "title" and v and v ~= "" then title = v break end
          end
        end
      end)

      local root = chat.get_project_root(agent.buf)
      local project = root and vim.fn.fnamemodify(root, ":t") or ""
      local usage = chat._usage[agent.buf]

      local status = agent.status or "idle"
      if chat._last_perm_tool[agent.buf] then
        status = "permission"
      elseif chat._waiting_input and chat._waiting_input[agent.buf] then
        status = "input"
      end

      local activity = ""
      if chat._streaming[agent.buf] then
        local tool_title = chat._last_tool_title[agent.buf]
        activity = tool_title or "streaming…"
      elseif chat._last_perm_tool[agent.buf] then
        activity = chat._last_perm_tool[agent.buf]
      elseif chat._waiting_input and chat._waiting_input[agent.buf] then
        activity = "waiting for input"
      end

      local cost = ""
      if usage and usage.cost and usage.cost > 0 then
        cost = string.format("$%.2f", usage.cost)
      end

      local context_pct = nil
      if usage and (usage.context_size or 0) > 0 then
        context_pct = math.floor((usage.context_used or 0) / usage.context_size * 100)
      end

      table.insert(result, {
        letter = agent.letter,
        buf = agent.buf,
        name = title,
        root = root,
        project = project,
        status = status,
        activity = activity,
        active = agent.active,
        tokens = "",
        cost = cost,
        context_pct = context_pct,
      })
      seen[agent.buf] = true
    end
  end

  local all_sessions = M._collect_sessions()
  for _, s in ipairs(all_sessions) do
    if not seen[s.buf] and not M._hidden_sessions[s.buf] then
      table.insert(result, {
        letter = nil,
        buf = s.buf,
        name = s.title,
        root = s.root,
        project = s.project,
        status = s.status,
        activity = s.activity,
        active = false,
        tokens = s.tokens,
        cost = s.cost,
        context_pct = s.context and tonumber(s.context:match("(%d+)")) or nil,
      })
      seen[s.buf] = true
    end
  end

  return result
end

local function _apply_buf_render(buf, buf_ns, lines, hl_marks, virt_texts, overlay_texts)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, buf_ns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, buf_ns, mark.line, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
    })
  end
  for line_idx, vt in pairs(virt_texts) do
    pcall(vim.api.nvim_buf_set_extmark, buf, buf_ns, line_idx, 0, {
      virt_text = vt,
      virt_text_pos = "right_align",
    })
  end
  for line_idx, vt in pairs(overlay_texts or {}) do
    pcall(vim.api.nvim_buf_set_extmark, buf, buf_ns, line_idx, 0, {
      virt_text = vt,
      virt_text_pos = "overlay",
    })
  end
end

function M.render()
  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then return end

  local lines = {}
  local hl_marks = {}
  local virt_texts = {}
  local overlay_texts = {}
  M._line_index = {}

  local function ln() return #lines end
  local function add(text) table.insert(lines, text) end
  local function hl(line_0, col, end_col, group)
    table.insert(hl_marks, { line = line_0, col = col, end_col = end_col, hl = group })
  end
  local function virt(line_0, parts) virt_texts[line_0] = parts end

  local cfg = get_config()
  local panel_w = math.max(cfg.panel and cfg.panel.width or 40, 40)

  local function truncate(str, max_w)
    if vim.fn.strdisplaywidth(str) <= max_w then return str end
    while vim.fn.strdisplaywidth(str) > max_w - 1 do
      str = str:sub(1, #str - 1)
    end
    return str .. "…"
  end

  local function section_header(id, title, count, folded)
    add("")
    local arrow = folded and ">" or "v"
    local text = arrow .. " " .. title .. " (" .. count .. ")"
    add(text)
    local i = ln()
    M._line_index[i] = { type = "section", id = id }
    hl(i - 1, 0, #arrow, "NonText")
    hl(i - 1, #arrow + 1, #text, "Statement")
    return not folded
  end

  local function get_last_message(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return nil end
    local ok, all_lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
    if not ok then return nil end
    local last_djinni_start = nil
    for i = #all_lines, 1, -1 do
      if all_lines[i]:match("^@Djinni%s*$") then
        last_djinni_start = i
        break
      end
      if all_lines[i]:match("^@You%s*$") then break end
    end
    if not last_djinni_start then return nil end
    local msg_lines = {}
    for i = last_djinni_start + 1, math.min(last_djinni_start + 10, #all_lines) do
      local l = all_lines[i]
      if l:match("^@You%s*$") or l:match("^@System%s*$") or l:match("^%-%-%-$") then break end
      if l ~= "" and not l:match("^%[%*%]") then
        table.insert(msg_lines, l:gsub("^%s+", ""))
      end
    end
    if #msg_lines == 0 then return nil end
    return table.concat(msg_lines, " ")
  end

  local function session_line(s, indent)
    indent = indent or "  "
    local marker
    if s.status == "permission" then marker = "!"
    elseif s.status == "running" then marker = "●"
    elseif s.status == "input" then marker = "▶"
    elseif s.status == "idle" then marker = "○"
    else marker = "·" end

    local letter_part = s.letter and (s.letter .. " ") or "  "
    local name = s.status == "permission" and s.activity or s.name
    local text = indent .. marker .. " " .. letter_part .. truncate(name, panel_w - #indent - 6)
    add(text)
    local i = ln()
    M._line_index[i] = { type = "session", session = s }

    local marker_hl = ({
      permission = "WarningMsg", running = "DiagnosticOk",
      input = "DiagnosticWarn", idle = "NonText",
    })[s.status] or "Comment"
    hl(i - 1, #indent, #indent + #marker, marker_hl)
    if s.letter then
      hl(i - 1, #indent + #marker + 1, #indent + #marker + 2, s.active and "CursorLineNr" or "Identifier")
    end

    local vt_parts = {}
    if s.context_pct then
      local phl = s.context_pct > 80 and "DiagnosticError" or s.context_pct > 50 and "DiagnosticWarn" or "Comment"
      table.insert(vt_parts, { s.context_pct .. "%", phl })
    end
    if s.cost and s.cost ~= "" then
      if #vt_parts > 0 then table.insert(vt_parts, { " ", "NonText" }) end
      table.insert(vt_parts, { s.cost, "Comment" })
    end
    if #vt_parts > 0 then virt(i - 1, vt_parts) end

    if s.activity and s.activity ~= "" and s.status ~= "permission" then
      local act = indent .. "  " .. truncate(s.activity, panel_w - #indent - 4)
      add(act)
      local ai = ln()
      M._line_index[ai] = { type = "activity", session = s }
      hl(ai - 1, 0, #act, "DiagnosticInfo")
    end

    local chat = require("djinni.nowork.chat")
    local last_msg = chat._pending_text[s.buf] or get_last_message(s.buf)
    if last_msg and last_msg ~= "" then
      local preview = last_msg:gsub("%s+", " "):gsub("^%s+", "")
      local msg_text = indent .. "  " .. truncate(preview, panel_w - #indent - 4)
      add(msg_text)
      local mi = ln()
      M._line_index[mi] = { type = "message", session = s }
      hl(mi - 1, 0, #msg_text, "Comment")
    end
  end

  local function file_line(task, indent)
    indent = indent or "  "
    local marker = ({ running = "●", input = "▶", idle = "○", done = "·" })[task.status] or "·"
    local text = indent .. marker .. " " .. truncate(task.title, panel_w - #indent - 4)
    add(text)
    local i = ln()
    M._line_index[i] = { type = "file", task = task }
    hl(i - 1, #indent, #indent + #marker, status_hl[task.status] or "Comment")
    hl(i - 1, #indent + #marker + 1, #text, "Comment")

    local vt = render_ai_virt(task)
    if #vt > 0 then virt(i - 1, vt) end
  end

  local sessions = M._collect_all_sessions()

  local total_cost = 0
  for _, s in ipairs(sessions) do
    if s.cost and s.cost ~= "" then
      total_cost = total_cost + (s.cost:match("$([%d.]+)") and tonumber(s.cost:match("$([%d.]+)")) or 0)
    end
  end

  add("nowork")
  hl(0, 0, 6, "Title")
  local view_label = M._view == "sessions" and "sessions" or "projects"
  virt(0, {
    { view_label, "Statement" },
    { "  " .. #sessions .. " active", "Comment" },
    { "  " .. string.format("$%.2f", total_cost), "String" },
  })

  if M._view == "sessions" then
    local perms, streaming, waiting, idle = {}, {}, {}, {}
    for _, s in ipairs(sessions) do
      if s.status == "permission" then table.insert(perms, s)
      elseif s.status == "running" then table.insert(streaming, s)
      elseif s.status == "input" or s.status == "idle" then table.insert(waiting, s)
      else table.insert(idle, s)
      end
    end

    local secs = {
      { id = "perms", title = "Permissions", items = perms },
      { id = "streaming", title = "Streaming", items = streaming },
      { id = "waiting", title = "Ready", items = waiting },
      { id = "idle", title = "Ended", items = idle },
    }

    for _, sec in ipairs(secs) do
      if #sec.items > 0 then
        local folded = M._collapsed[sec.id]
        if section_header(sec.id, sec.title, #sec.items, folded) then
          for _, s in ipairs(sec.items) do
            session_line(s)
          end
        end
      end
    end
  else
    M._scan_tasks()
    local by_root = {}
    local session_files = {}

    for _, s in ipairs(sessions) do
      if s.root then
        if not by_root[s.root] then
          by_root[s.root] = { root = s.root, name = vim.fn.fnamemodify(s.root, ":t"), sessions = {}, files = {} }
        end
        table.insert(by_root[s.root].sessions, s)
        local buf_name = vim.api.nvim_buf_get_name(s.buf)
        if buf_name ~= "" then session_files[buf_name] = true end
      end
    end

    for _, task in ipairs(M._tasks) do
      local root = task.root or ""
      if root ~= "" and root ~= "." then
        if not by_root[root] then
          by_root[root] = { root = root, name = vim.fn.fnamemodify(root, ":t"), sessions = {}, files = {} }
        end
        if not session_files[task.file_path] then
          table.insert(by_root[root].files, task)
        end
      end
    end

    local roots = {}
    for _, root_data in pairs(by_root) do
      table.insert(roots, root_data)
    end

    table.sort(roots, function(a, b)
      local function has_active(r)
        for _, s in ipairs(r.sessions) do
          if s.status == "running" or s.status == "input" then return true end
        end
        return false
      end
      local aa, ba = has_active(a), has_active(b)
      if aa ~= ba then return aa end
      local at, bt = #a.sessions + #a.files, #b.sessions + #b.files
      if at ~= bt then return at > bt end
      return a.name < b.name
    end)

    for _, root_data in ipairs(roots) do
      local n_sessions = #root_data.sessions
      local n_files = #root_data.files
      local folded = M._collapsed[root_data.root]

      add("")
      local arrow = folded and ">" or "v"
      local header = arrow .. " " .. root_data.name
      add(header)
      local hi = ln()
      M._line_index[hi] = { type = "project", root = root_data.root, id = root_data.root }
      hl(hi - 1, 0, #arrow, "NonText")
      hl(hi - 1, #arrow + 1, #header, "Directory")
      local hdr_vt = {}
      if n_sessions > 0 then
        table.insert(hdr_vt, { n_sessions .. " live", "DiagnosticOk" })
      end
      if n_files > 0 then
        if #hdr_vt > 0 then table.insert(hdr_vt, { "  ", "NonText" }) end
        table.insert(hdr_vt, { n_files .. " chats", "Comment" })
      end
      if #hdr_vt > 0 then virt(hi - 1, hdr_vt) end

      if not folded then
        for _, s in ipairs(root_data.sessions) do
          session_line(s, "  ")
        end
        for _, task in ipairs(root_data.files) do
          file_line(task, "  ")
        end
      end
    end
  end

  _apply_buf_render(M._buf, ns, lines, hl_marks, virt_texts, overlay_texts)

  if M._win and vim.api.nvim_win_is_valid(M._win) then
    local cur = vim.api.nvim_win_get_cursor(M._win)
    local line_count = vim.api.nvim_buf_line_count(M._buf)
    local target = math.min(cur[1], line_count)
    if target < 1 then target = 1 end
    pcall(vim.api.nvim_win_set_cursor, M._win, { target, 0 })
  end
end

function M._setup_keymaps()
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = M._buf, nowait = true })
  end

  map("j", M.cursor_down)
  map("k", M.cursor_up)
  map("{", M.jump_prev_section)
  map("}", M.jump_next_section)

  map("p", function()
    M._view = M._view == "sessions" and "projects" or "sessions"
    M.render()
  end)

  map("<CR>", M.open_in_vsplit)
  map("v", M.open_in_vsplit)
  map("<Tab>", M.toggle_fold)
  map("+", M.hive_start)
  map("x", M.interrupt_task)
  map("*", M.hive_set_active)
  map("!", M.hive_approve)
  map("~", M.hive_deny)
  map("c", M.create_task)
  map("d", M.archive_task)
  map("/", M.search_tasks)
  map("R", M.refresh)
  map("?", M.show_help)
  map("q", M.close)

  for n = 1, 9 do
    map(tostring(n), function() M.jump_session(n) end)
  end
end

function M.open()
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    if M._tab and vim.api.nvim_get_tabvar(M._tab, "") then
      vim.cmd(M._tab .. "tabnext")
      return
    end
    M.close()
  end

  M._source_tab = vim.api.nvim_get_current_tabpage()

  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].buftype = "nofile"
  vim.bo[M._buf].bufhidden = "wipe"
  vim.bo[M._buf].swapfile = false
  vim.bo[M._buf].filetype = "nowork-panel"

  vim.cmd("tabnew")
  M._tab = vim.api.nvim_get_current_tabpage()
  M._win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M._win, M._buf)

  vim.wo[M._win].cursorline = true
  vim.wo[M._win].wrap = false
  vim.wo[M._win].signcolumn = "no"
  vim.wo[M._win].number = false
  vim.wo[M._win].relativenumber = false
  vim.wo[M._win].foldenable = false
  vim.wo[M._win].statuscolumn = ""

  M._setup_keymaps()

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = M._buf,
    callback = function()
      M._buf = nil
      M._win = nil
      M._tab = nil
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(ev)
      if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then return true end
      local buf = ev.buf
      if buf == M._buf then return end
      if vim.bo[buf].filetype == "nowork-chat" then
        M._current_buf = buf
        local hist = M._session_history
        if hist[1] ~= buf then
          table.insert(hist, 1, buf)
          if #hist > 10 then hist[11] = nil end
        end
        M.schedule_render()
      end
    end,
  })

  M.render()
end

function M.open_in_vsplit()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  local entry = M._line_index[row]
  if not entry then return end

  if entry.type == "file" and entry.task then
    local path = entry.task.file_path
    if M._source_tab then
      pcall(vim.api.nvim_set_current_tabpage, M._source_tab)
    end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    return
  end

  local buf
  if entry.type == "session" or entry.type == "activity" then
    buf = entry.session and entry.session.buf
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local existing = vim.fn.bufwinid(buf)
  if existing ~= -1 then
    vim.api.nvim_set_current_win(existing)
    return
  end

  vim.cmd("rightbelow vsplit")
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, buf)

  local chat = require("djinni.nowork.chat")
  local root = chat.get_project_root(buf)
  if root then
    vim.api.nvim_win_call(new_win, function()
      vim.cmd("lcd " .. vim.fn.fnameescape(root))
    end)
  end
end

function M.close()
  local source = M._source_tab
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    pcall(vim.api.nvim_buf_delete, M._buf, { force = true })
  end
  M._buf = nil
  M._win = nil
  M._tab = nil
  if source and pcall(vim.api.nvim_set_current_tabpage, source) then
    M._source_tab = nil
  end
end

function M.toggle()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    M.close()
  else
    M.open()
  end
end

function M.toggle_fold()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  local entry = M._line_index[row]
  if not entry then return end

  local key = entry.id or entry.root
  if key then
    M._collapsed[key] = not M._collapsed[key]
  end
  M.render()
end

function M.toggle_projects()
  M._projects_hidden = not M._projects_hidden
  M.render()
end

-- Hive panel actions
function M._hive_at_cursor()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return nil end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  return M._line_hive[row]
end

function M.hive_approve()
  local entry = M._hive_at_cursor()
  if not entry then return end
  if entry.type == "permission" and entry.agent then
    local chat = require("djinni.nowork.chat")
    chat._permission_action(entry.agent.buf, "allow")
    M.schedule_render()
  end
end

function M.hive_deny()
  local entry = M._hive_at_cursor()
  if not entry then return end
  if entry.type == "permission" and entry.agent then
    local chat = require("djinni.nowork.chat")
    chat._permission_action(entry.agent.buf, "deny")
    M.schedule_render()
  end
end

function M.hive_set_active()
  local entry = M._hive_at_cursor()
  if not entry then return end
  if (entry.type == "agent" or entry.type == "permission") and entry.agent then
    require("djinni.nowork.hive").switch(entry.agent.letter)
    M.schedule_render()
  end
end

function M.hive_start()
  vim.ui.input({ prompt = "Agent letter: " }, function(letter)
    if not letter or not letter:match("^%a$") then return end
    vim.ui.input({ prompt = "Label (default: claude): " }, function(label)
      require("djinni.nowork.hive").start(letter, { label = label and label ~= "" and label or nil })
      M.schedule_render()
    end)
  end)
end

function M.hive_toggle_filter()
  M._hive_project_filter = M._hive_project_filter == "current" and "all" or "current"
  M.render()
end

function M.hive_toggle_section()
  local entry = M._hive_at_cursor()
  if not entry then return end
  if entry.type == "section" and entry.id then
    M._hive_fold[entry.id] = not M._hive_fold[entry.id]
    M.render()
  end
end



function M.cursor_down()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  local count = vim.api.nvim_buf_line_count(M._buf)
  for i = row + 1, count do
    if M._line_index[i] then
      vim.api.nvim_win_set_cursor(M._win, { i, 0 })
      return
    end
  end
end

function M.cursor_up()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  for i = row - 1, 1, -1 do
    if M._line_index[i] then
      vim.api.nvim_win_set_cursor(M._win, { i, 0 })
      return
    end
  end
end

function M.jump_next_section()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  local count = vim.api.nvim_buf_line_count(M._buf)
  for i = row + 1, count do
    local entry = M._line_index[i]
    if entry and (entry.type == "section" or entry.type == "project") then
      vim.api.nvim_win_set_cursor(M._win, { i, 0 })
      return
    end
  end
end

function M.jump_prev_section()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  for i = row - 1, 1, -1 do
    local entry = M._line_index[i]
    if entry and (entry.type == "section" or entry.type == "project") then
      vim.api.nvim_win_set_cursor(M._win, { i, 0 })
      return
    end
  end
end

function M.search_tasks()
  M._scan_tasks()
  if #M._tasks == 0 then
    vim.notify("No tasks", vim.log.levels.INFO)
    return
  end
  local items = {}
  for _, task in ipairs(M._tasks) do
    local icon = status_icons[task.status] or "◆"
    local fname = vim.fn.fnamemodify(task.file_path, ":t"):gsub("%.md$", "")
    table.insert(items, {
      text = task.project .. "/" .. fname,
      file = task.file_path,
      icon = icon,
      icon_hl = status_hl[task.status] or "Comment",
    })
  end
  Snacks.picker({
    title = "Tasks",
    items = items,
    layout = { preset = "vscode", preview = false },
    format = function(item)
      return {
        { item.icon .. " ", item.icon_hl },
        { item.text },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      local win = get_assoc_win()
      if win then
        vim.api.nvim_win_call(win, function()
          require("djinni.nowork.chat").open(item.file)
        end)
      end
    end,
  })
end

function M.next_task()
  if #M._tasks == 0 then return end
  M._cursor_idx = M._cursor_idx % #M._tasks + 1
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    local line_count = vim.api.nvim_buf_line_count(M._buf)
    local target = math.min(M._cursor_idx + 1, line_count)
    pcall(vim.api.nvim_win_set_cursor, M._win, { target, 0 })
  end
  local task = M._tasks[M._cursor_idx]
  if task then
    local win = get_assoc_win()
    if win then
      vim.api.nvim_win_call(win, function()
        if task.root and task.root ~= "" then
          vim.cmd("lcd " .. vim.fn.fnameescape(task.root))
        end
        require("djinni.nowork.chat").open(task.file_path)
      end)
    end
  end
end

function M.prev_task()
  if #M._tasks == 0 then return end
  M._cursor_idx = (M._cursor_idx - 2) % #M._tasks + 1
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    local line_count = vim.api.nvim_buf_line_count(M._buf)
    local target = math.min(M._cursor_idx + 1, line_count)
    pcall(vim.api.nvim_win_set_cursor, M._win, { target, 0 })
  end
  local task = M._tasks[M._cursor_idx]
  if task then
    local win = get_assoc_win()
    if win then
      vim.api.nvim_win_call(win, function()
        if task.root and task.root ~= "" then
          vim.cmd("lcd " .. vim.fn.fnameescape(task.root))
        end
        require("djinni.nowork.chat").open(task.file_path)
      end)
    end
  end
end

function M.open_task()
  local entry = M._hive_at_cursor()
  if entry and (entry.type == "agent" or entry.type == "permission") and entry.agent then
    local buf = entry.agent.buf
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local existing = vim.fn.bufwinid(buf)
      if existing ~= -1 then
        vim.api.nvim_set_current_win(existing)
      else
        local win = get_assoc_win()
        if win then vim.api.nvim_win_set_buf(win, buf) end
      end
    end
    return
  end

  local session = session_at_cursor()
  if session and vim.api.nvim_buf_is_valid(session.buf) then
    local existing = vim.fn.bufwinid(session.buf)
    if existing ~= -1 then
      vim.api.nvim_set_current_win(existing)
    else
      local win = get_assoc_win()
      if win then vim.api.nvim_win_set_buf(win, session.buf) end
    end
    return
  end

  local task = task_at_cursor()
  if not task then return end

  local bufnr = vim.fn.bufnr(task.file_path)
  local existing = bufnr ~= -1 and vim.fn.bufwinid(bufnr) or -1
  if existing ~= -1 then
    vim.api.nvim_set_current_win(existing)
    return
  end

  local win = get_assoc_win()
  if win then
    vim.api.nvim_win_call(win, function()
      if task.root and task.root ~= "" then
        vim.cmd("lcd " .. vim.fn.fnameescape(task.root))
      end
      require("djinni.nowork.chat").open(task.file_path)
    end)
  end
end

function M.hide_session()
  local sess = session_at_cursor()
  if not sess then return end
  M._hidden_sessions[sess.buf] = true
  _tasks_dirty = true
  M.render()
end

function M.archive_task()
  local sess = session_at_cursor()
  if sess then
    local chat = require("djinni.nowork.chat")
    local path = vim.api.nvim_buf_get_name(sess.buf)
    chat._invalidate_session(sess.buf)
    pcall(vim.api.nvim_buf_delete, sess.buf, { force = true })
    if path and path ~= "" then
      chat.archive_chat_file(path)
    end
    _tasks_dirty = true
    M.render()
    return
  end

  local task = task_at_cursor()
  if not task then return end

  local bufnr = vim.fn.bufnr(task.file_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local chat = require("djinni.nowork.chat")
    local session = require("djinni.acp.session")
    if chat._streaming[bufnr] and chat._stream_cleanup[bufnr] then
      pcall(chat._stream_cleanup[bufnr], true)
    end
    local root = chat.get_project_root(bufnr)
    local sid = chat.get_session_id(bufnr) or chat._sessions[bufnr]
    if root and sid and sid ~= "" then
      local provider = chat._read_frontmatter_csv and nil
      local prov_field = nil
      pcall(function()
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 20, false)
        for _, line in ipairs(lines) do
          local k, v = line:match("^([%w_]+):%s*(.*)")
          if k == "provider" and v and v ~= "" then prov_field = v end
        end
      end)
      session.unsubscribe_session(root, sid, prov_field)
      session.close_task_session(root, sid, prov_field)
    end
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  require("djinni.nowork.chat").archive_chat_file(task.file_path)
  _tasks_dirty = true
  local row = M._win and vim.api.nvim_win_is_valid(M._win) and vim.api.nvim_win_get_cursor(M._win)[1] or 1
  M.render()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    local line_count = vim.api.nvim_buf_line_count(M._buf)
    row = math.min(row, line_count)
    if row < 1 then row = 1 end
    pcall(vim.api.nvim_win_set_cursor, M._win, { row, 0 })
  end
end

function M.remove_project()
  local key = project_at_cursor()
  local root = root_from_key(key)
  if not root or root == "" then return end
  require("djinni.integrations.projects").remove(root)
  _tasks_dirty = true
  M.render()
end

function M.create_task()
  local key = project_at_cursor()
  local root = root_from_key(key)
  local worktree = key and key:match(":(.+)$")
  if not root or root == "" then
    local projects = require("djinni.integrations.projects")
    root = projects.find_root() or vim.fn.getcwd()
  end
  if not worktree or worktree == "" then
    local info = _detect_worktree_info(root)
    if info and info.branch then
      worktree = info.branch
    end
  end

  vim.ui.input({ prompt = "Task: " }, function(prompt)
    if not prompt or prompt == "" then return end

    local function do_create(task_root)
      vim.schedule(function()
        if task_root ~= root then
          require("djinni.integrations.projects").add(task_root)
        end
        local filepath = require("djinni.nowork.chat").create(task_root, { prompt = prompt, no_open = true })
        if filepath and worktree and worktree ~= "" and worktree ~= "main" then
          write_frontmatter_to_file(filepath, "worktree", worktree)
        end
        _tasks_dirty = true
        M.render()
        local win = get_assoc_win()
        if win and filepath then
          vim.api.nvim_win_call(win, function()
            vim.cmd("lcd " .. vim.fn.fnameescape(task_root))
            require("djinni.nowork.chat").open(filepath)
          end)
        end
      end)
    end

    if worktree and worktree ~= "" and worktree ~= "main" then
      local worktrunk = require("djinni.integrations.worktrunk")
      if worktrunk.available() then
        worktrunk.get_path(worktree, function(wt_path)
          do_create(wt_path or root)
        end)
        return
      end
    end
    do_create(root)
  end)
end

function M.merge_worktree()
  local task = task_at_cursor()
  if not task then return end

  local branch = task.worktree
  if not branch or branch == "" then
    vim.notify("[djinni] no worktree set for this task", vim.log.levels.WARN)
    return
  end

  local worktrunk = require("djinni.integrations.worktrunk")
  vim.ui.input({ prompt = "Merge into (empty = trunk): " }, function(target)
    if target == nil then return end
    worktrunk.get_path(branch, function(path)
      worktrunk.merge({ target = target ~= "" and target or nil, cwd = path }, function(ok, out)
        vim.schedule(function()
          if ok then
            vim.notify("[djinni] merged " .. branch .. (target ~= "" and " → " .. target or ""), vim.log.levels.INFO)
          else
            vim.notify("[djinni] merge failed: " .. tostring(out), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end)
end



function M.gen_worktree()
  local task = task_at_cursor()
  if not task then return end

  local worktrunk = require("djinni.integrations.worktrunk")
  if not worktrunk.available() then
    vim.notify("[djinni] worktrunk not available", vim.log.levels.WARN)
    return
  end

  local branch = task.title:lower():gsub("[^%w%-]", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
  if branch == "" then branch = "task" end

  vim.ui.select({ "Current branch", "Default branch", "Stacked (from current HEAD)" }, { prompt = "Worktree base:" }, function(choice)
    if not choice then return end
    local opts = (choice:match("Current") or choice:match("Stacked")) and { base = "@" } or {}
    worktrunk.create_for_task(branch, opts, function(path)
      vim.schedule(function()
        if not path then
          vim.notify("[djinni] worktree failed", vim.log.levels.ERROR)
          return
        end
        write_frontmatter_to_file(task.file_path, "worktree", branch)
        vim.notify("[djinni] worktree: " .. branch, vim.log.levels.INFO)
        _tasks_dirty = true
        M.render()
      end)
    end)
  end)
end

function M.add_project()
  local ok, snacks = pcall(require, "djinni.integrations.snacks")
  if ok and snacks.pick_project then
    snacks.pick_project(function(project_root)
      if project_root then
        require("djinni.integrations.projects").add(project_root)
        _tasks_dirty = true
        M.render()
      end
    end)
  end
end

function M.create_task_with_context()
  local file = vim.api.nvim_buf_get_name(0)
  local ok, snacks = pcall(require, "djinni.integrations.snacks")
  if ok and snacks.pick_task then
    snacks.pick_task({
      context = "@" .. file,
    })
  end
end

function M.create_task_with_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then return end

  local selection = table.concat(lines, "\n")
  local ok, snacks = pcall(require, "djinni.integrations.snacks")
  if ok and snacks.pick_task then
    snacks.pick_task({
      context = "@{selection:" .. selection .. "}",
    })
  end
end

function M.interrupt_task()
  local session = session_at_cursor()
  if session then
    require("djinni.nowork.chat").interrupt(session.buf)
    _tasks_dirty = true
    M.render()
    return
  end

  local task = task_at_cursor()
  if not task then return end
  local bufnr = vim.fn.bufnr(task.file_path)
  if bufnr == -1 then
    vim.notify("[djinni] task buffer not loaded", vim.log.levels.WARN)
    return
  end
  require("djinni.nowork.chat").interrupt(bufnr)
  _tasks_dirty = true
  M.render()
end

function M.dispatch_task()
  local task = task_at_cursor()
  if not task then return end
  if task.status == "running" or task.status == "input" then
    vim.notify("[djinni] task is active", vim.log.levels.WARN)
    return
  end
  local win = get_assoc_win()
  if win then
    vim.api.nvim_win_call(win, function()
      require("djinni.nowork.chat").open(task.file_path)
    end)
  end
end

function M.jump_session(n)
  local s = M._numbered_sessions[n]
  if not s or not vim.api.nvim_buf_is_valid(s.buf) then return end
  local existing = vim.fn.bufwinid(s.buf)
  if existing ~= -1 then
    vim.api.nvim_set_current_win(existing)
  else
    local win = get_assoc_win()
    if win then vim.api.nvim_win_set_buf(win, s.buf) end
  end
end

function M.switch_last_session()
  local hist = M._session_history
  local target = hist[2]
  if not target or not vim.api.nvim_buf_is_valid(target) then return end
  local existing = vim.fn.bufwinid(target)
  if existing ~= -1 then
    vim.api.nvim_set_current_win(existing)
  else
    local win = get_assoc_win()
    if win then vim.api.nvim_win_set_buf(win, target) end
  end
end

function M.show_help()
  local help = {
    "Navigation",
    "  j/k     next/prev item",
    "  {/}     next/prev section",
    "  TAB     toggle fold",
    "  p       toggle sessions/projects",
    "",
    "Agent",
    "  CR/v    open chat (vsplit)",
    "  +       start new agent",
    "  x       stop/interrupt",
    "  *       set active",
    "",
    "Permissions",
    "  !       approve",
    "  ~       deny",
    "",
    "Tasks",
    "  c       create task",
    "  d       archive",
    "  /       search",
    "",
    "  R refresh   q close   ? help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = 36
  local height = #help
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Nowork ",
    title_pos = "center",
  })

  local help_ns = vim.api.nvim_create_namespace("nowork_help")
  for i, line in ipairs(help) do
    if line ~= "" and not line:match("^%s") then
      vim.api.nvim_buf_set_extmark(buf, help_ns, i - 1, 0, {
        end_col = #line, hl_group = "Title",
      })
    end
  end

  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "?", function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf, once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end,
  })
end

return M
