local M = {}

local start = vim.health.start
local error = vim.health.error
local warn = vim.health.warn
local ok = vim.health.ok

local function check_executable(name, cmd)
  local exe = cmd
  if type(cmd) == "table" then exe = cmd[1] end
  local path = vim.fn.exepath(exe)
  if path == "" then
    error(name .. ": not found on $PATH")
    return false
  else
    ok(name .. ": " .. path)
    return true
  end
end

local function check_env_var(var_name)
  local val = os.getenv(var_name)
  if not val or val == "" then
    warn(var_name .. ": not set")
    return false
  else
    ok(var_name .. ": set")
    return true
  end
end

local function check_module(module_name)
  local ok_load, _ = pcall(require, module_name)
  return ok_load
end

function M.check()
  start("acp")

  if vim.fn.has("nvim-0.10") == 1 then
    ok("nvim >= 0.10")
  else
    error("nvim >= 0.10 required")
  end

  start("acp [agents]")

  local agents = require("acp.agents")
  local available = agents.available()

  if #available == 0 then
    warn("No agents available — install one of: claude-agent-acp, opencode, codex-acp, hermes, agent (cursor)")
  else
    ok("Found " .. #available .. " agent(s)")
    for _, agent in ipairs(available) do
      ok("  " .. agent.display .. ": " .. vim.fn.exepath(agent.cmd))
    end
  end

  start("acp [dependencies]")

  if check_module("snacks") then
    ok("snacks.nvim: installed")
  else
    warn("snacks.nvim: not installed (optional, used for composer UI)")
  end

  start("acp [sessions]")

  local session = require("acp.session")
  local active_sessions = session.active()
  ok("Active sessions: " .. #active_sessions)
end

return M
