local M = {}
M.__index = M

local function is_chat_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  return name:sub(-5) == ".chat"
end

function M.new()
  return setmetatable({}, M)
end

function M:enabled()
  return is_chat_buffer(vim.api.nvim_get_current_buf())
end

function M:get_trigger_characters()
  return { "@" }
end

local function match_at_prefix(line, col)
  local prefix = line:sub(1, col)
  local at_start, at_end, query = prefix:find("()@(%S*)$")
  if not at_start then return nil end
  local before = at_start > 1 and prefix:sub(at_start - 1, at_start - 1) or ""
  if before ~= "" and not before:match("%s") then return nil end
  return at_start, at_end, query
end

function M:get_completions(ctx, resolve)
  local bufnr = ctx and ctx.bufnr or vim.api.nvim_get_current_buf()
  if not is_chat_buffer(bufnr) then
    resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  local line = ctx and ctx.line or vim.api.nvim_get_current_line()
  local cursor = ctx and ctx.cursor or vim.api.nvim_win_get_cursor(0)
  local col = cursor[2]
  local at_start = match_at_prefix(line, col)
  if not at_start then
    resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  local row = cursor[1] - 1
  local start_col = at_start - 1
  local end_col = col

  local file_sources = require("neowork.file_sources")
  local entries = file_sources.list(bufnr) or {}
  local kind_file = vim.lsp.protocol.CompletionItemKind.File

  local items = {}
  for i, entry in ipairs(entries) do
    local label = "@./" .. entry.path
    items[#items + 1] = {
      label = label,
      insertText = label,
      filterText = label,
      kind = kind_file,
      sortText = string.format("%s%05d", entry.open and "0" or "1", i),
      textEdit = {
        newText = label,
        range = {
          start = { line = row, character = start_col },
          ["end"] = { line = row, character = end_col },
        },
      },
    }
  end

  resolve({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = items,
  })
end

return M
