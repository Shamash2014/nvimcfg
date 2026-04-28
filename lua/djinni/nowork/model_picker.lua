local M = {}

function M.pick(droid)
  if not droid then
    vim.notify("nowork: no active droid", vim.log.levels.WARN)
    return
  end
  if not droid.session_id or droid.session_id == "" then
    vim.notify("nowork: no active session", vim.log.levels.WARN)
    return
  end

  local session = require("djinni.acp.session")
  local Provider = require("djinni.acp.provider")
  local entry = session.get_session_entry and session.get_session_entry(droid.session_id) or nil
  local session_models = session.get_available_models(droid.session_id)
  local items = Provider.list_models(session_models, droid.provider_name) or {}

  if #items == 0 then
    local reason
    if not entry then
      reason = "session not registered (sid=" .. tostring(droid.session_id) .. ")"
    elseif not session_models then
      reason = "session has no model metadata yet — wait for session/new to complete"
    elseif type(session_models) == "table" and session_models.optionId
        and (not session_models.options or #session_models.options == 0) then
      reason = "agent returned empty model option list"
    else
      reason = "no models matched provider " .. tostring(droid.provider_name or "?")
    end
    vim.notify("nowork: " .. reason, vim.log.levels.WARN)
    return
  end

  Snacks.picker.select(items, {
    prompt = "switch model",
    format_item = function(item)
      return item.label or item.id
    end,
  }, function(choice)
    if not choice then return end
    session.set_model(nil, droid.session_id, choice.id, droid.provider_name, function(err)
      if err then
        vim.schedule(function()
          vim.notify("nowork: model switch failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
        end)
        return
      end
      vim.schedule(function()
        droid.model_name = choice.id
        droid.opts = droid.opts or {}
        droid.opts.model = choice.id
        if droid.log_buf and droid.log_buf.append then
          droid.log_buf:append("[model → " .. tostring(choice.label or choice.id) .. "]")
        end
        require("djinni.nowork.archive").write_state(droid)
        pcall(vim.cmd, "redrawstatus")
      end)
    end)
  end)
end

return M
