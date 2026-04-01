local M = {}

function M.get_models(buf)
  local chat = require("djinni.nowork.chat")
  local session = require("djinni.acp.session")
  local provider = require("djinni.acp.provider")
  local root = chat.get_project_root(buf)
  local provider_name = chat.get_provider(buf)
  local available = session.get_available_models(root, provider_name)
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
  { name = "/help", args = false, forward = false },
}

function M.get_names()
  local names = {}
  for _, cmd in ipairs(M.commands) do
    table.insert(names, cmd.name)
  end
  return names
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
    chat._set_frontmatter_field(buf, "provider", args)
    local lc = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, {
      "", "---", "", "@System", "Provider: " .. args, "",
    })
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
      vim.ui.select(discovered, {
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
      vim.ui.select(items, {
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

  if cmd.name == "/clear" then
    local mcp_mod = require("djinni.nowork.mcp")
    local root = chat.get_project_root(buf)
    if root then mcp_mod.clear_cache(root) end
    if chat._streaming[buf] then
      if chat._stream_cleanup[buf] then chat._stream_cleanup[buf](true) end
    end
    chat._set_frontmatter_field(buf, "session", "")
    chat._set_frontmatter_field(buf, "status", "")
    chat._set_frontmatter_field(buf, "tokens", "")
    chat._set_frontmatter_field(buf, "cost", "")
    chat._sessions[buf] = nil
    chat._continuation_count[buf] = 0
    chat._last_tool_failed[buf] = false
    chat._queue[buf] = nil
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
        "", "@You", "", "", "---", "",
      })
      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        vim.api.nvim_win_set_cursor(win, { fm_end + 2, 0 })
      end
    end
    vim.notify("[djinni] Buffer cleared", vim.log.levels.INFO)
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
      if model:find(base, 1, true) == 1 then
        table.insert(matches, { word = model })
      end
    end
    return matches
  end

  local matches = {}
  for _, cmd in ipairs(M.commands) do
    if cmd.name:find(base, 1, true) == 1 then
      table.insert(matches, {
        word = cmd.name,
        menu = cmd.args and "<args>" or "",
      })
    end
  end

  local ok_chat, chat = pcall(require, "djinni.nowork.chat")
  local ok_skills, skills_mod = pcall(require, "djinni.nowork.skills")
  if ok_chat and ok_skills then
    local root = chat.get_project_root(vim.api.nvim_get_current_buf())
    local discovered = skills_mod.discover(root)
    for _, skill in ipairs(discovered) do
      local word = "/" .. skill.name
      if word:find(base, 1, true) == 1 then
        table.insert(matches, { word = word, menu = skill.description or "" })
      end
    end
  end

  return matches
end

return M
