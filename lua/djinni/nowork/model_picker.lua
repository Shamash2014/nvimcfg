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
  local session_models = session.get_available_models(droid.session_id)
  local items = Provider.list_models(session_models, droid.provider_name) or {}
  if #items == 0 then
    vim.notify("nowork: no models reported by " .. tostring(droid.provider_name or "?"), vim.log.levels.WARN)
    return
  end

  Snacks.picker.select(items, {
    prompt = "switch model",
    format_item = function(item)
      return item.label or item.id
    end,
  }, function(choice)
    if not choice then return end
    session.set_model(nil, droid.session_id, choice.id, droid.provider_name)
    droid.model_name = choice.id
    droid.opts = droid.opts or {}
    droid.opts.model = choice.id
    if droid.log_buf and droid.log_buf.append then
      droid.log_buf:append("[model → " .. tostring(choice.label or choice.id) .. "]")
    end
    require("djinni.nowork.archive").write_state(droid)
    require("djinni.nowork.status_panel").update()
  end)
end

return M
