local M = {}

M._tmpdir = nil
M._counter = 0
M._cleanup_registered = false

local function register_cleanup()
  if M._cleanup_registered then return end
  M._cleanup_registered = true
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("NeoworkDiffviewCleanup", { clear = true }),
    callback = function() M.cleanup() end,
  })
end

local function ensure_tmpdir()
  if M._tmpdir and vim.fn.isdirectory(M._tmpdir) == 1 then
    return M._tmpdir
  end
  local dir = vim.fn.tempname() .. "_neowork_diff"
  vim.fn.mkdir(dir, "p")
  M._tmpdir = dir
  register_cleanup()
  return dir
end

local function write_file(path, text)
  local f, err = io.open(path, "w")
  if not f then
    error("neowork.diffview: cannot write " .. path .. ": " .. tostring(err))
  end
  f:write(text or "")
  f:close()
end

local function safe_basename(path)
  local base = vim.fn.fnamemodify(path or "file", ":t")
  base = base:gsub("[^%w%._%-]", "_")
  if base == "" then base = "file" end
  return base
end

local function has_diffview()
  return pcall(require, "diffview")
end

function M.open(tool_id, entry)
  if not entry or not entry.diff_files or #entry.diff_files == 0 then
    return false
  end
  if not has_diffview() then
    vim.notify("diffview.nvim not installed", vim.log.levels.WARN)
    return false
  end

  local file = entry.diff_files[1]
  local dir = ensure_tmpdir()
  M._counter = M._counter + 1
  local stem = string.format("%s_%d_%s", tostring(tool_id or "tool"), M._counter, safe_basename(file.path))
  local old_path = dir .. "/old_" .. stem
  local new_path = dir .. "/new_" .. stem
  write_file(old_path, file.old_text)
  write_file(new_path, file.new_text)

  local ok, err = pcall(vim.cmd, string.format("DiffviewDiffFiles %s %s",
    vim.fn.fnameescape(old_path),
    vim.fn.fnameescape(new_path)))
  if not ok then
    vim.notify("neowork.diffview: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.cleanup()
  if M._tmpdir and vim.fn.isdirectory(M._tmpdir) == 1 then
    vim.fn.delete(M._tmpdir, "rf")
  end
  M._tmpdir = nil
end

return M
