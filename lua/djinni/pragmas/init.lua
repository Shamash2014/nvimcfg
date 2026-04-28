local M = {}
local scanner = require("djinni.pragmas.scanner")
local features = require("djinni.pragmas.features")
local project = require("djinni.pragmas.project")

local cache = { root = nil, max_mtime = 0, scan_result = nil, time = 0 }

local function get_file_mtime(filepath)
  local ok, stat = pcall(vim.uv.fs_stat, filepath)
  return ok and stat and stat.mtime.sec or 0
end

local function compute_max_mtime(scan_result)
  local max_mtime = 0
  for _, files in pairs(scan_result.features) do
    for _, filepath in ipairs(files.files or {}) do
      max_mtime = math.max(max_mtime, get_file_mtime(filepath))
    end
  end
  for _, entry_list in pairs({
    scan_result.project, scan_result.constraint,
    scan_result.stack, scan_result.convention
  }) do
    for _, entry in ipairs(entry_list or {}) do
      if entry.file then
        max_mtime = math.max(max_mtime, get_file_mtime(entry.file))
      end
    end
  end
  return max_mtime
end

function M.scan(root)
  root = root or vim.fn.getcwd()
  local now = vim.uv.now() / 1000
  if cache.root == root and (now - cache.time) < 5 then
    local max_mtime = compute_max_mtime(cache.scan_result)
    if max_mtime == cache.max_mtime then
      return cache.scan_result
    end
  end
  local result = scanner.scan(root)
  cache.root = root
  cache.scan_result = result
  cache.max_mtime = compute_max_mtime(result)
  cache.time = now
  return result
end

function M.resolve_feature(name)
  local ok, pragmas = pcall(function()
    local root = vim.fn.getcwd()
    local scan = M.scan(root)
    return features.resolve(scan, { name }, {})
  end)
  if not ok or not pragmas then return nil end
  return pragmas ~= "" and pragmas or nil
end

function M.project_context()
  local ok, result = pcall(function()
    local root = vim.fn.getcwd()
    local scan = M.scan(root)
    return project.assemble(scan)
  end)
  if not ok or not result then return "" end
  return result or ""
end

function M.list()
  local ok, scan = pcall(function()
    return M.scan(vim.fn.getcwd())
  end)
  if not ok or not scan then return {} end
  local items = {}
  for name, data in pairs(scan.features or {}) do
    local file_count = data.files and #data.files or 0
    local description = ""
    if data.descriptions and #data.descriptions > 0 then
      description = data.descriptions[1]
      if description then
        description = description:sub(1, 60)
      end
    end
    table.insert(items, {
      name = name,
      file_count = file_count,
      description = description or "",
    })
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

return M
