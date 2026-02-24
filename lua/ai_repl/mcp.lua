local M = {}

local DEFAULT_MCP_SERVERS = {
}

local function normalize_server_config(server)
  if type(server) ~= "table" then
    return nil
  end

  local env = {}
  if server.env then
    if type(server.env) == "table" then
      if #server.env > 0 then
        env = server.env
      else
        local arr = {}
        for k, v in pairs(server.env) do
          table.insert(arr, { name = k, value = v })
        end
        env = arr
      end
    end
  end

  local headers = {}
  if server.headers then
    if type(server.headers) == "table" then
      if #server.headers > 0 then
        headers = server.headers
      else
        local arr = {}
        for k, v in pairs(server.headers) do
          table.insert(arr, { name = k, value = v })
        end
        headers = arr
      end
    end
  end

  local normalized = {
    type = server.type or "stdio",
    name = server.name,
    env = env,
    headers = headers,
  }

  if server.type == "http" or server.type == "https" then
    normalized.url = server.url
  elseif server.type == "stdio" then
    normalized.command = server.command or server.cmd
    normalized.args = server.args or {}
  end

  return normalized
end

function M.load_config(config_path)
  local ok, config_content = pcall(vim.fn.readfile, config_path)
  if not ok then
    return nil, "Failed to read MCP config file: " .. config_path
  end

  local json_str = table.concat(config_content, "\n")
  local ok2, config = pcall(vim.json.decode, json_str)
  if not ok2 then
    return nil, "Failed to parse MCP config JSON: " .. config_path
  end

  return config, nil
end

function M.get_servers_from_config(config)
  if not config or not config.mcpServers then
    return {}
  end

  local servers = {}
  for name, server_config in pairs(config.mcpServers) do
    local server = vim.tbl_extend("force", server_config, { name = name })
    local normalized = normalize_server_config(server)
    if normalized then
      table.insert(servers, normalized)
    end
  end

  return servers
end

function M.resolve_mcp_servers(opts)
  opts = opts or {}
  local explicit_servers = opts.mcp_servers or {}

  local all_servers = vim.deepcopy(explicit_servers)

  if opts.load_from_config then
    local config_path = opts.config_path
    if not config_path then
      local cwd = opts.cwd or vim.fn.getcwd()
      config_path = vim.fn.fnamemodify(cwd, ":p") .. "mcp.json"
    end

    if vim.fn.filereadable(config_path) == 1 then
      local config, err = M.load_config(config_path)
      if config then
        local config_servers = M.get_servers_from_config(config)
        for _, server in ipairs(config_servers) do
          table.insert(all_servers, server)
        end
      else
        if opts.debug then
          vim.notify("[mcp] " .. err, vim.log.levels.WARN)
        end
      end
    end
  end

  local normalized = {}
  for _, server in ipairs(all_servers) do
    local norm = normalize_server_config(server)
    if norm then
      table.insert(normalized, norm)
    end
  end

  return normalized
end

function M.validate_server(server)
  if not server.name then
    return false, "Server must have a name"
  end

  if not server.type then
    return false, "Server must have a type (stdio, http, https)"
  end

  if server.type == "stdio" then
    if not server.command then
      return false, "stdio server must have a command"
    end
  elseif server.type == "http" or server.type == "https" then
    if not server.url then
      return false, "http/https server must have a url"
    end
  else
    return false, "Unknown server type: " .. server.type
  end

  return true, nil
end

function M.get_provider_mcp_servers(provider_id)
  local providers = require("ai_repl.providers")
  local provider = providers.get(provider_id)

  if not provider or not provider.mcp_servers then
    return {}
  end

  local normalized = {}
  for _, server in ipairs(provider.mcp_servers) do
    local norm = normalize_server_config(server)
    if norm then
      table.insert(normalized, norm)
    end
  end

  return normalized
end

return M
