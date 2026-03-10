local M = {}

local parser = require("task_manager.parser")
local serializer = require("task_manager.serializer")

local TASKS_DIR = vim.fn.stdpath("data") .. "/tasks"

function M.ensure_dir()
  if vim.fn.isdirectory(TASKS_DIR) == 0 then
    vim.fn.mkdir(TASKS_DIR, "p")
  end
end

function M.board_path(name)
  return TASKS_DIR .. "/" .. name .. ".md"
end

function M.load(name)
  name = name or "default"
  M.ensure_dir()
  local path = M.board_path(name)

  local f = io.open(path, "r")
  if not f then
    local board = parser.parse("")
    board.title = name:sub(1, 1):upper() .. name:sub(2) .. " Board"
    return board, name
  end

  local content = f:read("*a")
  f:close()
  return parser.parse(content), name
end

function M.save(name, board)
  name = name or "default"
  M.ensure_dir()
  local path = M.board_path(name)
  local content = serializer.serialize(board)

  local f = io.open(path, "w")
  if not f then
    vim.notify("TaskManager: failed to write " .. path, vim.log.levels.ERROR)
    return
  end
  f:write(content)
  f:close()
end

function M.list()
  M.ensure_dir()
  local boards = {}
  local handle = vim.loop.fs_scandir(TASKS_DIR)
  if handle then
    while true do
      local entry, typ = vim.loop.fs_scandir_next(handle)
      if not entry then break end
      if typ == "file" and entry:match("%.md$") then
        table.insert(boards, entry:gsub("%.md$", ""))
      end
    end
  end
  table.sort(boards)
  return boards
end

function M.delete(name)
  local path = M.board_path(name)
  os.remove(path)
end

return M
