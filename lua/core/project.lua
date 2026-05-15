local M = {}

local did_setup = false

local markers = {
  ".git",
  ".hg",
  "package.json",
  "go.work",
  "go.mod",
  "Cargo.toml",
  "pyproject.toml",
  "pubspec.yaml",
  ".luarc.json",
  ".luarc.jsonc",
  "Makefile",
  "flake.nix",
}

local function normalize(path)
  if path == nil or path == "" then
    return nil
  end

  return vim.fs.normalize(path)
end

local function root_start(path)
  local normalized = normalize(path)
  if not normalized then
    return nil
  end

  local stat = vim.uv.fs_stat(normalized)
  if stat and stat.type == "file" then
    return vim.fs.dirname(normalized)
  end

  return normalized
end

local function startup_target()
  local argv = vim.fn.argv()
  if #argv > 0 and argv[1] ~= "" then
    return argv[1]
  end

  local current = vim.api.nvim_buf_get_name(0)
  if current ~= "" then
    return current
  end

  return vim.fn.getcwd()
end

local function oil_dir(bufnr)
  if vim.bo[bufnr].filetype ~= "oil" then
    return nil
  end

  local ok, oil = pcall(require, "oil")
  if ok and oil.get_current_dir then
    return oil.get_current_dir(bufnr)
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local path = bufname:match("^oil://(.+)$")
  return path
end

function M.root(path)
  local start = root_start(path)
  if not start then
    return nil
  end

  local root = vim.fs.root(start, markers)
  if not root then
    return nil
  end

  return vim.fs.normalize(root)
end

function M.sync(path)
  local root = M.root(path)
  if not root then
    return false
  end

  if vim.fn.getcwd() == root then
    return true
  end

  vim.cmd.tcd(vim.fn.fnameescape(root))
  return true
end

function M.sync_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local path = oil_dir(bufnr)
  if path then
    return M.sync(path)
  end

  if vim.bo[bufnr].buftype ~= "" then
    return false
  end

  return M.sync(vim.api.nvim_buf_get_name(bufnr))
end

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  local group = vim.api.nvim_create_augroup("nvim3_project_root", { clear = true })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      M.sync(startup_target())
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      M.sync_buffer(ev.buf)
    end,
  })
end

return M
