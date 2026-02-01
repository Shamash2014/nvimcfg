local M = {}

local providers = {
  claude = {
    name = "Claude",
    cmd = "claude-code-acp",
    args = {},
    env = {},
    -- Permission settings: "default", "bypassPermissions", "dontAsk"
    permission_mode = "default",
    -- Background permissions: "allow_always", "allow_once", "respect_agent"
    background_permissions = "allow_once",
  },

  goose = {
    name = "Goose",
    cmd = "goose",
    args = {"acp"},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
  },
  opencode = {
    name = "OpenCode",
    cmd = "opencode",
    args = {"acp"},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
  },
  codex = {
    name = "Codex",
    cmd = "codex-acp",
    args = {},
    env = {},
    permission_mode = "default",
    background_permissions = "allow_once",
  },
  stakpak = {
    name = "StakPak",
    cmd = "stakpak",
    args = {"acp"},
    env = {
      STAKPAK_API_KEY = os.getenv("STAKPAK_API_KEY") or "",
    },
    permission_mode = "default",
    background_permissions = "allow_once",
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

function M.set_providers(new_providers)
  for id, p in pairs(new_providers) do
    providers[id] = vim.tbl_extend("force", providers[id] or {}, p)
  end
end

return M
