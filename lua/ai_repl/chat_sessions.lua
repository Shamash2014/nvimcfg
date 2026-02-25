local M = {}

local chat_buffer = require("ai_repl.chat_buffer")
local chat_parser = require("ai_repl.chat_parser")
local chat_state = require("ai_repl.chat_state")

local ns_id = vim.api.nvim_create_namespace("AIReplChatSessions")

local sessions_buf = nil
local sessions_win = nil
local return_to_win = nil

local line_to_entry_map = {}

local function get_all_chat_buffers()
  local bufs = {}
  local seen_paths = {}
  local seen_buffers = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and chat_buffer.is_chat_buffer(buf) then
      -- Ensure unique by both buffer ID and file path
      local buf_name = vim.api.nvim_buf_get_name(buf)
      local buf_path = vim.fn.fnamemodify(buf_name, ":p")

      if not seen_buffers[buf] and not seen_paths[buf_path] then
        table.insert(bufs, buf)
        seen_buffers[buf] = true
        if buf_path ~= "" then
          seen_paths[buf_path] = buf
        end
      end
    end
  end
  return bufs
end

local function get_buffer_status(buf)
  local state = chat_state.get_buffer_state(buf)
  if state.session_id and state.process and state.process:is_alive() then
    local proc = state.process

    -- Check if agent is waiting for user response (harness)
    if proc.ui and proc.ui.permission_active then
      return "waiting"
    end

    -- Check if agent turn is complete (done)
    if not proc.state.busy and proc.state.session_ready then
      return "done"
    end

    -- Check if agent is busy processing
    if proc.state.busy then
      return "busy"
    end

    return "active"
  end
  return "inactive"
end

local function get_buffer_entries(buf)
  local buf_name = vim.api.nvim_buf_get_name(buf)
  local relative_name = vim.fn.fnamemodify(buf_name, ":t")

  if relative_name == "" then
    relative_name = "[No Name]"
  end

  local status = get_buffer_status(buf)
  local is_current = buf == vim.api.nvim_get_current_buf()

  local parsed = chat_parser.parse_buffer_cached(buf)
  local entries = {}

  table.insert(entries, {
    type = "header",
    buf = buf,
    name = relative_name,
    status = status,
    is_current = is_current,
    msg_count = #parsed.messages,
  })

  return entries
end

local function render_sessions_buffer()
  if not sessions_buf or not vim.api.nvim_buf_is_valid(sessions_buf) then
    return
  end

  local all_entries = {}
  local bufs = get_all_chat_buffers()

  table.sort(bufs, function(a, b)
    local status_a = get_buffer_status(a)
    local status_b = get_buffer_status(b)

    -- Priority order: waiting > busy > done > active > inactive
    local priority = {
      waiting = 5,
      busy = 4,
      done = 3,
      active = 2,
      inactive = 1
    }

    local prio_a = priority[status_a] or 0
    local prio_b = priority[status_b] or 0

    if prio_a ~= prio_b then
      return prio_a > prio_b
    end

    local name_a = vim.api.nvim_buf_get_name(a)
    local name_b = vim.api.nvim_buf_get_name(b)
    return name_a < name_b
  end)

  -- bufs is already de-duplicated from get_all_chat_buffers
  for _, buf in ipairs(bufs) do
    local buf_entries = get_buffer_entries(buf)
    for _, entry in ipairs(buf_entries) do
      table.insert(all_entries, entry)
    end
  end

  local lines = {}

  if #all_entries == 0 then
    table.insert(lines, "  No .chat buffers open")
    table.insert(lines, "")
    table.insert(lines, "  Press ? for help")
  else
    for _, entry in ipairs(all_entries) do
      if entry.type == "header" then
        local status_icon = ""

        if entry.status == "waiting" then
          status_icon = " "  -- Question mark for waiting
        elseif entry.status == "busy" then
          status_icon = " "  -- Loading spinner
        elseif entry.status == "done" then
          status_icon = " "  -- Checkmark for done
        elseif entry.status == "active" then
          status_icon = " "  -- Circle for active
        else
          status_icon = " "  -- Moon for inactive
        end

        local msg_info = string.format("(%d)", entry.msg_count)
        local line = string.format("%s %s %s",
          status_icon,
          entry.name,
          msg_info
        )
        table.insert(lines, line)
      end
    end
  end

  if not vim.api.nvim_buf_is_valid(sessions_buf) then
    return
  end

  vim.bo[sessions_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sessions_buf, 0, -1, false, lines)
  vim.bo[sessions_buf].modifiable = false

  if not vim.api.nvim_buf_is_valid(sessions_buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(sessions_buf, ns_id, 0, -1)

  local line_to_entry = {}
  for i, entry in ipairs(all_entries) do
    line_to_entry[i] = entry
  end

  line_to_entry_map = line_to_entry

  for line_idx = 1, #lines do
    local entry = line_to_entry[line_idx]
    if not entry then
      goto continue
    end

    if entry.type == "header" then
      local icon_hl = "Comment"
      if entry.status == "waiting" then
        icon_hl = "DiagnosticHint"  -- Blue for waiting/question
      elseif entry.status == "busy" then
        icon_hl = "DiagnosticWarn"  -- Yellow for busy
      elseif entry.status == "done" then
        icon_hl = "DiagnosticOk"    -- Green for done
      elseif entry.status == "active" then
        icon_hl = "DiagnosticInfo"  -- Cyan for active
      end

      vim.api.nvim_buf_set_extmark(sessions_buf, ns_id, line_idx - 1, 0, {
        end_col = 2,
        hl_group = icon_hl,
      })

      local name_start = 2
      local name_end = name_start + #entry.name
      vim.api.nvim_buf_set_extmark(sessions_buf, ns_id, line_idx - 1, name_start, {
        end_col = name_end,
        hl_group = "Directory",
      })

      local msg_info = string.format("(%d)", entry.msg_count)
      local msg_start = name_end + 1
      vim.api.nvim_buf_set_extmark(sessions_buf, ns_id, line_idx - 1, msg_start, {
        end_col = msg_start + #msg_info,
        hl_group = "Comment",
      })
    end

    ::continue::
  end
end

local function get_selected_entry()
  if not sessions_buf or not vim.api.nvim_buf_is_valid(sessions_buf) then
    return nil
  end

  if not sessions_win or not vim.api.nvim_win_is_valid(sessions_win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(sessions_win)
  local line_num = cursor[1]

  return line_to_entry_map[line_num]
end

local function open_selected_entry()
  local selected = get_selected_entry()
  if not selected then
    return
  end

  local buf = selected.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    vim.notify("[Sessions] Buffer no longer valid", vim.log.levels.WARN)
    render_sessions_buffer()
    return
  end

  M.close()

  if return_to_win and vim.api.nvim_win_is_valid(return_to_win) then
    vim.api.nvim_set_current_win(return_to_win)
    vim.api.nvim_win_set_buf(return_to_win, buf)
  else
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
    else
      vim.cmd("buffer " .. buf)
    end
  end
end

local function delete_selected_entry()
  local selected = get_selected_entry()
  if not selected then
    return
  end

  local buf = selected.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    render_sessions_buffer()
    return
  end

  local buf_name = vim.api.nvim_buf_get_name(buf)
  local relative_name = vim.fn.fnamemodify(buf_name, ":t")

  local choice = vim.fn.confirm(
    "Delete .chat buffer?\n" .. relative_name,
    "&Yes\n&No",
    2
  )

  if choice == 1 then
    vim.api.nvim_buf_delete(buf, { force = false })
    render_sessions_buffer()
  end
end

local function show_help()
  if not sessions_buf or not vim.api.nvim_buf_is_valid(sessions_buf) then
    return
  end

  local help_lines = {
    "",
    "  Chat Sessions - Help",
    "",
    "  <CR>         Open chat buffer",
    "  l            Open chat buffer",
    "  d            Delete buffer",
    "  R            Refresh list",
    "  - / q        Close window",
    "  g? / ?       Toggle help",
    "",
    "  Status indicators:",
    "      Waiting for your response",
    "      Agent processing",
    "      Agent turn done",
    "      Session active",
    "      Session inactive",
    "",
  }

  vim.bo[sessions_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sessions_buf, 0, -1, false, help_lines)
  vim.bo[sessions_buf].modifiable = false

  if not vim.api.nvim_buf_is_valid(sessions_buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(sessions_buf, ns_id, 0, -1)

  vim.api.nvim_buf_set_extmark(sessions_buf, ns_id, 1, 0, {
    end_col = 100,
    hl_group = "Title",
    hl_eol = true,
  })

  vim.defer_fn(function()
    if sessions_buf and vim.api.nvim_buf_is_valid(sessions_buf) then
      render_sessions_buffer()
    end
  end, 5000)
end

local function setup_keymaps()
  if not sessions_buf or not vim.api.nvim_buf_is_valid(sessions_buf) then
    return
  end

  local opts = { buffer = sessions_buf, silent = true, nowait = true }

  vim.keymap.set("n", "<CR>", open_selected_entry, opts)
  vim.keymap.set("n", "l", open_selected_entry, opts)
  vim.keymap.set("n", "d", delete_selected_entry, opts)
  vim.keymap.set("n", "R", render_sessions_buffer, opts)
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "-", function() M.close() end, opts)
  vim.keymap.set("n", "g?", show_help, opts)
  vim.keymap.set("n", "?", show_help, opts)
end

function M.open()
  if sessions_buf and vim.api.nvim_buf_is_valid(sessions_buf) then
    if sessions_win and vim.api.nvim_win_is_valid(sessions_win) then
      vim.api.nvim_set_current_win(sessions_win)
      render_sessions_buffer()
      return
    end
  end

  return_to_win = vim.api.nvim_get_current_win()

  sessions_buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(sessions_buf, "chat-sessions://")
  vim.bo[sessions_buf].buftype = "nofile"
  vim.bo[sessions_buf].swapfile = false
  vim.bo[sessions_buf].bufhidden = "wipe"
  vim.bo[sessions_buf].filetype = "chat-sessions"
  vim.bo[sessions_buf].modifiable = false

  vim.cmd("vsplit")
  sessions_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(sessions_win, sessions_buf)

  local width = math.max(40, math.floor(vim.o.columns * 0.3))
  vim.api.nvim_win_set_width(sessions_win, width)

  vim.wo[sessions_win].wrap = false
  vim.wo[sessions_win].cursorline = true
  vim.wo[sessions_win].cursorlineopt = "both"
  vim.wo[sessions_win].number = false
  vim.wo[sessions_win].relativenumber = false
  vim.wo[sessions_win].signcolumn = "no"
  vim.wo[sessions_win].foldcolumn = "0"
  vim.wo[sessions_win].spell = false
  vim.wo[sessions_win].list = false

  setup_keymaps()

  render_sessions_buffer()

  if vim.api.nvim_buf_line_count(sessions_buf) > 0 then
    vim.api.nvim_win_set_cursor(sessions_win, {1, 0})
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = sessions_buf,
    callback = function()
      if sessions_win and vim.api.nvim_win_is_valid(sessions_win) then
        return
      end
      M.close()
    end,
  })

  local timer = vim.uv.new_timer()
  if timer then
    timer:start(1000, 1000, vim.schedule_wrap(function()
      if not sessions_buf or not vim.api.nvim_buf_is_valid(sessions_buf) then
        if timer then
          timer:stop()
          timer:close()
        end
        return
      end
      render_sessions_buffer()
    end))

    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = sessions_buf,
      once = true,
      callback = function()
        if timer then
          timer:stop()
          timer:close()
        end
      end,
    })
  end
end

function M.close()
  if sessions_win and vim.api.nvim_win_is_valid(sessions_win) then
    vim.api.nvim_win_close(sessions_win, true)
    sessions_win = nil
  end

  if sessions_buf and vim.api.nvim_buf_is_valid(sessions_buf) then
    vim.api.nvim_buf_delete(sessions_buf, { force = true })
    sessions_buf = nil
  end

  if return_to_win and vim.api.nvim_win_is_valid(return_to_win) then
    vim.api.nvim_set_current_win(return_to_win)
  end

  return_to_win = nil
end

function M.toggle()
  if sessions_win and vim.api.nvim_win_is_valid(sessions_win) then
    M.close()
  else
    M.open()
  end
end

return M
