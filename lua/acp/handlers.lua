local M = {}

function M.dispatch(rpc, msg)
  local method = msg.method
  if     method == "session/request_permission" then M._handle_permission(rpc, msg)
  elseif method == "terminal/create"            then M._handle_term_create(rpc, msg)
  elseif method == "terminal/wait_for_exit"     then M._handle_term_wait(rpc, msg)
  elseif method == "terminal/output"            then M._handle_term_output(rpc, msg)
  elseif method == "terminal/kill"              then M._handle_term_kill(rpc, msg)
  elseif method == "terminal/release"           then M._handle_term_release(rpc, msg)
  else
    rpc:respond(msg.id, nil, { code = -32601, message = "Method not found: " .. method })
  end
end

function M._handle_permission(rpc, msg)
  local p    = msg.params or {}
  local tool = p.toolCall or {}
  vim.schedule(function()
    require("acp.mailbox").enqueue_permission({
      rpc        = rpc,
      msg_id     = msg.id,
      session_id = p.sessionId,
      tool_kind  = tool.kind or "other",
      tool_title = tool.title or tool.kind or "unknown",
      tool_input = tool.rawInput,
      options    = p.options or {
        { optionId = "allow-once",   name = "Allow once",   kind = "allow_once"   },
        { optionId = "allow-always", name = "Allow always", kind = "allow_always" },
        { optionId = "reject-once",  name = "Reject",       kind = "reject_once"  },
      },
    })
  end)
end

function M._handle_term_create(rpc, msg)
  local p = msg.params or {}
  if not p.command then
    rpc:respond(msg.id, nil, { code = -32602, message = "Missing command" })
    return
  end
  vim.schedule(function()
    require("acp.terminal").create(p, function(result, err)
      if err then rpc:respond(msg.id, nil, err)
      else        rpc:respond(msg.id, result) end
    end)
  end)
end

function M._handle_term_wait(rpc, msg)
  local p = msg.params or {}
  if not p.terminalId then
    rpc:respond(msg.id, nil, { code = -32602, message = "Missing terminalId" })
    return
  end
  vim.schedule(function()
    require("acp.terminal").wait_for_exit(p.terminalId, rpc, msg.id)
  end)
end

function M._handle_term_output(rpc, msg)
  local p = msg.params or {}
  if not p.terminalId then
    rpc:respond(msg.id, nil, { code = -32602, message = "Missing terminalId" })
    return
  end
  vim.schedule(function()
    local out = require("acp.terminal").get_output(p.terminalId)
    if out == nil then
      rpc:respond(msg.id, nil, { code = -32602, message = "Unknown terminalId: " .. p.terminalId })
    else
      rpc:respond(msg.id, { output = out })
    end
  end)
end

function M._handle_term_kill(rpc, msg)
  local p = msg.params or {}
  vim.schedule(function()
    if p.terminalId then require("acp.terminal").kill(p.terminalId) end
    rpc:respond(msg.id, {})
  end)
end

function M._handle_term_release(rpc, msg)
  local p = msg.params or {}
  vim.schedule(function()
    if p.terminalId then require("acp.terminal").release(p.terminalId) end
    rpc:respond(msg.id, {})
  end)
end

return M
