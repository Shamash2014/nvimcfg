local M = {}

local function get_providers()
  local ok, providers = pcall(require, "ai_repl.providers")
  if not ok then
    return nil, providers
  end
  return providers.list()
end

local function check_provider_cmd(cmd)
  local binary = vim.fn.exepath(cmd)
  if binary and binary ~= "" then
    return true, binary
  end
  if vim.fn.exists(":" .. cmd .. "cmd") == 1 then
    return true, "in PATH"
  end
  return false, nil
end

function M.check()
  vim.health.start("ai_repl")

  vim.health.info("Checking configuration...")

  local config = rawget(require("ai_repl.init"), "config")
  if config then
    vim.health.ok("Configuration loaded")
  else
    vim.health.warn("No configuration found")
  end

  vim.health.info("Checking dependencies...")

  local deps = {
    { name = "process", module = "ai_repl.process" },
    { name = "registry", module = "ai_repl.registry" },
    { name = "render", module = "ai_repl.render" },
    { name = "providers", module = "ai_repl.providers" },
    { name = "chat_buffer", module = "ai_repl.chat_buffer" },
  }

  for _, dep in ipairs(deps) do
    local ok, err = pcall(require, dep.module)
    if ok then
      vim.health.ok(dep.name .. " module loaded")
    else
      vim.health.error(dep.name .. " module failed to load: " .. tostring(err))
    end
  end

  vim.health.info("Checking providers...")

  local providers_list, providers_err = get_providers()
  if providers_err then
    vim.health.error("Failed to load providers: " .. tostring(providers_err))
  elseif providers_list then
    for _, provider in ipairs(providers_list) do
      local found, location = check_provider_cmd(provider.cmd)
      if found then
        vim.health.ok(provider.name .. " (" .. provider.cmd .. "): " .. location)
      else
        vim.health.warn(provider.name .. " (" .. provider.cmd .. "): not found in PATH")
      end
    end
  end

  vim.health.info("Checking external tools...")

  local tools = {
    { name = "git", cmd = "git" },
  }

  for _, tool in ipairs(tools) do
    local found = vim.fn.exepath(tool.cmd)
    if found and found ~= "" then
      vim.health.ok(tool.name .. ": " .. found)
    else
      vim.health.warn(tool.name .. ": not found in PATH")
    end
  end
end

return M
