local listen_mod = require("djinni.nowork.listen")

local M = {}

local function extract_commands(su)
  return su.availableCommands
    or su.available_commands
    or su.commands
    or (su.content and (su.content.availableCommands or su.content.available_commands or su.content.commands))
    or {}
end

local function extract_usage(su)
  local usage = su.tokenUsage or su.token_usage or su.usage or (su.content and su.content.usage)
  local cost = su.totalCostUsd or su.totalCost or su.cost or (su.content and su.content.cost)
  return usage, cost
end

function M.run(droid, text, opts, cb)
  opts = opts or {}
  if not droid or not droid.session_id or not droid._sink then
    return cb({ code = -1, message = "turn.run: droid missing session_id or _sink" }, nil)
  end

  local text_buf = {}
  local tool_calls = {}

  local L = listen_mod.new(droid)

  L:on("text", function(chunk)
    text_buf[#text_buf + 1] = chunk
    if opts.on_chunk then opts.on_chunk("agent_message_chunk", chunk) end
  end)

  L:on("thought", function(chunk)
    if opts.on_chunk then opts.on_chunk("agent_thought_chunk", chunk) end
  end)

  L:on("tool_call", function(su)
    tool_calls[#tool_calls + 1] = su
    if opts.on_tool_call then opts.on_tool_call(su) end
  end)

  local function forward_usage(su)
    local usage, cost = extract_usage(su)
    if (usage or cost) and opts.on_usage then opts.on_usage(usage, cost) end
  end
  L:on("usage", forward_usage)
  L:on("result", forward_usage)

  L:on("commands", function(su)
    if opts.on_commands then opts.on_commands(extract_commands(su)) end
  end)

  L:on("mode", function(su)
    if not opts.on_mode then return end
    if su.sessionUpdate == "current_mode_update" and su.modeId then
      opts.on_mode({ current_mode_id = su.modeId })
    else
      opts.on_mode({
        available_modes = su.availableModes or su.available_modes,
        current_mode_id = su.currentModeId or su.current_mode_id,
      })
    end
  end)

  L:on("plan", function(su)
    if opts.on_plan then opts.on_plan(su) end
  end)

  L:on("permission", function(params, respond)
    if opts.on_permission then
      opts.on_permission(params, respond)
    else
      respond({ outcome = { outcome = "cancelled" } })
    end
  end)

  L:start()

  droid._sink:say(text, function(err, result)
    L:stop()
    cb(err, {
      text = table.concat(text_buf),
      stop_reason = (result and result.stopReason) or nil,
      tool_calls = tool_calls,
    })
  end)
end

return M
