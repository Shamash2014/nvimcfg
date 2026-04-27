local session = require("djinni.acp.session")
local log_buffer = require("djinni.nowork.log_buffer")
local strutil = require("djinni.nowork.status_text")

local M = {}

function M.new(droid)
  local self = { droid = droid }

  function self:say(text, callback)
    if not text or text == "" then
      log_buffer.droid_log(droid, "[sink/say] (empty)")
    elseif not text:find("\n") then
      log_buffer.droid_log(droid, "[sink/say] " .. text)
    else
      local indented = vim.split(text, "\n", { plain = true })
      for i, line in ipairs(indented) do indented[i] = "  " .. line end
      log_buffer.droid_log(droid, "[sink/say]\n" .. table.concat(indented, "\n"))
    end
    return session.send_message(nil, droid.session_id, text, callback, nil, droid.provider_name)
  end

  function self:cancel()
    log_buffer.droid_log(droid, "[sink/cancel]")
    return session.interrupt(nil, droid.session_id, droid.provider_name)
  end

  function self:close()
    if not droid.session_id then return end
    log_buffer.droid_log(droid, "[sink/close]")
    return session.close_task_session(nil, droid.session_id, droid.provider_name)
  end

  function self:set_mode(mode_id, callback)
    log_buffer.droid_log(droid, "[sink/mode] → " .. tostring(mode_id))
    return session.set_mode(nil, droid.session_id, mode_id, droid.provider_name, callback)
  end

  function self:respond(entry, outcome)
    if not entry then return end
    local label = outcome and outcome.outcome and outcome.outcome.outcome or "?"
    local opt = outcome and outcome.outcome and outcome.outcome.optionId or "?"
    log_buffer.droid_log(droid, string.format("[sink/perm %s] %s · %s", entry.id or "?", label, opt))
    if entry.respond then pcall(entry.respond, outcome) end
  end

  return self
end

return M
