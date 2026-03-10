local M = {}

function M.setup(buf, ctx)
  local opts = { buffer = buf, silent = true, nowait = true }

  local function get_card_at_cursor()
    if not ctx.render_state then return nil end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local map = ctx.render_state.card_map
    if not map or not map[row] then return nil end

    local col_width = ctx.render_state.col_width
    local col_byte = cursor[2]
    local col_idx = math.floor(col_byte / (col_width + 1)) + 1
    if col_idx < 1 then col_idx = 1 end
    if col_idx > ctx.render_state.num_cols then col_idx = ctx.render_state.num_cols end

    return map[row][col_idx]
  end

  local function current_col_idx()
    if not ctx.render_state then return 1 end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local col_width = ctx.render_state.col_width
    local col_idx = math.floor(cursor[2] / (col_width + 1)) + 1
    if col_idx < 1 then col_idx = 1 end
    if col_idx > ctx.render_state.num_cols then col_idx = ctx.render_state.num_cols end
    return col_idx
  end

  local function move_to_col(col_idx)
    if not ctx.render_state then return end
    local col_width = ctx.render_state.col_width
    local target_byte = (col_idx - 1) * (col_width + 1) + 2
    local cursor = vim.api.nvim_win_get_cursor(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { cursor[1], target_byte })
  end

  vim.keymap.set("n", "h", function()
    local ci = current_col_idx()
    if ci > 1 then move_to_col(ci - 1) end
  end, opts)

  vim.keymap.set("n", "l", function()
    local ci = current_col_idx()
    if ci < (ctx.render_state and ctx.render_state.num_cols or 4) then
      move_to_col(ci + 1)
    end
  end, opts)

  vim.keymap.set("n", "j", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local total = vim.api.nvim_buf_line_count(buf)
    local header = ctx.render_state and ctx.render_state.header_lines or 3
    local footer = ctx.render_state and ctx.render_state.footer_line or total
    local next_row = cursor[1] + 1
    if next_row >= footer then return end
    if next_row <= header then next_row = header + 1 end
    pcall(vim.api.nvim_win_set_cursor, 0, { next_row, cursor[2] })
  end, opts)

  vim.keymap.set("n", "k", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local header = ctx.render_state and ctx.render_state.header_lines or 3
    local prev_row = cursor[1] - 1
    if prev_row <= header then return end
    pcall(vim.api.nvim_win_set_cursor, 0, { prev_row, cursor[2] })
  end, opts)

  vim.keymap.set("n", "gg", function()
    local header = ctx.render_state and ctx.render_state.header_lines or 3
    local cursor = vim.api.nvim_win_get_cursor(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { header + 1, cursor[2] })
  end, opts)

  vim.keymap.set("n", "G", function()
    local footer = ctx.render_state and ctx.render_state.footer_line or vim.api.nvim_buf_line_count(buf)
    local cursor = vim.api.nvim_win_get_cursor(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { footer - 1, cursor[2] })
  end, opts)

  vim.keymap.set("n", "a", function()
    local ci = current_col_idx()
    vim.ui.input({ prompt = "New card: " }, function(title)
      if not title or title == "" then return end
      local actions = require("task_manager.actions")
      actions.add_card(ctx.board, ci, title)
      ctx.save_and_render()
    end)
  end, opts)

  vim.keymap.set("n", "dd", function()
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    local choice = vim.fn.confirm("Delete card?\n" .. entry.card.title, "&Yes\n&No", 2)
    if choice ~= 1 then return end
    local actions = require("task_manager.actions")
    actions.delete_card(ctx.board, entry.col_idx, entry.card_idx)
    ctx.save_and_render()
  end, opts)

  vim.keymap.set("n", "e", function()
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    vim.ui.input({ prompt = "Title: ", default = entry.card.title }, function(title)
      if not title or title == "" then return end
      entry.card.title = title
      ctx.save_and_render()
    end)
  end, opts)

  vim.keymap.set("n", "<CR>", function()
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    local detail = require("task_manager.detail")
    detail.open(entry.card, {
      on_save = function()
        ctx.save_and_render()
      end,
    })
  end, opts)

  vim.keymap.set("n", "m", function()
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    local col_names = {}
    for i, col in ipairs(ctx.board.columns) do
      if i ~= entry.col_idx then
        table.insert(col_names, col.name)
      end
    end
    vim.ui.select(col_names, { prompt = "Move to:" }, function(choice)
      if not choice then return end
      local target_idx
      for i, col in ipairs(ctx.board.columns) do
        if col.name == choice then target_idx = i; break end
      end
      if not target_idx then return end
      local actions = require("task_manager.actions")
      actions.move_card(ctx.board, entry.col_idx, entry.card_idx, target_idx)
      ctx.save_and_render()
    end)
  end, opts)

  vim.keymap.set("n", "H", function()
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    if entry.col_idx <= 1 then return end
    local actions = require("task_manager.actions")
    actions.move_card(ctx.board, entry.col_idx, entry.card_idx, entry.col_idx - 1)
    ctx.save_and_render()
    move_to_col(entry.col_idx - 1)
  end, opts)

  vim.keymap.set("n", "L", function()
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    if entry.col_idx >= #ctx.board.columns then return end
    local actions = require("task_manager.actions")
    actions.move_card(ctx.board, entry.col_idx, entry.card_idx, entry.col_idx + 1)
    ctx.save_and_render()
    move_to_col(entry.col_idx + 1)
  end, opts)

  vim.keymap.set("n", "R", function()
    ctx.reload_and_render()
  end, opts)

  vim.keymap.set("n", "q", function() ctx.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() ctx.close() end, opts)
  vim.keymap.set("n", "?", function() ctx.toggle_help() end, opts)
end

function M.setup_commands(buf, ctx)
  local function get_card_at_cursor()
    if not ctx.render_state then return nil end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local map = ctx.render_state.card_map
    if not map or not map[row] then return nil end

    local col_width = ctx.render_state.col_width
    local col_idx = math.floor(cursor[2] / (col_width + 1)) + 1
    if col_idx < 1 then col_idx = 1 end
    if col_idx > ctx.render_state.num_cols then col_idx = ctx.render_state.num_cols end

    return map[row][col_idx]
  end

  vim.api.nvim_buf_create_user_command(buf, "P", function(cmd_opts)
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    local actions = require("task_manager.actions")
    actions.set_priority(entry.card, cmd_opts.args)
    ctx.save_and_render()
  end, { nargs = 1, complete = function() return { "high", "medium", "low", "none" } end })

  vim.api.nvim_buf_create_user_command(buf, "T", function(cmd_opts)
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    local actions = require("task_manager.actions")
    actions.add_tag(entry.card, cmd_opts.args)
    ctx.save_and_render()
  end, { nargs = 1 })

  vim.api.nvim_buf_create_user_command(buf, "D", function(cmd_opts)
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    local actions = require("task_manager.actions")
    actions.set_due(entry.card, cmd_opts.args)
    ctx.save_and_render()
  end, { nargs = 1 })

  vim.api.nvim_buf_create_user_command(buf, "Desc", function()
    local entry = get_card_at_cursor()
    if not entry or not entry.card then return end
    vim.ui.input({ prompt = "Description: ", default = entry.card.description }, function(val)
      if val then
        entry.card.description = val
        ctx.save_and_render()
      end
    end)
  end, { nargs = 0 })

  vim.api.nvim_buf_create_user_command(buf, "Board", function(cmd_opts)
    ctx.switch_board(cmd_opts.args)
  end, { nargs = 1, complete = function()
    local board_mod = require("task_manager.board")
    return board_mod.list()
  end })

  vim.api.nvim_buf_create_user_command(buf, "Boards", function()
    local board_mod = require("task_manager.board")
    local boards = board_mod.list()
    vim.ui.select(boards, { prompt = "Switch board:" }, function(choice)
      if choice then ctx.switch_board(choice) end
    end)
  end, { nargs = 0 })
end

return M
