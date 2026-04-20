local M = {}

function M.show(title, entries)
  local lines = { "# " .. (title or "keys"), "" }
  local key_w = 0
  for _, e in ipairs(entries) do key_w = math.max(key_w, #e.key) end
  for _, e in ipairs(entries) do
    lines[#lines + 1] = string.format("  %-" .. key_w .. "s  %s", e.key, e.desc)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  (press ?, q, <Esc> or <CR> to close)"

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.9))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.7))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " help ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "q",     close, opts)
  vim.keymap.set("n", "?",     close, opts)
  vim.keymap.set("n", "<CR>",  close, opts)
end

return M
