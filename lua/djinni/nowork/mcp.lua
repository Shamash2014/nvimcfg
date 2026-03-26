local M = {}
local cache = {}

function M.load(project_root)
  if cache[project_root] then return cache[project_root] end
  local f
  for _, name in ipairs({ ".mcp.json", "mcp.json" }) do
    f = io.open(project_root .. "/" .. name, "r")
    if f then break end
  end
  if not f then
    cache[project_root] = {}
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and data and data.mcpServers then
    cache[project_root] = data.mcpServers
  else
    cache[project_root] = {}
  end
  return cache[project_root]
end

function M.resolve(project_root, names)
  local configs = M.load(project_root)
  local result = {}
  for _, name in ipairs(names) do
    if configs[name] then
      result[name] = configs[name]
    end
  end
  return result
end

function M.list(project_root)
  local configs = M.load(project_root)
  local names = {}
  for name in pairs(configs) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function M.clear_cache(project_root)
  if project_root then
    cache[project_root] = nil
  else
    cache = {}
  end
end

return M
