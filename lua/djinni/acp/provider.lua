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
    command = "agent",
    args = { "acp" },
    models = {},
    resume = { method = "session/load", needs_cwd = true },
    static_models = {
      { id = "claude-3.5-sonnet",  label = "claude-3.5-sonnet" },
      { id = "claude-3-opus",      label = "claude-3-opus" },
      { id = "claude-3-haiku",     label = "claude-3-haiku" },
      { id = "gpt-4o",             label = "gpt-4o" },
      { id = "gpt-4o-mini",        label = "gpt-4o-mini" },
      { id = "o1",                 label = "o1" },
      { id = "o1-mini",            label = "o1-mini" },
      { id = "gemini-1.5-pro",     label = "gemini-1.5-pro" },
      { id = "gemini-2.0-flash",   label = "gemini-2.0-flash" },
      { id = "cursor-small",       label = "cursor-small" },
    },
  },
}

function M.list()
  local names = {}
  for name, cfg in pairs(M.providers) do
    if vim.fn.executable(cfg.command) == 1 then
      table.insert(names, name)
    end
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

function M.list_models(session_models, provider_name)
  local items = {}
  if session_models then
    if session_models.optionId and session_models.options then
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
    else
      local ids = iter_model_ids(session_models)
      for _, id in ipairs(ids) do
        items[#items + 1] = { id = id, label = id }
      end
    end
  end
  if #items == 0 and provider_name then
    local p = M.providers[provider_name]
    if p and p.static_models then
      for _, m in ipairs(p.static_models) do
        items[#items + 1] = { id = m.id, label = m.label or m.id }
      end
    end
  end
  return items
end

return M
