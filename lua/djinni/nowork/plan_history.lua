local M = {}

local function plans_dir(droid)
  local cwd = (droid and droid.opts and droid.opts.cwd and vim.fn.isdirectory(droid.opts.cwd) == 1)
    and droid.opts.cwd
    or vim.fn.getcwd()
  return cwd .. "/nowork/plans"
end

local function prompt_hash(droid)
  local raw = (droid and droid.initial_prompt) or "untitled"
  return string.sub(tostring(raw), 1, 32):gsub("[^a-zA-Z0-9]", ""):lower()
end

local function fmt_mtime(sec)
  return os.date("%Y-%m-%d %H:%M", sec)
end

function M.list(droid)
  local dir = plans_dir(droid)
  if vim.fn.isdirectory(dir) ~= 1 then return {} end
  local files = vim.fn.glob(dir .. "/*.md", false, true) or {}
  local hash = prompt_hash(droid)
  local matches, others = {}, {}
  for _, path in ipairs(files) do
    local stat = vim.loop.fs_stat(path)
    local mtime = stat and stat.mtime and stat.mtime.sec or 0
    local name = vim.fn.fnamemodify(path, ":t")
    local entry = { path = path, name = name, mtime = mtime, is_match = false }
    if name:find("-" .. hash, 1, true) then
      entry.is_match = true
      matches[#matches + 1] = entry
    else
      others[#others + 1] = entry
    end
  end
  local result = (#matches > 0) and matches or others
  table.sort(result, function(a, b) return a.mtime > b.mtime end)
  return result
end

function M.preview(path)
  if not path or vim.fn.filereadable(path) ~= 1 then
    vim.notify("nowork: plan file not readable", vim.log.levels.WARN)
    return
  end
  local lines = vim.fn.readfile(path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(120, math.floor(vim.o.columns * 0.9))
  local height = math.min(40, math.floor(vim.o.lines * 0.7))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " plan: " .. vim.fn.fnamemodify(path, ":t") .. " ",
    title_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "?", close, opts)
  vim.keymap.set("n", "<CR>", close, opts)
end

function M.pick(droid)
  local entries = M.list(droid)
  if #entries == 0 then
    vim.notify("nowork: no previous plans for this cwd", vim.log.levels.INFO)
    return
  end
  if #entries == 1 then
    M.preview(entries[1].path)
    return
  end
  local items = {}
  for _, e in ipairs(entries) do
    local marker = e.is_match and "● " or "○ "
    items[#items + 1] = {
      text = marker .. fmt_mtime(e.mtime) .. "  " .. e.name,
      path = e.path,
    }
  end
  Snacks.picker.select(items, {
    prompt = "previous plans",
    format_item = function(item) return item.text end,
  }, function(choice)
    if choice and choice.path then M.preview(choice.path) end
  end)
end

return M
