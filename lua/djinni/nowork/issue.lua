local M = {}

M.statuses = { "backlog", "todo", "in_progress", "in_review", "blocked", "done" }
M.priorities = { "critical", "high", "medium", "low" }

local function get_chat_dir()
  local ok, djinni = pcall(require, "djinni")
  if ok and djinni.config and djinni.config.chat then
    return djinni.config.chat.dir or ".chat"
  end
  return ".chat"
end

local function issues_dir(project_root)
  local dir = project_root .. "/" .. get_chat_dir() .. "/issues"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function generate_id()
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  local result = "iss-"
  for _ = 1, 6 do
    local idx = math.random(1, #chars)
    result = result .. chars:sub(idx, idx)
  end
  return result
end

local function iso_timestamp()
  return os.date("%Y-%m-%dT%H:%M:%S")
end

local function parse_issue(path, project_root)
  local f = io.open(path, "r")
  if not f then return nil end

  local fields = {}
  local body_lines = {}
  local in_frontmatter = false
  local fm_count = 0
  local past_frontmatter = false

  for line in f:lines() do
    if not past_frontmatter then
      if line:match("^%-%-%-") then
        fm_count = fm_count + 1
        if fm_count == 1 then
          in_frontmatter = true
        elseif fm_count == 2 then
          in_frontmatter = false
          past_frontmatter = true
        end
      elseif in_frontmatter then
        local k, v = line:match("^([%w_]+):%s*(.*)$")
        if k then fields[k] = v end
      end
    else
      table.insert(body_lines, line)
    end
  end
  f:close()

  while #body_lines > 0 and body_lines[1] == "" do
    table.remove(body_lines, 1)
  end

  local function nonempty(v)
    return (v and v ~= "") and v or nil
  end

  return {
    id               = nonempty(fields.id) or vim.fn.fnamemodify(path, ":t:r"),
    title            = fields.title or "",
    status           = nonempty(fields.status) or "backlog",
    priority         = nonempty(fields.priority) or "medium",
    assignee_session = nonempty(fields.assignee_session),
    parent_id        = nonempty(fields.parent_id),
    goal             = nonempty(fields.goal),
    created_at       = fields.created_at or "",
    updated_at       = fields.updated_at or "",
    body             = table.concat(body_lines, "\n"),
    path             = path,
    project_root     = project_root,
    project_name     = vim.fn.fnamemodify(project_root, ":t"),
  }
end

local function write_issue(project_root, issue)
  local path = issues_dir(project_root) .. "/" .. issue.id .. ".md"
  issue.path = path
  local content = table.concat({
    "---",
    "id: " .. issue.id,
    "title: " .. (issue.title or ""),
    "status: " .. (issue.status or "backlog"),
    "priority: " .. (issue.priority or "medium"),
    "assignee_session: " .. (issue.assignee_session or ""),
    "parent_id: " .. (issue.parent_id or ""),
    "goal: " .. (issue.goal or ""),
    "created_at: " .. (issue.created_at or iso_timestamp()),
    "updated_at: " .. (issue.updated_at or iso_timestamp()),
    "---",
    "",
    issue.body or "",
  }, "\n")
  local f = io.open(path, "w")
  if f then
    f:write(content)
    f:close()
  end
end

function M.list(project_root)
  local dir = issues_dir(project_root)
  local result = {}
  local handle = vim.loop.fs_scandir(dir)
  if not handle then return result end
  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if ftype == "file" and name:match("%.md$") then
      local issue = parse_issue(dir .. "/" .. name, project_root)
      if issue then
        table.insert(result, issue)
      end
    end
  end
  table.sort(result, function(a, b)
    return (a.updated_at or "") > (b.updated_at or "")
  end)
  return result
end

function M.get(project_root, id)
  return parse_issue(issues_dir(project_root) .. "/" .. id .. ".md", project_root)
end

function M.create(project_root, fields)
  local id = generate_id()
  local now = iso_timestamp()
  local issue = {
    id               = id,
    title            = fields.title or "",
    status           = fields.status or "backlog",
    priority         = fields.priority or "medium",
    assignee_session = fields.assignee_session,
    parent_id        = fields.parent_id,
    goal             = fields.goal,
    created_at       = now,
    updated_at       = now,
    body             = fields.body or "",
    project_root     = project_root,
    project_name     = vim.fn.fnamemodify(project_root, ":t"),
  }
  write_issue(project_root, issue)
  return issue
end

function M.update(project_root, id, fields)
  local issue = M.get(project_root, id)
  if not issue then return end
  for k, v in pairs(fields) do
    issue[k] = v
  end
  issue.updated_at = iso_timestamp()
  write_issue(project_root, issue)
  return issue
end

function M.archive(project_root, id)
  local src = issues_dir(project_root) .. "/" .. id .. ".md"
  local archive_dir = issues_dir(project_root) .. "/archive"
  vim.fn.mkdir(archive_dir, "p")
  local dst = archive_dir .. "/" .. id .. ".md"
  os.rename(src, dst)
end

function M.delete(project_root, id)
  local path = issues_dir(project_root) .. "/" .. id .. ".md"
  os.remove(path)
end

function M.next_status(current)
  for i, s in ipairs(M.statuses) do
    if s == current then
      return M.statuses[(i % #M.statuses) + 1]
    end
  end
  return "todo"
end

function M.dispatch(project_root, id)
  local issue = M.get(project_root, id)
  if not issue then return end

  local chat = require("djinni.nowork.chat")
  local prompt = issue.title
  if issue.body and issue.body ~= "" then
    prompt = prompt .. "\n\n" .. issue.body
  end

  local buf = chat.create(project_root, {
    title  = issue.title,
    prompt = prompt,
  })

  if buf then
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local sid = chat.get_session_id(buf)
      if sid then
        local new_status = (issue.status == "backlog" or issue.status == "todo") and "in_progress" or issue.status
        M.update(project_root, id, { assignee_session = sid, status = new_status })
      end
    end, 2000)
  end

  return buf
end

return M
