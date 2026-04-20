local parser = require("djinni.nowork.parser")
local qfix = require("djinni.nowork.qfix")
local qfix_share = require("djinni.nowork.qfix_share")
local templates = require("djinni.nowork.templates")

return {
  name = "explore",
  tail_stream = false,
  template_wrap = function(user_prompt, ctx)
    return user_prompt .. "\n\n" .. templates.explore_tail()
  end,
  on_turn_end = function(text, droid)
    local markers = require("djinni.nowork.markers")
    local name, payload = markers.detect(text)
    if name == markers.QUESTION then
      local options = markers.extract_options(text)
      require("djinni.nowork.ask").ask_and_resume(droid, vim.trim(payload or ""), options)
      return "suspend"
    end
    local items = parser.parse(text)
    local review_items, review_title = qfix_share.extract_review(text)
    local seen = {}
    local merged = {}
    local function push(it)
      if not it or not it.filename then return end
      local key = it.filename .. ":" .. (it.lnum or 0) .. ":" .. (it.col or 0)
      if not seen[key] then
        seen[key] = true
        merged[#merged + 1] = it
      end
    end
    for _, it in ipairs(items) do push(it) end
    for _, it in ipairs(review_items) do push(it) end
    if #merged > 0 then
      droid.state.qfix_items = merged
      droid.state.qfix_title = review_title or ("nowork explore: " .. (droid.initial_prompt or ""))
      qfix.set(merged, { mode = "replace", open = droid.opts.copen ~= false, title = droid.state.qfix_title })
      droid.log_buf:append(("[explore] %d location(s) → qflist"):format(#merged))
      vim.notify(
        ("nowork explore [%s]: %d location(s) → qflist"):format(droid.id, #merged),
        vim.log.levels.INFO
      )
    else
      droid.log_buf:append("[explore] no locations parsed")
      vim.notify(
        ("nowork explore [%s]: no locations found"):format(droid.id),
        vim.log.levels.WARN
      )
    end
    return "done"
  end,
  on_permission = function(params, respond, droid)
    local kind = params and params.toolCall and params.toolCall.kind or nil
    local allow = kind == "read" or kind == "search" or kind == "fetch" or kind == "think"
    local options = params and params.options or {}
    local target_id
    for _, opt in ipairs(options) do
      if allow and (opt.kind == "allow_once" or opt.kind == "allow_always") then
        target_id = opt.optionId
        break
      elseif not allow and (opt.kind == "reject_once" or opt.kind == "reject_always") then
        target_id = opt.optionId
        break
      end
    end
    if not target_id and options[1] then target_id = options[1].optionId end
    respond({ outcome = { outcome = "selected", optionId = target_id } })
  end,
}
