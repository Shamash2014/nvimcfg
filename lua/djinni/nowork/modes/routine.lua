local lifecycle = require("djinni.nowork.state")
local log_render = require("djinni.nowork.log_render")

return {
  name = "routine",
  tail_stream = true,
  log_render = log_render.render_slices,
  template_wrap = function(user_prompt, droid_opts)
    local templates = require("djinni.nowork.templates")
    if droid_opts and droid_opts.multitask then
      return user_prompt .. "\n\n" .. templates.multitask_lead_tail()
    end
    local tail = templates.routine_tail()
    if tail and tail ~= "" then
      return user_prompt .. "\n\n" .. tail
    end
    return user_prompt
  end,
  on_turn_end = function(text, droid, tool_calls)
    local qfix_share = require("djinni.nowork.qfix_share")
    local tasks_parser = require("djinni.nowork.tasks_parser")

    if droid.opts and droid.opts.multitask then
      local tasks = tasks_parser.parse_tasks(text)
      if #tasks == 0 then
        tasks = tasks_parser.parse_tasks(droid.initial_prompt)
      end

      if #tasks > 0 then
        local droid_mod = require("djinni.nowork.droid")
        droid.state.tasks = droid.state.tasks or {}
        droid.state.topo_order = droid.state.topo_order or {}

        for _, t in ipairs(tasks) do
          if not droid.state.tasks[t.id] then
            droid.state.tasks[t.id] = t
            table.insert(droid.state.topo_order, t.id)

            local sub_cwd = droid.opts and droid.opts.cwd
            if droid.opts and droid.opts.isolate then
              local wt_path = sub_cwd .. "/.nowork/worktrees/" .. t.id
              vim.fn.mkdir(vim.fn.fnamemodify(wt_path, ":h"), "p")
              local branch = "nowork-" .. t.id
              local obj = vim.system({ "git", "-C", sub_cwd, "worktree", "add", "-B", branch, wt_path }, { text = true }):wait()
              if obj.code == 0 then
                sub_cwd = wt_path
                t.worktree = wt_path
                t.branch = branch
              else
                vim.notify("multitask: failed to create worktree for " .. t.id .. ": " .. (obj.stderr or "?"), vim.log.levels.ERROR)
              end
            end

            local context = t.context and table.concat(t.context, "\n") or "none"
            local implementation = t.implementation and table.concat(t.implementation, "\n") or "none"
            local skills = t.skills and table.concat(t.skills, ", ") or "none"
            local acceptance = {}
            for _, a in ipairs(t.acceptance or {}) do
              table.insert(acceptance, (a.required and "[REQ] " or "[OPT] ") .. a.text)
            end
            
            local sub_prompt = string.format([[
You are a worker sub-droid for task %s: %s

### Context
%s

### Implementation Blueprint
%s

### Skills to Use
%s

### Acceptance Criteria
%s

Please execute this task and keep a detailed record of your work.
]], t.id, t.desc, context, implementation, skills, table.concat(acceptance, "\n"))

            local sub = droid_mod.new("routine", sub_prompt, {
              parent_id = droid.id,
              task_id = t.id,
              cwd = sub_cwd,
              provider = droid.opts and droid.opts.provider,
              skills = t.skills or {},
            })
            droid.state.tasks[t.id].droid_id = sub.id
            droid.state.tasks[t.id].status = "running"
            if droid._log_fh then
              droid._log_fh:write(string.format("[trace] spawned sub-droid %s for task %s in %s\n", sub.id, t.id, sub_cwd))
              droid._log_fh:flush()
            end
          end
        end
        qfix_share.render_tasks(droid, { title = "multitask status" })
        return "await_user"
      end
    end

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

    local turn_items = {}
    local review_items, title = qfix_share.extract_review(text, { cwd = droid.opts and droid.opts.cwd })
    if title and not bag.title then bag.title = title end
    for _, it in ipairs(review_items) do
      add(it)
      table.insert(turn_items, it)
    end

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
              text = string.format("[%s] %s", kind, tc.title or ""),
              cwd = droid.opts and droid.opts.cwd,
            })
            if it then
              add(it)
              table.insert(turn_items, it)
            end
          end
        end
      end
    end
    droid.state.last_turn_items = turn_items

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
      lifecycle.request_close_session_on_idle(droid)
      require("djinni.nowork.ask").ask_and_send(droid, question, ask_options)
    elseif lifecycle.is_composer_persistent(droid) then
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
