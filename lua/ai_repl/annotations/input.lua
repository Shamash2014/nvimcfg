local M = {}

function M.show(config, default_mode, selection, callback)
  local mode = default_mode
  local input_conf = config.input

  local function mode_label()
    return " annotate [" .. mode .. "] "
  end

  local input_buf = vim.api.nvim_create_buf(false, true)

  local lines = { mode_label(), "", " > " }
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, lines)

  local width = input_conf.width
  local height = 3

  local row = selection.end_line - selection.start_line + 2
  local col = 0

  local win_opts = {
    relative = "cursor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = input_conf.border,
  }

  local win = vim.api.nvim_open_win(input_buf, true, win_opts)

  vim.api.nvim_set_option_value("winhighlight", "Normal:Normal,FloatBorder:FloatBorder", { win = win })

  local function update_mode_label()
    local new_lines = { mode_label(), "", " > " .. vim.api.nvim_buf_get_lines(input_buf, 2, 3, false)[1]:sub(3) }
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, new_lines)
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(input_buf) then
      vim.api.nvim_buf_delete(input_buf, { force = true })
    end
  end

  vim.api.nvim_buf_set_keymap(input_buf, "i", "<Tab>", "", {
    callback = function()
      mode = mode == "location" and "snippet" or "location"
      update_mode_label()
    end,
    noremap = true,
  })

  vim.api.nvim_buf_set_keymap(input_buf, "i", "<CR>", "", {
    callback = function()
      local text = vim.api.nvim_buf_get_lines(input_buf, 2, 3, false)[1]:sub(3)
      close()
      callback(text, mode)
    end,
    noremap = true,
  })

  vim.api.nvim_buf_set_keymap(input_buf, "i", "<Esc>", "", {
    callback = function()
      close()
      callback(nil, mode)
    end,
    noremap = true,
  })

  vim.api.nvim_buf_set_keymap(input_buf, "n", "<Esc>", "", {
    callback = function()
      close()
      callback(nil, mode)
    end,
    noremap = true,
  })

  vim.cmd("startinsert!")
end

return M
