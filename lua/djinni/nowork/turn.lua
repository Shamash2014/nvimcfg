local session = require("djinni.acp.session")

local M = {}

local function extract_commands(su)
  return su.availableCommands
    or su.available_commands
    or su.commands
    or (su.content and (su.content.availableCommands or su.content.available_commands or su.content.commands))
    or {}
end

function M.run(session_id, text, opts, cb)
  opts = opts or {}
  local text_buf = {}
  local tool_calls = {}

  local handlers = {}

  handlers.on_update = function(params)
    local su = params.update or params
    local kind = su.sessionUpdate
    if not kind then return end

    if kind == "agent_message_chunk" then
      local chunk = (su.content and su.content.text) or ""
      text_buf[#text_buf + 1] = chunk
      if opts.on_chunk then
        opts.on_chunk("agent_message_chunk", chunk)
      end
    elseif kind == "agent_thought_chunk" then
      if opts.on_chunk then
        local chunk = (su.content and su.content.text) or ""
        opts.on_chunk("agent_thought_chunk", chunk)
      end
    elseif kind == "tool_call" or kind == "tool_call_update" then
      tool_calls[#tool_calls + 1] = su
      if opts.on_tool_call then
        opts.on_tool_call(su)
      end
    elseif kind == "usage_update" or kind == "result" then
      local usage = su.tokenUsage or su.token_usage or su.usage or (su.content and su.content.usage)
      local cost = su.totalCostUsd or su.totalCost or su.cost or (su.content and su.content.cost)
      if (usage or cost) and opts.on_usage then
        opts.on_usage(usage, cost)
      end
    elseif kind == "available_commands_update" then
      if opts.on_commands then
        opts.on_commands(extract_commands(su))
      end
    end
  end

  handlers.on_permission = function(params, respond)
    if opts.on_permission then
      opts.on_permission(params, respond)
    else
      respond({ outcome = { outcome = "cancelled" } })
    end
  end

  session.subscribe_session(nil, session_id, handlers, opts.provider_name)

  session.send_message(nil, session_id, text, function(err, result)
    session.unsubscribe_session(nil, session_id, opts.provider_name)
    cb(err, {
      text = table.concat(text_buf),
      stop_reason = (result and result.stopReason) or nil,
      tool_calls = tool_calls,
    })
  end, nil, opts.provider_name)
end

return M
