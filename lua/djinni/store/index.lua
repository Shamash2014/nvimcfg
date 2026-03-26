local M = {}

M.DATA_FILE = vim.fn.stdpath("data") .. "/djinni_index.json"
M.index = {}

function M.load()
  local f = io.open(M.DATA_FILE, "r")
  if not f then
    M.index = {}
    return
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    M.index = data
  else
    M.index = {}
  end
end

function M.save()
  local f = io.open(M.DATA_FILE, "w")
  if not f then return end
  f:write(vim.json.encode(M.index))
  f:close()
end

function M.update(file_path, data)
  M.index[file_path] = vim.tbl_extend("force", M.index[file_path] or {}, data)
  M.index[file_path].updated = os.time()
  M.save()
end

function M.remove(file_path)
  M.index[file_path] = nil
  M.save()
end

function M.get_all()
  if vim.tbl_isempty(M.index) then
    M.load()
  end
  return M.index
end

function M.get(file_path)
  return M.index[file_path]
end

return M
