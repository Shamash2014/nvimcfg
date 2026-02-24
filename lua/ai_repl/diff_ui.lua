local M = {}

local popup = require("nui.popup")
local layout = require("nui.layout")
local event = require("nui.utils.autocmd").event

M.active_diff_ui = nil

local function create_buffer_with_content(content, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

  if filetype then
    vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
  end

  if content then
    local lines = vim.split(content, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  return buf
end

local function get_filetype_from_path(file_path)
  local ext = vim.fn.fnamemodify(file_path, ":e")
  if ext and ext ~= "" then
    return ext
  end
  return nil
end

local function apply_diff_highlights(buf, diff_type)
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(buf)
  for i = 0, line_count - 1 do
    if diff_type == "removed" then
      vim.api.nvim_buf_add_highlight(buf, -1, "DiffDelete", i, 0, -1)
    elseif diff_type == "added" then
      vim.api.nvim_buf_add_highlight(buf, -1, "DiffAdd", i, 0, -1)
    end
  end
end

function M.show_diff(diff_data, opts)
  opts = opts or {}

  if M.active_diff_ui then
    M.close_diff()
  end

  local file_path = diff_data.path or diff_data.file_path or "unknown"
  local old_content = diff_data.old or diff_data.oldText or ""
  local new_content = diff_data.new or diff_data.newText or ""

  local filetype = get_filetype_from_path(file_path)

  local old_popup = popup({
    enter = false,
    border = {
      style = "rounded",
      text = {
        top = " Original ",
        top_align = "center",
      },
    },
  })

  local new_popup = popup({
    enter = true,
    border = {
      style = "rounded",
      text = {
        top = " Modified ",
        top_align = "center",
      },
    },
  })

  local old_buf = create_buffer_with_content(old_content, filetype)
  local new_buf = create_buffer_with_content(new_content, filetype)

  vim.api.nvim_win_set_buf(old_popup.winid, old_buf)
  vim.api.nvim_win_set_buf(new_popup.winid, new_buf)

  apply_diff_highlights(old_buf, "removed")
  apply_diff_highlights(new_buf, "added")

  local diff_layout = layout(
    {
      position = "50%",
      size = {
        width = "90%",
        height = "80%",
      },
    },
    layout.Box({
      layout.Box({
        layout.Box(old_popup, { size = "50%" }),
        layout.Box(new_popup, { size = "50%" }),
      }, { dir = "row" }),
    }, { dir = "col" })
  )

  local function close_ui()
    if diff_layout then
      pcall(function()
        diff_layout:unmount()
      end)
    end
    M.active_diff_ui = nil
  end

  local keymaps = {
    { "n", "q", close_ui },
    { "n", "<Esc>", close_ui },
    { "n", "a", function()
      if opts.on_accept then
        opts.on_accept(diff_data)
      end
      close_ui()
      vim.notify("Changes accepted", vim.log.levels.INFO)
    end },
    { "n", "r", function()
      if opts.on_reject then
        opts.on_reject(diff_data)
      end
      close_ui()
      vim.notify("Changes rejected", vim.log.levels.INFO)
    end },
  }

  for _, km in ipairs(keymaps) do
    local mode, key, handler = km[1], km[2], km[3]
    old_popup:map(mode, key, handler, { noremap = true })
    new_popup:map(mode, key, handler, { noremap = true })
  end

  old_popup:on(event.BufLeave, close_ui)
  new_popup:on(event.BufLeave, close_ui)

  diff_layout:mount()

  vim.api.nvim_set_option_value("number", true, { win = old_popup.winid })
  vim.api.nvim_set_option_value("number", true, { win = new_popup.winid })
  vim.api.nvim_set_option_value("relativenumber", false, { win = old_popup.winid })
  vim.api.nvim_set_option_value("relativenumber", false, { win = new_popup.winid })

  M.active_diff_ui = {
    layout = diff_layout,
    old_popup = old_popup,
    new_popup = new_popup,
    diff_data = diff_data,
  }

  vim.api.nvim_buf_set_lines(
    new_popup.bufnr,
    0,
    0,
    false,
    {
      string.format("# File: %s", file_path),
      "# Press 'a' to accept, 'r' to reject, 'q' to close",
      "",
    }
  )

  return M.active_diff_ui
end

function M.close_diff()
  if M.active_diff_ui then
    pcall(function()
      M.active_diff_ui.layout:unmount()
    end)
    M.active_diff_ui = nil
  end
end

function M.show_merge_conflict(conflict_data, opts)
  opts = opts or {}

  if M.active_diff_ui then
    M.close_diff()
  end

  local file_path = conflict_data.path or conflict_data.file_path or "unknown"
  local current_content = conflict_data.current or conflict_data.ours or ""
  local incoming_content = conflict_data.incoming or conflict_data.theirs or ""
  local base_content = conflict_data.base or ""

  local filetype = get_filetype_from_path(file_path)

  local current_popup = popup({
    enter = false,
    border = {
      style = "rounded",
      text = {
        top = " Current (Ours) ",
        top_align = "center",
      },
    },
  })

  local incoming_popup = popup({
    enter = false,
    border = {
      style = "rounded",
      text = {
        top = " Incoming (Theirs) ",
        top_align = "center",
      },
    },
  })

  local base_popup = popup({
    enter = true,
    border = {
      style = "rounded",
      text = {
        top = " Base ",
        top_align = "center",
      },
    },
  })

  local current_buf = create_buffer_with_content(current_content, filetype)
  local incoming_buf = create_buffer_with_content(incoming_content, filetype)
  local base_buf = create_buffer_with_content(base_content, filetype)

  vim.api.nvim_win_set_buf(current_popup.winid, current_buf)
  vim.api.nvim_win_set_buf(incoming_popup.winid, incoming_buf)
  vim.api.nvim_win_set_buf(base_popup.winid, base_buf)

  apply_diff_highlights(current_buf, "removed")
  apply_diff_highlights(incoming_buf, "added")

  local diff_layout = layout(
    {
      position = "50%",
      size = {
        width = "95%",
        height = "90%",
      },
    },
    layout.Box({
      layout.Box(base_popup, { size = "33%" }),
      layout.Box({
        layout.Box(current_popup, { size = "50%" }),
        layout.Box(incoming_popup, { size = "50%" }),
      }, { dir = "row", size = "67%" }),
    }, { dir = "col" })
  )

  local function close_ui()
    if diff_layout then
      pcall(function()
        diff_layout:unmount()
      end)
    end
    M.active_diff_ui = nil
  end

  local keymaps = {
    { "n", "q", close_ui },
    { "n", "<Esc>", close_ui },
    { "n", "c", function()
      if opts.on_choose_current then
        opts.on_choose_current(conflict_data)
      end
      close_ui()
      vim.notify("Chose current version", vim.log.levels.INFO)
    end },
    { "n", "i", function()
      if opts.on_choose_incoming then
        opts.on_choose_incoming(conflict_data)
      end
      close_ui()
      vim.notify("Chose incoming version", vim.log.levels.INFO)
    end },
    { "n", "b", function()
      if opts.on_choose_both then
        opts.on_choose_both(conflict_data)
      end
      close_ui()
      vim.notify("Chose both versions", vim.log.levels.INFO)
    end },
  }

  for _, km in ipairs(keymaps) do
    local mode, key, handler = km[1], km[2], km[3]
    current_popup:map(mode, key, handler, { noremap = true })
    incoming_popup:map(mode, key, handler, { noremap = true })
    base_popup:map(mode, key, handler, { noremap = true })
  end

  base_popup:on(event.BufLeave, close_ui)

  diff_layout:mount()

  M.active_diff_ui = {
    layout = diff_layout,
    current_popup = current_popup,
    incoming_popup = incoming_popup,
    base_popup = base_popup,
    conflict_data = conflict_data,
  }

  return M.active_diff_ui
end

return M
