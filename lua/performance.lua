-- Performance monitoring and optimizations (Zed-like)

local M = {}

-- Track startup time
local start_time = vim.uv.hrtime()

function M.get_startup_time()
  local end_time = vim.uv.hrtime()
  return (end_time - start_time) / 1e6 -- Convert to milliseconds
end

-- Zed-style large file detection and optimization
function M.setup_large_file_handling()
  vim.api.nvim_create_autocmd("BufReadPre", {
    group = vim.api.nvim_create_augroup("large_file_handling", { clear = true }),
    callback = function(args)
      local buf = args.buf
      local filename = vim.api.nvim_buf_get_name(buf)
      local file_size = vim.fn.getfsize(filename)
      
      -- More aggressive optimization starting at 500KB (Zed-like)
      if file_size > 500 * 1024 then
        vim.b[buf].large_file = true
        
        -- Optimize for performance immediately
        vim.opt_local.foldenable = false
        vim.opt_local.swapfile = false
        vim.opt_local.backup = false
        vim.opt_local.writebackup = false
        vim.opt_local.undofile = false
        vim.opt_local.spell = false
        vim.opt_local.cursorline = false
        vim.opt_local.cursorcolumn = false
        vim.opt_local.list = false
        
        -- For files >1MB, disable syntax and treesitter
        if file_size > 1024 * 1024 then
          vim.opt_local.syntax = "off"
          vim.opt_local.filetype = ""
          
          vim.schedule(function()
            pcall(function()
              vim.treesitter.stop(buf)
            end)
          end)
          
          vim.notify("High-performance mode: " .. math.floor(file_size / 1024 / 1024) .. "MB file", vim.log.levels.INFO)
        end
        
        -- Disable LSP for very large files (>2MB)
        if file_size > 2 * 1024 * 1024 then
          vim.schedule(function()
            pcall(function()
              local clients = vim.lsp.get_clients({ bufnr = buf })
              for _, client in pairs(clients) do
                vim.lsp.buf_detach_client(buf, client.id)
              end
            end)
          end)
        end
      end
    end,
  })
end

-- Memory usage monitoring
function M.get_memory_usage()
  local mem_kb = vim.fn.system("ps -o rss= -p " .. vim.fn.getpid()):gsub("%s+", "")
  return tonumber(mem_kb) / 1024 -- Convert to MB
end

-- Plugin loading time tracking
function M.track_plugin_times()
  local times = {}
  local original_require = require
  
  ---@diagnostic disable-next-line: duplicate-set-field
  require = function(module)
    local start = vim.uv.hrtime()
    local result = original_require(module)
    local duration = (vim.uv.hrtime() - start) / 1e6
    
    if duration > 1 then -- Only track modules that take more than 1ms
      times[module] = duration
    end
    
    return result
  end
  
  -- Restore original require after a delay
  vim.defer_fn(function()
    require = original_require
    
    -- Sort and display slowest modules
    local sorted = {}
    for module, time in pairs(times) do
      table.insert(sorted, { module = module, time = time })
    end
    
    table.sort(sorted, function(a, b) return a.time > b.time end)
    
    if #sorted > 0 then
      print("Slowest module loads:")
      for i = 1, math.min(5, #sorted) do
        print(string.format("  %s: %.2fms", sorted[i].module, sorted[i].time))
      end
    end
  end, 5000)
end

-- Cache frequently accessed functions
function M.cache_expensive_calls()
  -- Cache vim.fn.executable calls
  local executable_cache = {}
  local original_executable = vim.fn.executable
  
  vim.fn.executable = function(cmd)
    if executable_cache[cmd] == nil then
      executable_cache[cmd] = original_executable(cmd)
    end
    return executable_cache[cmd]
  end
end

-- Setup all performance optimizations
function M.setup()
  M.setup_large_file_handling()
  M.cache_expensive_calls()
  
  -- Report startup time after everything is loaded
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyDone",
    callback = function()
      vim.schedule(function()
        local startup_time = M.get_startup_time()
        local memory_usage = M.get_memory_usage()
        
        vim.notify(
          string.format(
            "Neovim loaded in %.0fms (Memory: %.1fMB)",
            startup_time,
            memory_usage
          ),
          vim.log.levels.INFO
        )
      end)
    end,
  })
end

return M