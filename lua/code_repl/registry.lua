local M = {}

-- Registry for managing REPL instances per buffer/project
local registry = {
  -- repls[buf][language] = Process
  repls = {},
  config = {},
}

function M.setup(config)
  registry.config = config
  
  -- Cleanup on buffer unload
  vim.api.nvim_create_autocmd("BufUnload", {
    callback = function(args)
      M.cleanup_buffer(args.buf)
    end,
  })
  
  -- Cleanup on vim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.cleanup_all()
    end,
  })
end

function M.get_or_create(buf, language)
  buf = buf or 0
  local repls = registry.repls[buf] or {}
  
  if repls[language] then
    return repls[language]
  end
  
  -- Create new REPL
  local languages = require("code_repl.languages")
  local lang_config = languages.get(language)
  
  if not lang_config then
    vim.notify("Unknown REPL language: " .. language, vim.log.levels.ERROR)
    return nil
  end
  
  local Process = require("code_repl.process")
  local repl = Process.new(language, lang_config)
  
  -- Setup output handler to capture results
  local last_output = {}
  local output_buffer = {}
  
  repl.on_output = function(_, data)
    -- Collect output
    for _, line in ipairs(data) do
      if line and line ~= "" then
        table.insert(output_buffer, line)
      end
    end
  end
  
  -- Start the REPL
  if repl:start() then
    repls[language] = repl
    registry.repls[buf] = repls
    
    vim.notify("REPL started: " .. language, vim.log.levels.INFO)
    return repl
  else
    vim.notify("Failed to start REPL: " .. language, vim.log.levels.ERROR)
    return nil
  end
end

function M.get(buf, language)
  buf = buf or 0
  local repls = registry.repls[buf]
  if repls then
    return repls[language]
  end
  return nil
end

function M.remove(buf, language)
  buf = buf or 0
  local repls = registry.repls[buf]
  if repls and repls[language] then
    repls[language]:kill()
    repls[language] = nil
  end
end

function M.cleanup_buffer(buf)
  if registry.repls[buf] then
    for language, repl in pairs(registry.repls[buf]) do
      repl:kill()
    end
    registry.repls[buf] = nil
  end
end

function M.cleanup_all()
  for buf, repls in pairs(registry.repls) do
    for language, repl in pairs(repls) do
      repl:kill()
    end
  end
  registry.repls = {}
end

function M.list()
  local list = {}
  for buf, repls in pairs(registry.repls) do
    for language, repl in pairs(repls) do
      table.insert(list, {
        buf = buf,
        language = language,
        alive = repl:is_alive(),
      })
    end
  end
  return list
end

return M
