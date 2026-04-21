local M = {}

local function normalize_filename(filename, cwd)
  if not filename or filename == "" then return nil end
  filename = tostring(filename):gsub("^%s+", ""):gsub("%s+$", "")
  filename = filename:gsub("^<", ""):gsub(">$", "")
  filename = filename:gsub("^`", ""):gsub("`$", "")
  if filename == "" then return nil end
  if filename:sub(1, 1) == "/" then return filename end
  if filename:match("^%a:[/\\]") then return filename end
  if cwd and cwd ~= "" then
    return vim.fs.normalize(cwd .. "/" .. filename)
  end
  return filename
end

function M.build_item(opts)
  if not opts or not opts.filename then return nil end
  local text = opts.text or ""
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  local filename = normalize_filename(opts.filename, opts.cwd)
  if not filename then return nil end
  return {
    filename = filename,
    lnum = tonumber(opts.lnum) or 1,
    col = tonumber(opts.col) or 1,
    text = text,
  }
end

function M.set(items, opts)
  opts = opts or {}
  local action = opts.mode == "append" and "a" or " "
  local what = { items = items }
  if opts.title then what.title = opts.title end
  vim.fn.setqflist({}, action, what)
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "NoworkQfChanged" })
  if opts.open then
    vim.cmd("copen")
  end
end

return M
