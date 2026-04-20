local M = {}

local function open_window(buf, title, footer)
  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local height = math.min(20, math.floor(vim.o.lines * 0.5))
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title or " nowork ",
    title_pos = "center",
    footer = footer or " <C-s> submit · <C-c> cancel ",
    footer_pos = "left",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].cursorline = false
  return win
end

function M.open(opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  if opts.filetype then vim.bo[buf].filetype = opts.filetype end

  local win = open_window(buf, opts.title, opts.footer)

  local lines = opts.content and vim.split(opts.content, "\n", { plain = true }) or { "" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  if opts.readonly then
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
  end

  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(all, "\n")
    if not opts.on_submit then close() return end
    local ok, err = opts.on_submit(text)
    if ok then
      close()
    else
      vim.notify("nowork: " .. (err or "invalid, try again"), vim.log.levels.WARN)
    end
  end

  local function cancel()
    close()
    if opts.on_cancel then opts.on_cancel() end
  end

  local km = { buffer = buf, nowait = true }
  vim.keymap.set({ "n", "i" }, "<C-s>", submit, km)
  vim.keymap.set({ "n", "i" }, "<C-c>", cancel, km)
  vim.keymap.set("n", "q", cancel, km)
  vim.keymap.set("n", "<Esc>", cancel, km)

  if opts.extra_keys then
    for key, fn in pairs(opts.extra_keys) do
      vim.keymap.set({ "n", "i" }, key, function() fn(close) end, km)
    end
  end

  local help_entries = { { key = "<C-s>", desc = "submit" }, { key = "<C-c>", desc = "cancel" }, { key = "q / <Esc>", desc = "cancel" } }
  if opts.help then
    for _, e in ipairs(opts.help) do help_entries[#help_entries + 1] = e end
  elseif opts.extra_keys then
    for key, _ in pairs(opts.extra_keys) do
      help_entries[#help_entries + 1] = { key = key, desc = "custom action" }
    end
  end
  help_entries[#help_entries + 1] = { key = "?", desc = "this help" }
  vim.keymap.set("n", "?", function()
    require("djinni.nowork.help").show(opts.title or "nowork", help_entries)
  end, km)

  return { buf = buf, win = win, close = close }
end

return M
