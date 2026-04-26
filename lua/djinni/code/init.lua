local utils = require("core.utils")

local M = {}

local function default_session_name(text, fallback)
  if fallback and fallback ~= "" then return fallback end
  local first = tostring(text or ""):match("([^\n]+)") or ""
  first = vim.trim(first)
  if first ~= "" then return first end
  return "session-" .. os.date("!%Y%m%dT%H%M%S")
end

local function set_compose_text(buf, text)
  local document = require("neowork.document")
  document.ensure_composer(buf)
  document.clear_compose(buf)
  local compose = document.find_compose_line(buf)
  if not compose then return end
  local lines = vim.split(text or "", "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, compose, compose + 1, false, lines)
end

local function append_compose_text(buf, text)
  local document = require("neowork.document")
  document.ensure_composer(buf)
  local current = document.get_compose_text(buf)
  if current ~= "" then
    text = current .. "\n\n" .. text
  end
  set_compose_text(buf, text)
  document.goto_compose(buf)
end

local function open_or_create_session(project_root, opts)
  opts = opts or {}
  local util = require("neowork.util")
  local document = require("neowork.document")
  local bridge = require("neowork.bridge")

  util.new_session_interactive(project_root, {
    name = default_session_name(opts.prompt, opts.title),
    provider = opts.provider,
  }, function(filepath)
    if not filepath then
      vim.notify("Failed to create neowork session", vim.log.levels.ERROR)
      return nil
    end

    local split = opts.split == false and "edit" or "vsplit"
    local buf = document.open(filepath, { split = split })

    if opts.no_send then
      set_compose_text(buf, opts.prompt or "")
    elseif opts.prompt and opts.prompt ~= "" then
      document.insert_turn(buf, "You", opts.prompt)
      bridge.send(buf, opts.prompt)
    end

    return buf, filepath
  end)
end

local function find_neowork_buf()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].neowork_chat then
      return buf
    end
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].neowork_chat then
      return buf
    end
  end

  return nil
end

function M.create_task(opts)
  opts = opts or {}
  local project_root = opts.project_root or utils.get_project_root() or vim.fn.getcwd()

  vim.ui.input({ prompt = opts.input_prompt or "Task: " }, function(prompt)
    if not prompt or prompt == "" then return end
    open_or_create_session(project_root, {
      prompt = prompt,
      split = opts.split,
      title = opts.title,
    })
  end)
end

function M.create_with_file()
  local name = vim.api.nvim_buf_get_name(0)
  local rel_path = vim.fn.fnamemodify(name, ":.")
  local project_root = utils.get_project_root() or vim.fn.getcwd()

  vim.ui.input({ prompt = "Task: " }, function(prompt)
    if not prompt or prompt == "" then return end
    open_or_create_session(project_root, {
      prompt = "Use `" .. rel_path .. "` as context.\n\n" .. prompt,
      split = true,
      title = rel_path,
    })
  end)
end

function M.create_with_selection()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  local s = vim.fn.line("'<")
  local e = vim.fn.line("'>")
  if s == 0 or e == 0 then
    vim.notify("No visual selection", vim.log.levels.WARN)
    return
  end
  M._create_task_with_name(s, e)
end

function M._create_task(s, e)
  local name = vim.api.nvim_buf_get_name(0)
  local rel_path = vim.fn.fnamemodify(name, ":.")
  local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
  if #lines == 0 then
    vim.notify("Empty selection", vim.log.levels.WARN)
    return
  end
  local selection = table.concat(lines, "\n")
  local project_root = utils.get_project_root() or vim.fn.getcwd()
  local ft = vim.bo.filetype or ""

  local reference = "From `" .. rel_path .. ":" .. s .. "-" .. e .. "`:\n\n```" .. ft .. "\n" .. selection .. "\n```"

  local basename = vim.fn.fnamemodify(rel_path, ":t:r")
  local title = "draft-" .. basename .. "-" .. s .. "-" .. e

  open_or_create_session(project_root, {
    prompt = reference,
    title = title,
    no_send = true,
    split = true,
  })

  vim.notify("Draft captured: " .. rel_path .. ":" .. s .. "-" .. e, vim.log.levels.INFO)
end

function M.generate_task_from_visual()
  local s = vim.fn.line("'<")
  local e = vim.fn.line("'>")
  if s == 0 or e == 0 then
    vim.notify("No visual selection", vim.log.levels.WARN)
    return
  end
  M._create_task(s, e)
end

function M.generate_task_operator(_type)
  local s = vim.fn.line("'[")
  local e = vim.fn.line("']")
  if s == 0 or e == 0 then
    vim.notify("No selection", vim.log.levels.WARN)
    return
  end
  M._create_task(s, e)
end

function M._create_task_with_name(s, e)
  local name = vim.api.nvim_buf_get_name(0)
  local rel_path = vim.fn.fnamemodify(name, ":.")
  local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
  if #lines == 0 then
    vim.notify("Empty selection", vim.log.levels.WARN)
    return
  end
  local selection = table.concat(lines, "\n")
  local project_root = utils.get_project_root() or vim.fn.getcwd()
  local ft = vim.bo.filetype or ""

  local reference = "From `" .. rel_path .. ":" .. s .. "-" .. e .. "`:\n\n```" .. ft .. "\n" .. selection .. "\n```"

  vim.ui.input({ prompt = "Task name: " }, function(title)
    if not title or title == "" then return end
    open_or_create_session(project_root, {
      prompt = reference,
      title = title,
      no_send = true,
      split = true,
    })
    vim.notify("Task captured: " .. title, vim.log.levels.INFO)
  end)
end

function M.generate_task_with_name_operator(_type)
  local s = vim.fn.line("'[")
  local e = vim.fn.line("']")
  if s == 0 or e == 0 then
    vim.notify("No selection", vim.log.levels.WARN)
    return
  end
  M._create_task_with_name(s, e)
end

function M.ga_operator()
  _G._djinni_ga_operatorfunc = M.generate_task_operator
  vim.o.operatorfunc = "v:lua._djinni_ga_operatorfunc"
  return "g@"
end

function M.gac_operator()
  _G._djinni_gac_operatorfunc = M.generate_task_with_name_operator
  vim.o.operatorfunc = "v:lua._djinni_gac_operatorfunc"
  return "g@"
end

function M.send_selection_to_chat()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  local name = vim.api.nvim_buf_get_name(0)
  local rel_path = vim.fn.fnamemodify(name, ":.")
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    vim.notify("[djinni] Empty selection", vim.log.levels.WARN)
    return
  end

  local ft = vim.bo.filetype or ""
  local selection = table.concat(lines, "\n")
  local text = "From `" .. rel_path .. ":" .. start_line .. "-" .. end_line .. "`:\n\n```" .. ft .. "\n" .. selection .. "\n```"
  local chat_buf = find_neowork_buf()

  if not chat_buf then
    vim.notify("[djinni] No open neowork session found", vim.log.levels.WARN)
    return
  end

  append_compose_text(chat_buf, text)
end

function M.send_selection_to_compose()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  local name = vim.api.nvim_buf_get_name(0)
  local rel_path = vim.fn.fnamemodify(name, ":.")
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    vim.notify("[djinni] Empty selection", vim.log.levels.WARN)
    return
  end

  local ft = vim.bo.filetype or ""
  local selection = table.concat(lines, "\n")
  local text = "From `" .. rel_path .. ":" .. start_line .. "-" .. end_line .. "`:\n\n```" .. ft .. "\n" .. selection .. "\n```"

  local ok = require("djinni.nowork.compose").append_text(text)
  if not ok then
    vim.notify("[djinni] No open compose buffer", vim.log.levels.WARN)
  end
end

return M
