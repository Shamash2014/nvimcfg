local source = {}
source.__index = source

function source.new()
  return setmetatable({}, source)
end

function source:get_trigger_characters()
  return { "@", "#", "/" }
end

local SLASH_CMDS = {
  { name = "/clear",  doc = "clear conversation buffer" },
  { name = "/cancel", doc = "cancel in-flight request" },
  { name = "/diff",   doc = "send git diff for review" },
  { name = "/review", doc = "review staged changes" },
  { name = "/model",  doc = "switch model" },
  { name = "/mode",   doc = "switch mode" },
  { name = "/agent",  doc = "switch agent" },
}

local files = { ts = 0, list = nil }
local rules = { ts = 0, list = nil }
local FILE_TTL = 5000
local RULES_TTL = 10000

local function git_root()
  local cwd = vim.uv.cwd() or "."
  local res =
    vim.system({ "git", "-C", cwd, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if res.code == 0 then return (res.stdout or ""):gsub("\n$", "") end
  return nil
end

local function list_files()
  local now = vim.uv.now()
  if files.list and (now - files.ts) < FILE_TTL then return files.list end
  local root = git_root()
  if not root then
    files = { ts = now, list = {} }
    return files.list
  end
  local res = vim.system({ "git", "-C", root, "ls-files" }, { text = true }):wait()
  local out = {}
  if res.code == 0 then
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      table.insert(out, line)
    end
  end
  files = { ts = now, list = out }
  return out
end

local function list_rules()
  local now = vim.uv.now()
  if rules.list and (now - rules.ts) < RULES_TTL then return rules.list end
  local out = {}
  local cwd = vim.uv.cwd() or "."
  local dir = cwd
  local seen = {}
  for _ = 1, 8 do
    for _, name in ipairs({ "AGENT.md", "AGENTS.md", "CLAUDE.md" }) do
      local path = dir .. "/" .. name
      if not seen[path] and vim.uv.fs_stat(path) then
        seen[path] = true
        local ok, lines = pcall(vim.fn.readfile, path)
        if ok then
          for _, line in ipairs(lines) do
            local heading = line:match("^#+%s+(.+)$")
            if heading then
              table.insert(out, { name = heading, source = path })
            end
          end
        end
      end
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then break end
    dir = parent
  end
  rules = { ts = now, list = out }
  return out
end

local function file_kind()
  local ok, kinds = pcall(function() return vim.lsp.protocol.CompletionItemKind end)
  if ok and kinds then return kinds.File, kinds.Reference, kinds.Keyword end
  return 17, 18, 14
end

function source:get_completions(ctx, callback)
  local KIND_FILE, KIND_REF, KIND_KEY = file_kind()
  local before = ctx.line:sub(1, ctx.cursor[2])
  local trigger = before:match("([@#/])[%w_./%-]*$")
  if not trigger then
    callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
    return
  end

  local items = {}

  if trigger == "@" then
    for _, path in ipairs(list_files()) do
      local insert = "@" .. path
      table.insert(items, {
        label = insert,
        insertText = insert,
        kind = KIND_FILE,
        filterText = insert,
        detail = vim.fs.basename(path),
      })
    end
  elseif trigger == "#" then
    for _, r in ipairs(list_rules()) do
      local insert = "#" .. r.name
      table.insert(items, {
        label = insert,
        insertText = insert,
        kind = KIND_REF,
        filterText = insert,
        detail = vim.fs.basename(r.source),
      })
    end
  elseif trigger == "/" then
    for _, cmd in ipairs(SLASH_CMDS) do
      table.insert(items, {
        label = cmd.name,
        insertText = cmd.name,
        kind = KIND_KEY,
        filterText = cmd.name,
        detail = cmd.doc,
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
