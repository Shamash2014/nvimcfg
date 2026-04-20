local function render_slices(text, log_buf)
  local slices = require("djinni.nowork.parser").extract_log_slices(text)
  for _, s in ipairs(slices) do
    if s.kind == "block" then
      local open_tag
      if s.title and s.title ~= "" then
        open_tag = "<" .. s.tag .. " title=\"" .. s.title .. "\">"
      else
        open_tag = "<" .. s.tag .. ">"
      end
      log_buf:append(open_tag)
      for _, line in ipairs(vim.split(s.body or "", "\n", { plain = true })) do
        log_buf:append(line)
      end
      log_buf:append("</" .. s.tag .. ">")
    else
      log_buf:append(s.tag)
    end
  end
end

return {
  name = "routine",
  tail_stream = true,
  log_render = render_slices,
  template_wrap = function(user_prompt, ctx)
    local templates = require("djinni.nowork.templates")
    local tail = templates.routine_tail()
    if tail and tail ~= "" then
      return user_prompt .. "\n\n" .. tail
    end
    return user_prompt
  end,
  on_turn_end = function(text, droid, tool_calls)
    local qfix_share = require("djinni.nowork.qfix_share")
    droid.state.touched = droid.state.touched or { items = {}, seen = {}, title = nil }
    local bag = droid.state.touched
    local before = #bag.items

    local function add(item)
      local key = (item.filename or "") .. ":" .. (item.lnum or 0) .. ":" .. (item.col or 0)
      if item.filename and not bag.seen[key] then
        bag.seen[key] = true
        bag.items[#bag.items + 1] = item
      end
    end

    local review_items, title = qfix_share.extract_review(text)
    if title and not bag.title then bag.title = title end
    for _, it in ipairs(review_items) do add(it) end

    if tool_calls then
      local qfix = require("djinni.nowork.qfix")
      for _, tc in ipairs(tool_calls) do
        local kind = tc.kind or ""
        if kind == "edit" or kind == "write" or kind == "create" or kind == "delete" then
          for _, loc in ipairs(tc.locations or {}) do
            local it = qfix.build_item({
              filename = loc.path,
              lnum = loc.line,
              col = loc.column,
              text = tc.title or "",
            })
            if it then add(it) end
          end
        end
      end
    end

    if #bag.items > 0 then
      local qfix = require("djinni.nowork.qfix")
      qfix.set(bag.items, {
        mode = "replace",
        open = false,
        title = bag.title or ("nowork routine: " .. (droid.initial_prompt or droid.id)),
      })
      local added = #bag.items - before
      if added > 0 then
        vim.notify(
          ("nowork routine: +%d → qflist (total %d)"):format(added, #bag.items),
          vim.log.levels.INFO
        )
      end
    end

    local markers = require("djinni.nowork.markers")
    local question, ask_options = markers.extract_ask_user(text)
    if question then
      require("djinni.nowork.ask").ask_and_send(droid, question, ask_options)
    elseif droid.state.composer_persistent then
      local compose = require("djinni.nowork.compose")
      local parser = require("djinni.nowork.parser")
      local sections = parser.extract_sections(text)
      if next(sections) == nil then
        compose.reopen(droid, nil, text)
      else
        compose.reopen(droid, sections, nil)
      end
    end

    pcall(function()
      require("djinni.nowork.archive").write_state(droid)
    end)

    return "await_user"
  end,
  on_permission = function(params, respond, droid)
    local kind = params and params.toolCall and params.toolCall.kind
    if kind and droid.state.sticky_permissions[kind] then
      local sticky = droid.state.sticky_permissions[kind]
      for _, opt in ipairs(params.options or {}) do
        if (sticky == "allow" and (opt.kind == "allow_once" or opt.kind == "allow_always"))
           or (sticky == "deny" and (opt.kind == "reject_once" or opt.kind == "reject_always")) then
          respond({ outcome = { outcome = "selected", optionId = opt.optionId } })
          return
        end
      end
    end
    require("djinni.nowork.mailbox").enqueue(droid, params, respond)
  end,
}
