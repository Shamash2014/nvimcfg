local M = {}
local ui = require("djinni.integrations.snacks_ui")

M._entries = {}
M._max = 100

function M.add(level, msg)
  local ts = os.date("%H:%M:%S")
  local prefix = ({ [1] = "ERR", [2] = "WRN", [3] = "INF", [4] = "DBG" })[level] or "   "
  table.insert(M._entries, ts .. " " .. prefix .. " " .. tostring(msg):gsub("\n", " "))
  if #M._entries > M._max then
    table.remove(M._entries, 1)
  end
end

function M.info(msg) M.add(3, msg) end
function M.warn(msg) M.add(2, msg) end
function M.err(msg) M.add(1, msg) end
function M.dbg(msg) M.add(4, msg) end

function M.show()
  local lines = {}
  for i = #M._entries, 1, -1 do
    lines[#lines + 1] = M._entries[i]
  end
  if #lines == 0 then
    lines = { "  (no events)" }
  end
  local width = math.min(100, vim.o.columns - 10)
  local height = math.min(#lines, 30)
  ui.popup(lines, {
    title = " Djinni Log ",
    width = width,
    height = height,
    on_buf = function(win)
      vim.api.nvim_create_autocmd("BufLeave", {
        buffer = win.buf,
        once = true,
        callback = function()
          win:close()
        end,
      })
    end,
  })
end

return M
