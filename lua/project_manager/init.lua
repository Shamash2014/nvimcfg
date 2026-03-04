local M = {}

local projects_mod = require("project_manager.projects")

local ns_id = vim.api.nvim_create_namespace("ProjectManager")

local pm_buf = nil
local return_buf = nil
local line_to_entry_map = {}
local showing_help = false

local function render()
  if not pm_buf or not vim.api.nvim_buf_is_valid(pm_buf) then
    return
  end

  local projects = projects_mod.gather()
  local lines = {}
  local entries = {}

  if #projects == 0 then
    table.insert(lines, "  No projects found")
    table.insert(lines, "")
    table.insert(lines, "  Press ? for help")
  else
    for _, proj in ipairs(projects) do
      table.insert(lines, proj.name .. "/")
      table.insert(entries, {
        type = "project",
        path = proj.path,
        name = proj.name,
        sessions = proj.sessions,
      })

      for _, session in ipairs(proj.sessions) do
        if session.type == "live" then
          local status_icon
          if session.status == "waiting" then
            status_icon = " "
          elseif session.status == "busy" then
            status_icon = " "
          elseif session.status == "done" then
            status_icon = " "
          elseif session.status == "active" then
            status_icon = " "
          else
            status_icon = " "
          end

          local name_part = session.buf_name or "(repl)"
          local msg_part = session.msg_count > 0 and string.format(" (%d)", session.msg_count) or ""
          local line = string.format("  %s %s  %s%s",
            status_icon, session.provider_name, name_part, msg_part)
          table.insert(lines, line)
          table.insert(entries, {
            type = "live_session",
            session_id = session.session_id,
            buf = session.buf,
            process = session.process,
            provider_name = session.provider_name,
            status = session.status,
            buf_name = name_part,
            msg_count = session.msg_count,
            project_path = proj.path,
          })
        elseif session.type == "persisted" then
          local line = string.format("    %s  (%s)",
            session.provider_name, session.time_display)
          table.insert(lines, line)
          table.insert(entries, {
            type = "persisted_session",
            session_id = session.session_id,
            provider_name = session.provider_name,
            time_display = session.time_display,
            project_path = proj.path,
          })
        end
      end
    end
  end

  vim.bo[pm_buf].modifiable = true
  vim.api.nvim_buf_set_lines(pm_buf, 0, -1, false, lines)
  vim.bo[pm_buf].modifiable = false

  if not vim.api.nvim_buf_is_valid(pm_buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(pm_buf, ns_id, 0, -1)

  line_to_entry_map = {}
  for i, entry in ipairs(entries) do
    line_to_entry_map[i] = entry
  end

  for line_idx = 1, #lines do
    local entry = line_to_entry_map[line_idx]
    if not entry then
      goto continue
    end

    if entry.type == "project" then
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, 0, {
        end_col = #lines[line_idx],
        hl_group = "Title",
      })
    elseif entry.type == "live_session" then
      local icon_hl = "Comment"
      if entry.status == "waiting" then
        icon_hl = "DiagnosticHint"
      elseif entry.status == "busy" then
        icon_hl = "DiagnosticWarn"
      elseif entry.status == "done" then
        icon_hl = "DiagnosticOk"
      elseif entry.status == "active" then
        icon_hl = "DiagnosticInfo"
      end

      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, 2, {
        end_col = 4,
        hl_group = icon_hl,
      })

      local provider_start = 5
      local provider_end = provider_start + #entry.provider_name
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, provider_start, {
        end_col = math.min(provider_end, #lines[line_idx]),
        hl_group = "Keyword",
      })

      local name_start = provider_end + 2
      local name_end = name_start + #entry.buf_name
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, name_start, {
        end_col = math.min(name_end, #lines[line_idx]),
        hl_group = "Directory",
      })

      if entry.msg_count > 0 then
        local msg_text = string.format(" (%d)", entry.msg_count)
        local msg_start = name_end
        vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, msg_start, {
          end_col = math.min(msg_start + #msg_text, #lines[line_idx]),
          hl_group = "Comment",
        })
      end
    elseif entry.type == "persisted_session" then
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, 4, {
        end_col = math.min(4 + #entry.provider_name, #lines[line_idx]),
        hl_group = "Keyword",
      })

      local time_start = 4 + #entry.provider_name + 2
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, time_start, {
        end_col = #lines[line_idx],
        hl_group = "Comment",
      })
    end

    ::continue::
  end
end

local function get_selected_entry()
  if not pm_buf or not vim.api.nvim_buf_is_valid(pm_buf) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  return line_to_entry_map[cursor[1]]
end

local function open_selected()
  local entry = get_selected_entry()
  if not entry then
    return
  end

  if entry.type == "project" then
    M.close()
    vim.cmd("Oil " .. vim.fn.fnameescape(entry.path))
    return
  end

  if entry.type == "live_session" and entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
    M.close()
    vim.api.nvim_win_set_buf(0, entry.buf)
    return
  end
end

local function delete_selected()
  local entry = get_selected_entry()
  if not entry then
    return
  end

  if entry.type == "project" then
    local total = #entry.sessions
    if total == 0 then
      return
    end

    local choice = vim.fn.confirm(
      string.format("Delete all %d session(s) for '%s'?", total, entry.name),
      "&Yes\n&No",
      2
    )
    if choice ~= 1 then
      return
    end

    local registry = require("ai_repl.registry")
    for _, s in ipairs(entry.sessions) do
      if s.type == "live" then
        if s.process and s.process:is_alive() then
          s.process:kill()
        end
        if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
          vim.api.nvim_buf_delete(s.buf, { force = true })
        end
        registry.unregister(s.session_id)
      elseif s.type == "persisted" then
        registry.delete_session(s.session_id)
      end
    end
    render()
    return
  end

  if entry.type == "live_session" then
    local name = entry.buf_name or entry.session_id
    local choice = vim.fn.confirm("Delete session?\n" .. name, "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end

    if entry.process and entry.process:is_alive() then
      entry.process:kill()
    end
    if entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
      vim.api.nvim_buf_delete(entry.buf, { force = true })
    end
    local registry = require("ai_repl.registry")
    registry.unregister(entry.session_id)
    render()
    return
  end

  if entry.type == "persisted_session" then
    local choice = vim.fn.confirm(
      "Remove persisted session?\n" .. entry.provider_name .. " " .. entry.time_display,
      "&Yes\n&No",
      2
    )
    if choice ~= 1 then
      return
    end

    local registry = require("ai_repl.registry")
    registry.delete_session(entry.session_id)
    render()
    return
  end
end

local function show_help()
  if not pm_buf or not vim.api.nvim_buf_is_valid(pm_buf) then
    return
  end

  if showing_help then
    showing_help = false
    render()
    return
  end

  showing_help = true

  local help_lines = {
    "",
    "  Project Manager",
    "",
    "  On project:",
    "  <CR> / l     Open in Oil",
    "  d            Kill all sessions",
    "",
    "  On live session:",
    "  <CR> / l     Open chat buffer",
    "  d            Delete session",
    "",
    "  On saved session:",
    "  d            Remove from disk",
    "",
    "  General:",
    "  R            Refresh",
    "  - / q / Esc  Close",
    "  ? / g?       Toggle help",
    "",
    "  Status:",
    "      Waiting for input",
    "      Agent processing",
    "      Agent done",
    "      Session active",
    "      Session inactive",
    "",
  }

  vim.bo[pm_buf].modifiable = true
  vim.api.nvim_buf_set_lines(pm_buf, 0, -1, false, help_lines)
  vim.bo[pm_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(pm_buf, ns_id, 0, -1)

  vim.api.nvim_buf_set_extmark(pm_buf, ns_id, 1, 0, {
    end_col = #help_lines[2],
    hl_group = "Title",
  })
end

local function setup_keymaps()
  if not pm_buf or not vim.api.nvim_buf_is_valid(pm_buf) then
    return
  end

  local opts = { buffer = pm_buf, silent = true, nowait = true }

  vim.keymap.set("n", "<CR>", open_selected, opts)
  vim.keymap.set("n", "l", open_selected, opts)
  vim.keymap.set("n", "d", delete_selected, opts)
  vim.keymap.set("n", "R", function()
    showing_help = false
    render()
  end, opts)
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, opts)
  vim.keymap.set("n", "-", function() M.close() end, opts)
  vim.keymap.set("n", "g?", show_help, opts)
  vim.keymap.set("n", "?", show_help, opts)
end

function M.open()
  if pm_buf and vim.api.nvim_buf_is_valid(pm_buf) then
    local wins = vim.fn.win_findbuf(pm_buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      showing_help = false
      render()
      return
    end
    vim.api.nvim_win_set_buf(0, pm_buf)
    showing_help = false
    render()
    return
  end

  return_buf = vim.api.nvim_get_current_buf()

  pm_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[pm_buf].buftype = "nofile"
  vim.bo[pm_buf].swapfile = false
  vim.bo[pm_buf].bufhidden = "wipe"
  vim.bo[pm_buf].filetype = "project-manager"
  vim.bo[pm_buf].modifiable = false

  vim.api.nvim_win_set_buf(0, pm_buf)

  vim.wo[0].cursorline = true
  vim.wo[0].cursorlineopt = "both"
  vim.wo[0].number = false
  vim.wo[0].relativenumber = false
  vim.wo[0].signcolumn = "no"
  vim.wo[0].foldcolumn = "0"
  vim.wo[0].spell = false
  vim.wo[0].list = false
  vim.wo[0].wrap = false

  setup_keymaps()
  showing_help = false
  render()

  if vim.api.nvim_buf_line_count(pm_buf) > 0 then
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = pm_buf,
    callback = function()
      pm_buf = nil
      return_buf = nil
      line_to_entry_map = {}
      showing_help = false
    end,
    once = true,
  })
end

function M.close()
  if return_buf and vim.api.nvim_buf_is_valid(return_buf) then
    vim.api.nvim_win_set_buf(0, return_buf)
  end

  if pm_buf and vim.api.nvim_buf_is_valid(pm_buf) then
    vim.api.nvim_buf_delete(pm_buf, { force = true })
    pm_buf = nil
  end

  return_buf = nil
  line_to_entry_map = {}
  showing_help = false
end

function M.toggle()
  if pm_buf and vim.api.nvim_buf_is_valid(pm_buf) then
    local wins = vim.fn.win_findbuf(pm_buf)
    if #wins > 0 then
      M.close()
      return
    end
  end
  M.open()
end

return M
