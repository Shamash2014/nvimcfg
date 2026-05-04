local M = {}

function M.new()
  return setmetatable({}, { __index = M })
end

function M:get_completions(context, callback)
  local line = context.line
  local col  = context.cursor[2]
  local before = line:sub(1, col)

  local items = {}
  local cwd = vim.fn.getcwd()

  if before:match("/%w*$") then
    local cmds = require("acp.session").get_commands(cwd)
    for _, c in ipairs(cmds) do
      local desc = c.description or ""
      table.insert(items, {
        label             = "/" .. c.name,
        kind              = vim.lsp.protocol.CompletionItemKind.Event,
        insertText        = c.name,
        documentation     = desc,
        labelDetails      = { description = desc },
        score_offset      = 100,
      })
    end

    local skills = require("acp.skills").load(cwd)
    for _, s in ipairs(skills) do
      local desc = s.description or ""
      table.insert(items, {
        label             = "/" .. s.name,
        kind              = vim.lsp.protocol.CompletionItemKind.Module,
        insertText        = s.name,
        documentation     = desc,
        labelDetails      = { description = desc },
        score_offset      = 90,
      })
    end
  end

  if before:match("@%w*$") then
    local files = vim.fn.systemlist("git ls-files")
    if vim.v.shell_error ~= 0 then
      files = vim.fn.glob("**/*", false, true)
    end

    for _, f in ipairs(files) do
      if type(f) == "string" and #f > 0 then
        table.insert(items, {
          label = "@" .. f,
          kind = vim.lsp.protocol.CompletionItemKind.File,
          insertText = f,
          score_offset = 50,
        })
      end
    end
  end

  callback({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = items,
  })
end

return M
