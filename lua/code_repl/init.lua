local M = {}

-- Dependencies
local Process = require("code_repl.process")
local registry = require("code_repl.registry")
local render = require("code_repl.render")
local languages = require("code_repl.languages")

-- Configuration
local config = {
  auto_start = true,
  persist_per_project = true,
  result_max_length = 100,
  show_errors_inline = true,
  auto_detect_language = true,
  default_repl = "bash",
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  registry.setup(config)
end

-- Get language for current buffer
local function get_buffer_language(buf)
  buf = buf or 0
  local filetype = vim.bo[buf].filetype
  
  -- Map filetypes to REPL languages
  local filetype_map = {
    python = "python",
    javascript = "javascript",
    typescript = "javascript",
    javascriptreact = "javascript",
    typescriptreact = "javascript",
    lua = "lua",
    go = "go",
    gomod = "go",
    bash = "bash",
    sh = "bash",
    zsh = "bash",
    fish = "bash",
    ruby = "ruby",
    perl = "perl",
    php = "php",
  }
  
  return filetype_map[filetype] or config.default_repl
end

-- Get current line or selection
local function get_content(mode)
  mode = mode or vim.fn.mode()
  
  if mode:match("[vV]") then
    -- Visual mode: get selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local start_line = start_pos[2]
    local end_line = end_pos[2]
    
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    return table.concat(lines, "\n")
  else
    -- Normal mode: get current line
    local current_line = vim.api.nvim_get_current_line()
    return current_line
  end
end

-- Evaluate content in appropriate REPL
function M.evaluate(content, language)
  content = content or get_content()
  language = language or (config.auto_detect_language and get_buffer_language() or config.default_repl)
  
  local buf = 0
  local repl = registry.get_or_create(buf, language)
  
  if not repl then
    vim.notify("Failed to create REPL for: " .. language, vim.log.levels.ERROR)
    return
  end
  
  -- Clear previous virtual text
  render.clear_result(buf)
  
  -- Send to REPL
  local result = repl:send(content)
  
  if result then
    render.show_result(buf, result)
  end
end

-- Convenience functions
function M.evaluate_line()
  M.evaluate(get_content("n"))
end

function M.evaluate_selection()
  M.evaluate(get_content("v"))
end

function M.evaluate_visual()
  M.evaluate(get_content("V"))
end

-- Toggle REPL visibility
function M.toggle_repl()
  local buf = 0
  local language = get_buffer_language(buf)
  local repl = registry.get(buf, language)
  
  if repl then
    if repl:is_visible() then
      repl:hide()
    else
      repl:show()
    end
  else
    vim.notify("No REPL active for current buffer", vim.log.levels.WARN)
  end
end

-- Restart REPL for current buffer
function M.restart_repl()
  local buf = 0
  local language = get_buffer_language(buf)
  local repl = registry.get(buf, language)
  
  if repl then
    repl:restart()
    vim.notify("REPL restarted: " .. language, vim.log.levels.INFO)
  else
    vim.notify("No REPL to restart", vim.log.levels.WARN)
  end
end

-- Kill REPL for current buffer
function M.kill_repl()
  local buf = 0
  local language = get_buffer_language(buf)
  local repl = registry.get(buf, language)
  
  if repl then
    repl:kill()
    registry.remove(buf, language)
    vim.notify("REPL killed: " .. language, vim.log.levels.INFO)
  else
    vim.notify("No REPL to kill", vim.log.levels.WARN)
  end
end

-- Show REPL status
function M.status()
  local buf = 0
  local language = get_buffer_language(buf)
  local repl = registry.get(buf, language)
  
  if repl then
    local status = repl:is_alive() and "Running" or "Stopped"
    vim.notify(string.format("REPL [%s]: %s", language, status), vim.log.levels.INFO)
  else
    vim.notify("No REPL for current buffer", vim.log.levels.INFO)
  end
end

-- User commands
function M.create_commands()
  vim.api.nvim_create_user_command("REPLEval", function()
    M.evaluate_line()
  end, { desc = "Evaluate current line in REPL" })
  
  vim.api.nvim_create_user_command("REPLEvalVisual", function()
    M.evaluate_selection()
  end, { range = true, desc = "Evaluate selection in REPL" })
  
  vim.api.nvim_create_user_command("REPLToggle", function()
    M.toggle_repl()
  end, { desc = "Toggle REPL window" })
  
  vim.api.nvim_create_user_command("REPLRestart", function()
    M.restart_repl()
  end, { desc = "Restart current REPL" })
  
  vim.api.nvim_create_user_command("REPLKill", function()
    M.kill_repl()
  end, { desc = "Kill current REPL" })
  
  vim.api.nvim_create_user_command("REPLStatus", function()
    M.status()
  end, { desc = "Show REPL status" })
end

return M
