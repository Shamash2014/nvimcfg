local M = {}

local providers = {
  claude = {
    name = "Claude",
    cmd = "claude-code-acp",
    args = {},
    env = {},
  },
  cursor = {
    name = "Cursor",
    cmd = "cursor-agent-acp",
    args = {},
    env = {},
  },
}

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
