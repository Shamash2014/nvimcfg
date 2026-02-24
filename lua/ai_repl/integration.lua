local M = {}

local async = require("ai_repl.async")
local lifecycle = require("ai_repl.client_lifecycle")
local mcp = require("ai_repl.mcp")
local agents_md = require("ai_repl.agents_md")
local diff_ui = require("ai_repl.diff_ui")

M.config = {
  enable_lifecycle = true,
  enable_agents_md = true,
  enable_mcp_auto_discovery = true,
  enable_diff_ui = true,
  debug = false,
}

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_extend("force", M.config, opts)

  if M.config.enable_lifecycle then
    lifecycle.setup_auto_cleanup()
  end
end

function M.create_session_with_context(session_id, process_opts)
  process_opts = process_opts or {}

  local cwd = process_opts.cwd or vim.fn.getcwd()

  local mcp_servers = {}
  if M.config.enable_mcp_auto_discovery then
    mcp_servers = mcp.resolve_mcp_servers({
      cwd = cwd,
      load_from_config = true,
      mcp_servers = process_opts.mcp_servers or {},
      debug = M.config.debug,
    })
  elseif process_opts.mcp_servers then
    mcp_servers = process_opts.mcp_servers
  end

  local provider_mcp = mcp.get_provider_mcp_servers(process_opts.provider or "claude")
  for _, server in ipairs(provider_mcp) do
    table.insert(mcp_servers, server)
  end

  process_opts.mcp_servers = mcp_servers

  local agents_context = nil
  if M.config.enable_agents_md and agents_md.should_inject(process_opts) then
    agents_context = agents_md.get_context_for_session({
      cwd = cwd,
      debug = M.config.debug,
    })

    if agents_context and M.config.debug then
      vim.notify(
        string.format("[integration] Loaded AGENTS.md from %s", agents_context.path),
        vim.log.levels.INFO
      )
    end
  end

  return {
    process_opts = process_opts,
    agents_context = agents_context,
    mcp_servers = mcp_servers,
  }
end

function M.register_process(session_id, process, opts)
  opts = opts or {}

  if M.config.enable_lifecycle then
    lifecycle.register_client(session_id, process, {
      chat_buf = opts.chat_buf,
      debug = M.config.debug,
    })
  end
end

function M.unregister_process(session_id)
  if M.config.enable_lifecycle then
    lifecycle.unregister_client(session_id, {
      debug = M.config.debug,
    })
  end
end

function M.enhance_prompt_with_agents_md(prompt, opts)
  opts = opts or {}

  if not M.config.enable_agents_md then
    return prompt
  end

  local cwd = opts.cwd or vim.fn.getcwd()
  local context = agents_md.get_context_for_session({ cwd = cwd })

  if context then
    return agents_md.inject_into_session_prompt(prompt, context.content)
  end

  return prompt
end

function M.show_diff_for_tool_update(tool_update, opts)
  opts = opts or {}

  if not M.config.enable_diff_ui then
    return
  end

  if not tool_update.diff then
    return
  end

  diff_ui.show_diff(tool_update.diff, {
    on_accept = opts.on_accept,
    on_reject = opts.on_reject,
  })
end

function M.show_merge_conflict_ui(conflict_data, opts)
  opts = opts or {}

  if not M.config.enable_diff_ui then
    return
  end

  diff_ui.show_merge_conflict(conflict_data, {
    on_choose_current = opts.on_choose_current,
    on_choose_incoming = opts.on_choose_incoming,
    on_choose_both = opts.on_choose_both,
  })
end

function M.send_async(process, method, params, timeout_ms)
  timeout_ms = timeout_ms or 30000
  return process:send(method, params, timeout_ms)
end

function M.get_status()
  local cwd = vim.fn.getcwd()

  return {
    lifecycle = {
      enabled = M.config.enable_lifecycle,
      active_clients = M.config.enable_lifecycle and lifecycle.get_active_count() or 0,
    },
    agents_md = agents_md.get_status(cwd),
    mcp = {
      enabled = M.config.enable_mcp_auto_discovery,
    },
    diff_ui = {
      enabled = M.config.enable_diff_ui,
      active = diff_ui.active_diff_ui ~= nil,
    },
  }
end

function M.create_async_process_wrapper(process)
  return {
    send_async = function(method, params, timeout)
      return process:send(method, params, timeout)
    end,

    send_prompt_async = function(prompt, opts)
      return process:send_prompt(prompt, opts)
    end,
  }
end

return M
