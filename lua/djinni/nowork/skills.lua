local M = {}

local cache = { skills = nil, ts = 0, root = nil }
local TTL = 30

local function parse_frontmatter(content)
  local fm = content:match("^%-%-%-\n(.-)\n%-%-%-")
  if not fm then return {} end
  local result = {}
  for line in fm:gmatch("[^\n]+") do
    local key, val = line:match("^(%w+):%s*(.+)$")
    if key then result[key] = val end
  end
  return result
end

local function scan_dir(dir)
  local skills = {}
  local pattern = dir .. "/*/SKILL.md"
  local paths = vim.fn.glob(pattern, false, true)
  for _, path in ipairs(paths) do
    local content = vim.fn.readfile(path)
    if content and #content > 0 then
      local text = table.concat(content, "\n")
      local fm = parse_frontmatter(text)
      local name = fm.name or vim.fn.fnamemodify(path, ":h:t")
      table.insert(skills, {
        name = name,
        description = fm.description or "",
        path = path,
      })
    end
  end
  return skills
end

function M.discover(project_root)
  local now = os.time()
  if cache.skills and cache.root == project_root and (now - cache.ts) < TTL then
    return cache.skills
  end

  local skills = {}
  local seen = {}

  local src = debug.getinfo(1, "S").source:sub(2)
  local bundled_dir = vim.fn.fnamemodify(src, ":h:h:h:h") .. "/djinni-skills"
  for _, s in ipairs(scan_dir(bundled_dir)) do
    if not seen[s.name] then
      seen[s.name] = true
      table.insert(skills, s)
    end
  end

  local global_dir = vim.fn.expand("~/.claude/skills")
  for _, s in ipairs(scan_dir(global_dir)) do
    if not seen[s.name] then
      seen[s.name] = true
      table.insert(skills, s)
    end
  end

  if project_root then
    local project_dir = project_root .. "/.claude/skills"
    for _, s in ipairs(scan_dir(project_dir)) do
      if not seen[s.name] then
        seen[s.name] = true
        table.insert(skills, s)
      end
    end
  end

  cache.skills = skills
  cache.ts = now
  cache.root = project_root
  return skills
end

function M.get(name, project_root)
  local skills = M.discover(project_root)
  for _, s in ipairs(skills) do
    if s.name == name then
      local content = vim.fn.readfile(s.path)
      if content then return table.concat(content, "\n") end
    end
  end
  return nil
end

function M.list_names(project_root)
  local skills = M.discover(project_root)
  local names = {}
  for _, s in ipairs(skills) do
    table.insert(names, s.name)
  end
  return names
end

return M
