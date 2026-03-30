local M = {}

M._buf = nil
M._win = nil
M._maximized = false
M._cursor_idx = 1
M._tasks = {}

M._assoc_win = nil
M._orig_height = nil

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

local _wt_dirty = {}
local _wt_dirty_ttl = 30

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

local function _refresh_wt_dirty(tasks)
  local worktrunk = require("djinni.integrations.worktrunk")
  if not worktrunk.available() then return end
  for _, task in ipairs(tasks) do
    local branch = task.worktree
    if branch and branch ~= "" then
      local entry = _wt_dirty[branch]
      if not entry or (os.time() - entry.at) >= _wt_dirty_ttl then
        worktrunk.is_dirty(branch, function(dirty)
          _wt_dirty[branch] = { dirty = dirty, at = os.time() }
          if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
            M.render()
          end
        end)
      end
    end
  end
end

local function get_config()
  local ok, djinni = pcall(require, "djinni")
  if ok and djinni.config then
    return djinni.config
  end
  return { panel = { height = 15, position = "bottom" }, chat = { dir = ".chat" } }
end

local function get_assoc_win()
  if M._assoc_win and vim.api.nvim_win_is_valid(M._assoc_win) and M._assoc_win ~= M._win then
    return M._assoc_win
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= M._win then
      return win
    end
  end
  vim.cmd("above split")
  local new_win = vim.api.nvim_get_current_win()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_set_current_win(M._win)
  end
  M._assoc_win = new_win
  return new_win
end

M._line_tasks = {}
M._line_projects = {}

local function task_at_cursor()
  if not M._buf or not M._win then return nil end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  return M._line_tasks[row]
end

local function project_at_cursor()
  if not M._buf or not M._win then return nil end
  local row = vim.api.nvim_win_get_cursor(M._win)[1]
  return M._line_projects[row]
end

function M._get_grouped_tasks()
  local groups = {}
  local group_map = {}

  local projects = require("djinni.integrations.projects")
  for _, root in ipairs(projects.get()) do
    local name = vim.fn.fnamemodify(root, ":t")
    if not group_map[root] then
      group_map[root] = { name = name, root = root, tasks = {} }
      table.insert(groups, group_map[root])
    end
  end

  for _, task in ipairs(M._tasks) do
    local task_root = task.root or task.file_path:match("^(.-)/%.[^/]+/[^/]+$") or ""
    if not group_map[task_root] then
      group_map[task_root] = { name = task.project, root = task_root, tasks = {} }
      table.insert(groups, group_map[task_root])
    end
    table.insert(group_map[task_root].tasks, task)
  end
  return groups
end

function M._scan_tasks()
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
        if type == "file" and name:match("%.md$") then
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
            local in_frontmatter = false
            local fm_count = 0
            for line in f:lines() do
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
      end
      if chat._streaming[bufnr] then
        task.status = "running"
      end
    end
  end

  M._tasks = tasks
  _refresh_wt_dirty(tasks)
end

local function format_model(model)
  if not model or model == "" then return "" end
  return model:gsub("^claude%-", ""):gsub("^anthropic/", "")
end

local function aggregate_group(group_tasks)
  local total_tokens = 0
  local total_cost = 0
  for _, task in ipairs(group_tasks) do
    local tok = task.tokens or ""
    local n = tonumber(tok:match("^([%d%.]+)k$"))
    if n then
      total_tokens = total_tokens + n * 1000
    else
      total_tokens = total_tokens + (tonumber(tok) or 0)
    end
    total_cost = total_cost + (tonumber(task.cost) or 0)
  end
  local parts = { tostring(#group_tasks) .. " tasks" }
  if total_tokens > 0 then
    table.insert(parts, total_tokens >= 1000 and string.format("%.1fk", total_tokens / 1000) or tostring(total_tokens))
  end
  if total_cost > 0 then
    table.insert(parts, string.format("$%.2f", total_cost))
  end
  return table.concat(parts, ", ")
end

function M.render()
  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then return end

  M._scan_tasks()

  local lines = {}
  local hl_marks = {}
  M._line_tasks = {}
  M._line_projects = {}
  local virt_texts = {}

  local groups = M._get_grouped_tasks()
  for _, group in ipairs(groups) do
    local summary = aggregate_group(group.tasks)
    local header = group.name .. " (" .. summary .. ")"
    table.insert(lines, header)
    local line_nr = #lines
    M._line_projects[line_nr] = group.root
    table.insert(hl_marks, {
      line = line_nr - 1, col = 0, end_col = #group.name,
      hl = "Directory",
    })

    for _, task in ipairs(group.tasks) do
      local icon = status_icons[task.status] or "◆"
      local fname = vim.fn.fnamemodify(task.file_path, ":t"):gsub("%.md$", "")
      local task_line = "  " .. icon .. " " .. fname
      table.insert(lines, task_line)
      local tline_nr = #lines
      M._line_tasks[tline_nr] = task
      M._line_projects[tline_nr] = group.root

      table.insert(hl_marks, {
        line = tline_nr - 1, col = 2, end_col = 2 + #icon,
        hl = status_hl[task.status] or "Comment",
      })

      local vt = {}
      local model_str = format_model(task.model)
      if model_str ~= "" then
        table.insert(vt, { model_str, "Comment" })
        table.insert(vt, { " │ ", "NonText" })
      end
      if task.tokens ~= "" then
        table.insert(vt, { task.tokens, "Number" })
      end
      if task.cost ~= "" then
        table.insert(vt, { " │ ", "NonText" })
        table.insert(vt, { "$" .. task.cost, "String" })
      end
      if task.skills ~= "" then
        if #vt > 0 then table.insert(vt, { " │ ", "NonText" }) end
        local count = select(2, task.skills:gsub(",", ",")) + 1
        table.insert(vt, { count .. " skill" .. (count > 1 and "s" or ""), "DiagnosticInfo" })
      end
      if task.mcp ~= "" then
        if #vt > 0 then table.insert(vt, { " │ ", "NonText" }) end
        local count = select(2, task.mcp:gsub(",", ",")) + 1
        table.insert(vt, { count .. " mcp", "Special" })
      end
      if task.worktree and task.worktree ~= "" then
        if #vt > 0 then table.insert(vt, { " │ ", "NonText" }) end
        local entry = _wt_dirty[task.worktree]
        local label = "⎇ " .. task.worktree
        if entry and entry.dirty then label = label .. "*" end
        local hl = (entry and entry.dirty) and "DiagnosticWarn" or "DiagnosticHint"
        table.insert(vt, { label, hl })
      end
      if #vt > 0 then
        virt_texts[tline_nr - 1] = vt
      end
    end
  end

  if #lines == 0 then
    table.insert(lines, "  No tasks")
    table.insert(hl_marks, { line = 0, col = 0, end_col = 10, hl = "Comment" })
  end

  vim.bo[M._buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(M._buf, ns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_set_extmark, M._buf, ns, mark.line, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
    })
  end
  for line_idx, vt in pairs(virt_texts) do
    pcall(vim.api.nvim_buf_set_extmark, M._buf, ns, line_idx, 0, {
      virt_text = vt,
      virt_text_pos = "right_align",
    })
  end

  if M._win and vim.api.nvim_win_is_valid(M._win) then
    local line_count = vim.api.nvim_buf_line_count(M._buf)
    local target = math.min(M._cursor_idx, line_count)
    if target < 1 then target = 1 end
    pcall(vim.api.nvim_win_set_cursor, M._win, { target, 0 })
  end
end

function M.open()
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    M.close()
  end

  M._assoc_win = vim.api.nvim_get_current_win()
  local cfg = get_config()
  local height = cfg.panel and cfg.panel.height or 15

  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].buftype = "nofile"
  vim.bo[M._buf].bufhidden = "wipe"
  vim.bo[M._buf].swapfile = false
  vim.bo[M._buf].filetype = "nowork-panel"

  vim.cmd("botright " .. height .. "split")
  M._win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M._win, M._buf)

  vim.wo[M._win].winfixheight = true
  vim.wo[M._win].cursorline = true
  vim.wo[M._win].wrap = false
  vim.wo[M._win].signcolumn = "no"
  vim.wo[M._win].number = false
  vim.wo[M._win].relativenumber = false
  vim.wo[M._win].foldenable = false

  M._orig_height = height

  local buf = M._buf
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true })
  end

  map("<CR>", M.open_task)
  map("c", M.create_task)
  map("<C-w>", M.gen_worktree)
  map("m", M.merge_worktree)
  map("P", M.add_project)
  map("Z", M.maximize)
  map("d", M.archive_task)
  map("D", M.remove_project)
  map("q", M.close)
  map("j", M.cursor_down)
  map("k", M.cursor_up)
  map("/", M.search_tasks)
  map("?", M.show_help)

  M.render()
end

function M.close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
  end
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    pcall(vim.api.nvim_buf_delete, M._buf, { force = true })
  end
  M._buf = nil
  M._win = nil
  M._maximized = false
end

function M.toggle()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    M.close()
  else
    M.open()
  end
end

function M.maximize()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end

  if M._maximized then
    vim.api.nvim_win_set_height(M._win, M._orig_height)
  else
    vim.api.nvim_win_set_height(M._win, vim.o.lines - 3)
  end
  M._maximized = not M._maximized
end


function M.cursor_down()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local cursor = vim.api.nvim_win_get_cursor(M._win)
  local line_count = vim.api.nvim_buf_line_count(M._buf)
  local new_row = math.min(cursor[1] + 1, line_count)
  vim.api.nvim_win_set_cursor(M._win, { new_row, 0 })

  if M._line_tasks[new_row] then
    for i, t in ipairs(M._tasks) do
      if t == M._line_tasks[new_row] then
        M._cursor_idx = i
        break
      end
    end
  end
end

function M.cursor_up()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then return end
  local cursor = vim.api.nvim_win_get_cursor(M._win)
  local new_row = math.max(cursor[1] - 1, 1)
  vim.api.nvim_win_set_cursor(M._win, { new_row, 0 })

  if M._line_tasks[new_row] then
    for i, t in ipairs(M._tasks) do
      if t == M._line_tasks[new_row] then
        M._cursor_idx = i
        break
      end
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
        require("djinni.nowork.chat").open(task.file_path)
      end)
    end
  end
end

function M.open_task()
  local task = task_at_cursor()
  if not task then return end

  local win = get_assoc_win()
  if win then
    vim.api.nvim_win_call(win, function()
      require("djinni.nowork.chat").open(task.file_path)
    end)
  end
end

function M.archive_task()
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
  os.remove(task.file_path)
  M.render()
end

function M.remove_project()
  local root = project_at_cursor()
  if not root or root == "" then return end
  require("djinni.integrations.projects").remove(root)
  M.render()
end

function M.create_task()
  local root = project_at_cursor()
  if not root or root == "" then
    local projects = require("djinni.integrations.projects")
    root = projects.find_root() or vim.fn.getcwd()
  end

  vim.ui.input({ prompt = "Task: " }, function(prompt)
    if not prompt or prompt == "" then return end
    vim.schedule(function()
      local filepath = require("djinni.nowork.chat").create(root, { prompt = prompt, no_open = true })
      M.render()
      local win = get_assoc_win()
      if win and filepath then
        vim.api.nvim_win_call(win, function()
          require("djinni.nowork.chat").open(filepath)
        end)
      end
    end)
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
    worktrunk.merge(target, branch, function(ok, out)
      vim.schedule(function()
        if ok then
          vim.notify("[djinni] merged " .. branch .. (target ~= "" and " → " .. target or ""), vim.log.levels.INFO)
        else
          vim.notify("[djinni] merge failed: " .. tostring(out), vim.log.levels.ERROR)
        end
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

  vim.ui.select({ "Normal (default branch)", "Stacked (from current HEAD)" }, { prompt = "Worktree base:" }, function(choice)
    if not choice then return end
    local opts = choice:match("Stacked") and { base = "@" } or {}
    worktrunk.create(branch, opts, function(ok, path_or_err)
      vim.schedule(function()
        if not ok then
          vim.notify("[djinni] worktree failed: " .. tostring(path_or_err), vim.log.levels.ERROR)
          return
        end
        write_frontmatter_to_file(task.file_path, "worktree", branch)
        vim.notify("[djinni] worktree: " .. branch, vim.log.levels.INFO)
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

function M.show_help()
  local help = {
    "Nowork Keybinds",
    "",
    "  c       Create task",
    "  <C-w>   Gen worktree",
    "  m       Merge worktree",
    "  P       Add project",
    "  Z       Maximize / restore",
    "  d       Delete task",
    "  D       Remove project",
    "  <CR>    Open task",
    "  /       Search tasks",
    "  j / k   Navigate",
    "  q       Close panel",
    "  ?       This help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = 30
  local height = #help
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = vim.o.lines - height - 4,
    style = "minimal",
    border = "rounded",
    title = " Help ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

return M
