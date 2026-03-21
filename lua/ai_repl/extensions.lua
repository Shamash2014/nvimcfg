local M = {}

local EXTENSION_TYPES = {
  SKILL = "skill",
  COMMAND = "command",
  LOCAL = "local",
}

function M.discover_all_extensions(provider_id)
  local extensions = {}

  local skills_module = require("ai_repl.skills")
  local skills = skills_module.list_skills()

  for _, skill in ipairs(skills) do
    local is_accessible = skills_module.verify_skill_accessible(skill.name, provider_id)

    table.insert(extensions, {
      type = EXTENSION_TYPES.SKILL,
      name = skill.name,
      display_name = "📚 " .. skill.name,
      description = skill.description,
      version = skill.version,
      accessible = is_accessible,
      category = "skills",
      invoke = function()
        return { type = "activate_skill", skill_name = skill.name }
      end,
    })
  end

  return extensions
end

function M.merge_with_agent_commands(extensions, slash_commands)
  local merged = vim.deepcopy(extensions)

  for _, cmd in ipairs(slash_commands or {}) do
    table.insert(merged, {
      type = EXTENSION_TYPES.COMMAND,
      name = cmd.name,
      display_name = "⚡ " .. cmd.name,
      description = cmd.description or "",
      accessible = true,
      category = "agent",
      invoke = function()
        return { type = "slash_command", command = cmd }
      end,
    })
  end

  return merged
end

function M.get_local_commands()
  return {
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "help",
      display_name = "📖 help",
      description = "Show chat help and commands",
      accessible = true,
      category = "system",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "new",
      display_name = "✨ new",
      description = "Start a new session",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "sessions",
      display_name = "📋 sessions",
      description = "List and switch sessions",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "start",
      display_name = "▶️ start",
      description = "Start AI session for current .chat buffer",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "init",
      display_name = "🚀 init",
      description = "Initialize AI session (alias for /start)",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "mode",
      display_name = "🎭 mode",
      description = "Switch mode (chat/spec)",
      accessible = true,
      category = "mode",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "config",
      display_name = "⚙️ config",
      description = "Show session config options picker",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "chat",
      display_name = "💬 chat",
      description = "Open/create .chat buffer",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "chat-new",
      display_name = "✨ chat-new",
      description = "Start chat in current buffer or create new",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "restart-chat",
      display_name = "🔄 restart-chat",
      description = "Restart conversation in current .chat buffer",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "summarize",
      display_name = "📝 summarize",
      description = "Summarize current conversation",
      accessible = true,
      category = "messages",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "spec",
      display_name = "📄 spec",
      description = "Export spec to markdown",
      accessible = true,
      category = "mode",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "cwd",
      display_name = "📂 cwd",
      description = "Show/change working directory",
      accessible = true,
      category = "system",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "strategy",
      display_name = "🎯 strategy",
      description = "Show/set session strategy (new/latest/prompt/new-deferred)",
      accessible = true,
      category = "session",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "edit",
      display_name = "✏️ edit",
      description = "Edit queued message",
      accessible = true,
      category = "messages",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "remove",
      display_name = "🗑️ remove",
      description = "Remove queued message",
      accessible = true,
      category = "messages",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "clearq",
      display_name = "🧹 clearq",
      description = "Clear all queued messages",
      accessible = true,
      category = "messages",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "revoke",
      display_name = "🔓 revoke",
      description = "Revoke allow rule",
      accessible = true,
      category = "security",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "kill",
      display_name = "☠️ kill",
      description = "Kill current session (terminate process)",
      accessible = true,
      category = "control",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "restart",
      display_name = "♻️ restart",
      description = "Restart session (kill and create fresh)",
      accessible = true,
      category = "control",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "force-cancel",
      display_name = "🛑 force-cancel",
      description = "Force cancel + kill (for stuck agents)",
      accessible = true,
      category = "control",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "quit",
      display_name = "🚪 quit",
      description = "Close chat buffer",
      accessible = true,
      category = "control",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "debug",
      display_name = "🐛 debug",
      description = "Toggle debug mode",
      accessible = true,
      category = "system",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "ralph",
      display_name = "🎭 ralph",
      description = "Ralph Wiggum mode commands",
      accessible = true,
      category = "mode",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "ralph-loop",
      display_name = "🔁 ralph-loop",
      description = "Start simple re-injection loop",
      accessible = true,
      category = "mode",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "cancel-ralph",
      display_name = "⏹️ cancel-ralph",
      description = "Cancel Ralph loop",
      accessible = true,
      category = "control",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "ralph-loop-status",
      display_name = "📊 ralph-loop-status",
      description = "Show Ralph loop status",
      accessible = true,
      category = "system",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "queue",
      display_name = "📬 queue",
      description = "Show queued messages",
      accessible = true,
      category = "messages",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "perms",
      display_name = "🔒 perms",
      description = "Show permission rules",
      accessible = true,
      category = "security",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "clear",
      display_name = "🧹 clear",
      description = "Clear chat buffer",
      accessible = true,
      category = "system",
    },
    {
      type = EXTENSION_TYPES.LOCAL,
      name = "cancel",
      display_name = "🛑 cancel",
      description = "Cancel current operation",
      accessible = true,
      category = "control",
    },
  }
end

function M.create_unified_picker(proc)
  local provider_id = proc.data.provider or "claude"

  local extensions = M.discover_all_extensions(provider_id)

  extensions = M.merge_with_agent_commands(extensions, proc.data.slash_commands)

  local local_cmds = M.get_local_commands()
  for _, cmd in ipairs(local_cmds) do
    table.insert(extensions, cmd)
  end

  table.sort(extensions, function(a, b)
    if a.category ~= b.category then
      local order = { skills = 1, agent = 2, mode = 3, session = 4, messages = 5, security = 6, control = 7, system = 8 }
      return (order[a.category] or 99) < (order[b.category] or 99)
    end
    return a.name < b.name
  end)

  return extensions
end

function M.format_extension_for_display(ext)
  local status = ""
  if ext.type == EXTENSION_TYPES.SKILL then
    status = ext.accessible and "" or " ⚠️"
  end

  local category_prefix = ""
  if ext.category == "skills" then
    category_prefix = "[Skill] "
  elseif ext.category == "agent" then
    category_prefix = "[Agent] "
  elseif ext.category == "mode" then
    category_prefix = "[Mode] "
  elseif ext.category == "session" then
    category_prefix = "[Session] "
  end

  local desc = ext.description
  if #desc > 70 then
    desc = desc:sub(1, 67) .. "..."
  end

  return category_prefix .. ext.display_name .. status .. " - " .. desc
end

return M
