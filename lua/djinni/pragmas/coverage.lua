local M = {}
local pragmas = require("djinni.pragmas")

local DEFAULT_IGNORE = { "node_modules", ".git", ".chat", "dist", "build" }

local function should_ignore(path, ignore_list)
  for _, pattern in ipairs(ignore_list or {}) do
    if path:find(pattern, 1, true) then return true end
  end
  return false
end

local function list_all_files(root, ignore_list)
  local files = {}
  local ok, result = pcall(function()
    return vim.system({ "rg", "--files", root, "--no-ignore-vcs" }, { text = true }):wait()
  end)
  if ok and result and result.code == 0 and result.stdout and result.stdout ~= "" then
    for _, line in ipairs(vim.split(result.stdout, "\n", { trimempty = true })) do
      if not should_ignore(line, ignore_list) then
        table.insert(files, line)
      end
    end
    return files
  end
  local function walk(dir)
    local ok2, entries = pcall(vim.fs.dir, dir)
    if not ok2 then return end
    for name, type in entries do
      local path = dir .. "/" .. name
      if not should_ignore(path, ignore_list) then
        if type == "file" then
          table.insert(files, path)
        elseif type == "directory" then
          walk(path)
        end
      end
    end
  end
  walk(root)
  return files
end

local function collect_tagged(scan)
  local tagged = {}
  for fname, data in pairs(scan.features or {}) do
    for _, fp in ipairs(data.files or {}) do
      tagged[fp] = tagged[fp] or { features = {} }
      tagged[fp].features[fname] = true
    end
  end
  for _, key in ipairs({ "project", "constraint", "stack", "convention" }) do
    for _, entry in ipairs(scan[key] or {}) do
      if entry.file then
        tagged[entry.file] = tagged[entry.file] or { features = {} }
        tagged[entry.file][key] = true
      end
    end
  end
  return tagged
end

function M.report(root)
  root = root or vim.fn.getcwd()
  local scan = pragmas.scan(root)
  local tagged = collect_tagged(scan)
  local all = list_all_files(root, DEFAULT_IGNORE)
  local untagged = {}
  for _, path in ipairs(all) do
    if not tagged[path] then
      table.insert(untagged, path)
    end
  end
  table.sort(untagged)
  local tagged_count = vim.tbl_count(tagged)
  local total = tagged_count + #untagged
  local ratio = total > 0 and (tagged_count / total) or 0
  return {
    tagged = tagged,
    untagged = untagged,
    tagged_count = tagged_count,
    untagged_count = #untagged,
    total = total,
    ratio = ratio,
  }
end

local function feature_list(meta)
  local names = {}
  for name in pairs(meta.features or {}) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.format(report, root)
  root = root or vim.fn.getcwd()
  local lines = {}
  table.insert(lines, string.format("# Pragma coverage — %s", root))
  table.insert(lines, string.format("# %d tagged / %d untagged / %d total (%.1f%%)",
    report.tagged_count, report.untagged_count, report.total, report.ratio * 100))
  table.insert(lines, "")
  table.insert(lines, "## Tagged")
  local tagged_paths = {}
  for path in pairs(report.tagged) do table.insert(tagged_paths, path) end
  table.sort(tagged_paths)
  for _, path in ipairs(tagged_paths) do
    local meta = report.tagged[path]
    local rel = path
    if rel:sub(1, #root + 1) == root .. "/" then rel = rel:sub(#root + 2) end
    local tags = feature_list(meta)
    local extras = {}
    for _, key in ipairs({ "project", "constraint", "stack", "convention" }) do
      if meta[key] then table.insert(extras, "@" .. key) end
    end
    local tag_str = #tags > 0 and ("@feature:" .. table.concat(tags, ",@feature:")) or ""
    if #extras > 0 then
      tag_str = tag_str ~= "" and (tag_str .. " " .. table.concat(extras, " ")) or table.concat(extras, " ")
    end
    table.insert(lines, string.format("  %s  %s", rel, tag_str))
  end
  table.insert(lines, "")
  table.insert(lines, "## Untagged")
  for _, path in ipairs(report.untagged) do
    local rel = path
    if rel:sub(1, #root + 1) == root .. "/" then rel = rel:sub(#root + 2) end
    table.insert(lines, "  " .. rel)
  end
  return table.concat(lines, "\n")
end

return M
