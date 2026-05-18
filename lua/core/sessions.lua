local M = {}

local function dir()
  return vim.fn.stdpath("state") .. "/sessions"
end

local function ensure_dir()
  vim.fn.mkdir(dir(), "p")
end

local function encode_cwd(cwd)
  return (cwd:gsub("[/:]", "%%")) .. ".vim"
end

local function decode_name(name)
  local stripped = name:gsub("%.vim$", "")
  return (stripped:gsub("%%", "/"))
end

function M.save_path()
  return dir() .. "/" .. encode_cwd(vim.fn.getcwd())
end

local SESSION_OPTS = "buffers,curdir,folds,winsize"

function M.save()
  ensure_dir()
  local saved = vim.o.sessionoptions
  vim.o.sessionoptions = SESSION_OPTS
  pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(M.save_path()))
  vim.o.sessionoptions = saved
end

function M.list()
  local out = {}
  local d = dir()
  if vim.fn.isdirectory(d) == 0 then
    return out
  end
  for _, name in ipairs(vim.fn.readdir(d)) do
    if name:match("%.vim$") then
      local path = d .. "/" .. name
      local stat = vim.uv.fs_stat(path)
      table.insert(out, {
        name = name,
        path = path,
        cwd = decode_name(name),
        mtime = stat and stat.mtime.sec or 0,
      })
    end
  end
  table.sort(out, function(a, b)
    return a.mtime > b.mtime
  end)
  return out
end

local function pick(items, opts, on_choice)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.picker and snacks.picker.select then
    snacks.picker.select(items, opts or {}, on_choice)
    return
  end
  vim.ui.select(items, opts or {}, on_choice)
end

local function source_in_tab(path)
  vim.cmd("tabnew")
  vim.cmd("source " .. vim.fn.fnameescape(path))
end

function M.load()
  local items = M.list()
  if #items == 0 then
    vim.notify("No sessions saved", vim.log.levels.INFO)
    return
  end
  pick(items, {
    prompt = "Sessions",
    format_item = function(item)
      return item.cwd
    end,
  }, function(item)
    if not item then
      return
    end
    source_in_tab(item.path)
  end)
end

function M.reload()
  local path = M.save_path()
  if not vim.uv.fs_stat(path) then
    vim.notify("No session for " .. vim.fn.getcwd(), vim.log.levels.INFO)
    return
  end
  source_in_tab(path)
end

local function has_real_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      if vim.api.nvim_buf_get_name(buf) ~= "" then
        return true
      end
    end
  end
  return false
end

function M.setup()
  local group = vim.api.nvim_create_augroup("nvim3_sessions", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if has_real_buffer() then
        pcall(M.save)
      end
    end,
  })
end

return M
