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

return M
