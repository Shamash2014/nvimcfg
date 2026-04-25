local session = require("djinni.acp.session")

local M = {}

local function mode_label(mode)
  if type(mode) ~= "table" then return tostring(mode) end
  return mode.name or mode.title or mode.label or mode.id or "?"
end

local function ensure(droid)
  if not droid then
    vim.notify("nowork: no droid attached", vim.log.levels.WARN)
    return nil
  end
  if not droid.session_id then
    vim.notify("nowork: droid has no ACP session yet", vim.log.levels.WARN)
    return nil
  end
  local m = droid.acp_modes
  if not m or not m.available or #m.available == 0 then
    vim.notify("nowork: agent has not advertised modes yet", vim.log.levels.WARN)
    return nil
  end
  return m
end

function M.set(droid, mode_id)
  if not droid or not droid.session_id or not mode_id then return end
  require("djinni.nowork.droid").set_acp_mode_id(droid, mode_id)
  session.set_mode(nil, droid.session_id, mode_id, droid.provider_name, function(err)
    if err then
      vim.schedule(function()
        vim.notify("nowork: set_mode failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
      end)
    end
  end)
end

function M.cycle(droid)
  local m = ensure(droid)
  if not m then return end
  if #m.available < 2 then
    vim.notify("nowork: only one ACP mode (" .. mode_label(m.available[1]) .. ")", vim.log.levels.WARN)
    return
  end
  local idx = 1
  for i, mode in ipairs(m.available) do
    if mode.id == m.current_id then idx = i; break end
  end
  local next_mode = m.available[(idx % #m.available) + 1]
  if next_mode and next_mode.id then M.set(droid, next_mode.id) end
end

function M.pick(droid)
  local m = ensure(droid)
  if not m then return end
  local items = {}
  for _, mode in ipairs(m.available) do
    if mode and mode.id then
      local marker = (mode.id == m.current_id) and "● " or "○ "
      items[#items + 1] = {
        text = marker .. mode_label(mode),
        id = mode.id,
      }
    end
  end
  if #items == 0 then return end
  if #items == 1 then
    vim.notify("nowork: only one ACP mode (" .. items[1].text .. ")", vim.log.levels.WARN)
    return
  end
  Snacks.picker.select(items, {
    prompt = "ACP mode",
    format_item = function(item) return item.text end,
  }, function(choice)
    if choice and choice.id and choice.id ~= m.current_id then
      M.set(droid, choice.id)
    end
  end)
end

return M
