local M = {}

local FRAMES = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local INTERVAL = 100

local _timer = nil
local _idx = 1
local _callback = nil

function M.start(on_frame)
  if _timer then return end
  _callback = on_frame
  _idx = 1
  if _callback then _callback(FRAMES[_idx]) end
  _timer = vim.uv.new_timer()
  _timer:start(
    INTERVAL,
    INTERVAL,
    vim.schedule_wrap(function()
      _idx = (_idx % #FRAMES) + 1
      if _callback then _callback(FRAMES[_idx]) end
    end)
  )
end

function M.stop()
  if _timer then
    _timer:stop()
    _timer:close()
    _timer = nil
  end
  _callback = nil
  _idx = 1
end

return M
