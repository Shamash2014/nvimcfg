-- Performance monitoring and optimization for Neovim startup
local M = {}

-- Store startup time
local start_time = vim.loop.hrtime()

-- Function to measure and report startup time
function M.report_startup()
  local end_time = vim.loop.hrtime()
  local startup_time = (end_time - start_time) / 1e6 -- Convert to milliseconds
  
  -- Only show if startup is slow
  if startup_time > 100 then
    vim.notify(string.format("Startup time: %.2fms", startup_time), vim.log.levels.INFO)
  end
end

-- Large file optimization
function M.optimize_large_files()
  vim.api.nvim_create_autocmd("BufReadPre", {
    callback = function()
      local file = vim.fn.expand("<afile>")
      local size = vim.fn.getfsize(file)
      
      -- Files larger than 500KB get performance optimizations
      if size > 500 * 1024 then
        vim.opt_local.syntax = "off"
        vim.opt_local.spell = false
        vim.opt_local.swapfile = false
        vim.opt_local.undofile = false
        vim.opt_local.backup = false
        vim.opt_local.writebackup = false
        vim.opt_local.foldmethod = "manual"
        vim.opt_local.eventignore = "all"
        vim.notify("Large file detected, performance optimizations applied", vim.log.levels.INFO)
      end
      
      -- Files larger than 2MB get more aggressive optimizations
      if size > 2 * 1024 * 1024 then
        vim.opt_local.syntax = "off"
        vim.cmd("TSBufDisable highlight")
        vim.cmd("TSBufDisable indent")
        vim.cmd("TSBufDisable incremental_selection")
        vim.cmd("TSBufDisable textobjects")
        vim.notify("Very large file detected, aggressive optimizations applied", vim.log.levels.WARN)
      end
    end,
  })
end

-- Defer non-essential features
function M.defer_non_essential()
  vim.defer_fn(function()
    -- Enable some features after startup
    vim.opt.cursorline = true
    vim.opt.cursorcolumn = false
  end, 100)
end

-- Cache expensive function calls
local executable_cache = {}
function M.cached_executable(name)
  if executable_cache[name] == nil then
    executable_cache[name] = vim.fn.executable(name) == 1
  end
  return executable_cache[name]
end

-- Initialize performance optimizations
function M.setup()
  -- Report startup time after lazy loading is complete
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyDone",
    callback = M.report_startup,
    once = true,
  })
  
  -- Setup large file optimizations
  M.optimize_large_files()
  
  -- Defer non-essential features
  M.defer_non_essential()
end

return M