local M = {}

M._cache = M._cache or {}

local function resolve_root(buf)
  local ok, document = pcall(require, "neowork.document")
  if ok then
    local root = document.read_frontmatter_field(buf, "root")
    if root and root ~= "" then return root end
  end
  return vim.fn.getcwd()
end

local function run(cmd, cwd)
  local out = vim.fn.systemlist({ "sh", "-c", "cd " .. vim.fn.shellescape(cwd) .. " && " .. cmd })
  if vim.v.shell_error ~= 0 then return nil end
  return out
end

local function collect(root)
  if vim.fn.isdirectory(root .. "/.git") == 1 or vim.fn.finddir(".git", root .. ";") ~= "" then
    local out = run("git ls-files -co --exclude-standard", root)
    if out and #out > 0 then return out end
  end
  if vim.fn.executable("rg") == 1 then
    local out = run("rg --files --hidden --glob '!.git'", root)
    if out and #out > 0 then return out end
  end
  local out = run("find . -type f -not -path './.git/*' | sed 's|^\\./||'", root)
  return out or {}
end

local function open_buffer_paths(root)
  local root_sep = root:sub(-1) == "/" and root or (root .. "/")
  local paths = {}
  local seen = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and name:sub(1, #root_sep) == root_sep then
        local rel = name:sub(#root_sep + 1)
        if rel ~= "" and not seen[rel] then
          paths[#paths + 1] = rel
          seen[rel] = true
        end
      end
    end
  end
  return paths, seen
end

function M.list(buf)
  local c = M._cache[buf]
  if c and c.time and (vim.loop.now() - c.time) < 10000 then
    return c.items
  end

  local root = resolve_root(buf)
  local files = collect(root)
  local open_paths, open_set = open_buffer_paths(root)

  local items = {}
  for _, p in ipairs(open_paths) do
    items[#items + 1] = { path = p, open = true }
  end
  for _, p in ipairs(files) do
    if not open_set[p] then
      items[#items + 1] = { path = p, open = false }
    end
  end

  M._cache[buf] = { items = items, time = vim.loop.now(), root = root }
  return items
end

function M.invalidate(buf)
  if buf then
    M._cache[buf] = nil
  else
    M._cache = {}
  end
end

local augroup = vim.api.nvim_create_augroup("NeoworkFileSources", { clear = true })
vim.api.nvim_create_autocmd({ "BufWritePost", "BufDelete", "DirChanged" }, {
  group = augroup,
  callback = function() M.invalidate() end,
})

return M
