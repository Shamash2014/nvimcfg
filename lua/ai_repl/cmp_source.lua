local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  local buf = vim.api.nvim_get_current_buf()
  local chat_buffer = require("ai_repl.chat_buffer")
  return chat_buffer.is_chat_buffer(buf)
end

function source:get_trigger_characters()
  return { "/" }
end

function source:complete(params, callback)
  local items = {}
  local line = params.line_before_cursor
  local cursor_col = params.cursor.col
  local before_cursor = line:sub(1, cursor_col)

  -- Only trigger after / at start of line or after whitespace
  local trigger_pos = before_cursor:match("^%s*/()") or before_cursor:match("%s*/()$")
  if not trigger_pos then
    callback({ items = items, isIncomplete = false })
    return
  end

  -- Get the typed part after /
  local typed = before_cursor:match("/(.*)") or ""

  local local_cmds = {
    { label = "/help", detail = "Show this help message" },
    { label = "/ext", detail = "All extensions (skills + commands + local)" },
    { label = "/cmd", detail = "Agent slash commands only" },
    { label = "/skill", detail = "Make a skill available to agent" },
    { label = "/new", detail = "Create new session" },
    { label = "/sessions", detail = "List all sessions" },
    { label = "/kill", detail = "Kill current session (terminate process)" },
    { label = "/force-cancel", detail = "Force cancel + kill (for stuck agents)" },
    { label = "/restart", detail = "Restart session (kill and create fresh)" },
    { label = "/mode", detail = "Switch mode or show mode picker" },
    { label = "/chat", detail = "Open/create .chat buffer" },
    { label = "/restart-chat", detail = "Restart conversation in current .chat buffer" },
    { label = "/summarize", detail = "Summarize current conversation" },
    { label = "/cwd", detail = "Show/change working directory" },
    { label = "/queue", detail = "Show queued messages" },
    { label = "/edit", detail = "Edit queued message" },
    { label = "/remove", detail = "Remove queued message" },
    { label = "/clearq", detail = "Clear all queued messages" },
    { label = "/perms", detail = "Show allow rules" },
    { label = "/revoke", detail = "Revoke allow rule" },
    { label = "/clear", detail = "Clear buffer" },
    { label = "/cancel", detail = "Cancel current operation" },
    { label = "/quit", detail = "Close chat buffer" },
    { label = "/debug", detail = "Toggle debug mode" },
    { label = "/ralph", detail = "Ralph Wiggum mode commands" },
    { label = "/ralph-loop", detail = "Start simple re-injection loop" },
    { label = "/cancel-ralph", detail = "Cancel Ralph loop" },
    { label = "/ralph-loop-status", detail = "Show Ralph loop status" },
  }

  -- Add local commands with filtering
  for _, cmd in ipairs(local_cmds) do
    local cmd_name = cmd.label:gsub("^/", "")
    -- Filter by typed text
    if cmd_name:sub(1, #typed) == typed then
      table.insert(items, {
        label = cmd.label,
        kind = require("cmp").lsp.CompletionItemKind.Function,
        detail = cmd.detail,
        documentation = cmd.detail,
      })
    end
  end

  -- Add agent-provided slash commands
  local registry = require("ai_repl.registry")
  local proc = registry.active()

  if proc and proc.data.slash_commands then
    for _, sc in ipairs(proc.data.slash_commands) do
      local cmd_name = sc.name:gsub("^/", "")
      -- Filter by typed text
      if cmd_name:sub(1, #typed) == typed then
        table.insert(items, {
          label = sc.name,
          kind = require("cmp").lsp.CompletionItemKind.Function,
          detail = sc.description or "Agent command",
          documentation = sc.description,
        })
      end
    end
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

return source
