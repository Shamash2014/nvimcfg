local M = {}

M.state = {
  active = false,
  file_path = nil,
  bufnr = nil,
}

local function notify(config, msg, level)
  if config.notify then
    vim.notify(msg, level)
  end
end

local function get_session_name(name)
  if name then
    return name
  end
  return "session_" .. os.date("%Y-%m-%d_%H-%M-%S")
end

function M.start(config)
  local config = require("ai_repl.annotations.config").config

  if M.state.active then
    notify(config, "Annotation session already active", vim.log.levels.WARN)
    return false
  end

  -- Check if there's an active .chat buffer to reuse
  local chat_buffer = require("ai_repl.chat_buffer")
  local existing_chat_buf = chat_buffer.get_active_chat_buffer()

  if existing_chat_buf and vim.api.nvim_buf_is_valid(existing_chat_buf) then
    -- Reuse existing .chat buffer
    M.state = {
      active = true,
      file_path = vim.api.nvim_buf_get_name(existing_chat_buf),
      bufnr = existing_chat_buf,
      name = vim.fn.fnamemodify(existing_chat_buf, ":t"),
    }

    if config.auto_open_panel then
      require("ai_repl.annotations.window").open(config, existing_chat_buf)
    end

    notify(config, "Annotation session started (using .chat buffer)", vim.log.levels.INFO)
    return true
  end

  -- Fall back to creating new annotation session
  vim.fn.mkdir(config.session_dir, "p")

  local name = get_session_name(config.session_name)
  local filename = name .. ".md"
  local file_path = config.session_dir .. "/" .. filename
  local cwd = vim.fn.getcwd()
  local title = "Annotation Session — " .. os.date("%b %d, %Y %I:%M %p")

  local header = config.format.header({
    title = title,
    file_path = file_path,
    cwd = cwd,
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
  })

  local f = io.open(file_path, "w")
  if not f then
    vim.notify("Failed to create annotation file: " .. file_path, vim.log.levels.ERROR)
    return false
  end

  f:write(table.concat(header, "\n"))
  f:close()

  local bufnr = vim.fn.bufadd(file_path)
  vim.fn.bufload(bufnr)
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].filetype = "markdown"

  M.state = {
    active = true,
    file_path = file_path,
    bufnr = bufnr,
    name = name,
  }

  if config.auto_open_panel then
    require("ai_repl.annotations.window").open(config, bufnr)
  end

  notify(config, "Annotation session started", vim.log.levels.INFO)
  return true
end

function M.stop(config)
  local config = config or require("ai_repl.annotations.config").config

  if not M.state.active then
    notify(config, "No active annotation session", vim.log.levels.WARN)
    return false
  end

  local window = require("ai_repl.annotations.window")
  window.close()

  local bufnr = M.state.bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local footer = config.format.footer({
      timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    })

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, footer)

    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write")
    end)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  M.state = {
    active = false,
    file_path = nil,
    bufnr = nil,
  }

  notify(config, "Annotation session ended", vim.log.levels.INFO)
  return true
end

function M.resume(config, file_path)
  local config = config or require("ai_repl.annotations.config").config

  if M.state.active then
    notify(config, "Annotation session already active", vim.log.levels.WARN)
    return false
  end

  if vim.fn.filereadable(file_path) ~= 1 then
    vim.notify("Session file not found: " .. file_path, vim.log.levels.ERROR)
    return false
  end

  local bufnr = vim.fn.bufadd(file_path)
  vim.fn.bufload(bufnr)
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].filetype = "markdown"

  local marker = config.format.resumed({
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
  })

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, marker)

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent write")
  end)

  M.state = {
    active = true,
    file_path = file_path,
    bufnr = bufnr,
  }

  if config.auto_open_panel then
    require("ai_repl.annotations.window").open(config, bufnr)
  end

  notify(config, "Annotation session resumed", vim.log.levels.INFO)
  return true
end

function M.get_state()
  return M.state
end

function M.is_active()
  return M.state.active
end

function M.get_bufnr()
  return M.state.bufnr
end

return M
