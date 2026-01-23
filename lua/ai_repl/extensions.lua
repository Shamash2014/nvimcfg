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
      description = "Show REPL help and commands",
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
      name = "mode",
      display_name = "🎭 mode",
      description = "Switch mode (chat/spec)",
      accessible = true,
      category = "mode",
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
      description = "Clear REPL buffer",
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
