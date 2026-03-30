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

local function iter_model_ids(session_models)
  if not session_models then return {} end
  if session_models.optionId and session_models.options then
    local ids = {}
    for _, opt in ipairs(session_models.options) do
      local id = opt.value or opt.id
      if id then ids[#ids + 1] = id end
    end
    return ids
  end
  local models = session_models.availableModels or session_models
  if type(models) == "table" and #models > 0 then
    local ids = {}
    for _, m in ipairs(models) do
      if type(m) == "string" then
        ids[#ids + 1] = m
      elseif m.modelId then
        ids[#ids + 1] = m.modelId
      elseif m.id then
        ids[#ids + 1] = m.id
      end
    end
    return ids
  end
  return {}
end

function M.resolve_model(provider_name, alias, session_models)
  if not alias or alias == "" then return nil end
  local p = M.providers[provider_name]
  local expanded = (p and p.models and p.models[alias]) or alias
  if session_models then
    local ids = iter_model_ids(session_models)
    if #ids > 0 then
      for _, id in ipairs(ids) do
        if id == alias then return alias end
      end
      for _, id in ipairs(ids) do
        if id == expanded then return expanded end
      end
      return nil
    end
  end
  return expanded
end

function M.list_models(session_models)
  if not session_models then return {} end
  if session_models.optionId and session_models.options then
    local items = {}
    for _, opt in ipairs(session_models.options) do
      local id = opt.value or opt.id
      if id then
        local label = opt.name or id
        if opt.description and opt.description ~= "" then
          label = label .. " — " .. opt.description
        end
        items[#items + 1] = { id = id, label = label }
      end
    end
    return items
  end
  local ids = iter_model_ids(session_models)
  local items = {}
  for _, id in ipairs(ids) do
    items[#items + 1] = { id = id, label = id }
  end
  return items
end

return M
