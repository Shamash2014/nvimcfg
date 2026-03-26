local M = {}

M.providers = {
  ["claude-code"] = {
    command = "claude-agent-acp",
    args = {},
  },
  ["opencode"] = {
    command = "opencode-acp",
    args = {},
  },
  ["cursor"] = {
    command = "cursor-acp",
    args = {},
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

return M
