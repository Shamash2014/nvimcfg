local M = {}

M.data = {
  sdk_path = nil,
  tools = {},
  gradlew = nil,
  project_root = nil,
  is_android_project = false,
  selected_device = nil,
  selected_module = nil,
  selected_variant = nil,
  application_id = nil,
  modules = {},
  variants = {},
  gradle_tasks_cache = nil,
  gradle_tasks_cache_time = 0,
  last_apk_path = nil,
  last_build_cmd = nil,
}

function M.get(key)
  return M.data[key]
end

function M.set(key, value)
  M.data[key] = value
end

local function state_file()
  local root = M.data.project_root or vim.fn.getcwd()
  local hash = vim.fn.sha256(root):sub(1, 12)
  return vim.fn.stdpath("data") .. "/android_state_" .. hash .. ".json"
end

function M.save()
  local persist = {
    selected_device = M.data.selected_device,
    selected_module = M.data.selected_module,
    selected_variant = M.data.selected_variant,
    last_apk_path = M.data.last_apk_path,
    last_build_cmd = M.data.last_build_cmd,
  }
  local ok, json = pcall(vim.json.encode, persist)
  if ok then
    vim.fn.writefile({ json }, state_file())
  end
end

function M.load()
  local path = state_file()
  if vim.fn.filereadable(path) == 0 then
    return
  end
  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return
  end
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if ok and data then
    for k, v in pairs(data) do
      if M.data[k] ~= nil then
        M.data[k] = v
      end
    end
  end
end

function M.reset()
  M.data = {
    sdk_path = nil,
    tools = {},
    gradlew = nil,
    project_root = nil,
    is_android_project = false,
    selected_device = nil,
    selected_module = nil,
    selected_variant = nil,
    application_id = nil,
    modules = {},
    variants = {},
    gradle_tasks_cache = nil,
    gradle_tasks_cache_time = 0,
    last_apk_path = nil,
    last_build_cmd = nil,
  }
end

return M
