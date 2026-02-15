local M = {}

local config = require("ai_repl.annotations.config")
local session = require("ai_repl.annotations.session")
local input = require("ai_repl.annotations.input")
local writer = require("ai_repl.annotations.writer")
local window = require("ai_repl.annotations.window")

function M.setup(opts)
  config.apply(opts or {})
  M._register_keymaps()
  M._register_commands()
end

function M._register_keymaps()
  local keys = config.config.keys

  vim.keymap.set("n", keys.start_session, function()
    M.start_session()
  end, { desc = "Annotations: Start session" })

  vim.keymap.set("n", keys.stop_session, function()
    M.stop_session()
  end, { desc = "Annotations: Stop session" })

  vim.keymap.set("v", keys.annotate, function()
    M.annotate()
  end, { desc = "Annotations: Add annotation" })

  vim.keymap.set("n", keys.toggle_window, function()
    M.toggle_window()
  end, { desc = "Annotations: Toggle window" })
end

function M._register_commands()
  vim.api.nvim_create_user_command("AnnotateStart", function()
    M.start_session()
  end, { desc = "Start annotation session" })

  vim.api.nvim_create_user_command("AnnotateStop", function()
    M.stop_session()
  end, { desc = "Stop annotation session" })

  vim.api.nvim_create_user_command("Annotate", function()
    M.annotate()
  end, { range = true, desc = "Add annotation to selection" })

  vim.api.nvim_create_user_command("AnnotateToggle", function()
    M.toggle_window()
  end, { desc = "Toggle annotation window" })
end

function M.start_session()
  return session.start(config.config)
end

function M.stop_session()
  return session.stop(config.config)
end

function M.resume_session(file_path)
  return session.resume(config.config, file_path)
end

function M.toggle_window()
  local session_state = session.get_state()

  if not session_state.active then
    vim.notify("No active annotation session", vim.log.levels.WARN)
    return
  end

  window.toggle(config.config, session_state.bufnr)
end

function M.annotate()
  local session_state = session.get_state()

  if not session_state.active then
    vim.notify("No active annotation session. Start one first.", vim.log.levels.WARN)
    return
  end

  local selection = M._capture_selection()
  input.show(config.config, config.config.capture_mode, selection, function(note, mode)
    if note ~= nil then
      if mode == "snippet" and not selection.text then
        selection.text = M._get_visual_text(
          selection.start_line,
          selection.start_col,
          selection.end_line,
          selection.end_col
        )
      end
      writer.append(session_state, mode, selection, note)
    end
  end)
end

function M._get_visual_text(start_line, start_col, end_line, end_col)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  if #lines == 0 then
    return ""
  end

  if #lines == 1 then
    return lines[1]:sub(start_col + 1, end_col + 1)
  end

  lines[1] = lines[1]:sub(start_col + 1)
  lines[#lines] = lines[#lines]:sub(1, end_col + 1)

  return table.concat(lines, "\n")
end

function M._capture_selection()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  local start_pos = vim.api.nvim_buf_get_mark(0, "<")
  local end_pos = vim.api.nvim_buf_get_mark(0, ">")

  local start_line = start_pos[1]
  local start_col = start_pos[2]
  local end_line = end_pos[1]
  local end_col = end_pos[2]

  local file = vim.api.nvim_buf_get_name(0)
  local relative_file = vim.fn.fnamemodify(file, ":~:.")

  local result = {
    file = relative_file,
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
    filetype = vim.bo.filetype,
  }

  if config.config.capture_mode == "snippet" then
    result.text = M._get_visual_text(start_line, start_col, end_line, end_col)
  end

  return result
end

function M.send_annotation_to_ai()
  local session_state = session.get_state()

  if not session_state.active then
    vim.notify("No active annotation session", vim.log.levels.WARN)
    return
  end

  local bufnr = session_state.bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("Invalid annotation buffer", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  local ai_repl = require("ai_repl")
  ai_repl.open()
  ai_repl.send_prompt("Please analyze these annotations:\n\n" .. content)
end

function M.get_session_state()
  return session.get_state()
end

return M
