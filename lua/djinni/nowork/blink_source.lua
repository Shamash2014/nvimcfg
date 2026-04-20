local M = {}
M.__index = M

local function is_compose_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return false end
  return vim.b[bufnr].nowork_compose == true
end

local function buffer_droid(bufnr)
  local id = vim.b[bufnr].nowork_droid
  if not id then return nil end
  local ok, droid_mod = pcall(require, "djinni.nowork.droid")
  if not ok then return nil end
  return droid_mod.active[id]
end

function M.new()
  return setmetatable({}, M)
end

function M:enabled()
  return is_compose_buffer(vim.api.nvim_get_current_buf())
end

function M:get_trigger_characters()
  return { "/", "@", "#" }
end

local function match_prefix(line, col, char, allow_embedded)
  local prefix = line:sub(1, col)
  local s, e, query
  if allow_embedded then
    s, e, query = prefix:find("()" .. char .. "([%w%._%-/:]*)$")
  else
    s, e, query = prefix:find("^%s*()" .. char .. "([%w%._%-/:]*)$")
    if not s then
      s, e, query = prefix:find("\n%s*()" .. char .. "([%w%._%-/:]*)$")
    end
  end
  if not s then return nil end
  local before = s > 1 and prefix:sub(s - 1, s - 1) or ""
  if not allow_embedded and before ~= "" and not before:match("%s") then return nil end
  return s, e, query
end

local function walk_files(root, out, prefix, depth)
  if depth > 4 or #out >= 200 then return end
  if vim.fn.isdirectory(root) == 0 then return end
  for _, name in ipairs(vim.fn.readdir(root) or {}) do
    if not name:match("^%.") then
      local full = root .. "/" .. name
      local rel = prefix == "" and name or (prefix .. "/" .. name)
      local stat = vim.loop.fs_stat(full)
      if stat then
        if stat.type == "file" then
          out[#out + 1] = rel
          if #out >= 200 then return end
        elseif stat.type == "directory" then
          if not name:match("^node_modules$") and not name:match("^target$") and not name:match("^build$") and not name:match("^dist$") then
            walk_files(full, out, rel, depth + 1)
          end
        end
      end
    end
  end
end

local function complete_slash(droid, row, start_col, end_col)
  local cmds = droid and droid.state and droid.state.available_commands or {}
  local kind = vim.lsp.protocol.CompletionItemKind.Function
  local items = {}
  for i, cmd in ipairs(cmds) do
    local name = cmd.name or cmd.id or cmd.command or cmd.label
    if name and name ~= "" then
      local label = "/" .. name
      items[#items + 1] = {
        label = label,
        insertText = label,
        filterText = label,
        detail = cmd.description or cmd.detail,
        kind = kind,
        sortText = string.format("%05d", i),
        textEdit = {
          newText = label,
          range = {
            start = { line = row, character = start_col },
            ["end"] = { line = row, character = end_col },
          },
        },
      }
    end
  end
  return items
end

local function complete_at(droid, row, start_col, end_col)
  local cwd = (droid and droid.opts and droid.opts.cwd) or vim.b.nowork_cwd or vim.fn.getcwd()
  local files = {}
  walk_files(cwd, files, "", 0)
  local kind = vim.lsp.protocol.CompletionItemKind.File
  local items = {}
  for i, rel in ipairs(files) do
    local label = "@" .. rel
    items[#items + 1] = {
      label = label,
      insertText = label,
      filterText = label,
      kind = kind,
      sortText = string.format("%05d", i),
      textEdit = {
        newText = label,
        range = {
          start = { line = row, character = start_col },
          ["end"] = { line = row, character = end_col },
        },
      },
    }
  end
  return items
end

local function complete_hash(droid, row, start_col, end_col)
  local state = droid and droid.state or {}
  local order = state.topo_order or {}
  local tasks = state.tasks or {}
  local kind = vim.lsp.protocol.CompletionItemKind.Reference
  local items = {}
  for i, id in ipairs(order) do
    local t = tasks[id]
    if t then
      local label = "#" .. id
      items[#items + 1] = {
        label = label,
        insertText = label,
        filterText = label,
        detail = t.desc,
        kind = kind,
        sortText = string.format("%05d", i),
        textEdit = {
          newText = label,
          range = {
            start = { line = row, character = start_col },
            ["end"] = { line = row, character = end_col },
          },
        },
      }
    end
  end
  return items
end

function M:get_completions(ctx, resolve)
  local bufnr = ctx and ctx.bufnr or vim.api.nvim_get_current_buf()
  if not is_compose_buffer(bufnr) then
    resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  local line = ctx and ctx.line or vim.api.nvim_get_current_line()
  local cursor = ctx and ctx.cursor or vim.api.nvim_win_get_cursor(0)
  local col = cursor[2]
  local row = cursor[1] - 1
  local droid = buffer_droid(bufnr)

  local items = {}
  local s, e = match_prefix(line, col, "/", false)
  if s then
    items = complete_slash(droid, row, s - 1, col)
  else
    s, e = match_prefix(line, col, "@", true)
    if s then
      items = complete_at(droid, row, s - 1, col)
    else
      s, e = match_prefix(line, col, "#", true)
      if s then
        items = complete_hash(droid, row, s - 1, col)
      end
    end
  end

  resolve({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = items,
  })
end

return M
