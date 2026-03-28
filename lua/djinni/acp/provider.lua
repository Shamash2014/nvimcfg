local M = {}

M.providers = {
  ["claude-code"] = {
    command = "claude-agent-acp",
    args = {},
    models = {},
    resume = { method = "session/resume" },
  },
  ["opencode"] = {
    command = "opencode",
    args = { "acp" },
    models = {},
    resume = { method = "session/load", needs_cwd = true },
  },
  ["cursor"] = {
    command = "cursor-acp",
    args = {},
    models = {},
    resume = { method = "session/resume" },
  },
}

function M.list()
  local names = {}
  for name in pairs(M.providers) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.get(name)
  return M.providers[name] or M.providers["claude-code"]
end

function M.register(name, config)
  M.providers[name] = config
end

function M.resolve_model(provider_name, alias, session_models)
  if not alias or alias == "" then return nil end
  local p = M.providers[provider_name]
  local expanded = (p and p.models and p.models[alias]) or alias
  if session_models and session_models.availableModels then
    for _, m in ipairs(session_models.availableModels) do
      if m.modelId == alias then return alias end
    end
    for _, m in ipairs(session_models.availableModels) do
      if m.modelId == expanded then return expanded end
    end
    return nil
  end
  return expanded
end

function M.list_models(session_models)
  if not session_models or not session_models.availableModels then return {} end
  local result = {}
  for _, m in ipairs(session_models.availableModels) do
    result[#result + 1] = m.modelId
  end
  return result
end

return M
