local M = {}

M._task_bufs = {}
M._task_lines = {}
M._line_to_file = {}

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

local ns = vim.api.nvim_create_namespace("nowork_task_section")

local function get_config()
  local ok, djinni = pcall(require, "djinni")
  if ok and djinni.config then
    return djinni.config
  end
  return { chat = { dir = ".chat" } }
end

local function normalize_root(root)
  return vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
end

local function resolve_root(root)
  if root then return normalize_root(root) end
  local projects = require("djinni.integrations.projects")
  local found = projects.find_root()
  return normalize_root(found or vim.fn.getcwd())
end

local function format_model(model)
  if not model or model == "" then return "" end
  return model:gsub("^claude%-", ""):gsub("^anthropic/", "")
end

local function project_name(root)
  return vim.fn.fnamemodify(root, ":t")
end

local function task_file_path(root)
  local cfg = get_config()
  local chat_dir = cfg.chat and cfg.chat.dir or ".chat"
  return root .. "/" .. chat_dir .. "/TASK.md"
end

function M.is_task_buf(buf)
  return M._task_bufs[buf] == true
end

function M._scan_project_tasks(root)
  local cfg = get_config()
  local chat_dir = cfg.chat and cfg.chat.dir or ".chat"
  local tasks = {}
  local task_path = task_file_path(root)

  local dir = root .. "/" .. chat_dir
  local handle = vim.loop.fs_scandir(dir)
  if not handle then return tasks end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if type == "file" and name:match("%.md$") then
      local path = dir .. "/" .. name
      if path == task_path then goto continue end
      local f = io.open(path, "r")
      if f then
        local title = name:gsub("%.md$", "")
        local status = "idle"
        local model = ""
        local tokens = ""
        local cost = ""
        local worktree = ""
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
            if k == "model" then model = v end
            if k == "tokens" then tokens = v end
            if k == "cost" then cost = v end
            if k == "worktree" then worktree = v end
          end
        end
        f:close()

        local chat = require("djinni.nowork.chat")
        local bufnr = vim.fn.bufnr(path)
        if bufnr ~= -1 then
          local usage = chat._usage[bufnr]
          if usage then
            local total = usage.input_tokens + usage.output_tokens
            if total > 0 then
              tokens = total >= 1000 and string.format("%.1fk", total / 1000) or tostring(total)
            end
            if usage.cost > 0 then
              cost = string.format("%.2f", usage.cost)
            end
          end
          if chat._streaming[bufnr] then
            status = "running"
          end
        end

        table.insert(tasks, {
          title = title,
          status = status,
          model = model,
          tokens = tokens,
          cost = cost,
          worktree = worktree,
          file_path = path,
        })
      end
      ::continue::
    end
  end

  table.sort(tasks, function(a, b)
    local oa = status_order[a.status] or 99
    local ob = status_order[b.status] or 99
    if oa ~= ob then return oa < ob end
    return a.title < b.title
  end)

  return tasks
end

function M._build_task_lines(tasks)
  local lines = { "", "### Tasks" }
  for _, task in ipairs(tasks) do
    local icon = status_icons[task.status] or "◆"
    local fname = vim.fn.fnamemodify(task.file_path, ":t"):gsub("%.md$", "")
    local parts = { "  " .. icon .. " " .. fname }
    local model_str = format_model(task.model)
    local meta = {}
    if model_str ~= "" then table.insert(meta, model_str) end
    if task.tokens ~= "" then table.insert(meta, task.tokens) end
    if task.cost ~= "" then table.insert(meta, "$" .. task.cost) end
    if task.worktree ~= "" then table.insert(meta, "⎇ " .. task.worktree) end
    if #meta > 0 then
      parts[1] = parts[1] .. "  " .. table.concat(meta, " │ ")
    end
    table.insert(lines, parts[1])
  end
  if #tasks == 0 then
    table.insert(lines, "  No tasks yet")
  end
  table.insert(lines, "")
  table.insert(lines, "---")
  return lines
end

function M._apply_task_highlights(buf, section_start, tasks)
  vim.api.nvim_buf_clear_namespace(buf, ns, section_start, section_start + #tasks + 10)
  for i, task in ipairs(tasks) do
    local line_idx = section_start + 1 + i
    local icon = status_icons[task.status] or "◆"
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, line_idx, 2, {
      end_col = 2 + #icon,
      hl_group = status_hl[task.status] or "Comment",
    })
  end
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, section_start + 1, 0, {
    end_col = 8,
    hl_group = "Directory",
  })
end

function M.update_tasks_section(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if not M._task_bufs[buf] then return end

  local chat = require("djinni.nowork.chat")
  local root = chat.get_project_root(buf)
  if not root then return end

  local tasks = M._scan_project_tasks(root)
  local task_lines = M._build_task_lines(tasks)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local fm_end = nil
  local fm_count = 0
  for i, line in ipairs(lines) do
    if line:match("^%-%-%-$") then
      fm_count = fm_count + 1
      if fm_count == 2 then
        fm_end = i
        break
      end
    end
  end
  if not fm_end then return end

  local task_start = nil
  local task_end = nil
  for i = fm_end + 1, #lines do
    if lines[i]:match("^### Tasks") then
      task_start = i
    elseif task_start and lines[i]:match("^%-%-%-$") then
      task_end = i
      break
    end
  end

  local section_start
  if task_start and task_end then
    vim.api.nvim_buf_set_lines(buf, task_start - 1, task_end, false, task_lines)
    section_start = task_start - 1
  else
    vim.api.nvim_buf_set_lines(buf, fm_end, fm_end, false, task_lines)
    section_start = fm_end
  end

  M._task_lines[buf] = { start_line = section_start, end_line = section_start + #task_lines }
  M._apply_task_highlights(buf, section_start, tasks)

  M._line_to_file[buf] = {}
  for i, task in ipairs(tasks) do
    local line_nr = section_start + 2 + i
    M._line_to_file[buf][line_nr] = task.file_path
  end
end

function M.open_task_at_cursor(buf)
  local map = M._line_to_file[buf]
  if not map then return false end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local file = map[row]
  if not file then return false end
  require("djinni.nowork.chat").open(file)
  return true
end

function M.setup_keymaps(buf)
  local chat = require("djinni.nowork.chat")
  vim.keymap.set("n", "<CR>", function()
    if not M.open_task_at_cursor(buf) then
      local text = chat._get_you_block_at_cursor(buf)
      if not text or text == "" then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local row = vim.api.nvim_win_get_cursor(0)[1]
        for i = row, 1, -1 do
          if lines[i] and lines[i]:match("^@You%s*$") then
            local win = vim.fn.bufwinid(buf)
            if win ~= -1 then
              vim.api.nvim_win_set_cursor(win, { i + 1, 0 })
              vim.cmd("startinsert!")
            end
            return
          end
          if lines[i] and (lines[i]:match("^@%w+%s*$") or lines[i]:match("^%-%-%-$")) then
            break
          end
        end
        return
      end
      chat._migrate_you_block(buf)
      if chat._streaming[buf] then
        if not chat._queue[buf] then chat._queue[buf] = {} end
        table.insert(chat._queue[buf], text)
      else
        chat.send(buf, text)
      end
    end
  end, { buffer = buf, silent = true, nowait = true })
end

local function setup_task_autocmds(buf)
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        M.update_tasks_section(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      M._task_bufs[buf] = nil
      M._task_lines[buf] = nil
      M._line_to_file[buf] = nil
    end,
  })
end

function M.open(root)
  root = resolve_root(root)
  local chat = require("djinni.nowork.chat")
  local path = task_file_path(root)

  local existing = vim.fn.bufnr(path)
  if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
    vim.api.nvim_set_current_buf(existing)
    M.update_tasks_section(existing)
    return existing
  end

  if vim.fn.filereadable(path) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    M._task_bufs[buf] = true
    chat.attach(buf)
    M.setup_keymaps(buf)
    chat._ensure_session(buf)
    setup_task_autocmds(buf)
    M.update_tasks_section(buf)
    return buf
  end

  local cfg = get_config()
  local chat_dir = root .. "/" .. (cfg.chat and cfg.chat.dir or ".chat")
  vim.fn.mkdir(chat_dir, "p")

  local mcp_mod = require("djinni.nowork.mcp")
  local auto_mcps = mcp_mod.list(root)
  local mcp_value = #auto_mcps > 0 and table.concat(auto_mcps, ", ") or ""

  local content = table.concat({
    "---",
    "project: " .. project_name(root),
    "root: " .. root,
    "type: task",
    "session:",
    "provider: claude-code",
    "model:",
    "mcp: " .. mcp_value,
    "status:",
    "created: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
    "---",
    "",
    "### Tasks",
    "  No tasks yet",
    "",
    "---",
    "",
    "@System",
    "Task buffer ready",
    "",
    "---",
    "",
    string.rep("~", 45),
    "",
  }, "\n")

  local f = io.open(path, "w")
  if f then
    f:write(content)
    f:close()
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  M._task_bufs[buf] = true
  chat.attach(buf)
  M.setup_keymaps(buf)
  chat._ensure_session(buf)
  setup_task_autocmds(buf)
  M.update_tasks_section(buf)
  return buf
end

function M.toggle(root)
  root = resolve_root(root)
  local path = task_file_path(root)
  local existing = vim.fn.bufnr(path)
  if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
    local win = vim.fn.bufwinid(existing)
    if win ~= -1 then
      vim.api.nvim_win_close(win, false)
      return
    end
  end
  M.open(root)
end

return M
