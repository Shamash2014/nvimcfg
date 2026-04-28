local M = {}

local function safe_call(fn)
  local ok, val = pcall(fn)
  if not ok then return "" end
  return val or ""
end

local function passive_current(bufnr)
  local ok_droid, droid = pcall(require, "djinni.nowork.droid")
  if not ok_droid or not droid then return nil end
  if droid.by_buf then return droid.by_buf(bufnr) end
  return nil
end

local function truncate(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  return s:sub(1, n - 1) .. "…"
end

local function title_for(d)
  local s = d.state or {}
  if s.title and s.title ~= "" then return s.title end
  local id = s.current_task_id
  if id and id ~= "" and type(s.tasks) == "table" then
    local entry = s.tasks[id]
    if type(entry) == "table" and entry.desc and entry.desc ~= "" then
      return entry.desc
    end
  end
  local ip = d.initial_prompt
  if ip and ip ~= "" then
    local first = ip:match("[^\r\n]+")
    if first and first ~= "" then return first end
  end
  return d.id or ""
end

local function pick_global_droid()
  local ok_d, droid = pcall(require, "djinni.nowork.droid")
  if not ok_d or not droid or not droid.active then return nil end
  local ok_s, lifecycle = pcall(require, "djinni.nowork.state")
  if not ok_s then return nil end
  local ok_e, events = pcall(require, "djinni.nowork.events")
  if not ok_e then return nil end

  local rank = { waiting = 4, blocked = 3, running = 2, booting = 1, idle = 0 }
  local best, best_score, best_id
  for _, d in pairs(droid.active) do
    if not lifecycle.is_finished(d) then
      local sum = events.summary(d) or { total = 0 }
      local score = (sum.total > 0 and 100 or 0) + (rank[d.status] or 0)
      if not best or score > best_score
         or (score == best_score and tostring(d.id or "") < tostring(best_id or "")) then
        best, best_score, best_id = d, score, d.id
      end
    end
  end
  return best
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
    local d = passive_current(bufnr) or pick_global_droid()
    if not d then return "" end
    local title = title_for(d)
    local st = d.status or ""
    if st ~= "" and st ~= "idle" then
      return truncate(title, 36) .. " · " .. st
    end
    return truncate(title, 40)
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
    "%y %l:%c %P ",
    "%{%v:lua.require'djinni.statusline'.droid()%}",
  })
end

function M.install()
  vim.o.laststatus = 2
  local line = M.line()
  if vim.o.statusline ~= line then
    vim.opt.statusline = line
  end
end

local aug = vim.api.nvim_create_augroup("DjinniStatuslineCache", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
  group = aug,
  callback = function(args)
    local b = args.buf or vim.api.nvim_get_current_buf()
    pcall(function() vim.b[b].djinni_project_name = nil end)
  end,
})

vim.api.nvim_create_autocmd("User", {
  group = aug,
  pattern = { "NoworkChanged", "NoworkSessionRecreated", "NoworkSessionReconnected", "NoworkAcpModeChanged" },
  callback = function()
    pcall(vim.cmd, "redrawstatus!")
  end,
})

return M
