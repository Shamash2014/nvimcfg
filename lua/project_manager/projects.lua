local M = {}

local STATUS_PRIORITY = {
  waiting = 5,
  busy = 4,
  done = 3,
  active = 2,
  inactive = 1,
}

local git_root_cache = {}
local git_root_cache_time = 0

local function resolve_git_root(path)
  if not path or path == '' then
    return nil
  end

  local now = vim.uv.hrtime()
  if (now - git_root_cache_time) > 10e9 then
    git_root_cache = {}
    git_root_cache_time = now
  end

  if git_root_cache[path] ~= nil then
    return git_root_cache[path] or nil
  end

  local git_dir = vim.fs.find('.git', { upward = true, path = path, limit = 1 })
  if git_dir and #git_dir > 0 then
    local root = vim.fn.fnamemodify(git_dir[1], ':h')
    git_root_cache[path] = root
    return root
  end

  git_root_cache[path] = false
  return nil
end

local function normalize_path(path)
  return vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
end

local function get_worktree_parent(path)
  local git_path = path .. "/.git"
  local stat = vim.uv.fs_stat(git_path)
  if not stat or stat.type ~= "file" then return nil end

  local f = io.open(git_path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()

  local gitdir = content:match("gitdir:%s*(.+)")
  if not gitdir then return nil end
  gitdir = gitdir:gsub("%s+$", "")
  if not gitdir:match("^/") then
    gitdir = vim.fn.fnamemodify(path .. "/" .. gitdir, ":p")
  end
  local common = gitdir:match("(.+)/%.git/worktrees/")
  if common then
    return vim.fn.fnamemodify(common, ":p"):gsub("/$", "")
  end
  return nil
end

local function relative_time(timestamp)
  if not timestamp then
    return "unknown"
  end
  local diff = os.time() - timestamp
  if diff < 60 then
    return "just now"
  elseif diff < 3600 then
    return string.format("%dm ago", math.floor(diff / 60))
  elseif diff < 86400 then
    return string.format("%dh ago", math.floor(diff / 3600))
  else
    return string.format("%dd ago", math.floor(diff / 86400))
  end
end

local function get_process_status(proc)
  if not proc or not proc:is_alive() then
    return "inactive"
  end
  if proc.ui and proc.ui.permission_active then
    return "waiting"
  end
  if not proc.state.busy and proc.state.session_ready then
    return "done"
  end
  if proc.state.busy then
    return "busy"
  end
  return "active"
end

local function ensure_project(projects, root)
  if not projects[root] then
    projects[root] = {
      path = root,
      name = vim.fn.fnamemodify(root, ":t"),
      sessions = {},
      best_priority = 0,
      source = "oldfiles",
    }
  end
  return projects[root]
end

local function collect_live_sessions(projects, seen_paths)
  local ok_reg, registry = pcall(require, "ai_repl.registry")
  if not ok_reg then return end

  local ok_prov, providers = pcall(require, "ai_repl.providers")
  local ok_parser, chat_parser = pcall(require, "ai_repl.chat_parser")

  for sid, proc in pairs(registry.all()) do
    local cwd = proc.data and proc.data.cwd
    if not cwd then
      goto continue
    end

    local root = resolve_git_root(cwd) or cwd
    root = normalize_path(root)

    local proj = ensure_project(projects, root)
    proj.source = "live"

    local status = get_process_status(proc)
    local prio = STATUS_PRIORITY[status] or 0
    if prio > proj.best_priority then
      proj.best_priority = prio
    end

    local provider_id = proc.data.provider
    local provider_name = provider_id or "Agent"
    if ok_prov and provider_id then
      local cfg = providers.get(provider_id)
      if cfg then
        provider_name = cfg.name
      end
    end

    local chat_buf = proc.ui and proc.ui.chat_buf
    local buf_valid = chat_buf and vim.api.nvim_buf_is_valid(chat_buf)
    local buf_name = buf_valid and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(chat_buf), ":t") or nil
    local msg_count = 0
    local annotation_count = 0
    if buf_valid and ok_parser then
      local parse_ok, parsed = pcall(chat_parser.parse_buffer_cached, chat_buf)
      if parse_ok and parsed then
        msg_count = #parsed.messages
        annotation_count = parsed.annotations and #parsed.annotations or 0
      end
    end

    local plan = proc.ui and proc.ui.current_plan or {}
    local open_tasks = {}
    for _, item in ipairs(plan) do
      if item.status ~= "completed" then
        table.insert(open_tasks, {
          content = item.content or item.activeForm or "",
          status = item.status or "pending",
        })
      end
    end

    table.insert(proj.sessions, {
      type = "live",
      session_id = sid,
      buf = buf_valid and chat_buf or nil,
      process = proc,
      provider_name = provider_name,
      status = status,
      priority = prio,
      buf_name = buf_name,
      msg_count = msg_count,
      annotation_count = annotation_count,
      plan_items = open_tasks,
      open_task_count = #open_tasks,
    })

    seen_paths[root] = true
    ::continue::
  end
end

local function collect_persisted_sessions(projects, seen_paths)
  local ok_reg, registry = pcall(require, "ai_repl.registry")
  if not ok_reg then return end

  local ok_prov, providers = pcall(require, "ai_repl.providers")

  local saved_sessions = registry.load_from_disk()
  local live_sids = {}
  for sid in pairs(registry.all()) do
    live_sids[sid] = true
  end

  for sid, info in pairs(saved_sessions) do
    if live_sids[sid] then
      goto continue
    end

    local cwd = info.cwd
    if not cwd then
      goto continue
    end

    local root = resolve_git_root(cwd) or cwd
    root = normalize_path(root)

    local proj = ensure_project(projects, root)
    if proj.source ~= "live" then
      proj.source = "persisted"
    end

    local provider_id = info.provider
    local provider_name = provider_id or "Agent"
    if ok_prov and provider_id then
      local cfg = providers.get(provider_id)
      if cfg then
        provider_name = cfg.name
      end
    end

    table.insert(proj.sessions, {
      type = "persisted",
      session_id = sid,
      provider_name = provider_name,
      last_saved = info.last_saved,
      time_display = "saved " .. relative_time(info.last_saved),
    })

    seen_paths[root] = true
    ::continue::
  end
end

local function collect_open_buffers(projects, tab_visible_bufs)
  local ok_chat, chat_buffer = pcall(require, "ai_repl.chat_buffer")

  local buffers = vim.fn.getbufinfo({ buflisted = 1 })
  for _, buf_info in ipairs(buffers) do
    local name = buf_info.name
    if name == "" then
      goto continue
    end

    local buftype = vim.bo[buf_info.bufnr].buftype
    if buftype ~= "" then
      goto continue
    end

    if tab_visible_bufs and tab_visible_bufs[buf_info.bufnr] then
      goto continue
    end

    if ok_chat and chat_buffer.is_chat_buffer(buf_info.bufnr) then
      goto continue
    end

    local dir = vim.fn.fnamemodify(name, ":h")
    local root = resolve_git_root(dir)
    if not root then
      goto continue
    end
    root = normalize_path(root)

    local proj = projects[root]
    if not proj then
      goto continue
    end

    if not proj.buffers then
      proj.buffers = {}
    end

    table.insert(proj.buffers, {
      bufnr = buf_info.bufnr,
      name = vim.fn.fnamemodify(name, ":t"),
      path = name,
      modified = buf_info.changed == 1,
    })

    ::continue::
  end
end

local function collect_running_tasks(projects, seen_paths)
  local ok_tasks, tasks_mod = pcall(require, "core.tasks")
  if not ok_tasks then return end

  for _, task in ipairs(tasks_mod.running_tasks) do
    if task.ai_session then
      goto continue
    end

    if not task:is_alive() then
      goto continue
    end

    local cwd = task.cwd
    if not cwd then
      goto continue
    end

    local root = resolve_git_root(cwd) or cwd
    root = normalize_path(root)

    local proj = ensure_project(projects, root)
    if proj.source ~= "live" then
      proj.source = "persisted"
    end

    if not proj.running_tasks then
      proj.running_tasks = {}
    end

    local runtime = os.difftime(os.time(), task.start_time)
    local runtime_str
    if runtime < 60 then
      runtime_str = string.format("%ds", runtime)
    else
      runtime_str = string.format("%dm %ds", math.floor(runtime / 60), runtime % 60)
    end

    table.insert(proj.running_tasks, {
      type = "running_task",
      name = task.name,
      runtime_str = runtime_str,
      background = task.background,
      term_buf = task.term and task.term.buf,
      task_ref = task,
    })

    seen_paths[root] = true
    ::continue::
  end
end

local function collect_open_tabs(projects)
  local current_tabpage = vim.api.nvim_get_current_tabpage()
  local tab_visible_bufs = {}

  for tabnr, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local wins = vim.api.nvim_tabpage_list_wins(tabpage)
    local tab_windows = {}
    local tab_root = nil

    for _, winid in ipairs(wins) do
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local buftype = vim.bo[bufnr].buftype
      if buftype ~= "" then
        goto continue_win
      end

      local name = vim.api.nvim_buf_get_name(bufnr)
      if name == "" then
        goto continue_win
      end

      local short_name = vim.fn.fnamemodify(name, ":t")

      if not tab_root then
        local dir = vim.fn.fnamemodify(name, ":h")
        tab_root = resolve_git_root(dir)
        if tab_root then
          tab_root = normalize_path(tab_root)
        end
      end

      tab_visible_bufs[bufnr] = true
      table.insert(tab_windows, {
        winid = winid,
        bufnr = bufnr,
        name = short_name,
      })

      ::continue_win::
    end

    if tab_root and #tab_windows > 0 then
      local proj = ensure_project(projects, tab_root)
      if not proj.tabs then
        proj.tabs = {}
      end
      table.insert(proj.tabs, {
        type = "tab",
        tabnr = tabnr,
        tabpage = tabpage,
        is_current = (tabpage == current_tabpage),
        windows = tab_windows,
      })
    end
  end

  return tab_visible_bufs
end

local function collect_oldfiles_projects(projects, seen_paths)
  local oldfiles = vim.v.oldfiles or {}
  local checked_dirs = {}
  local added = 0

  for _, filepath in ipairs(oldfiles) do
    if added >= 20 then
      break
    end

    local dir = vim.fn.fnamemodify(filepath, ":h")
    if checked_dirs[dir] then
      goto continue
    end
    checked_dirs[dir] = true

    local root = resolve_git_root(dir)
    if not root then
      goto continue
    end
    root = normalize_path(root)

    if seen_paths[root] then
      goto continue
    end

    ensure_project(projects, root)
    seen_paths[root] = true
    added = added + 1

    ::continue::
  end
end

function M.gather()
  local projects = {}
  local seen_paths = {}

  collect_live_sessions(projects, seen_paths)
  collect_persisted_sessions(projects, seen_paths)
  collect_running_tasks(projects, seen_paths)
  collect_oldfiles_projects(projects, seen_paths)
  local tab_visible_bufs = collect_open_tabs(projects)
  collect_open_buffers(projects, tab_visible_bufs)

  local ok_mem, memory = pcall(require, "core.memory")
  if ok_mem then
    for _, proj in pairs(projects) do
      if memory.exists(proj.path) then
        proj.has_memory = true
        proj.memory_lines = memory.line_count(proj.path)
      end
    end
  end

  local sorted = {}
  for _, proj in pairs(projects) do
    table.sort(proj.sessions, function(a, b)
      if a.type ~= b.type then
        return a.type == "live"
      end
      if a.type == "live" then
        return (a.priority or 0) > (b.priority or 0)
      end
      return (a.last_saved or 0) > (b.last_saved or 0)
    end)
    table.insert(sorted, proj)
  end

  local SOURCE_PRIORITY = { live = 3, persisted = 2, oldfiles = 1 }
  table.sort(sorted, function(a, b)
    local sa = SOURCE_PRIORITY[a.source] or 0
    local sb = SOURCE_PRIORITY[b.source] or 0
    if sa ~= sb then
      return sa > sb
    end
    if a.best_priority ~= b.best_priority then
      return a.best_priority > b.best_priority
    end
    return a.name < b.name
  end)

  for _, proj in ipairs(sorted) do
    local parent = get_worktree_parent(proj.path)
    if parent then
      proj.worktree_parent = normalize_path(parent)
      proj.name = proj.name .. " (wt)"
    end
  end

  return sorted
end

M.STATUS_PRIORITY = STATUS_PRIORITY

return M
