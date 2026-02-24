local M = {}

local registry = require("ai_repl.registry")

-- Session strategies:
-- - "new": Always create a new session
-- - "latest": Reuse the most recent active session
-- - "prompt": Ask user which session to use
-- - "new-deferred": Create session on first message (lazy init)

function M.get_or_create_session(strategy, cwd, callback)
  strategy = strategy or "latest"

  if strategy == "new" then
    return M._create_new_session(cwd, callback)
  elseif strategy == "latest" then
    return M._get_latest_session(cwd, callback)
  elseif strategy == "prompt" then
    return M._prompt_for_session(cwd, callback)
  elseif strategy == "new-deferred" then
    -- Return nil to signal deferred creation
    callback(nil)
  else
    -- Default to latest
    return M._get_latest_session(cwd, callback)
  end
end

function M._create_new_session(cwd, callback)
  local ai_repl = require("ai_repl.init")
  ai_repl.pick_provider(function(provider_id)
    if not provider_id then
      callback(nil)
      return
    end

    vim.notify("[Session Strategy] Creating new session...", vim.log.levels.INFO)
    ai_repl.new_session(provider_id)

    -- Wait for session to be ready
    vim.defer_fn(function()
      local proc = registry.active()
      if proc then
        M._wait_for_ready(proc, callback)
      else
        callback(nil)
      end
    end, 100)
  end)
end

function M._get_latest_session(cwd, callback)
  -- Find existing session for this project
  local proc_for_project = nil
  for sid, p in pairs(registry.all()) do
    if p:is_alive() and p.data.cwd == cwd then
      proc_for_project = p
      break
    end
  end

  if proc_for_project and proc_for_project:is_ready() then
    vim.notify("[Session Strategy] Using existing session", vim.log.levels.INFO)
    callback(proc_for_project)
  else
    -- No session exists, create one
    vim.notify("[Session Strategy] No existing session found, creating new one...", vim.log.levels.INFO)
    M._create_new_session(cwd, callback)
  end
end

function M._prompt_for_session(cwd, callback)
  -- Get all active sessions
  local sessions = {}
  for sid, p in pairs(registry.all()) do
    if p:is_alive() then
      local providers = require("ai_repl.providers")
      local provider_cfg = providers.get(p.data.provider) or {}
      local provider_name = provider_cfg.name or p.data.provider
      local same_project = p.data.cwd == cwd
      local label = string.format("%s%s - %s",
        same_project and "✓ " or "  ",
        provider_name,
        vim.fn.fnamemodify(p.data.cwd, ":t")
      )
      table.insert(sessions, {
        label = label,
        proc = p,
      })
    end
  end

  -- Add "Create New Session" option
  table.insert(sessions, 1, {
    label = "+ Create New Session",
    proc = nil,
  })

  if #sessions == 1 then
    -- Only "Create New Session" option
    M._create_new_session(cwd, callback)
    return
  end

  -- Show picker
  vim.ui.select(sessions, {
    prompt = "Select Session:",
    format_item = function(item)
      return item.label
    end,
  }, function(choice, idx)
    if not choice then
      callback(nil)
      return
    end

    if choice.proc then
      vim.notify("[Session Strategy] Using selected session", vim.log.levels.INFO)
      callback(choice.proc)
    else
      M._create_new_session(cwd, callback)
    end
  end)
end

function M._wait_for_ready(proc, callback, attempts)
  attempts = attempts or 0
  local max_attempts = 100

  if attempts >= max_attempts then
    vim.notify("[Session Strategy] Session creation timeout", vim.log.levels.ERROR)
    callback(nil)
    return
  end

  if proc:is_ready() then
    callback(proc)
  else
    vim.defer_fn(function()
      M._wait_for_ready(proc, callback, attempts + 1)
    end, 100)
  end
end

return M
