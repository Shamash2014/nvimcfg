local M = {}

local cache = {
  branch = nil,
  count = 0,
  is_secondary = false,
  fetched_at = 0,
  inflight = false,
}
local TTL_MS = 5000

local function parse_porcelain(text)
  local list = {}
  local entry = {}
  for line in (text or ""):gmatch("[^\n]+") do
    if line:sub(1, 9) == "worktree " then
      if entry.path then table.insert(list, entry) end
      entry = { path = line:sub(10) }
    elseif line:sub(1, 7) == "branch " then
      entry.branch = (line:sub(8)):gsub("^refs/heads/", "")
    elseif line == "bare" then
      entry.bare = true
    elseif line == "detached" then
      entry.detached = true
    end
  end
  if entry.path then table.insert(list, entry) end
  return list
end

local function path_under(parent, child)
  if not parent or not child then return false end
  if child == parent then return true end
  return child:sub(1, #parent + 1) == parent .. "/"
end

local function refresh()
  if cache.inflight then return end
  cache.inflight = true
  local cwd = vim.uv.cwd() or ""
  vim.system(
    { "git", "-C", cwd, "worktree", "list", "--porcelain" },
    { text = true },
    function(out)
      local list = out.code == 0 and parse_porcelain(out.stdout) or {}
      local primary = list[1]
      local current
      for _, e in ipairs(list) do
        if path_under(e.path, cwd) then
          current = e
        end
      end
      cache.branch = current
          and (current.branch or (current.detached and "detached" or (current.bare and "bare" or "")))
        or nil
      cache.count = #list
      cache.is_secondary = current and primary and current.path ~= primary.path or false
      cache.fetched_at = vim.uv.now()
      cache.inflight = false
      vim.schedule(function()
        pcall(vim.cmd, "redrawstatus")
      end)
    end
  )
end

function M.piece()
  if not cache.branch or cache.count <= 1 then return "" end
  local marker = cache.is_secondary and "wt" or "main"
  return string.format(" %s:%s(%d) ", marker, cache.branch, cache.count)
end

function M.refresh()
  refresh()
end

function M.info()
  return vim.deepcopy(cache)
end

local function list_sync()
  local cwd = vim.uv.cwd() or ""
  local res =
    vim.system({ "git", "-C", cwd, "worktree", "list", "--porcelain" }, { text = true }):wait()
  if res.code ~= 0 then return {} end
  return parse_porcelain(res.stdout)
end

function M.list()
  return list_sync()
end

function M.info_for(cwd)
  cwd = cwd or vim.uv.cwd() or ""
  local entries = list_sync()
  if #entries == 0 then return nil end
  local main = entries[1]
  for _, e in ipairs(entries) do
    if path_under(e.path, cwd) then
      return {
        path = e.path,
        branch = e.branch or (e.detached and "detached" or (e.bare and "bare" or "?")),
        main_repo = main and main.path or e.path,
        is_secondary = main and e.path ~= main.path or false,
      }
    end
  end
  return nil
end

local function notify_result(prefix, out)
  if out.code == 0 then
    local msg = (out.stdout or ""):match("[^\n]+") or ""
    vim.notify(prefix .. (msg ~= "" and (": " .. msg) or " ok"), vim.log.levels.INFO)
  else
    vim.notify(
      prefix .. " failed: " .. ((out.stderr or out.stdout or ""):gsub("%s+$", "")),
      vim.log.levels.ERROR
    )
  end
end

local function run_wt(args, prefix, on_ok)
  if vim.fn.executable("wt") ~= 1 then
    vim.notify("wt: binary not found on PATH", vim.log.levels.ERROR)
    return
  end
  vim.system(args, { text = true }, function(out)
    vim.schedule(function()
      notify_result(prefix, out)
      refresh()
      if out.code == 0 and on_ok then on_ok(out) end
    end)
  end)
end

local function open_neogit()
  local ok, neogit = pcall(require, "neogit")
  if ok then neogit.open() end
end

function M.switch(path, opts)
  opts = opts or {}
  if not path or path == "" then return end
  vim.cmd("cd " .. vim.fn.fnameescape(path))
  refresh()
  if opts.neogit then open_neogit() end
end

function M.create(branch, opts)
  opts = opts or {}
  if not branch or branch == "" then return end
  run_wt({ "wt", "switch", "--create", branch, "-y" }, "wt create " .. branch, function()
    vim.defer_fn(function()
      for _, e in ipairs(list_sync()) do
        if e.branch == branch then
          M.switch(e.path, opts)
          return
        end
      end
    end, 150)
  end)
end

function M.remove(path)
  path = path or vim.uv.cwd()
  if not path then return end
  run_wt({ "wt", "-C", path, "remove", "-y" }, "wt remove " .. vim.fs.basename(path))
end

function M.merge(target)
  local args = { "wt", "merge", "-y" }
  if target and target ~= "" then table.insert(args, target) end
  run_wt(args, "wt merge")
end

function M.pick(opts)
  opts = opts or { neogit = false }
  local list = list_sync()
  if #list == 0 then
    vim.notify("wt: no worktrees", vim.log.levels.WARN)
    return
  end
  local cwd = vim.uv.cwd() or ""
  vim.ui.select(list, {
    prompt = opts.neogit and "Worktrees -> Neogit" or "Worktrees",
    format_item = function(e)
      local label = e.branch or (e.detached and "detached" or (e.bare and "bare" or "?"))
      local here = path_under(e.path, cwd) and " *" or ""
      return string.format("%-30s  %s%s", label, e.path, here)
    end,
  }, function(choice)
    if not choice then return end
    M.switch(choice.path, opts)
  end)
end

local function user_command(opts)
  local args = vim.split(opts.args or "", "%s+", { trimempty = true })
  local sub = args[1] or "pick"
  if sub == "pick" then
    M.pick({ neogit = false })
  elseif sub == "neogit" then
    M.pick({ neogit = true })
  elseif sub == "create" then
    local branch = args[2]
    if not branch then
      branch = vim.fn.input("wt create branch: ")
    end
    M.create(branch, { neogit = true })
  elseif sub == "remove" then
    M.remove(args[2])
  elseif sub == "merge" then
    M.merge(args[2])
  elseif sub == "list" then
    for _, e in ipairs(list_sync()) do
      print(string.format("%s\t%s", e.branch or "?", e.path))
    end
  else
    vim.notify("Wt: unknown subcommand " .. sub, vim.log.levels.WARN)
  end
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("nvim3_wt", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained" }, {
    group = grp,
    callback = function()
      if (vim.uv.now() - cache.fetched_at) > TTL_MS then
        refresh()
      end
    end,
  })
  vim.api.nvim_create_user_command("Wt", user_command, {
    nargs = "*",
    complete = function()
      return { "pick", "neogit", "create", "remove", "merge", "list" }
    end,
  })
  refresh()
end

return M
