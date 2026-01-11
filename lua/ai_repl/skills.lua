local M = {}

local SKILL_SEARCH_PATHS = {
  vim.fn.expand("~/.claude/skills"),
  vim.fn.expand("~/.cursor/skills"),
  vim.fn.expand("~/.config/opencode/skill"),
  "./.opencode",
  "./.claude/skills",
}

local TARGET_SKILL_DIR = vim.fn.expand("~/.claude/skills")

local PROVIDER_SKILL_PATHS = {
  claude = { vim.fn.expand("~/.claude/skills") },
  cursor = { vim.fn.expand("~/.cursor/skills"), vim.fn.expand("~/.claude/skills") },
  goose = { vim.fn.expand("~/.claude/skills") },
  opencode = {
    vim.fn.expand("~/.config/opencode/skill"),
    vim.fn.expand("~/.claude/skills"),
    "./.opencode",
  },
}

local function parse_skill_metadata(content)
  local frontmatter = content:match("^%-%-%-\n(.-)%-%-%-")
  if not frontmatter then return nil end

  local metadata = {}
  for line in frontmatter:gmatch("[^\n]+") do
    local key, value = line:match("^(%w+):%s*(.+)$")
    if key and value then
      metadata[key] = value
    end
  end

  return metadata
end

local function read_skill_file(skill_path)
  local file = io.open(skill_path, "r")
  if not file then return nil end

  local content = file:read("*all")
  file:close()

  return content
end

function M.discover_skills()
  local skills = {}
  local seen_skills = {}

  for _, search_path in ipairs(SKILL_SEARCH_PATHS) do
    local expanded_path = search_path:sub(1, 1) == "." and search_path or vim.fn.expand(search_path)

    if vim.fn.isdirectory(expanded_path) == 1 then
      local skill_dirs = vim.fn.glob(expanded_path .. "/*", false, true)

      for _, skill_dir in ipairs(skill_dirs) do
        local skill_file = skill_dir .. "/SKILL.md"
        if vim.fn.filereadable(skill_file) == 1 then
          local content = read_skill_file(skill_file)
          if content then
            local metadata = parse_skill_metadata(content)
            if metadata and metadata.name then
              if not seen_skills[metadata.name] then
                seen_skills[metadata.name] = true

                local references = {}
                local refs_dir = skill_dir .. "/references"
                if vim.fn.isdirectory(refs_dir) == 1 then
                  local ref_files = vim.fn.glob(refs_dir .. "/*.md", false, true)
                  for _, ref_file in ipairs(ref_files) do
                    table.insert(references, {
                      name = vim.fn.fnamemodify(ref_file, ":t:r"),
                      path = ref_file,
                    })
                  end
                end

                local scripts = {}
                local scripts_dir = skill_dir .. "/scripts"
                if vim.fn.isdirectory(scripts_dir) == 1 then
                  local script_files = vim.fn.glob(scripts_dir .. "/*", false, true)
                  for _, script_file in ipairs(script_files) do
                    if vim.fn.isdirectory(script_file) == 0 then
                      table.insert(scripts, {
                        name = vim.fn.fnamemodify(script_file, ":t"),
                        path = script_file,
                      })
                    end
                  end
                end

                skills[metadata.name] = {
                  name = metadata.name,
                  description = metadata.description or "",
                  version = metadata.version or "1.0.0",
                  license = metadata.license or "MIT",
                  path = skill_dir,
                  skill_file = skill_file,
                  content = content,
                  references = references,
                  scripts = scripts,
                  location = search_path,
                }
              end
            end
          end
        end
      end
    end
  end

  return skills
end

function M.get_skill(skill_name)
  local skills = M.discover_skills()
  return skills[skill_name]
end

function M.list_skills()
  local skills = M.discover_skills()
  local list = {}

  for name, skill in pairs(skills) do
    table.insert(list, {
      name = name,
      description = skill.description,
      version = skill.version,
      location = skill.location,
    })
  end

  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

function M.get_skill_context(skill_name)
  local skill = M.get_skill(skill_name)
  if not skill then
    return nil, "Skill not found: " .. skill_name
  end

  local context = {
    skill_name = skill.name,
    description = skill.description,
    main_content = skill.content,
    references = {},
  }

  for _, ref in ipairs(skill.references) do
    local ref_content = read_skill_file(ref.path)
    if ref_content then
      table.insert(context.references, {
        name = ref.name,
        content = ref_content,
      })
    end
  end

  return context
end

function M.format_skill_for_prompt(skill_name, include_references)
  local skill = M.get_skill(skill_name)
  if not skill then
    return nil, "Skill not found: " .. skill_name
  end

  local parts = {
    "# Skill: " .. skill.name,
    "",
    skill.content,
  }

  if include_references and #skill.references > 0 then
    table.insert(parts, "")
    table.insert(parts, "## Available References")
    table.insert(parts, "")

    for _, ref in ipairs(skill.references) do
      local ref_content = read_skill_file(ref.path)
      if ref_content then
        table.insert(parts, "### " .. ref.name)
        table.insert(parts, "")
        table.insert(parts, ref_content)
        table.insert(parts, "")
      end
    end
  end

  return table.concat(parts, "\n")
end

function M.ensure_skill_available(skill_name)
  local skill = M.get_skill(skill_name)
  if not skill then
    return false, "Skill not found: " .. skill_name
  end

  vim.fn.mkdir(TARGET_SKILL_DIR, "p")

  local target_path = TARGET_SKILL_DIR .. "/" .. skill_name
  local source_path = skill.path

  if source_path == target_path then
    return true, "already_available"
  end

  if vim.fn.isdirectory(target_path) == 1 or vim.fn.filereadable(target_path) == 1 then
    local existing_link = vim.fn.resolve(target_path)
    if existing_link == vim.fn.resolve(source_path) then
      return true, "already_linked"
    end
  end

  local result = vim.fn.system({"ln", "-sf", source_path, target_path})
  if vim.v.shell_error ~= 0 then
    result = vim.fn.system({"cp", "-r", source_path, target_path})
    if vim.v.shell_error ~= 0 then
      return false, "Failed to make skill available: " .. result
    end
    return true, "copied"
  end

  return true, "linked"
end

function M.remove_skill_link(skill_name)
  local target_path = TARGET_SKILL_DIR .. "/" .. skill_name

  if vim.fn.isdirectory(target_path) == 0 and vim.fn.filereadable(target_path) == 0 then
    return false, "Skill not found in target location"
  end

  local link_dest = vim.fn.resolve(target_path)
  local is_symlink = link_dest ~= target_path

  if is_symlink then
    vim.fn.delete(target_path)
    return true, "removed_link"
  else
    return false, "not_a_symlink"
  end
end

function M.get_skill_info(skill_name)
  local skill = M.get_skill(skill_name)
  if not skill then
    return nil, "Skill not found: " .. skill_name
  end

  local target_path = TARGET_SKILL_DIR .. "/" .. skill_name
  local is_available = vim.fn.isdirectory(target_path) == 1

  local status = "not_available"
  if is_available then
    local resolved = vim.fn.resolve(target_path)
    if resolved == target_path then
      status = "copied"
    else
      status = "linked"
    end
  end

  return {
    name = skill.name,
    description = skill.description,
    version = skill.version,
    source_path = skill.path,
    target_path = target_path,
    is_available = is_available,
    status = status,
    references_count = #skill.references,
    scripts_count = #skill.scripts,
  }
end

function M.get_provider_skill_paths(provider_id)
  return PROVIDER_SKILL_PATHS[provider_id] or { TARGET_SKILL_DIR }
end

function M.ensure_skill_available_for_provider(skill_name, provider_id)
  local skill = M.get_skill(skill_name)
  if not skill then
    return false, "Skill not found: " .. skill_name
  end

  local provider_paths = M.get_provider_skill_paths(provider_id)
  local target_path = provider_paths[1]

  if target_path:sub(1, 1) == "." then
    target_path = vim.fn.getcwd() .. "/" .. target_path
  else
    target_path = vim.fn.expand(target_path)
  end

  vim.fn.mkdir(target_path, "p")

  local target_skill_path = target_path .. "/" .. skill_name
  local source_path = skill.path

  if source_path == target_skill_path then
    return true, "already_available"
  end

  if vim.fn.isdirectory(target_skill_path) == 1 or vim.fn.filereadable(target_skill_path) == 1 then
    local existing_link = vim.fn.resolve(target_skill_path)
    if existing_link == vim.fn.resolve(source_path) then
      return true, "already_linked"
    end
  end

  local result = vim.fn.system({"ln", "-sf", source_path, target_skill_path})
  if vim.v.shell_error ~= 0 then
    result = vim.fn.system({"cp", "-r", source_path, target_skill_path})
    if vim.v.shell_error ~= 0 then
      return false, "Failed to make skill available: " .. result
    end
    return true, "copied"
  end

  return true, "linked"
end

function M.verify_skill_accessible(skill_name, provider_id)
  local provider_paths = M.get_provider_skill_paths(provider_id)

  for _, path in ipairs(provider_paths) do
    local expanded_path = path:sub(1, 1) == "." and path or vim.fn.expand(path)
    local skill_path = expanded_path .. "/" .. skill_name .. "/SKILL.md"

    if vim.fn.filereadable(skill_path) == 1 then
      return true, path
    end
  end

  return false, "Skill not accessible to " .. provider_id
end

function M.create_skill_selector_ui()
  local skills = M.list_skills()

  if #skills == 0 then
    vim.notify("No skills found in search paths", vim.log.levels.WARN)
    return
  end

  local lines = {}
  for i, skill in ipairs(skills) do
    local desc = skill.description:sub(1, 80)
    if #skill.description > 80 then desc = desc .. "..." end
    table.insert(lines, string.format("%d. %s - %s", i, skill.name, desc))
  end

  vim.ui.select(lines, {
    prompt = "Select a skill to use:",
  }, function(choice, idx)
    if choice and idx then
      return skills[idx].name
    end
  end)
end

return M
