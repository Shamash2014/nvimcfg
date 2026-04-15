local M = {}
local ui = require("djinni.integrations.snacks_ui")

local LOCAL_COMMAND_META = {
  ["/model"] = { description = "Set or select the active model", input_hint = "model id" },
  ["/provider"] = { description = "Switch the active ACP provider", input_hint = "provider name" },
  ["/compact"] = { description = "Ask the agent to compact the conversation" },
  ["/new"] = { description = "Start a new local chat session" },
  ["/cost"] = { description = "Ask the agent for cost details" },
  ["/mode"] = { description = "Set or cycle the session mode", input_hint = "mode id" },
  ["/skill"] = { description = "Toggle a project skill", input_hint = "skill name" },
  ["/mcp"] = { description = "Toggle an MCP server", input_hint = "server name" },
  ["/clear"] = { description = "Clear the conversation and reset session state" },
  ["/resume"] = { description = "Resume an existing ACP session if supported" },
  ["/fork"] = { description = "Fork this chat into a new task buffer" },
  ["/tree"] = { description = "Show the task tree" },
  ["/lesson"] = { description = "Save or manage a lesson", input_hint = "lesson text" },
  ["/lessons"] = { description = "Extract reusable lessons from the conversation" },
  ["/help"] = { description = "Show chat help" },
}

function M.get_models(buf)
  local chat = require("djinni.nowork.chat")
  local session = require("djinni.acp.session")
  local provider = require("djinni.acp.provider")
  local provider_name = chat.get_provider(buf)
  local sid = chat.get_session_id and chat.get_session_id(buf) or nil
  if (not sid or sid == "") and chat._sessions then sid = chat._sessions[buf] end
  local available = sid and session.get_available_models(sid) or nil
  return provider.list_models(available, provider_name)
end

M.commands = {
  { name = "/model", args = true, forward = true },
  { name = "/provider", args = true, forward = false },
  { name = "/compact", args = false, forward = true },
  { name = "/new", args = false, forward = false },
  { name = "/cost", args = false, forward = true },
  { name = "/mode", args = true, forward = false },
  { name = "/skill", args = true, forward = false },
  { name = "/mcp", args = true, forward = false },
  { name = "/clear", args = false, forward = false },
  { name = "/resume", args = false, forward = false },
  { name = "/fork", args = false, forward = false },
  { name = "/tree", args = false, forward = false },
  { name = "/lesson", args = true, forward = false },
  { name = "/lessons", args = false, forward = false },
  { name = "/help", args = false, forward = false },
}

function M.get_names()
  local names = {}
  for _, cmd in ipairs(M.commands) do
    table.insert(names, cmd.name)
  end
  return names
end

local function add_slash_command(items, seen, item)
  local slash = item and item.slash
  if not slash or slash == "" or seen[slash] then return end
  seen[slash] = true
  items[#items + 1] = item
end

function M.get_slash_commands(buf)
  local chat = require("djinni.nowork.chat")
  local skills_mod = require("djinni.nowork.skills")
  local root = chat.get_project_root(buf)
  local items = {}
  local seen = {}

  for _, cmd in ipairs(M.commands) do
    local meta = LOCAL_COMMAND_META[cmd.name] or {}
    add_slash_command(items, seen, {
      name = cmd.name:sub(2),
      slash = cmd.name,
      description = meta.description or "",
      input = cmd.args and { hint = meta.input_hint or "arguments" } or nil,
      source = "local",
      forward = cmd.forward,
      args = cmd.args,
    })
  end

  local advertised = chat._available_commands[buf] or {}
  for _, cmd in ipairs(advertised) do
    local name = cmd.name
    if type(name) == "string" and name ~= "" then
      add_slash_command(items, seen, {
        name = name,
        slash = "/" .. name,
        description = cmd.description or "",
        input = cmd.input,
        source = "agent",
      })
    end
  end

  if root then
    local discovered = skills_mod.discover(root)
    for _, skill in ipairs(discovered) do
      add_slash_command(items, seen, {
        name = skill.name,
        slash = "/" .. skill.name,
        description = skill.description or "",
        source = "skill",
      })
    end
  end

  return items
end

function M.match(text)
  local trimmed = text:match("^%s*(.-)%s*$")
  for _, cmd in ipairs(M.commands) do
    if trimmed == cmd.name or trimmed:match("^" .. cmd.name:gsub("/", "/") .. "%s") then
      local args = trimmed:sub(#cmd.name + 1):match("^%s*(.-)%s*$")
      return cmd, args
    end
  end
  return nil, nil
end

function M.execute(buf, text)
  local cmd, args = M.match(text)
  if not cmd then
    local skill_name = text:match("^%s*/([%w%-_]+)%s*$")
    if skill_name then
      local skills_mod = require("djinni.nowork.skills")
      local chat = require("djinni.nowork.chat")
      local root = chat.get_project_root(buf)
      if skills_mod.get(skill_name, root) then
        return M.execute(buf, "/skill " .. skill_name)
      end
    end
    return false
  end

  local chat = require("djinni.nowork.chat")

  if cmd.name == "/help" then
    chat.show_help()
    return true
  end

  if cmd.name == "/model" then
    if args and args ~= "" then
      chat._set_frontmatter_field(buf, "model", args)
      vim.notify("[djinni] Model: " .. args, vim.log.levels.INFO)
      local lc = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
        "", "---", "", "@System", "Model: " .. args, "",
      })
      chat.restart_session(buf)
    else
      chat.pick_model(buf)
    end
    return true
  end

  if cmd.name == "/provider" and args and args ~= "" then
    chat.switch_provider(buf, args)
    return true
  end

  if cmd.name == "/mode" then
    if args and args ~= "" then
      local modes = chat._modes[buf] or {}
      for _, m in ipairs(modes) do
        if m.id == args or (m.name and m.name:lower() == args:lower()) then
          local root = chat.get_project_root(buf)
          local sid = chat.get_session_id(buf) or chat._sessions[buf]
          if root and sid then
            local session = require("djinni.acp.session")
            session.set_mode(root, sid, m.id)
            chat._current_mode[buf] = m.id
            chat._set_frontmatter_field(buf, "mode", m.id)
            vim.notify("[djinni] Mode: " .. (m.displayName or m.name or m.id), vim.log.levels.INFO)
            local lc = vim.api.nvim_buf_line_count(buf)
            vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
              "", "---", "", "@System", "Mode: " .. (m.displayName or m.name or m.id), "",
            })
          end
          return true
        end
      end
    end
    chat.pick_mode(buf)
    return true
  end

  if cmd.name == "/skill" then
    local skills_mod = require("djinni.nowork.skills")
    local root = chat.get_project_root(buf)
    local current = chat._read_frontmatter_csv(buf, "skills")
    if args and args ~= "" then
      local name = vim.trim(args)
      local found = false
      for i, s in ipairs(current) do
        if s == name then table.remove(current, i); found = true; break end
      end
      if not found then
        if not skills_mod.get(name, root) then
          vim.notify("[djinni] Skill not found: " .. name, vim.log.levels.WARN)
          return true
        end
        table.insert(current, name)
      end
      chat._set_frontmatter_field(buf, "skills", table.concat(current, ", "))
      chat._set_frontmatter_field(buf, "session", "")
      chat._sessions[buf] = nil
      local status = found and "removed" or "added"
      vim.notify("[djinni] Skill " .. status .. ": " .. name, vim.log.levels.INFO)
    else
      local discovered = skills_mod.discover(root)
      if #discovered == 0 then
        vim.notify("No skills found", vim.log.levels.INFO)
        return true
      end
      local current_set = {}
      for _, s in ipairs(current) do current_set[s] = true end
      ui.select(discovered, {
        prompt = "Toggle skill",
        format_item = function(item)
          local mark = current_set[item.name] and "[x] " or "[ ] "
          return mark .. item.name .. (item.description ~= "" and (" — " .. item.description) or "")
        end,
      }, function(choice)
        if not choice then return end
        vim.schedule(function()
          M.execute(buf, "/skill " .. choice.name)
        end)
      end)
    end
    return true
  end

  if cmd.name == "/mcp" then
    local mcp_mod = require("djinni.nowork.mcp")
    local root = chat.get_project_root(buf)
    local current = chat._read_frontmatter_csv(buf, "mcp")
    if args and args ~= "" then
      local name = vim.trim(args)
      local found = false
      for i, s in ipairs(current) do
        if s == name then table.remove(current, i); found = true; break end
      end
      if not found then table.insert(current, name) end
      chat._set_frontmatter_field(buf, "mcp", table.concat(current, ", "))
      chat._set_frontmatter_field(buf, "session", "")
      chat._sessions[buf] = nil
      vim.notify("[djinni] MCP: " .. table.concat(current, ", "), vim.log.levels.INFO)
    else
      local available = mcp_mod.list(root)
      if #available == 0 then
        vim.notify("No MCP servers in .claude/mcp.json", vim.log.levels.INFO)
        return true
      end
      local current_set = {}
      for _, s in ipairs(current) do current_set[s] = true end
      local items = {}
      for _, name in ipairs(available) do
        table.insert(items, { name = name, active = current_set[name] })
      end
      ui.select(items, {
        prompt = "Toggle MCP server",
        format_item = function(item)
          return (item.active and "[x] " or "[ ] ") .. item.name
        end,
      }, function(choice)
        if not choice then return end
        vim.schedule(function()
          M.execute(buf, "/mcp " .. choice.name)
        end)
      end)
    end
    return true
  end

  if cmd.name == "/compact" then
    local lc = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
      "", "---", "", "@System", "Compacting conversation...", "",
    })
    return false
  end

  if cmd.name == "/new" then
    local mcp_mod = require("djinni.nowork.mcp")
    local root = chat.get_project_root(buf)
    if root then mcp_mod.clear_cache(root) end
    if chat._streaming[buf] then
      if chat._stream_cleanup[buf] then chat._stream_cleanup[buf](true) end
    end
    chat._set_frontmatter_field(buf, "session", "")
    chat._sessions[buf] = nil
    chat._waiting_input[buf] = nil
    chat._continuation_count[buf] = 0
    chat._last_tool_failed[buf] = false
    chat._queue[buf] = nil
    vim.notify("[djinni] Session stopped", vim.log.levels.INFO)
    local lc = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
      "", "---", "", "@System", "New session", "", "---", "", "@You", "", "", "---", "",
    })
    return true
  end

  if cmd.name == "/fork" then
    local root = chat.get_project_root(buf)
    if not root then
      vim.notify("[djinni] No project root", vim.log.levels.WARN)
      return true
    end
    local path = vim.api.nvim_buf_get_name(buf)
    local parent_name = vim.fn.fnamemodify(path, ":t")
    chat.create(root, { parent = parent_name })
    return true
  end

  if cmd.name == "/resume" then
    chat.resume_session(buf, args and vim.trim(args) ~= "" and vim.trim(args) or nil)
    return true
  end

  if cmd.name == "/tree" then
    chat.show_tree(buf)
    return true
  end

  if cmd.name == "/clear" then
    local root = chat.get_project_root(buf)
    local sid = chat.get_session_id(buf) or chat._sessions[buf]
    local provider_name = chat.get_provider(buf)
    if chat._streaming[buf] then
      if chat._stream_cleanup[buf] then chat._stream_cleanup[buf](true) end
    end
    if root and sid and sid ~= "" then
      local session_mod = require("djinni.acp.session")
      session_mod.send_message(root, sid, "/clear", function()
        vim.schedule(function()
          session_mod.close_task_session(root, sid, provider_name)
        end)
      end, nil, provider_name)
      session_mod.unsubscribe_session(root, sid, provider_name)
    end
    chat._sessions[buf] = nil
    local mcp_mod = require("djinni.nowork.mcp")
    if root then mcp_mod.clear_cache(root) end
    chat._set_frontmatter_field(buf, "status", "")
    chat._set_frontmatter_field(buf, "session", "")
    chat._set_frontmatter_field(buf, "tokens", "")
    chat._set_frontmatter_field(buf, "cost", "")
    chat._waiting_input[buf] = nil
    chat._continuation_count[buf] = 0
    chat._last_tool_failed[buf] = false
    chat._queue[buf] = nil
    chat._usage[buf] = nil
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 20, false)
    local fm_end = 0
    for i, line in ipairs(lines) do
      if i > 1 and line == "---" then
        fm_end = i
        break
      end
    end
    if fm_end > 0 then
      vim.api.nvim_buf_set_lines(buf, fm_end, -1, false, {
        "", "@System", "Conversation cleared", "", "---", "", "@You", "", "", "---", "",
      })
      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        vim.api.nvim_win_set_cursor(win, { fm_end + 7, 0 })
      end
    end
    vim.notify("[djinni] Cleared", vim.log.levels.INFO)
    return true
  end

  if cmd.name == "/lesson" then
    local lessons_mod = require("djinni.nowork.lessons")
    local root = chat.get_project_root(buf)
    if not root then
      vim.notify("[djinni] No project root", vim.log.levels.WARN)
      return true
    end
    if not args or args == "" or args == "list" then
      local lessons = lessons_mod.list(root)
      if #lessons == 0 then
        vim.notify("[djinni] No lessons saved", vim.log.levels.INFO)
      else
        local out = {}
        for _, l in ipairs(lessons) do
          out[#out + 1] = string.format("[%s] %s", l.id, l.text)
        end
        vim.notify("[djinni] Lessons:\n" .. table.concat(out, "\n"), vim.log.levels.INFO)
      end
      return true
    end
    if args == "clear" then
      lessons_mod.clear(root)
      vim.notify("[djinni] All lessons cleared", vim.log.levels.INFO)
      return true
    end
    local remove_id = args:match("^remove%s+(%S+)$")
    if remove_id then
      if lessons_mod.remove(root, remove_id) then
        vim.notify("[djinni] Lesson " .. remove_id .. " removed", vim.log.levels.INFO)
      else
        vim.notify("[djinni] Lesson " .. remove_id .. " not found", vim.log.levels.WARN)
      end
      return true
    end
    local source = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    local lesson = lessons_mod.add(root, args, source)
    vim.notify("[djinni] Lesson saved: " .. lesson.text, vim.log.levels.INFO)
    local lc = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
      "", "---", "", "@System", "Lesson saved: " .. lesson.text, "",
    })
    return true
  end

  if cmd.name == "/lessons" then
    local root = chat.get_project_root(buf)
    if not root then
      vim.notify("[djinni] No project root", vim.log.levels.WARN)
      return true
    end
    local extract_prompt = "Analyze this conversation and extract reusable lessons — patterns, corrections, project insights, or things that worked well. Output each as <lesson>one concise sentence</lesson>. Only extract genuinely useful patterns, not obvious things."
    chat.send(buf, extract_prompt)
    return true
  end

  if cmd.forward then
    return false
  end

  return true
end

function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".") - 1

    local model_prefix = line:match("^%s*/model%s+")
    if model_prefix then
      return #model_prefix
    end

    local start = col
    while start > 0 and line:sub(start, start) ~= "/" do
      start = start - 1
    end
    if start > 0 and line:sub(start, start) == "/" then
      return start - 1
    end
    return -3
  end

  local line = vim.api.nvim_get_current_line()
  if line:match("^%s*/model%s") then
    local matches = {}
    for _, model in ipairs(M.get_models(vim.api.nvim_get_current_buf())) do
      local id = model.id or model.label
      if id and id:find(base, 1, true) == 1 then
        table.insert(matches, { word = id, menu = model.label or model.id or "" })
      end
    end
    return matches
  end

  local matches = {}
  local source_labels = {
    ["local"] = "[local]",
    agent = "[agent]",
    skill = "[skill]",
  }
  local slash_cmds = M.get_slash_commands(vim.api.nvim_get_current_buf())
  for _, item in ipairs(slash_cmds) do
    local word = item.slash
    if word and word:find(base, 1, true) == 1 then
      local menu = source_labels[item.source] or ""
      if item.description and item.description ~= "" then
        menu = menu ~= "" and (menu .. " " .. item.description) or item.description
      elseif item.input and item.input.hint then
        menu = menu ~= "" and (menu .. " " .. item.input.hint) or item.input.hint
      end
      table.insert(matches, { word = word, menu = menu })
    end
  end

  return matches
end

return M
