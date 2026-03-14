local M = {}

local projects_mod = require("project_manager.projects")

local ns_id = vim.api.nvim_create_namespace("ProjectManager")

local pm_buf = nil
local return_tab = nil
local line_to_entry_map = {}
local showing_help = false
---@type false|"v"|"s"
local split_mode = false

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
          local ann_part = session.annotation_count and session.annotation_count > 0
            and string.format("  %d", session.annotation_count) or ""
          local task_part = session.open_task_count and session.open_task_count > 0
            and string.format("  %d", session.open_task_count) or ""
          local line = string.format("  %s %s  %s%s%s%s",
            status_icon, session.provider_name, name_part, msg_part, ann_part, task_part)
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
            annotation_count = session.annotation_count or 0,
            open_task_count = session.open_task_count or 0,
            project_path = proj.path,
          })

          if session.plan_items and #session.plan_items > 0 then
            for _, task in ipairs(session.plan_items) do
              local task_icon = task.status == "in_progress" and "◐" or "○"
              local task_line = string.format("      %s %s", task_icon, task.content)
              table.insert(lines, task_line)
              table.insert(entries, {
                type = "task",
                buf = session.buf,
                session_id = session.session_id,
                task_content = task.content,
                task_status = task.status,
                project_path = proj.path,
              })
            end
          end
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

      if proj.running_tasks and #proj.running_tasks > 0 then
        for _, rt in ipairs(proj.running_tasks) do
          local icon = " "
          local bg_tag = rt.background and " [bg]" or ""
          local line = string.format("  %s %s  (%s)%s", icon, rt.name, rt.runtime_str, bg_tag)
          table.insert(lines, line)
          table.insert(entries, {
            type = "running_task",
            name = rt.name,
            runtime_str = rt.runtime_str,
            background = rt.background,
            term_buf = rt.term_buf,
            task_ref = rt.task_ref,
            project_path = proj.path,
          })
        end
      end

      if proj.tabs and #proj.tabs > 0 then
        for _, tab in ipairs(proj.tabs) do
          local current_marker = tab.is_current and "" or " "
          local win_count = #tab.windows
          local line = string.format("  %s Tab %d (%d win%s)",
            current_marker, tab.tabnr, win_count, win_count == 1 and "" or "s")
          table.insert(lines, line)
          table.insert(entries, {
            type = "tab",
            tabnr = tab.tabnr,
            tabpage = tab.tabpage,
            is_current = tab.is_current,
            project_path = proj.path,
          })

          for _, win in ipairs(tab.windows) do
            local win_line = string.format("      %s", win.name)
            table.insert(lines, win_line)
            table.insert(entries, {
              type = "tab_window",
              winid = win.winid,
              bufnr = win.bufnr,
              name = win.name,
              tabpage = tab.tabpage,
              project_path = proj.path,
            })
          end
        end
      end

      if proj.buffers and #proj.buffers > 0 then
        for _, buffer in ipairs(proj.buffers) do
          local modified = buffer.modified and " [+]" or ""
          local line = string.format("    %s%s", buffer.name, modified)
          table.insert(lines, line)
          table.insert(entries, {
            type = "buffer",
            bufnr = buffer.bufnr,
            name = buffer.name,
            path = buffer.path,
            modified = buffer.modified,
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

      local cursor = name_end
      if entry.msg_count > 0 then
        local msg_text = string.format(" (%d)", entry.msg_count)
        vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, cursor, {
          end_col = math.min(cursor + #msg_text, #lines[line_idx]),
          hl_group = "Comment",
        })
        cursor = cursor + #msg_text
      end

      if entry.annotation_count > 0 then
        local ann_text = string.format("  %d", entry.annotation_count)
        vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, cursor, {
          end_col = math.min(cursor + #ann_text, #lines[line_idx]),
          hl_group = "DiagnosticInfo",
        })
        cursor = cursor + #ann_text
      end

      if entry.open_task_count and entry.open_task_count > 0 then
        local task_text = string.format("  %d", entry.open_task_count)
        vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, cursor, {
          end_col = math.min(cursor + #task_text, #lines[line_idx]),
          hl_group = "DiagnosticHint",
        })
      end
    elseif entry.type == "buffer" then
      local name_start = 4
      local name_end = name_start + #entry.name
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, name_start, {
        end_col = math.min(name_end, #lines[line_idx]),
        hl_group = "Normal",
      })

      if entry.modified then
        vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, name_end, {
          end_col = #lines[line_idx],
          hl_group = "DiagnosticWarn",
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
    elseif entry.type == "task" then
      local icon_hl = entry.task_status == "in_progress" and "DiagnosticWarn" or "Comment"
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, 6, {
        end_col = math.min(8, #lines[line_idx]),
        hl_group = icon_hl,
      })
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, 8, {
        end_col = #lines[line_idx],
        hl_group = "Comment",
      })
    elseif entry.type == "running_task" then
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, 2, {
        end_col = 4,
        hl_group = "DiagnosticOk",
      })
      local name_start = 5
      local name_end = name_start + #entry.name
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, name_start, {
        end_col = math.min(name_end, #lines[line_idx]),
        hl_group = "Keyword",
      })
      local rest_start = name_end + 2
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, rest_start, {
        end_col = #lines[line_idx],
        hl_group = "Comment",
      })
    elseif entry.type == "tab" then
      local hl = entry.is_current and "DiagnosticInfo" or "Comment"
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, 2, {
        end_col = #lines[line_idx],
        hl_group = hl,
      })
    elseif entry.type == "tab_window" then
      vim.api.nvim_buf_set_extmark(pm_buf, ns_id, line_idx - 1, 6, {
        end_col = #lines[line_idx],
        hl_group = "Normal",
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

local function close_without_restore()
  if pm_buf and vim.api.nvim_buf_is_valid(pm_buf) then
    vim.api.nvim_buf_delete(pm_buf, { force = true })
    pm_buf = nil
  end
  return_tab = nil
  line_to_entry_map = {}
  showing_help = false
  split_mode = false
end

local function open_in_split_neighbor(callback)
  local pm_win = vim.api.nvim_get_current_win()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  local target_win = nil
  for _, w in ipairs(wins) do
    if w ~= pm_win then
      target_win = w
      break
    end
  end
  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end
  local cmd = split_mode == "s" and "split" or "vsplit"
  vim.cmd(cmd)
  callback()
  close_without_restore()
end

local function open_in_pm_tab(callback)
  close_without_restore()
  vim.cmd("tabnew")
  callback()
end

local function open_selected()
  local entry = get_selected_entry()
  if not entry then
    return
  end

  if not split_mode then
    split_mode = "v"
  end
  local open = open_in_split_neighbor

  if entry.type == "project" then
    open(function()
      vim.cmd("Oil " .. vim.fn.fnameescape(entry.path))
    end)
    return
  end

  if entry.type == "live_session" and entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
    open(function()
      vim.api.nvim_win_set_buf(0, entry.buf)
    end)
    return
  end

  if entry.type == "task" and entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
    open(function()
      vim.api.nvim_win_set_buf(0, entry.buf)
    end)
    return
  end

  if entry.type == "buffer" and entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
    open(function()
      vim.api.nvim_set_current_buf(entry.bufnr)
    end)
    return
  end

  if entry.type == "running_task" then
    if entry.task_ref then
      open(function()
        entry.task_ref:attach()
      end)
    end
    return
  end

  if entry.type == "tab" then
    close_without_restore()
    pcall(vim.api.nvim_set_current_tabpage, entry.tabpage)
    return
  end

  if entry.type == "tab_window" then
    close_without_restore()
    local ok = pcall(vim.api.nvim_set_current_tabpage, entry.tabpage)
    if ok then
      pcall(vim.api.nvim_set_current_win, entry.winid)
    end
    return
  end
end

local function open_selected_in_split(direction)
  split_mode = direction
  open_selected()
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

  if entry.type == "buffer" then
    local label = entry.modified and (entry.name .. " [+]") or entry.name
    local choice = vim.fn.confirm("Close buffer?\n" .. label, "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
    if vim.api.nvim_buf_is_valid(entry.bufnr) then
      vim.api.nvim_buf_delete(entry.bufnr, { force = true })
    end
    render()
    return
  end

  if entry.type == "running_task" then
    local choice = vim.fn.confirm("Kill task?\n" .. entry.name, "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
    if entry.task_ref and entry.task_ref.term then
      pcall(function() entry.task_ref.term:close() end)
    end
    render()
    return
  end

  if entry.type == "tab" then
    if #vim.api.nvim_list_tabpages() <= 1 then
      vim.notify("Cannot close the last tab", vim.log.levels.WARN)
      return
    end
    local choice = vim.fn.confirm(
      string.format("Close Tab %d?", entry.tabnr),
      "&Yes\n&No",
      2
    )
    if choice ~= 1 then
      return
    end
    M.close()
    local ok = pcall(vim.api.nvim_set_current_tabpage, entry.tabpage)
    if ok then
      vim.cmd("tabclose")
    end
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
    "  n            New session (default provider)",
    "  s            New session (pick provider)",
    "  d            Kill all sessions",
    "",
    "  On live session / task:",
    "  <CR> / l     Open chat buffer",
    "  n            New session in project",
    "  s            New session (pick provider)",
    "  d            Delete session",
    "",
    "  On saved session:",
    "  d            Remove from disk",
    "",
    "  On buffer:",
    "  <CR> / l     Open buffer",
    "  d            Close buffer",
    "",
    "  On running task:",
    "  <CR> / l     Attach to task terminal",
    "  d            Kill task",
    "",
    "  On tab:",
    "  <CR> / l     Switch to tab",
    "  d            Close tab",
    "",
    "  On tab window:",
    "  <CR> / l     Switch to tab & window",
    "",
    "  Navigation:",
    "  ]p / [p      Next/prev project",
    "  ]s / [s      Next/prev session",
    "  ]t / [t      Next/prev task",
    "  J / K        Next/prev same type",
    "",
    "  Split open:",
    "  <localleader>v  Open in vsplit",
    "  <localleader>w  Open in split",
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

local function get_project_for_entry(entry)
  if entry.type == "project" then
    return entry
  end
  if entry.project_path then
    for _, e in pairs(line_to_entry_map) do
      if e.type == "project" and e.path == entry.project_path then
        return e
      end
    end
  end
  return nil
end

local function start_new_session(provider_id)
  local entry = get_selected_entry()
  if not entry then return end

  local project = get_project_for_entry(entry)
  if not project then return end

  M.close()
  vim.cmd("cd " .. vim.fn.fnameescape(project.path))
  local ai_repl = require("ai_repl")
  if provider_id then
    ai_repl.new_session(provider_id)
  else
    ai_repl.open_chat_buffer()
  end
end

local function start_new_session_pick_provider()
  local entry = get_selected_entry()
  if not entry then return end

  local project = get_project_for_entry(entry)
  if not project then return end

  local ai_repl = require("ai_repl")
  ai_repl.pick_provider(function(provider_id)
    M.close()
    vim.cmd("cd " .. vim.fn.fnameescape(project.path))
    ai_repl.new_session(provider_id)
  end)
end

local function get_lines_by_type(match_fn)
  local lines = {}
  for line_nr, entry in pairs(line_to_entry_map) do
    if match_fn(entry) then
      table.insert(lines, line_nr)
    end
  end
  table.sort(lines)
  return lines
end

local function jump_to(lines, direction)
  if not pm_buf or not vim.api.nvim_buf_is_valid(pm_buf) then return end
  if #lines == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)[1]

  if direction == 'next' then
    for _, ln in ipairs(lines) do
      if ln > cursor then
        vim.api.nvim_win_set_cursor(0, { ln, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { lines[1], 0 })
  else
    for i = #lines, 1, -1 do
      if lines[i] < cursor then
        vim.api.nvim_win_set_cursor(0, { lines[i], 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { lines[#lines], 0 })
  end
end

local function jump_typed(type_name, direction)
  jump_to(get_lines_by_type(function(e) return e.type == type_name end), direction)
end

local SESSION_TYPES = {
  live_session = true,
  persisted_session = true,
}

local function jump_session(direction)
  jump_to(get_lines_by_type(function(e) return SESSION_TYPES[e.type] end), direction)
end

local function jump_same_type(direction)
  if not pm_buf or not vim.api.nvim_buf_is_valid(pm_buf) then return end
  local current = get_selected_entry()
  if not current then return end
  jump_typed(current.type, direction)
end

local function setup_keymaps()
  if not pm_buf or not vim.api.nvim_buf_is_valid(pm_buf) then
    return
  end

  local opts = { buffer = pm_buf, silent = true, nowait = true }

  vim.keymap.set("n", "<CR>", open_selected, opts)
  vim.keymap.set("n", "l", open_selected, opts)
  vim.keymap.set("n", "<localleader>v", function() open_selected_in_split("v") end, opts)
  vim.keymap.set("n", "<localleader>w", function() open_selected_in_split("s") end, opts)
  vim.keymap.set("n", "d", delete_selected, opts)
  vim.keymap.set("n", "<localleader>n", function() start_new_session() end, opts)
  vim.keymap.set("n", "s", start_new_session_pick_provider, opts)
  vim.keymap.set("n", "R", function()
    showing_help = false
    render()
  end, opts)
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, opts)
  vim.keymap.set("n", "-", function() M.close() end, opts)
  vim.keymap.set("n", "g?", show_help, opts)
  vim.keymap.set("n", "?", show_help, opts)
  vim.keymap.set('n', ']p', function() jump_typed('project', 'next') end, opts)
  vim.keymap.set('n', '[p', function() jump_typed('project', 'prev') end, opts)
  vim.keymap.set('n', ']s', function() jump_session('next') end, opts)
  vim.keymap.set('n', '[s', function() jump_session('prev') end, opts)
  vim.keymap.set('n', ']t', function() jump_typed('running_task', 'next') end, opts)
  vim.keymap.set('n', '[t', function() jump_typed('running_task', 'prev') end, opts)
  vim.keymap.set('n', 'J', function() jump_same_type('next') end, opts)
  vim.keymap.set('n', 'K', function() jump_same_type('prev') end, opts)
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
  end

  return_tab = vim.api.nvim_get_current_tabpage()

  pm_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[pm_buf].buftype = "nofile"
  vim.bo[pm_buf].swapfile = false
  vim.bo[pm_buf].bufhidden = "wipe"
  vim.bo[pm_buf].filetype = "project-manager"
  vim.bo[pm_buf].modifiable = false

  vim.cmd("tabnew")
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
      return_tab = nil
      line_to_entry_map = {}
      showing_help = false
      split_mode = false
    end,
    once = true,
  })
end

function M.close()
  local tab_to_restore = return_tab

  if pm_buf and vim.api.nvim_buf_is_valid(pm_buf) then
    vim.api.nvim_buf_delete(pm_buf, { force = true })
    pm_buf = nil
  end

  if tab_to_restore and vim.api.nvim_tabpage_is_valid(tab_to_restore) then
    vim.api.nvim_set_current_tabpage(tab_to_restore)
  end

  return_tab = nil
  line_to_entry_map = {}
  showing_help = false
  split_mode = false
end

function M.open_split()
  if pm_buf and vim.api.nvim_buf_is_valid(pm_buf) then
    local wins = vim.fn.win_findbuf(pm_buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      showing_help = false
      render()
      return
    end
  end

  return_tab = nil
  split_mode = "v"

  pm_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[pm_buf].buftype = "nofile"
  vim.bo[pm_buf].swapfile = false
  vim.bo[pm_buf].bufhidden = "wipe"
  vim.bo[pm_buf].filetype = "project-manager"
  vim.bo[pm_buf].modifiable = false

  vim.cmd("topleft vsplit")
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
      return_tab = nil
      line_to_entry_map = {}
      showing_help = false
      split_mode = false
    end,
    once = true,
  })
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

function M.toggle_split()
  if pm_buf and vim.api.nvim_buf_is_valid(pm_buf) then
    local wins = vim.fn.win_findbuf(pm_buf)
    if #wins > 0 then
      M.close()
      return
    end
  end
  M.open_split()
end

return M
