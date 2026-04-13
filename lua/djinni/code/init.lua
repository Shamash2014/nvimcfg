local utils = require("core.utils")

local M = {}

function M.create_with_file()
  local name = vim.api.nvim_buf_get_name(0)
  local rel_path = vim.fn.fnamemodify(name, ":.")
  local project_root = utils.get_project_root() or vim.fn.getcwd()

  vim.ui.input({ prompt = "Task: " }, function(prompt)
    if not prompt or prompt == "" then return end
    require("djinni.nowork.chat").create(project_root, {
      prompt = prompt,
      context_file = rel_path,
      split = true,
    })
  end)
end

function M.create_with_selection()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  local name = vim.api.nvim_buf_get_name(0)
  local rel_path = vim.fn.fnamemodify(name, ":.")
  local project_root = utils.get_project_root() or vim.fn.getcwd()

  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  vim.ui.input({ prompt = "Task: " }, function(prompt)
    if not prompt or prompt == "" then return end
    require("djinni.nowork.chat").create(project_root, {
      prompt = prompt,
      context_selection = rel_path .. ":" .. start_line .. "-" .. end_line,
      split = true,
    })
  end)
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

  require("djinni.nowork.chat").create(project_root, {
    prompt = reference,
    title = title,
    no_send = true,
    silent = true,
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
    require("djinni.nowork.chat").create(project_root, {
      prompt = reference,
      title = title,
      no_send = true,
      silent = true,
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

  local chat_buf = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local wb = vim.api.nvim_win_get_buf(win)
    if vim.bo[wb].filetype == "nowork-chat" then
      chat_buf = wb
      break
    end
  end

  if not chat_buf then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "nowork-chat" then
        chat_buf = b
        break
      end
    end
  end

  if not chat_buf then
    vim.notify("[djinni] No open chat buffer found", vim.log.levels.WARN)
    return
  end

  require("djinni.nowork.chat").quick_input_text(chat_buf, text)
end

return M
