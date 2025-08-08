-- Performance monitoring and optimization for Neovim startup
local M = {}

-- Store startup time
local start_time = vim.loop.hrtime()

-- Function to measure and report startup time
function M.report_startup()
  local end_time = vim.loop.hrtime()
  local startup_time = (end_time - start_time) / 1e6 -- Convert to milliseconds
  
  -- Memory usage
  local mem_usage = collectgarbage("count") / 1024 -- Convert to MB
  
  -- Always show startup metrics in a compact format
  local msg = string.format("⚡ %.0fms | 🧠 %.1fMB", startup_time, mem_usage)
  
  -- Color code based on performance
  local level = vim.log.levels.INFO
  if startup_time > 150 then
    level = vim.log.levels.WARN
  elseif startup_time < 50 then
    msg = msg .. " 🚀"
  end
  
  vim.notify(msg, level)
end

-- Large file optimization with tiered approach
function M.optimize_large_files()
  vim.api.nvim_create_autocmd("BufReadPre", {
    callback = function(ev)
      local file = vim.fn.expand("<afile>")
      local size = vim.fn.getfsize(file)
      local bufnr = ev.buf
      
      -- Tiered optimization based on file size
      if size > 10 * 1024 * 1024 then -- > 10MB: Maximum optimizations
        vim.b[bufnr].large_file = true
        vim.opt_local.syntax = "off"
        vim.opt_local.filetype = "off"
        vim.opt_local.spell = false
        vim.opt_local.swapfile = false
        vim.opt_local.undofile = false
        vim.opt_local.backup = false
        vim.opt_local.writebackup = false
        vim.opt_local.foldmethod = "manual"
        vim.opt_local.list = false
        vim.opt_local.relativenumber = false
        vim.opt_local.colorcolumn = ""
        vim.opt_local.signcolumn = "no"
        vim.cmd("TSBufDisable highlight")
        vim.cmd("TSBufDisable indent")
        vim.notify(string.format("🐘 Huge file (%.1fMB) - all features disabled", size / 1024 / 1024), vim.log.levels.WARN)
      elseif size > 2 * 1024 * 1024 then -- > 2MB: Heavy optimizations
        vim.b[bufnr].large_file = true
        vim.opt_local.syntax = "off"
        vim.opt_local.spell = false
        vim.opt_local.swapfile = false
        vim.opt_local.undofile = false
        vim.opt_local.foldmethod = "manual"
        vim.opt_local.relativenumber = false
        vim.cmd("TSBufDisable highlight")
        vim.notify(string.format("📄 Large file (%.1fMB) - syntax disabled", size / 1024 / 1024), vim.log.levels.INFO)
      elseif size > 500 * 1024 then -- > 500KB: Light optimizations
        vim.opt_local.spell = false
        vim.opt_local.swapfile = false
        vim.opt_local.foldmethod = "manual"
        vim.notify(string.format("📋 Medium file (%.0fKB) - light optimizations", size / 1024), vim.log.levels.INFO)
      end
    end,
  })
  
  -- Disable LSP for very large files
  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
      if vim.b[args.buf].large_file then
        vim.schedule(function()
          vim.lsp.buf_detach_client(args.buf, args.data.client_id)
          vim.notify("LSP detached for large file", vim.log.levels.INFO)
        end)
      end
    end,
  })
end

-- Defer non-essential features with staged loading
function M.defer_non_essential()
  -- Stage 1: Immediate post-startup (50ms)
  vim.defer_fn(function()
    vim.opt.cursorline = true
    vim.opt.showmode = false
  end, 50)
  
  -- Stage 2: Early features (150ms)
  vim.defer_fn(function()
    -- Load matchparen if needed
    if vim.fn.exists(":DoMatchParen") == 2 then
      vim.cmd("DoMatchParen")
    end
  end, 150)
  
  -- Stage 3: Background features (500ms)
  vim.defer_fn(function()
    -- Trigger garbage collection
    collectgarbage("collect")
  end, 500)
end

-- Enhanced caching system
local cache = {
  executable = {},
  glob = {},
  findfile = {},
  last_clear = vim.loop.hrtime()
}

-- Cache expensive function calls
function M.cached_executable(name)
  if cache.executable[name] == nil then
    cache.executable[name] = vim.fn.executable(name) == 1
  end
  return cache.executable[name]
end

-- Cache glob operations
function M.cached_glob(pattern, nosuf, list)
  local key = pattern .. (nosuf and "1" or "0") .. (list and "1" or "0")
  if cache.glob[key] == nil then
    cache.glob[key] = vim.fn.glob(pattern, nosuf, list)
  end
  return cache.glob[key]
end

-- Clear caches periodically
function M.clear_caches()
  local now = vim.loop.hrtime()
  if (now - cache.last_clear) > 60e9 then -- Clear every 60 seconds
    cache.glob = {}
    cache.findfile = {}
    cache.last_clear = now
    collectgarbage("collect")
  end
end

-- Plugin loading optimizations
function M.optimize_plugins()
  -- Fast filetype detection
  vim.g.do_filetype_lua = 1
  vim.g.did_load_filetypes = 0
  
  -- Optimize provider checks
  vim.g.loaded_python3_provider = 0
  vim.g.loaded_python_provider = 0
  vim.g.loaded_node_provider = 0
  vim.g.loaded_perl_provider = 0
  vim.g.loaded_ruby_provider = 0
  
  -- Disable remote plugins
  vim.g.loaded_remote_plugins = 1
end

-- Startup optimizations
function M.optimize_startup()
  -- Defer expensive operations
  vim.defer_fn(function()
    -- Re-enable features after startup
    vim.o.lazyredraw = false
    
    -- Setup syntax highlighting for smaller files
    if not vim.b.large_file then
      vim.cmd("syntax on")
    end
    
    -- Load treesitter highlighting conditionally
    if vim.fn.exists(":TSEnable") > 0 and not vim.b.large_file then
      vim.cmd("silent! TSEnable highlight")
    end
  end, 100)
end

-- Optimize buffer operations
function M.optimize_buffers()
  -- Auto-close unused buffers after timeout
  vim.api.nvim_create_autocmd({"BufLeave", "FocusLost"}, {
    callback = function()
      vim.defer_fn(function()
        -- Close buffers that haven't been used in 30 minutes
        local buffers = vim.fn.getbufinfo({buflisted = 1})
        local current_time = os.time()
        
        for _, buf in ipairs(buffers) do
          if buf.hidden == 1 and buf.changed == 0 then
            local last_used = buf.lastused or 0
            if current_time - last_used > 1800 then -- 30 minutes
              pcall(vim.api.nvim_buf_delete, buf.bufnr, {force = false})
            end
          end
        end
      end, 60000) -- Check after 1 minute
    end,
  })
end

-- Initialize performance optimizations
function M.setup()
  -- Apply plugin optimizations first
  M.optimize_plugins()
  
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
  
  -- Optimize startup
  M.optimize_startup()
  
  -- Setup buffer optimizations
  M.optimize_buffers()
  
  -- Periodic cache clearing
  vim.api.nvim_create_autocmd("CursorHold", {
    callback = M.clear_caches,
  })
end

return M