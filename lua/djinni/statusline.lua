local M = {}

local function safe_call(fn)
  local ok, val = pcall(fn)
  if not ok then return "" end
  return val or ""
end

local function passive_current(bufnr)
  local ok_droid, droid = pcall(require, "djinni.nowork.droid")
  if not ok_droid or not droid then return nil end
  local by_buf = droid.by_buf and droid.by_buf(bufnr)
  if by_buf then return by_buf end
  local ok_state, lifecycle = pcall(require, "djinni.nowork.state")
  if not ok_state then return nil end
  local active = {}
  for _, x in pairs(droid.active or {}) do
    if not lifecycle.is_finished(x) then active[#active + 1] = x end
  end
  if #active == 1 then return active[1] end
  return nil
end

local function truncate(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  return s:sub(1, n - 1) .. "…"
end

function M.project()
  return safe_call(function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cached = vim.b[bufnr].djinni_project_name
    if cached and cached ~= "" then return cached end
    local ok, utils = pcall(require, "core.utils")
    local root
    if ok and utils and utils.get_project_root then
      root = utils.get_project_root()
    end
    root = root or vim.fn.getcwd()
    local name = vim.fn.fnamemodify(root, ":t")
    vim.b[bufnr].djinni_project_name = name
    return name
  end)
end

function M.task()
  return safe_call(function()
    local bufnr = vim.api.nvim_get_current_buf()
    local d = passive_current(bufnr)
    if not d or not d.state then return "" end
    local id = d.state.current_task_id
    local title = d.state.title
    if (not id or id == "") then
      if title and title ~= "" then return truncate(title, 40) end
      return ""
    end
    if title and title ~= "" then
      return "T:" .. id .. " " .. truncate(title, 30)
    end
    local tasks = d.state.tasks
    if type(tasks) == "table" then
      local entry = tasks[id]
      if type(entry) == "table" and entry.desc then
        return "T:" .. id .. " " .. truncate(entry.desc, 30)
      end
    end
    return "T:" .. id
  end)
end

function M.droid()
  return safe_call(function()
    local ok, mod = pcall(require, "djinni.nowork.statusline")
    if not ok or not mod or not mod.component then return "" end
    return mod.component()
  end)
end

function M.line()
  return table.concat({
    " %f %h%m%r %=",
    "[%{v:lua.require'djinni.statusline'.project()}] ",
    "%{v:lua.require'djinni.statusline'.task()} ",
    "%{v:lua.require'djinni.statusline'.droid()} ",
    "%y %l:%c %P ",
  })
end

local aug = vim.api.nvim_create_augroup("DjinniStatuslineCache", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
  group = aug,
  callback = function(args)
    local b = args.buf or vim.api.nvim_get_current_buf()
    pcall(function() vim.b[b].djinni_project_name = nil end)
  end,
})

return M
