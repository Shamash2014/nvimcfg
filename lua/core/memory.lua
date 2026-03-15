local M = {}

local data_dir = vim.fn.stdpath("data") .. "/project_memory"

local function slugify(path)
  return path:gsub("/", "%%")
end

function M.memory_dir()
  return data_dir
end

function M.global_path()
  vim.fn.mkdir(data_dir, "p")
  return data_dir .. "/global.md"
end

function M.memory_path(project_root)
  if not project_root then
    project_root = vim.fn.getcwd()
  end
  project_root = vim.fn.fnamemodify(project_root, ":p"):gsub("/$", "")
  vim.fn.mkdir(data_dir, "p")
  return data_dir .. "/" .. slugify(project_root) .. ".md"
end

local function ensure_and_open(path, header)
  if vim.fn.filereadable(path) == 0 then
    local f = io.open(path, "w")
    if f then
      f:write("# " .. header .. "\n\n")
      f:close()
    end
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

function M.open(project_root)
  local path = M.memory_path(project_root)
  local name = vim.fn.fnamemodify(project_root or vim.fn.getcwd(), ":t")
  ensure_and_open(path, name .. " — Memory")
end

function M.open_global()
  ensure_and_open(M.global_path(), "Global Memory")
end

function M.exists(project_root)
  return vim.fn.filereadable(M.memory_path(project_root)) == 1
end

function M.global_exists()
  return vim.fn.filereadable(M.global_path()) == 1
end

local function count_lines(path)
  if vim.fn.filereadable(path) == 0 then
    return 0
  end
  local n = 0
  for _ in io.lines(path) do
    n = n + 1
  end
  return n
end

function M.line_count(project_root)
  return count_lines(M.memory_path(project_root))
end

function M.global_line_count()
  return count_lines(M.global_path())
end

return M
