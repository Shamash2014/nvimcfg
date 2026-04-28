local M = {}

M.providers = {
  ["claude-code"] = {
    command = "claude-agent-acp",
    models = {},
    resume = { method = "session/resume" },
    plan_mode = "plan",
  },
  ["opencode"] = {
    command = "opencode",
    args = { "acp" },
    models = {},
    resume = { method = "session/load", needs_cwd = true },
    plan_mode = "plan",
  },
  ["codex"] = {
    command = "codex-acp",
    args = {},
    models = {},
    resume = { method = "session/load", needs_cwd = true },
    plan_mode = "read-only",
  },
  ["hermes"] = {
    command = "hermes",
    args = { "acp" },
    models = {},
    resume = { method = "session/load", needs_cwd = true },
    plan_mode = "plan",
  },
  ["cursor"] = {
    command = "agent",
    args = { "acp" },
    models = {},
    resume = { method = "session/load", needs_cwd = true },
    plan_mode = "plan",
    static_models = {
      { id = "claude-opus-4-6",    label = "claude-opus-4-6" },
      { id = "claude-sonnet-4-6",  label = "claude-sonnet-4-6" },
      { id = "claude-haiku-4-5",   label = "claude-haiku-4-5" },
      { id = "gpt-4o",             label = "gpt-4o" },
      { id = "gpt-4o-mini",        label = "gpt-4o-mini" },
      { id = "o3",                 label = "o3" },
      { id = "o3-mini",            label = "o3-mini" },
      { id = "gemini-2.5-pro",     label = "gemini-2.5-pro" },
      { id = "gemini-2.0-flash",   label = "gemini-2.0-flash" },
      { id = "cursor-small",       label = "cursor-small" },
    },
  },
  ["gemini"] = {
    command = "gemini-acp",
    args = {},
    models = {},
    resume = { method = "session/load", needs_cwd = true },
    plan_mode = "plan",
    static_models = {
      { id = "gemini-2.5-pro",    label = "gemini-2.5-pro" },
      { id = "gemini-2.0-flash",  label = "gemini-2.0-flash" },
    },
  },
  ["aider"] = {
    command = "aider-acp",
    args = {},
    models = {},
    resume = { method = "session/load", needs_cwd = true },
    plan_mode = "plan",
  },
}

local function merged_providers()
  local ok, djinni = pcall(require, "djinni")
  local cfg = ok and djinni and djinni.config and djinni.config.acp or nil
  local user = cfg and cfg.providers or nil
  if type(user) ~= "table" or next(user) == nil then
    return M.providers
  end
  return vim.tbl_deep_extend("force", {}, M.providers, user)
end

function M.list()
  local names = {}
  for name, cfg in pairs(merged_providers()) do
    if vim.fn.executable(cfg.command) == 1 then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function M.get(name)
  local providers = merged_providers()
  return providers[name] or providers["claude-code"]
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
  local p = merged_providers()[provider_name]
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
      local models = session_models.availableModels or session_models
      if type(models) == "table" and #models > 0 then
        for _, m in ipairs(models) do
          if type(m) == "string" then
            items[#items + 1] = { id = m, label = m }
          elseif m.modelId or m.id then
            local id = m.modelId or m.id
            local label = m.name or id
            items[#items + 1] = { id = id, label = label }
          end
        end
      end
    end
  end
  if #items == 0 and provider_name then
    local p = merged_providers()[provider_name]
    if p and p.static_models then
      for _, m in ipairs(p.static_models) do
        items[#items + 1] = { id = m.id, label = m.label or m.id }
      end
    end
    if p and type(p.models) == "table" and next(p.models) ~= nil then
      for alias, target in pairs(p.models) do
        if type(alias) == "string" and alias ~= "" and type(target) == "string" and target ~= "" then
          items[#items + 1] = { id = alias, label = alias .. " → " .. target }
        end
      end
    end
  end
  if #items == 0 then
    return items
  end

  local by_id = {}
  local order = {}
  for _, it in ipairs(items) do
    if it and it.id and it.id ~= "" then
      if not by_id[it.id] then
        by_id[it.id] = { id = it.id, label = it.label or it.id }
        order[#order + 1] = it.id
      else
        local existing = by_id[it.id]
        local label = it.label or it.id
        if existing.label == existing.id and label ~= existing.id then
          existing.label = label
        end
      end
    end
  end

  local out = {}
  local label_counts = {}
  for _, id in ipairs(order) do
    local it = by_id[id]
    if it then
      label_counts[it.label] = (label_counts[it.label] or 0) + 1
      out[#out + 1] = it
    end
  end

  for _, it in ipairs(out) do
    if label_counts[it.label] and label_counts[it.label] > 1 and it.label ~= it.id then
      it.label = it.label .. " (" .. it.id .. ")"
    end
  end

  table.sort(out, function(a, b)
    local al = (a.label or a.id or ""):lower()
    local bl = (b.label or b.id or ""):lower()
    if al == bl then
      return (a.id or "") < (b.id or "")
    end
    return al < bl
  end)

  return out
end

return M
