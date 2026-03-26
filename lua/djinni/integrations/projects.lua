local utils = require("core.utils")

local M = {}

M.known_projects = {}
M.DATA_FILE = vim.fn.stdpath("data") .. "/djinni_projects.json"

function M.load()
  local f = io.open(M.DATA_FILE, "r")
  if not f then
    M.known_projects = { vim.fn.getcwd() }
    return
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    M.known_projects = data
  else
    M.known_projects = { vim.fn.getcwd() }
  end
end

function M.save()
  local f = io.open(M.DATA_FILE, "w")
  if not f then return end
  f:write(vim.json.encode(M.known_projects))
  f:close()
end

function M.add(root)
  root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
  for _, p in ipairs(M.known_projects) do
    if p == root then return end
  end
  table.insert(M.known_projects, root)
  M.save()
end

function M.remove(root)
  for i, p in ipairs(M.known_projects) do
    if p == root then
      table.remove(M.known_projects, i)
      M.save()
      return
    end
  end
end

function M.find_root(path)
  return utils.get_project_root(path)
end

function M.discover()
  if #M.known_projects == 0 then
    M.load()
  end
  local root = M.find_root()
  if root then
    M.add(root)
  end
  return M.known_projects
end

function M.auto_register()
  if #M.known_projects == 0 then
    M.load()
  end
  local root = M.find_root()
  if root then
    M.add(root)
  end
end

function M.get()
  if #M.known_projects == 0 then
    M.load()
  end
  local root = M.find_root()
  if root then
    M.add(root)
  end
  return M.known_projects
end

return M
