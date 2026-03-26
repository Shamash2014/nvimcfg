local M = {}

M._entries = {}
M._max = 100

function M.add(level, msg)
  local ts = os.date("%H:%M:%S")
  local prefix = ({ [1] = "ERR", [2] = "WRN", [3] = "INF", [4] = "DBG" })[level] or "   "
  table.insert(M._entries, ts .. " " .. prefix .. " " .. msg:gsub("\n", " "))
  if #M._entries > M._max then
    table.remove(M._entries, 1)
  end
end

function M.info(msg) M.add(3, msg) end
function M.warn(msg) M.add(2, msg) end
function M.err(msg) M.add(1, msg) end
function M.dbg(msg) M.add(4, msg) end

function M.show()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for i = #M._entries, 1, -1 do
    table.insert(lines, M._entries[i])
  end
  if #lines == 0 then
    lines = { "  (no events)" }
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(100, vim.o.columns - 10)
  local height = math.min(#lines, 30)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Djinni Log ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

return M
