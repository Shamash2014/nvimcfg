local M = {}

local board_mod = require("task_manager.board")
local render_mod = require("task_manager.render")
local keymaps_mod = require("task_manager.keymaps")

local ns_id = vim.api.nvim_create_namespace("TaskManager")

local tm_buf = nil
local return_tab = nil
local showing_help = false

local state = {
  board = nil,
  board_name = "default",
  render_state = nil,
}

local function save_and_render()
  board_mod.save(state.board_name, state.board)
  if tm_buf and vim.api.nvim_buf_is_valid(tm_buf) then
    state.render_state = render_mod.render(tm_buf, state.board, state)
  end
end

local function reload_and_render()
  state.board = board_mod.load(state.board_name)
  save_and_render()
end

local function switch_board(name)
  if not name or name == "" then return end
  state.board, state.board_name = board_mod.load(name)
  showing_help = false
  save_and_render()
end

local function show_help()
  if not tm_buf or not vim.api.nvim_buf_is_valid(tm_buf) then return end

  if showing_help then
    showing_help = false
    save_and_render()
    return
  end

  showing_help = true

  local help_lines = {
    "",
    "  Task Manager",
    "",
    "  Navigation:",
    "  h / l         Move between columns",
    "  j / k         Move between cards",
    "  gg / G        First / last card",
    "",
    "  Card Actions:",
    "  a             Add new card",
    "  dd            Delete card",
    "  e             Edit card title",
    "  <CR>          Open card detail",
    "",
    "  Moving Cards:",
    "  m             Move card (pick column)",
    "  H / L         Quick-move left / right",
    "",
    "  Metadata:",
    "  :P <val>      Set priority (high/medium/low/none)",
    "  :T <val>      Add tag",
    "  :D <val>      Set due date (YYYY-MM-DD or +3d/+1w)",
    "  :Desc         Edit description",
    "",
    "  Board:",
    "  :Board <name> Switch / create board",
    "  :Boards       List all boards",
    "",
    "  General:",
    "  R             Refresh",
    "  q / <Esc>     Close",
    "  ?             Toggle help",
    "",
  }

  vim.bo[tm_buf].modifiable = true
  vim.api.nvim_buf_set_lines(tm_buf, 0, -1, false, help_lines)
  vim.bo[tm_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(tm_buf, ns_id, 0, -1)
  vim.api.nvim_buf_set_extmark(tm_buf, ns_id, 1, 0, {
    end_col = #help_lines[2],
    hl_group = "Title",
  })
end

function M.close()
  local tab_to_restore = return_tab

  if tm_buf and vim.api.nvim_buf_is_valid(tm_buf) then
    vim.api.nvim_buf_delete(tm_buf, { force = true })
    tm_buf = nil
  end

  if tab_to_restore and vim.api.nvim_tabpage_is_valid(tab_to_restore) then
    vim.api.nvim_set_current_tabpage(tab_to_restore)
  end

  return_tab = nil
  showing_help = false
end

function M.open(board_name)
  board_name = board_name or "default"

  if tm_buf and vim.api.nvim_buf_is_valid(tm_buf) then
    local wins = vim.fn.win_findbuf(tm_buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      state.board, state.board_name = board_mod.load(board_name)
      showing_help = false
      save_and_render()
      return
    end
  end

  return_tab = vim.api.nvim_get_current_tabpage()

  state.board, state.board_name = board_mod.load(board_name)

  tm_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[tm_buf].buftype = "nofile"
  vim.bo[tm_buf].swapfile = false
  vim.bo[tm_buf].bufhidden = "wipe"
  vim.bo[tm_buf].filetype = "task-manager"
  vim.bo[tm_buf].modifiable = false

  vim.cmd("tabnew")
  vim.api.nvim_win_set_buf(0, tm_buf)

  vim.wo[0].cursorline = true
  vim.wo[0].cursorlineopt = "both"
  vim.wo[0].number = false
  vim.wo[0].relativenumber = false
  vim.wo[0].signcolumn = "no"
  vim.wo[0].foldcolumn = "0"
  vim.wo[0].spell = false
  vim.wo[0].list = false
  vim.wo[0].wrap = false

  local ctx = {
    board = state.board,
    render_state = state.render_state,
    save_and_render = save_and_render,
    reload_and_render = reload_and_render,
    close = M.close,
    toggle_help = show_help,
    switch_board = switch_board,
  }

  setmetatable(ctx, {
    __index = function(_, key)
      if key == "render_state" then return state.render_state end
      if key == "board" then return state.board end
    end,
  })

  keymaps_mod.setup(tm_buf, ctx)
  keymaps_mod.setup_commands(tm_buf, ctx)

  showing_help = false
  save_and_render()

  local header = state.render_state and state.render_state.header_lines or 3
  pcall(vim.api.nvim_win_set_cursor, 0, { header + 1, 2 })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = tm_buf,
    callback = function()
      tm_buf = nil
      return_tab = nil
      showing_help = false
    end,
    once = true,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    buffer = tm_buf,
    callback = function()
      if not showing_help then
        save_and_render()
      end
    end,
  })
end

function M.toggle(board_name)
  if tm_buf and vim.api.nvim_buf_is_valid(tm_buf) then
    local wins = vim.fn.win_findbuf(tm_buf)
    if #wins > 0 then
      M.close()
      return
    end
  end
  M.open(board_name)
end

function M.setup()
  vim.api.nvim_create_user_command("TaskManager", function(cmd_opts)
    local name = cmd_opts.args ~= "" and cmd_opts.args or nil
    M.toggle(name)
  end, {
    nargs = "?",
    complete = function()
      return board_mod.list()
    end,
  })
end

return M
