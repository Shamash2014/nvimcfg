local M = {}

local function find_up(name, start)
  start = start or vim.uv.cwd()
  local found = vim.fs.find(name, { upward = true, path = start, type = "file", limit = 1 })
  return found[1]
end

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then return nil end
  local data = fd:read("*a")
  fd:close()
  return data
end

local function detect_pm(root)
  if vim.uv.fs_stat(root .. "/bun.lockb") or vim.uv.fs_stat(root .. "/bun.lock") then return "bun" end
  if vim.uv.fs_stat(root .. "/pnpm-lock.yaml") then return "pnpm" end
  if vim.uv.fs_stat(root .. "/yarn.lock") then return "yarn" end
  return "npm"
end

local function npm_tasks()
  local pkg = find_up("package.json")
  if not pkg then return {} end
  local data = read_file(pkg)
  if not data then return {} end
  local ok, decoded = pcall(vim.json.decode, data)
  if not ok or type(decoded) ~= "table" or type(decoded.scripts) ~= "table" then return {} end
  local root = vim.fs.dirname(pkg)
  local pm = detect_pm(root)
  local items = {}
  for name, body in pairs(decoded.scripts) do
    table.insert(items, {
      kind = "npm",
      name = name,
      label = name,
      detail = tostring(body),
      cwd = root,
      cmd = { pm, "run", name },
      source = pm .. " (" .. vim.fs.basename(root) .. ")",
    })
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

local function justfile_tasks()
  local jf
  for _, name in ipairs({ "justfile", "Justfile", ".justfile" }) do
    jf = find_up(name)
    if jf then break end
  end
  if not jf then return {} end
  local root = vim.fs.dirname(jf)
  local res = vim.system(
    { "just", "--justfile", jf, "--list", "--unsorted" },
    { text = true, cwd = root }
  ):wait()

  local items = {}
  if res.code == 0 and res.stdout and res.stdout ~= "" then
    for line in res.stdout:gmatch("[^\n]+") do
      if not line:match("^Available recipes") then
        local indented = line:match("^%s+(.+)$")
        if indented then
          local name, detail = indented:match("^([%w%-_:%.]+)%s*(.*)$")
          if name then
            table.insert(items, {
              kind = "just",
              name = name,
              label = name,
              detail = detail or "",
              cwd = root,
              cmd = { "just", "--justfile", jf, name },
              source = "just (" .. vim.fs.basename(root) .. ")",
            })
          end
        end
      end
    end
  else
    local data = read_file(jf) or ""
    for line in data:gmatch("[^\n]+") do
      local name = line:match("^([%w%-_][%w%-_:%.]*)%s*[^:=]*:")
      if name and not line:match("^%s") then
        table.insert(items, {
          kind = "just",
          name = name,
          label = name,
          detail = "",
          cwd = root,
          cmd = { "just", "--justfile", jf, name },
          source = "just (" .. vim.fs.basename(root) .. ")",
        })
      end
    end
  end
  return items
end

local registry = {}

local function gc()
  for buf in pairs(registry) do
    if not vim.api.nvim_buf_is_valid(buf) then registry[buf] = nil end
  end
end

local function spawn(kind, name, cmd_args, cwd)
  vim.cmd("botright vsplit")
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.jobstart(cmd_args, {
    term = true,
    cwd = cwd,
    on_exit = function(_, code)
      vim.schedule(function()
        if registry[buf] then
          registry[buf].exit_code = code
          registry[buf].running = false
        end
      end)
    end,
  })
  if job <= 0 then
    vim.notify("task: failed to start", vim.log.levels.ERROR)
    return
  end
  pcall(vim.api.nvim_buf_set_name, buf, "task://" .. kind .. "/" .. name)
  vim.bo[buf].buflisted = true
  vim.b[buf].task_kind = kind
  vim.b[buf].task_name = name
  registry[buf] = {
    kind = kind,
    name = name,
    cmd = cmd_args,
    cwd = cwd,
    job = job,
    started_at = os.time(),
    running = true,
  }
  vim.keymap.set("t", "<C-q>", [[<C-\><C-n>]], { buffer = buf, silent = true })
  vim.keymap.set("n", "q", "<cmd>hide<cr>", { buffer = buf, silent = true })
  vim.cmd("startinsert")
  return buf
end

local function run_task(item)
  spawn(item.kind, item.name, item.cmd, item.cwd)
end

function M.run_shell(shell_cmd, cwd)
  spawn("shell", shell_cmd, { vim.o.shell, "-lc", shell_cmd }, cwd or vim.uv.cwd())
end

function M.nvim_in(dir)
  if not dir or dir == "" then
    vim.notify("nvim_in: missing dir", vim.log.levels.WARN)
    return
  end
  spawn("nvim", vim.fs.basename(dir), { "nvim" }, dir)
end

function M.list_running()
  gc()
  local out = {}
  for buf, meta in pairs(registry) do
    table.insert(out, vim.tbl_extend("force", { bufnr = buf }, meta))
  end
  return out
end

function M.collect()
  local items = {}
  for _, it in ipairs(npm_tasks()) do table.insert(items, it) end
  for _, it in ipairs(justfile_tasks()) do table.insert(items, it) end
  return items
end

function M.pick()
  local items = M.collect()
  if #items == 0 then
    vim.notify("tasks: no package.json or justfile found", vim.log.levels.WARN)
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if not (ok and snacks and snacks.picker and snacks.picker.pick) then
    vim.ui.select(items, {
      prompt = "Tasks",
      format_item = function(e)
        return string.format("%-6s %-24s  %s", e.kind, e.name, e.detail or "")
      end,
    }, function(choice) if choice then run_task(choice) end end)
    return
  end

  local picker_items = {}
  for _, e in ipairs(items) do
    table.insert(picker_items, {
      text = e.kind .. " " .. e.name .. " " .. (e.detail or ""),
      data = e,
    })
  end

  snacks.picker.pick({
    source = "tasks",
    title = "Tasks (npm / just)",
    items = picker_items,
    format = function(item)
      local e = item.data
      local hl = e.kind == "just" and "Constant" or "Function"
      return {
        { string.format("%-6s ", e.kind), "Comment" },
        { string.format("%-24s ", e.name), hl },
        { e.detail or "", "Comment" },
      }
    end,
    preview = function(ctx)
      local e = ctx.item and ctx.item.data
      if not e then return end
      ctx.preview:set_lines({
        "Task:    " .. e.name,
        "Kind:    " .. e.kind,
        "Cwd:     " .. e.cwd,
        "Command: " .. table.concat(e.cmd, " "),
        "",
        "Detail:",
        e.detail or "",
      })
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.data then vim.schedule(function() run_task(item.data) end) end
    end,
  })
end

function M.setup()
  vim.api.nvim_create_user_command("Tasks", function() M.pick() end,
    { desc = "Pick and run npm/just task" })

  vim.api.nvim_create_user_command("Task", function(opts)
    if opts.args == "" then
      vim.notify("Task: usage :Task <shell command>", vim.log.levels.WARN)
      return
    end
    M.run_shell(opts.args)
  end, { nargs = "+", complete = "shellcmd", desc = "Run shell command as async terminal job" })

  vim.api.nvim_create_user_command("NvimIn", function(opts)
    local dir = opts.args ~= "" and vim.fn.fnamemodify(opts.args, ":p") or vim.uv.cwd()
    M.nvim_in(dir)
  end, { nargs = "?", complete = "dir", desc = "Spawn nvim in given folder as task" })
end

return M
