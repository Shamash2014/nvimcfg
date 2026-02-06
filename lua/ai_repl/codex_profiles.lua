local M = {}

local CONFIG_PATH = vim.fn.expand("~/.codex/config.toml")
local LAST_PROFILE_PATH = vim.fn.stdpath("data") .. "/ai_repl_codex_profile"

function M.parse_config()
  if vim.fn.filereadable(CONFIG_PATH) ~= 1 then
    return nil
  end

  local lines = vim.fn.readfile(CONFIG_PATH)

  local result = {
    model_providers = {},
    profiles = {},
  }

  local current_section = nil
  local current_name = nil

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")

    if trimmed == "" or trimmed:match("^#") then
      goto continue
    end

    local provider_match = trimmed:match("^%[model_providers%.([^%]]+)%]$")
    if provider_match then
      current_section = "model_providers"
      current_name = provider_match
      result.model_providers[current_name] = {}
      goto continue
    end

    local profile_match = trimmed:match("^%[profiles%.([^%]]+)%]$")
    if profile_match then
      current_section = "profiles"
      current_name = profile_match
      result.profiles[current_name] = {}
      goto continue
    end

    local other_section = trimmed:match("^%[([^%]]+)%]$")
    if other_section then
      current_section = nil
      current_name = nil
      goto continue
    end

    if current_section and current_name then
      local key, value = trimmed:match("^([%w_]+)%s*=%s*(.+)$")
      if key and value then
        value = value:gsub('^"(.+)"$', "%1")
        value = value:gsub("^'(.+)'$", "%1")

        if value:match("^%d+$") then
          value = tonumber(value)
        end

        result[current_section][current_name][key] = value
      end
    end

    ::continue::
  end

  return result
end

function M.list_profiles()
  local config = M.parse_config()
  if not config then
    return {}
  end

  local profiles = {}

  for profile_id, profile_data in pairs(config.profiles) do
    local model = profile_data.model or "unknown"
    local model_provider = profile_data.model_provider
    local provider_display = model_provider

    if model_provider and config.model_providers[model_provider] then
      local mp = config.model_providers[model_provider]
      provider_display = mp.name or model_provider
    end

    table.insert(profiles, {
      id = profile_id,
      name = profile_id,
      model = model,
      model_provider = model_provider,
      provider_display = provider_display,
      context_window = profile_data.model_context_window,
    })
  end

  table.sort(profiles, function(a, b)
    return a.name < b.name
  end)

  return profiles
end

function M.build_args(profile_id)
  if not profile_id or profile_id == "" then
    return {}
  end
  return { "-c", 'profile="' .. profile_id .. '"' }
end

function M.get_last_profile()
  local f = io.open(LAST_PROFILE_PATH, "r")
  if f then
    local profile = f:read("*l")
    f:close()
    return profile ~= "" and profile or nil
  end
  return nil
end

function M.set_last_profile(profile_id)
  local f = io.open(LAST_PROFILE_PATH, "w")
  if f then
    f:write(profile_id or "")
    f:close()
  end
end

function M.format_profile_label(profile)
  local label = profile.name
  if profile.model then
    label = label .. " [" .. profile.model .. "]"
  end
  if profile.provider_display then
    label = label .. " via " .. profile.provider_display
  end
  return label
end

return M
