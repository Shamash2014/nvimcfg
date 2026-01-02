local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  return vim.bo.filetype == "ai_repl"
end

function source:get_trigger_characters()
  return { "/" }
end

function source:get_completions(ctx, callback)
  local items = {}
  local line = ctx.line
  local cursor_col = ctx.cursor[2]
  local before_cursor = line:sub(1, cursor_col)

  local local_cmds = {
    { name = "help", desc = "Show help" },
    { name = "clear", desc = "Clear buffer" },
    { name = "mode", desc = "Switch mode" },
    { name = "modes", desc = "List modes" },
    { name = "commands", desc = "Agent commands" },
    { name = "plan", desc = "Show plan" },
    { name = "sessions", desc = "Session picker" },
    { name = "new", desc = "New session" },
    { name = "root", desc = "Project root" },
    { name = "quit", desc = "Close" },
  }

  for _, cmd in ipairs(local_cmds) do
    table.insert(items, {
      label = "/" .. cmd.name,
      filterText = cmd.name,
      kind = vim.lsp.protocol.CompletionItemKind.Function,
      documentation = cmd.desc,
    })
  end

  local ok, ai_repl = pcall(require, "ai_repl")
  if ok and ai_repl.get_slash_commands then
    for _, cmd in ipairs(ai_repl.get_slash_commands()) do
      table.insert(items, {
        label = "/" .. cmd.name,
        filterText = cmd.name,
        kind = vim.lsp.protocol.CompletionItemKind.Function,
        documentation = cmd.description or "",
      })
    end
  end

  callback({
    items = items,
    is_incomplete_backward = false,
    is_incomplete_forward = false,
  })
end

return source
