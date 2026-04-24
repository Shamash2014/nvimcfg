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

local function walk_files(root, out, prefix, depth, cap)
  cap = cap or 1000
  if depth > 6 or #out >= cap then return end
  if vim.fn.isdirectory(root) == 0 then return end
  for _, name in ipairs(vim.fn.readdir(root) or {}) do
    if not name:match("^%.") then
      local full = root .. "/" .. name
      local rel = prefix == "" and name or (prefix .. "/" .. name)
      local stat = vim.loop.fs_stat(full)
      if stat then
        if stat.type == "file" then
          out[#out + 1] = rel
          if #out >= cap then return end
        elseif stat.type == "directory" then
          if not name:match("^node_modules$") and not name:match("^target$")
             and not name:match("^build$") and not name:match("^dist$")
             and not name:match("^%.git$") then
            walk_files(full, out, rel, depth + 1, cap)
          end
        end
      end
    end
  end
end

local FILE_CACHE = {}
local FILE_CACHE_TTL = 5

local function is_git_repo(cwd)
  local result = vim.system({ "git", "-C", cwd, "rev-parse", "--is-inside-work-tree" },
    { text = true, timeout = 500 }):wait()
  return result and result.code == 0 and (result.stdout or ""):match("true") ~= nil
end

local function git_ls_files(cwd)
  local result = vim.system(
    { "git", "-C", cwd, "ls-files", "-co", "--exclude-standard" },
    { text = true, timeout = 2000 }
  ):wait()
  if not result or result.code ~= 0 then return nil end
  local out = {}
  for line in (result.stdout or ""):gmatch("[^\n]+") do
    if line ~= "" then out[#out + 1] = line end
    if #out >= 5000 then break end
  end
  return out
end

local function list_files(cwd)
  local now = os.time()
  local cached = FILE_CACHE[cwd]
  if cached and (now - cached.at) < FILE_CACHE_TTL then
    return cached.files
  end
  local files
  if is_git_repo(cwd) then
    files = git_ls_files(cwd)
  end
  if not files then
    files = {}
    walk_files(cwd, files, "", 0, 1000)
  end
  FILE_CACHE[cwd] = { at = now, files = files }
  return files
end

local function load_skills(cwd)
  local ok, skills = pcall(require("djinni.acp.skills").load, cwd)
  if not ok or type(skills) ~= "table" then return {} end
  return skills
end

local function normalize_command_name(cmd)
  local raw = cmd and (cmd.name or cmd.id or cmd.command or cmd.label) or nil
  if type(raw) ~= "string" then return nil end
  local name = vim.trim(raw):gsub("^/+", "")
  if name == "" then return nil end
  return name
end

local function complete_slash(droid, row, start_col, end_col)
  local cmds = droid and droid.state and droid.state.available_commands or {}
  local cmd_kind = vim.lsp.protocol.CompletionItemKind.Function
  local skill_kind = vim.lsp.protocol.CompletionItemKind.Module
  local items = {}
  local seen = {}
  local i = 0
  for _, cmd in ipairs(cmds) do
    local name = normalize_command_name(cmd)
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      i = i + 1
      local label = "/" .. name
      items[#items + 1] = {
        label = label,
        insertText = label,
        filterText = label,
        detail = cmd.description or cmd.detail,
        kind = cmd_kind,
        sortText = string.format("1-%05d", i),
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
  local cwd = (droid and droid.opts and droid.opts.cwd) or vim.b.nowork_cwd or vim.fn.getcwd()
  local skills = load_skills(cwd)
  local j = 0
  for _, skill in ipairs(skills) do
    local name = skill.name
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      j = j + 1
      local label = "/" .. name
      local insert = "Use the " .. name .. " skill."
      items[#items + 1] = {
        label = label,
        insertText = insert,
        filterText = label,
        detail = (skill.description or "skill") .. " · djinni-skill",
        kind = skill_kind,
        sortText = string.format("2-%05d", j),
        textEdit = {
          newText = insert,
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
  local files = list_files(cwd)
  local kind = vim.lsp.protocol.CompletionItemKind.File
  local items = {}
  for i, rel in ipairs(files) do
    local label = "@" .. rel
    local basename = rel:match("([^/]+)$") or rel
    items[#items + 1] = {
      label = label,
      insertText = label,
      filterText = basename .. " " .. rel,
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
  local skill_kind = vim.lsp.protocol.CompletionItemKind.Module
  local items = {}
  local seen = {}
  for i, id in ipairs(order) do
    local t = tasks[id]
    if t then
      local label = "#" .. id
      seen[label] = true
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

  local cwd = (droid and droid.opts and droid.opts.cwd) or vim.b.nowork_cwd or vim.fn.getcwd()
  for i, skill in ipairs(load_skills(cwd)) do
    local name = skill.name
    local label = name and ("#" .. name) or nil
    if label and label ~= "#" and not seen[label] then
      seen[label] = true
      items[#items + 1] = {
        label = label,
        insertText = label,
        filterText = label .. " " .. (skill.description or ""),
        detail = (skill.description or "skill") .. " · djinni-skill",
        kind = skill_kind,
        sortText = string.format("1-%05d", i),
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
