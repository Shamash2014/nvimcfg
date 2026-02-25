local M = {}

local IMAGE_EXTENSIONS = {
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  webp = "image/webp",
  svg = "image/svg+xml",
}

local function get_mime_type(file_path)
  local ext = file_path:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    if IMAGE_EXTENSIONS[ext] then
      return IMAGE_EXTENSIONS[ext], true
    end
  end
  return "text/plain", false
end

local function read_file_content(file_path, is_image)
  if is_image then
    local f = io.open(file_path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local ok, encoded = pcall(function()
      return vim.base64.encode(data)
    end)
    if ok then return encoded end
    return nil
  else
    local lines = vim.fn.readfile(file_path)
    return table.concat(lines, "\n")
  end
end

local function build_resource_block(file_path)
  local mime_type, is_image = get_mime_type(file_path)
  local content = read_file_content(file_path, is_image)
  if not content then return nil end

  local resource = {
    uri = "file://" .. file_path,
    name = vim.fn.fnamemodify(file_path, ":t"),
    mimeType = mime_type,
  }
  if is_image then
    resource.blob = content
  else
    resource.text = content
  end
  return { type = "resource", resource = resource }
end

-- Project file cache
local file_cache = {}
local file_cache_root = nil
local file_cache_time = 0
local CACHE_TTL = 30

function M.get_project_files(project_root)
  local now = os.time()
  if file_cache_root == project_root and (now - file_cache_time) < CACHE_TTL then
    return file_cache
  end

  local files = vim.fn.systemlist("git -C " .. vim.fn.shellescape(project_root) .. " ls-files 2>/dev/null")
  if vim.v.shell_error ~= 0 or #files == 0 then
    files = vim.fn.globpath(project_root, "**/*", false, true)
    for i, f in ipairs(files) do
      files[i] = f:sub(#project_root + 2)
    end
  end

  file_cache = files
  file_cache_root = project_root
  file_cache_time = now
  return files
end

function M.invalidate_cache()
  file_cache = {}
  file_cache_root = nil
  file_cache_time = 0
end

function M.fuzzy_match(query, project_root)
  local files = M.get_project_files(project_root)
  local query_lower = query:lower()

  -- Phase 1: exact basename match
  for _, f in ipairs(files) do
    local basename = f:match("[^/]+$")
    if basename and basename:lower() == query_lower then
      return f
    end
  end

  -- Phase 2: path suffix match
  for _, f in ipairs(files) do
    if f:lower():sub(-#query_lower) == query_lower then
      return f
    end
  end

  -- Phase 3: substring match
  local candidates = {}
  for _, f in ipairs(files) do
    if f:lower():find(query_lower, 1, true) then
      table.insert(candidates, f)
    end
  end
  if #candidates == 1 then
    return candidates[1]
  end

  -- Phase 4: fuzzy char-sequence match (shortest wins)
  if #candidates == 0 then
    for _, f in ipairs(files) do
      local fi = 1
      local fl = f:lower()
      for ci = 1, #query_lower do
        local ch = query_lower:sub(ci, ci)
        local found = fl:find(ch, fi, true)
        if not found then break end
        fi = found + 1
        if ci == #query_lower then
          table.insert(candidates, f)
        end
      end
    end
  end

  if #candidates > 0 then
    table.sort(candidates, function(a, b) return #a < #b end)
    return candidates[1]
  end

  return nil
end

function M.resolve_references(text, project_root, source_file)
  local blocks = {}
  local remaining = text
  local seen = {}

  -- Handle @{file}
  if source_file and remaining:find("@{file}", 1, true) then
    local abs_path = vim.fn.fnamemodify(source_file, ":p")
    if vim.fn.filereadable(abs_path) == 1 and not seen[abs_path] then
      seen[abs_path] = true
      local block = build_resource_block(abs_path)
      if block then
        table.insert(blocks, block)
      end
    end
    remaining = remaining:gsub("@{file}", "", 1)
  end

  -- Handle @token references
  for ref in text:gmatch("@([^%s{}]+)") do
    local abs_path = nil

    -- Skip if looks like a role marker (@You:, @Djinni:, etc.)
    if ref:match("^%u%w*:$") then
      goto continue
    end

    -- Try 1: exact path relative to project root
    local candidate = project_root .. "/" .. ref
    if vim.fn.filereadable(candidate) == 1 then
      abs_path = vim.fn.fnamemodify(candidate, ":p")
    end

    -- Try 2: absolute path
    if not abs_path and ref:sub(1, 1) == "/" and vim.fn.filereadable(ref) == 1 then
      abs_path = ref
    end

    -- Try 3: fnamemodify (cwd-relative)
    if not abs_path then
      local expanded = vim.fn.fnamemodify(ref, ":p")
      if vim.fn.filereadable(expanded) == 1 then
        abs_path = expanded
      end
    end

    -- Try 4: fuzzy match
    if not abs_path and project_root then
      local match = M.fuzzy_match(ref, project_root)
      if match then
        abs_path = project_root .. "/" .. match
      end
    end

    if abs_path and not seen[abs_path] then
      seen[abs_path] = true
      local block = build_resource_block(abs_path)
      if block then
        table.insert(blocks, block)
      end
      remaining = remaining:gsub("@" .. vim.pesc(ref), "", 1)
    end

    ::continue::
  end

  remaining = remaining:gsub("^%s*(.-)%s*$", "%1")
  return blocks, remaining, vim.tbl_count(seen)
end

function M.get_completion_candidates(prefix, project_root, limit)
  limit = limit or 50
  local files = M.get_project_files(project_root)
  local prefix_lower = (prefix or ""):lower()
  local results = {}

  for _, f in ipairs(files) do
    if #results >= limit then break end
    if prefix_lower == "" then
      table.insert(results, f)
    else
      local fl = f:lower()
      local basename = fl:match("[^/]+$") or fl
      if basename:sub(1, #prefix_lower) == prefix_lower or fl:find(prefix_lower, 1, true) then
        table.insert(results, f)
      end
    end
  end

  return results
end

return M
