local M = {}

local providers = {
  claude = {
    name = "Claude",
    cmd = "claude-code-acp",
    args = {},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
    mcp_servers = {},
  },

  goose = {
    name = "Goose",
    cmd = "goose",
    args = {"acp"},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
    mcp_servers = {},
  },
  opencode = {
    name = "OpenCode",
    cmd = "opencode",
    args = {"acp"},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
    supports_profiles = true,
    mcp_servers = {},
  },
  codex = {
    name = "Codex",
    cmd = "codex-acp",
    args = {},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
    supports_profiles = true,
    mcp_servers = {},
  },
  droid = {
    name = "Droid",
    cmd = "droid",
    args = {"exec", "--output-format", "acp"},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
    mcp_servers = {},
  },
  stakpak = {
    name = "Stakpak",
    cmd = "stakpak",
    args = {"acp"},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
    mcp_servers = {},
  },
  fastagent = {
    name = "Fast Agent",
    cmd = "uvx",
    args = {"fast-agent-acp@latest", "--model", "glm-4"},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
    mcp_servers = {},
  },
  pi = {
    name = "Pi",
    cmd = "npx",
    args = {"-y", "pi-acp"},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
    mcp_servers = {},
  },
}

-- Helper to get provider config with fallback to defaults
function M.get_config(id)
  local provider = providers[id]
  if not provider then
    return nil
  end

  return {
    name = provider.name,
    cmd = provider.cmd,
    args = provider.args or {},
    env = provider.env or {},
    permission_mode = provider.permission_mode or "default",
    background_permissions = provider.background_permissions or "allow_once",
    mcp_servers = provider.mcp_servers or {},
  }
end

function M.get(id)
  return providers[id]
end

function M.list()
  local result = {}
  for id, p in pairs(providers) do
    table.insert(result, vim.tbl_extend("force", { id = id }, p))
  end
  return result
end

function M.register(id, provider)
  providers[id] = provider
end

function M.supports_profiles(id)
  local provider = providers[id]
  return provider and provider.supports_profiles == true
end

function M.set_providers(new_providers)
  for id, p in pairs(new_providers) do
    providers[id] = vim.tbl_extend("force", providers[id] or {}, p)
  end
end

return M
