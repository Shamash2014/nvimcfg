-- Custom window maximize implementation
-- Replaces swell.nvim plugin

local M = {}

-- Store original window layout
local original_layout = nil

function M.is_maximized()
  return original_layout ~= nil
end

function M.maximize_window()
  if original_layout then
    -- Already maximized, restore
    vim.cmd(original_layout)
    original_layout = nil
  else
    -- Save current layout and maximize
    original_layout = vim.fn.winrestcmd()
    vim.cmd("resize")
    vim.cmd("vertical resize")
  end
end

function M.toggle_window_maximize()
  M.maximize_window()
end

-- Setup keymap
vim.keymap.set("n", "<leader>wm", function()
  M.toggle_window_maximize()
end, { desc = "Toggle window maximize" })

return {}