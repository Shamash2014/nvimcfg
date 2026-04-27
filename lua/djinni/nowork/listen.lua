local session = require("djinni.acp.session")
local log_buffer = require("djinni.nowork.log_buffer")
local strutil = require("djinni.nowork.status_text")

local M = {}

local KINDS = { "text", "thought", "tool_call", "plan", "usage", "mode", "commands", "result", "permission" }

function M.new(droid)
  local self = {
    droid = droid,
    handlers = {},
    started = false,
    _subs = nil,
  }
  for _, k in ipairs(KINDS) do self.handlers[k] = {} end

  function self:on(kind, fn)
    self.handlers[kind] = self.handlers[kind] or {}
    table.insert(self.handlers[kind], fn)
    return self
  end

  local function dispatch(kind, ...)
    local hs = self.handlers[kind]
    if not hs then return end
    for _, fn in ipairs(hs) do
      pcall(fn, ...)
    end
  end

  local function on_update(params)
    local su = params.update or params
    local kind = su.sessionUpdate
    if kind == "agent_message_chunk" then
      dispatch("text", (su.content and su.content.text) or "")
    elseif kind == "agent_thought_chunk" then
      local text = (su.content and su.content.text) or ""
      log_buffer.droid_log(droid, "[listen/thought] " .. strutil.one_line(text, 120))
      dispatch("thought", text)
    elseif kind == "tool_call" or kind == "tool_call_update" then
      local tc = su.toolCall or su.tool_call or su
      local title = tc.title or "tool"
      local k = tc.kind or "?"
      local status = tc.status or ""
      log_buffer.droid_log(droid, string.format("[listen/tool_call] %s · %s%s",
        k, strutil.one_line(title, 80), status ~= "" and (" · " .. status) or ""))
      dispatch("tool_call", su)
    elseif kind == "plan" then
      log_buffer.droid_log(droid, "[listen/plan] update")
      dispatch("plan", su)
    elseif kind == "usage_update" then
      dispatch("usage", su)
    elseif kind == "modes" or kind == "current_mode_update" then
      dispatch("mode", su)
    elseif kind == "available_commands_update" then
      dispatch("commands", su)
    elseif kind == "result" then
      log_buffer.droid_log(droid, "[listen/result] " .. tostring(su.stopReason or su.stop_reason or "?"))
      dispatch("result", su)
    end
  end

  local function on_permission(params, respond)
    local tc = params and params.toolCall or {}
    log_buffer.droid_log(droid, string.format("[listen/perm] %s · %s",
      tc.kind or "?", strutil.one_line(tc.title or "tool", 80)))
    dispatch("permission", params, respond)
  end

  function self:start()
    if self.started then return self end
    self._subs = { on_update = on_update, on_permission = on_permission }
    session.subscribe_session(nil, droid.session_id, self._subs, droid.provider_name)
    self.started = true
    return self
  end

  function self:stop()
    if not self.started then return self end
    session.unsubscribe_session(nil, droid.session_id, droid.provider_name)
    self.started = false
    self._subs = nil
    return self
  end

  return self
end

return M
