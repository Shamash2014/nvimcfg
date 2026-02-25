local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  local buf = vim.api.nvim_get_current_buf()
  local chat_buffer = require("ai_repl.chat_buffer")
  return chat_buffer.is_chat_buffer(buf)
end

function source:get_trigger_characters()
  return { "/", "@" }
end

function source:get_completions(ctx, callback)
  local items = {}
  local line = ctx.line
  local cursor_col = ctx.cursor[2]
  local before_cursor = line:sub(1, cursor_col)

  -- Check for @ file reference trigger
  local at_typed = before_cursor:match("@([^%s{}]*)$")
  if at_typed then
    local file_refs = require("ai_repl.file_references")
    local buf = vim.api.nvim_get_current_buf()
    local state = require("ai_repl.chat_state").get_buffer_state(buf)
    local project_root = state.repo_root or vim.fn.getcwd()

    table.insert(items, {
      label = "@{file}",
      filterText = "{file}",
      kind = vim.lsp.protocol.CompletionItemKind.File,
      documentation = {
        kind = "markdown",
        value = "Current file (this .chat file, or last edited file in REPL)",
      },
    })

    local candidates = file_refs.get_completion_candidates(at_typed, project_root, 30)
    for _, filepath in ipairs(candidates) do
      table.insert(items, {
        label = "@" .. filepath,
        filterText = filepath,
        kind = vim.lsp.protocol.CompletionItemKind.File,
        documentation = {
          kind = "markdown",
          value = "Attach file: " .. filepath,
        },
      })
    end

    callback({
      items = items,
      is_incomplete_backward = true,
      is_incomplete_forward = true,
    })
    return
  end

  -- Only trigger after / at start of line or after whitespace
  local trigger_pos = before_cursor:match("^%s*/()") or before_cursor:match("%s*/()$")
  if not trigger_pos then
    callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
    return
  end

  -- Get the typed part after /
  local typed = before_cursor:match("/(.*)") or ""

  local local_cmds = {
    { name = "help", desc = "Show this help message" },
    { name = "ext", desc = "All extensions (skills + commands + local)" },
    { name = "cmd", desc = "Agent slash commands only" },
    { name = "skill", desc = "Make a skill available to agent" },
    { name = "new", desc = "Create new session" },
    { name = "sessions", desc = "List all sessions" },
    { name = "start", desc = "Start AI session for current .chat buffer" },
    { name = "init", desc = "Initialize AI session (alias for /start)" },
    { name = "kill", desc = "Kill current session (terminate process)" },
    { name = "force-cancel", desc = "Force cancel + kill (for stuck agents)" },
    { name = "restart", desc = "Restart session (kill and create fresh)" },
    { name = "mode", desc = "Switch mode or show mode picker" },
    { name = "config", desc = "Show session config options picker" },
    { name = "chat", desc = "Open/create .chat buffer" },
    { name = "chat-new", desc = "Start chat in current buffer or create new" },
    { name = "restart-chat", desc = "Restart conversation in current .chat buffer" },
    { name = "summarize", desc = "Summarize current conversation" },
    { name = "cwd", desc = "Show/change working directory" },
    { name = "strategy", desc = "Show/set session strategy (new/latest/prompt/new-deferred)" },
    { name = "queue", desc = "Show queued messages" },
    { name = "edit", desc = "Edit queued message" },
    { name = "remove", desc = "Remove queued message" },
    { name = "clearq", desc = "Clear all queued messages" },
    { name = "perms", desc = "Show allow rules" },
    { name = "revoke", desc = "Revoke allow rule" },
    { name = "clear", desc = "Clear buffer" },
    { name = "cancel", desc = "Cancel current operation" },
    { name = "quit", desc = "Close chat buffer" },
    { name = "debug", desc = "Toggle debug mode" },
    { name = "ralph", desc = "Ralph Wiggum mode commands" },
    { name = "ralph-loop", desc = "Start simple re-injection loop" },
    { name = "cancel-ralph", desc = "Cancel Ralph loop" },
    { name = "ralph-loop-status", desc = "Show Ralph loop status" },
  }

  -- Add local commands
  for _, cmd in ipairs(local_cmds) do
    -- Filter by typed text
    if cmd.name:sub(1, #typed) == typed then
      table.insert(items, {
        label = "/" .. cmd.name,
        filterText = cmd.name,
        kind = vim.lsp.protocol.CompletionItemKind.Function,
        documentation = {
          kind = "markdown",
          value = cmd.desc,
        },
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
          filterText = cmd_name,
          kind = vim.lsp.protocol.CompletionItemKind.Function,
          documentation = {
            kind = "markdown",
            value = sc.description or "Agent command",
          },
        })
      end
    end
  end

  callback({
    items = items,
    is_incomplete_backward = false,
    is_incomplete_forward = false,
  })
end

return source
