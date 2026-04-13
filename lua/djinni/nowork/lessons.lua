local M = {}

local cache = { lessons = nil, ts = 0, root = nil }
local TTL = 5

local function lessons_path(project_root)
  return project_root .. "/.djinni/lessons.json"
end

function M.load(project_root)
  if not project_root then return {} end
  local now = os.time()
  if cache.lessons and cache.root == project_root and (now - cache.ts) < TTL then
    return cache.lessons
  end
  local path = lessons_path(project_root)
  local ok, content = pcall(vim.fn.readfile, path)
  if not ok or not content or #content == 0 then
    cache.lessons = {}
    cache.ts = now
    cache.root = project_root
    return {}
  end
  local json_str = table.concat(content, "\n")
  local decoded = vim.json.decode(json_str)
  if type(decoded) ~= "table" then decoded = {} end
  cache.lessons = decoded
  cache.ts = now
  cache.root = project_root
  return decoded
end

function M.save(project_root, lessons)
  if not project_root then return end
  local dir = project_root .. "/.djinni"
  vim.fn.mkdir(dir, "p")
  local json_str = vim.json.encode(lessons)
  vim.fn.writefile({ json_str }, lessons_path(project_root))
  cache.lessons = lessons
  cache.ts = os.time()
  cache.root = project_root
end

function M.add(project_root, text, source)
  local lessons = M.load(project_root)
  local lesson = {
    id = vim.fn.sha256(text .. os.time()):sub(1, 8),
    text = text,
    created = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    source = source or "",
  }
  table.insert(lessons, lesson)
  M.save(project_root, lessons)
  return lesson
end

function M.remove(project_root, id)
  local lessons = M.load(project_root)
  for i, l in ipairs(lessons) do
    if l.id == id then
      table.remove(lessons, i)
      M.save(project_root, lessons)
      return true
    end
  end
  return false
end

function M.list(project_root)
  return M.load(project_root)
end

function M.clear(project_root)
  M.save(project_root, {})
end

function M.has_any(project_root)
  local lessons = M.load(project_root)
  return #lessons > 0
end

function M.format_for_injection(project_root)
  local lessons = M.load(project_root)
  if #lessons == 0 then return nil end
  local lines = { "<lessons>" }
  for _, l in ipairs(lessons) do
    lines[#lines + 1] = "- " .. l.text
  end
  lines[#lines + 1] = "</lessons>"
  return table.concat(lines, "\n") .. "\n\n"
end

function M.extract_from_text(text)
  local extracted = {}
  local cleaned = text:gsub("<lesson>(.-)</lesson>", function(content)
    local trimmed = content:match("^%s*(.-)%s*$")
    if trimmed and trimmed ~= "" then
      extracted[#extracted + 1] = trimmed
    end
    return ""
  end)
  return extracted, cleaned
end

return M
