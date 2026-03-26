local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  local buf = vim.api.nvim_get_current_buf()
  return vim.bo[buf].filetype == "nowork-chat"
end

function source:get_trigger_characters()
  return { "/", "@" }
end

function source:get_completions(ctx, callback)
  local items = {}
  local line = ctx.line
  local cursor_col = ctx.cursor[2]
  local before_cursor = line:sub(1, cursor_col)

  local at_typed = before_cursor:match("@([^%s{}]*)$")
  if at_typed then
    table.insert(items, {
      label = "@{file}",
      filterText = "@{file}",
      kind = vim.lsp.protocol.CompletionItemKind.Variable,
      documentation = { kind = "markdown", value = "Current active buffer" },
    })
    table.insert(items, {
      label = "@{selection}",
      filterText = "@{selection}",
      kind = vim.lsp.protocol.CompletionItemKind.Variable,
      documentation = { kind = "markdown", value = "Current visual selection" },
    })

    local root = vim.fn.getcwd()
    local pattern = root .. "/" .. (at_typed == "" and "*" or at_typed .. "*")
    local files = vim.fn.glob(pattern, false, true)
    local count = 0
    for _, filepath in ipairs(files) do
      if count >= 30 then break end
      local rel = filepath:sub(#root + 2)
      if not rel:match("^%.git/") and not rel:match("^%.chat/") then
        count = count + 1
        local is_dir = vim.fn.isdirectory(filepath) == 1
        table.insert(items, {
          label = "@./" .. rel .. (is_dir and "/" or ""),
          filterText = "@./" .. rel,
          kind = is_dir and vim.lsp.protocol.CompletionItemKind.Folder
            or vim.lsp.protocol.CompletionItemKind.File,
        })
      end
    end

    callback({ items = items, is_incomplete_backward = true, is_incomplete_forward = true })
    return
  end

  local model_arg = before_cursor:match("^%s*/model%s+(.*)$")
  if model_arg then
    local commands = require("djinni.nowork.commands")
    for _, model in ipairs(commands.models) do
      if model:find(model_arg, 1, true) == 1 or model_arg == "" then
        table.insert(items, {
          label = model,
          kind = vim.lsp.protocol.CompletionItemKind.EnumMember,
        })
      end
    end
    callback({ items = items, is_incomplete_backward = false, is_incomplete_forward = false })
    return
  end

  local skill_arg = before_cursor:match("^%s*/skill%s+(.*)$")
  if skill_arg then
    local skills = require("djinni.nowork.skills")
    local root = vim.fn.getcwd()
    for _, name in ipairs(skills.list_names(root)) do
      if name:find(skill_arg, 1, true) == 1 or skill_arg == "" then
        table.insert(items, {
          label = name,
          kind = vim.lsp.protocol.CompletionItemKind.EnumMember,
        })
      end
    end
    callback({ items = items, is_incomplete_backward = false, is_incomplete_forward = false })
    return
  end

  if before_cursor:match("^%s*/") then
    local typed = before_cursor:match("/(.*)$") or ""
    local commands = require("djinni.nowork.commands")
    for _, cmd in ipairs(commands.commands) do
      if cmd.name:find("/" .. typed, 1, true) == 1 then
        table.insert(items, {
          label = cmd.name,
          kind = vim.lsp.protocol.CompletionItemKind.Function,
          documentation = cmd.args and { kind = "markdown", value = "Takes arguments" } or nil,
        })
      end
    end
    callback({ items = items, is_incomplete_backward = false, is_incomplete_forward = false })
    return
  end

  callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
end

return source
