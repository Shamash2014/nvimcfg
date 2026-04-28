local M = {}
local patterns = require("djinni.pragmas.patterns")
local ripgrep_fallback_notified = false

local function should_ignore(path, ignore_list)
  for _, pattern in ipairs(ignore_list or {}) do
    if path:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

local function scan_file(filepath)
  local f = io.open(filepath, "r")
  if not f then
    return { features = {}, project = {}, constraint = {}, stack = {}, convention = {} }
  end
  local content = f:read("*a")
  f:close()
  local lines = vim.split(content, "\n", { plain = true })

  local features = {}
  local project = {}
  local constraint = {}
  local stack = {}
  local convention = {}

  for i, line in ipairs(lines) do
    local fname = line:match(patterns.FEATURE_PATTERN)
    if fname then
      if not features[fname] then
        features[fname] = { files = {}, descriptions = {} }
      end
      table.insert(features[fname].files, filepath)
      table.insert(features[fname].descriptions, patterns.extract_description(lines, i))
    end

    if line:match(patterns.PROJECT_PATTERN) then
      table.insert(project, { file = filepath, line = i, desc = patterns.extract_description(lines, i) })
    end
    if line:match(patterns.CONSTRAINT_PATTERN) then
      table.insert(constraint, { file = filepath, line = i, desc = patterns.extract_description(lines, i) })
    end
    if line:match(patterns.STACK_PATTERN) then
      table.insert(stack, { file = filepath, line = i, desc = patterns.extract_description(lines, i) })
    end
    if line:match(patterns.CONVENTION_PATTERN) then
      table.insert(convention, { file = filepath, line = i, desc = patterns.extract_description(lines, i) })
    end
  end

  return {
    features = features,
    project = project,
    constraint = constraint,
    stack = stack,
    convention = convention,
  }
end

local function walk_dir(root, ignore_list)
  local matches = {}
  local function traverse(dir)
    local ok, entries = pcall(vim.fs.dir, dir)
    if not ok then
      return
    end
    for name, type in entries do
      local path = dir .. "/" .. name
      if should_ignore(path, ignore_list) then
        goto continue
      end
      if type == "file" then
        table.insert(matches, path)
      elseif type == "directory" then
        traverse(path)
      end
      ::continue::
    end
  end
  traverse(root)
  return matches
end

function M.scan(root, opts)
  opts = opts or {}
  local ignore = opts.ignore or { "node_modules", ".git", ".chat", "dist", "build" }

  local files = {}

  local ok, result = pcall(function()
    return vim.system({"rg", "--files-with-matches", "@(feature|project|constraint|stack|convention)", root, "--no-ignore-vcs"}, { text = true }):wait()
  end)

  if ok and result and result.code == 0 and result.stdout then
    files = vim.split(result.stdout, "\n", { trimempty = true })
  else
    if not ripgrep_fallback_notified then
      vim.notify("[djinni.pragmas] ripgrep unavailable, falling back to manual walk", vim.log.levels.INFO)
      ripgrep_fallback_notified = true
    end
    files = walk_dir(root, ignore)
  end

  local result_features = {}
  local result_project = {}
  local result_constraint = {}
  local result_stack = {}
  local result_convention = {}

  for _, file in ipairs(files) do
    if not should_ignore(file, ignore) then
      local scan_result = scan_file(file)
      for fname, data in pairs(scan_result.features) do
        if not result_features[fname] then
          result_features[fname] = { files = {}, descriptions = {} }
        end
        vim.list_extend(result_features[fname].files, data.files)
        vim.list_extend(result_features[fname].descriptions, data.descriptions)
      end
      vim.list_extend(result_project, scan_result.project)
      vim.list_extend(result_constraint, scan_result.constraint)
      vim.list_extend(result_stack, scan_result.stack)
      vim.list_extend(result_convention, scan_result.convention)
    end
  end

  return {
    features = result_features,
    project = result_project,
    constraint = result_constraint,
    stack = result_stack,
    convention = result_convention,
  }
end

return M
