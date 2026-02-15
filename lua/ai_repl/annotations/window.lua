local M = {}

local win_state = {
  win = nil,
  bufnr = nil,
}

function M.open(config, bufnr)
  if win_state.win and vim.api.nvim_win_is_valid(win_state.win) then
    vim.api.nvim_win_set_buf(win_state.win, bufnr)
    win_state.bufnr = bufnr
    return
  end

  local width = config.window.width < 1
    and math.floor(vim.o.columns * config.window.width)
    or config.window.width

  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, width)

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].breakindentopt = "shift:2,sbr"
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  vim.api.nvim_win_set_buf(win, bufnr)

  win_state.win = win
  win_state.bufnr = bufnr
end

function M.close()
  if win_state.win and vim.api.nvim_win_is_valid(win_state.win) then
    vim.api.nvim_win_close(win_state.win, true)
  end
  win_state.win = nil
  win_state.bufnr = nil
end

function M.toggle(config, bufnr)
  if win_state.win and vim.api.nvim_win_is_valid(win_state.win) then
    vim.api.nvim_win_hide(win_state.win)
  else
    M.open(config, bufnr)
  end
end

function M.refresh(bufnr)
  if win_state.win and vim.api.nvim_win_is_valid(win_state.win) then
    if win_state.bufnr == bufnr then
      vim.api.nvim_win_call(win_state.win, function()
        vim.cmd("normal! G")
      end)
    end
  end
end

function M.get_win()
  return win_state.win
end

function M.is_open()
  return win_state.win and vim.api.nvim_win_is_valid(win_state.win)
end

return M
