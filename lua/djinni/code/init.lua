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

  local reference = "From `" .. rel_path .. ":" .. s .. "-" .. e .. "`:\n\n```\n" .. selection .. "\n```"

  vim.notify("Adding reference from " .. rel_path .. ":" .. s .. "-" .. e, vim.log.levels.INFO)

  require("djinni.nowork.chat").create(project_root, {
    prompt = reference,
    title = "ref-" .. vim.fn.fnamemodify(rel_path, ":t:r"),
    no_send = true,
  })
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

function M.ga_operator()
  vim.o.operatorfunc = "v:lua.require'djinni.code'.generate_task_operator"
  return "g@"
end

return M
