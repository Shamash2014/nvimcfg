local M = {}

-- Cache frequently used functions
local executable_cache = {}
local function cached_executable(cmd)
  if executable_cache[cmd] == nil then
    executable_cache[cmd] = vim.fn.executable(cmd) == 1
  end
  return executable_cache[cmd]
end

-- File size detection for performance optimization
local function get_file_size(file)
  local ok, stats = pcall(vim.loop.fs_stat, file)
  if not ok or not stats then
    return 0
  end
  return stats.size
end

-- Large file detection and optimization
local function setup_large_file_handling()
  local large_file_threshold = 100 * 1024 -- 100KB
  local very_large_file_threshold = 500 * 1024 -- 500KB
  local huge_file_threshold = 1024 * 1024 -- 1MB

  vim.api.nvim_create_autocmd("BufReadPre", {
    callback = function(args)
      local file = args.file
      local size = get_file_size(file)
      
      if size > large_file_threshold then
        -- Disable expensive features for large files
        vim.schedule(function()
          vim.bo[args.buf].syntax = "off"
          vim.bo[args.buf].swapfile = false
          vim.bo[args.buf].undofile = false
          vim.bo[args.buf].foldmethod = "manual"
          vim.wo.foldcolumn = "0"
          vim.wo.signcolumn = "no"
          vim.wo.colorcolumn = ""
          vim.wo.cursorline = false
          vim.wo.relativenumber = false
          
          -- Disable treesitter for very large files
          if size > very_large_file_threshold then
            vim.b[args.buf].large_file = true
            vim.api.nvim_buf_set_var(args.buf, "large_file", true)
          end
          
          -- Disable LSP for huge files
          if size > huge_file_threshold then
            vim.schedule(function()
              local clients = vim.lsp.get_clients({ bufnr = args.buf })
              for _, client in ipairs(clients) do
                vim.lsp.buf_detach_client(args.buf, client.id)
              end
            end)
          end
        end)
      end
    end,
  })
end

-- Startup time monitoring
local function track_startup_time()
  vim.defer_fn(function()
    local stats = require("lazy").stats()
    local startup_time = stats.startuptime
    local plugin_count = stats.count
    
    -- Only show if startup is slow
    if startup_time > 150 then
      vim.notify(
        string.format("Startup: %.2fms | Plugins: %d | Memory: %.1fMB", 
          startup_time, plugin_count, vim.fn.luaeval("collectgarbage('count')") / 1024),
        vim.log.levels.INFO
      )
    end
  end, 100)
end

-- Memory optimization
local function optimize_memory()
  -- Garbage collection tuning
  vim.schedule(function()
    -- Force garbage collection after startup
    collectgarbage("collect")
    
    -- Set up periodic garbage collection
    local gc_timer = vim.loop.new_timer()
    gc_timer:start(60000, 60000, function() -- Every 60 seconds
      vim.schedule(function()
        collectgarbage("step", 100)
      end)
    end)
  end)
end

-- Async file operations
local function setup_async_operations()
  -- Async clipboard operations
  vim.schedule(function()
    if cached_executable("pbcopy") or cached_executable("xclip") or cached_executable("wl-copy") then
      vim.g.clipboard = {
        name = "async",
        copy = {
          ["+"] = function(lines)
            vim.schedule(function()
              vim.fn.setreg("+", lines, "V")
            end)
          end,
          ["*"] = function(lines)
            vim.schedule(function()
              vim.fn.setreg("*", lines, "V")
            end)
          end,
        },
        paste = {
          ["+"] = function()
            return vim.fn.getreg("+", 1, true)
          end,
          ["*"] = function()
            return vim.fn.getreg("*", 1, true)
          end,
        },
      }
    end
  end)
end

-- Optimize redraw performance
local function optimize_redraw()
  -- Reduce unnecessary redraws
  vim.api.nvim_create_autocmd("CursorHold", {
    callback = function()
      if vim.bo.modified then
        vim.cmd.redraw()
      end
    end,
  })
  
  -- Smart cursor line only in focused window
  vim.api.nvim_create_autocmd({ "WinEnter", "FocusGained" }, {
    callback = function()
      vim.wo.cursorline = true
    end,
  })
  
  vim.api.nvim_create_autocmd({ "WinLeave", "FocusLost" }, {
    callback = function()
      vim.wo.cursorline = false
    end,
  })
end

-- Buffer management optimization
local function optimize_buffers()
  -- Auto-close unused buffers
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
      local buffers = vim.api.nvim_list_bufs()
      local loaded_count = 0
      
      for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_loaded(buf) then
          loaded_count = loaded_count + 1
        end
      end
      
      -- Close unused buffers if we have too many
      if loaded_count > 10 then
        for _, buf in ipairs(buffers) do
          if vim.api.nvim_buf_is_loaded(buf) 
            and not vim.bo[buf].modified 
            and vim.fn.buflisted(buf) == 0 then
            vim.api.nvim_buf_delete(buf, { force = true })
          end
        end
      end
    end,
  })
end

-- Initialize all performance optimizations
function M.setup()
  setup_large_file_handling()
  track_startup_time()
  optimize_memory()
  setup_async_operations()
  optimize_redraw()
  optimize_buffers()
end

return M