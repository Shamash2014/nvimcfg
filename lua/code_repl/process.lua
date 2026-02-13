local M = {}

-- Process class for managing individual REPL instances
local Process = {}
Process.__index = Process

function Process.new(language, config)
  local self = setmetatable({}, Process)
  
  self.language = language
  self.config = config
  self.job_id = nil
  self.visible = false
  self.win = nil
  self.buf = nil
  
  return self
end

function Process:start()
  if self.job_id then
    return false -- Already running
  end
  
  local cmd = self.config.cmd
  local args = self.config.args or {}
  
  self.job_id = vim.fn.jobstart({ cmd, unpack(args) }, {
    stdin = "pipe",
    stdout_buffered = false,
    on_stdout = function(_, data)
      self:_handle_output(data)
    end,
    on_stderr = function(_, data)
      self:_handle_error(data)
    end,
    on_exit = function(_, code)
      self:_handle_exit(code)
    end,
  })
  
  return self.job_id > 0
end

function Process:send(input)
  if not self.job_id then
    return nil, "REPL not started"
  end
  
  -- Add newline if not present
  if not input:match("\n$") then
    input = input .. "\n"
  end
  
  vim.fn.chansend(self.job_id, input)
  return true
end

function Process:kill()
  if self.job_id then
    vim.fn.jobstop(self.job_id)
    self.job_id = nil
  end
  
  self:_close_window()
end

function Process:restart()
  self:kill()
  vim.defer_fn(function()
    self:start()
  end, 100)
end

function Process:is_alive()
  return self.job_id ~= nil
end

function Process:is_visible()
  return self.visible and self.win and vim.api.nvim_win_is_valid(self.win)
end

function Process:show()
  if self:is_visible() then
    return
  end
  
  self:_create_window()
  self.visible = true
end

function Process:hide()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
    self.win = nil
  end
  self.visible = false
end

-- Internal methods
function Process:_handle_output(data)
  -- Parse output to extract results
  -- This will be called by the registry to capture results
  if self.on_output then
    self:on_output(data)
  end
end

function Process:_handle_error(data)
  if self.on_error then
    self:on_error(data)
  end
end

function Process:_handle_exit(code)
  if self.on_exit then
    self:on_exit(code)
  end
end

function Process:_create_window()
  -- Create a split window for the REPL
  vim.cmd("botright 10split")
  self.win = vim.api.nvim_get_current_win()
  
  -- Start the REPL in the window using termopen
  -- This creates and initializes the terminal buffer properly
  local cmd = self.config.cmd
  local args = self.config.args or {}
  
  -- Build command array for termopen
  local full_cmd = { cmd }
  vim.list_extend(full_cmd, args)
  
  vim.fn.termopen(full_cmd, {
    cwd = vim.fn.getcwd(),
    on_exit = function(_, code)
      self:_handle_exit(code)
    end,
  })
  
  -- Get the buffer that termopen created
  self.buf = vim.api.nvim_get_current_buf()
  
  -- Set buffer options
  vim.bo[self.buf].swapfile = false
  vim.bo[self.buf].bufhidden = "hide"
  
  -- Set window options
  vim.wo[self.win].number = false
  vim.wo[self.win].relativenumber = false
  vim.wo[self.win].signcolumn = "no"
end

function Process:_close_window()
  self:hide()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end
end

return Process
