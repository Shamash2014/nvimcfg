local M = {}

local function skills_root()
  return vim.fn.stdpath("config") .. "/djinni-skills"
end

local function strip_quotes(s)
  if not s then return s end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s:sub(1, 1) == '"' and s:sub(-1) == '"' then
    s = s:sub(2, -2)
  elseif s:sub(1, 1) == "'" and s:sub(-1) == "'" then
    s = s:sub(2, -2)
  end
  return s
end

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then return nil end
  local data = fd:read("*a")
  fd:close()
  return data
end

local function parse_skill(path)
  local data = read_file(path)
  if not data or data == "" then return nil end

  local name, description
  local in_fm = false
  local fm_seen = false
  local in_summary = false

  for line in data:gmatch("([^\n]*)\n?") do
    if line == "---" then
      if not fm_seen then
        in_fm = true
        fm_seen = true
      elseif in_fm then
        in_fm = false
      end
    elseif in_fm then
      local key, val = line:match("^(%w[%w_-]*)%s*:%s*(.*)$")
      if key == "name" then
        name = strip_quotes(val)
      elseif key == "description" then
        description = strip_quotes(val)
      end
    elseif not description then
      if line:match("^##%s+Summary%s*$") then
        in_summary = true
      elseif in_summary then
        if line:match("^##") then
          in_summary = false
        elseif line:match("%S") then
          description = strip_quotes(line)
          in_summary = false
        end
      end
    end
  end

  if not name then return nil end
  return {
    name = name,
    description = description or "",
    path = path,
  }
end

function M.load(_project_root)
  local root = skills_root()
  local ok, entries = pcall(vim.fn.readdir, root)
  if not ok or type(entries) ~= "table" then return {} end

  local skills = {}
  for _, entry in ipairs(entries) do
    local skill_path = root .. "/" .. entry .. "/SKILL.md"
    if vim.fn.filereadable(skill_path) == 1 then
      local parsed = parse_skill(skill_path)
      if parsed then
        skills[#skills + 1] = parsed
      end
    end
  end

  table.sort(skills, function(a, b) return a.name < b.name end)
  return skills
end

function M.build_prompt_block(project_root)
  local ok, skills = pcall(M.load, project_root)
  if not ok or type(skills) ~= "table" or #skills == 0 then
    return nil
  end

  local lines = {
    "The following Djinni custom skills are available in this environment. Each skill is a Markdown file you can Read when the user's request matches its purpose. Do not load them unless relevant.",
    "",
  }
  for _, s in ipairs(skills) do
    local desc = s.description ~= "" and (" — " .. s.description) or ""
    lines[#lines + 1] = string.format("- %s%s — %s", s.name, desc, s.path)
  end

  return { type = "text", text = table.concat(lines, "\n") }
end

return M
