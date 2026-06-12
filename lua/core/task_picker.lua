local M = {}

local function find_up(name, start)
  start = start or vim.uv.cwd()
  local found = vim.fs.find(name, { upward = true, path = start, type = "file", limit = 1 })
  return found[1]
end

local function find_up_any(names, start)
  for _, name in ipairs(names) do
    local found = find_up(name, start)
    if found then return found end
  end
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

local function read_package_json(start)
  local pkg = find_up("package.json", start)
  if not pkg then return nil end
  local data = read_file(pkg)
  if not data then return nil end
  local ok, decoded = pcall(vim.json.decode, data)
  if not ok or type(decoded) ~= "table" then return nil end
  local root = vim.fs.dirname(pkg)
  return {
    path = pkg,
    root = root,
    decoded = decoded,
    pm = detect_pm(root),
  }
end

local function with_args(head, tail)
  local out = vim.deepcopy(head)
  for _, arg in ipairs(tail) do
    table.insert(out, arg)
  end
  return out
end

local function package_exec_cmd(pm, bin, args)
  args = args or {}
  if pm == "pnpm" then
    return with_args({ "pnpm", "exec", bin }, args)
  end
  if pm == "yarn" then
    return with_args({ "yarn", bin }, args)
  end
  if pm == "bun" then
    return with_args({ "bunx", bin }, args)
  end
  return with_args({ "npm", "exec", "--", bin }, args)
end

local function package_tasks(package)
  if not package or type(package.decoded.scripts) ~= "table" then return {} end
  local items = {}
  for name, body in pairs(package.decoded.scripts) do
    table.insert(items, {
      kind = package.pm,
      name = name,
      label = name,
      detail = tostring(body),
      cwd = package.root,
      cmd = { package.pm, "run", name },
      source = package.pm .. " (" .. vim.fs.basename(package.root) .. ")",
    })
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

local function react_native_tasks(package, existing_names)
  if not package then return {} end
  local deps = package.decoded.dependencies
  local dev_deps = package.decoded.devDependencies
  local has_react_native = type(deps) == "table" and deps["react-native"]
    or type(dev_deps) == "table" and dev_deps["react-native"]
  if not has_react_native then return {} end

  existing_names = existing_names or {}
  local defaults = {
    { name = "android", detail = "react-native run-android", args = { "run-android" } },
    { name = "ios", detail = "react-native run-ios", args = { "run-ios" } },
    { name = "start", detail = "react-native start", args = { "start" } },
  }

  local items = {}
  for _, task in ipairs(defaults) do
    if not existing_names[task.name] then
      table.insert(items, {
        kind = "react-native",
        name = task.name,
        label = task.name,
        detail = task.detail,
        cwd = package.root,
        cmd = package_exec_cmd(package.pm, "react-native", task.args),
        source = "react-native (" .. vim.fs.basename(package.root) .. ")",
      })
    end
  end

  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

local function mix_tasks(mix)
  if not mix then return {} end
  local data = read_file(mix) or ""
  local aliases = data:match("defp%s+aliases%s+do(.-)\n%s*end")
  if not aliases then return {} end

  local root = vim.fs.dirname(mix)
  local items = {}
  for line in aliases:gmatch("[^\n]+") do
    local name, detail = line:match('^%s*"([^"]+)"%s*:%s*(.-)%s*,?%s*$')
    if not name then
      name, detail = line:match("^%s*([%w%._%-]+)%s*:%s*(.-)%s*,?%s*$")
    end
    if name then
      table.insert(items, {
        kind = "mix",
        name = name,
        label = name,
        detail = detail or "",
        cwd = root,
        cmd = { "mix", name },
        source = "mix (" .. vim.fs.basename(root) .. ")",
      })
    end
  end

  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

local function flutter_pub_tasks(pubspec)
  if not pubspec then return {} end
  local data = read_file(pubspec) or ""
  local root = vim.fs.dirname(pubspec)
  local items = {}
  local in_scripts = false
  local scripts_indent = 0

  for line in data:gmatch("[^\n]+") do
    if not in_scripts then
      local indent = line:match("^(%s*)scripts:%s*$")
      if indent then
        in_scripts = true
        scripts_indent = #indent
      end
    else
      local current_indent = #(line:match("^(%s*)") or "")
      if line:match("^%s*$") then
        goto continue
      end
      if current_indent <= scripts_indent then
        break
      end

      local name, detail = line:match("^%s*([%w%._%-]+):%s*(.-)%s*$")
      if current_indent == scripts_indent + 2 and name then
        table.insert(items, {
          kind = "flutter",
          name = name,
          label = name,
          detail = detail or "",
          cwd = root,
          cmd = { vim.o.shell, "-lc", detail },
          source = "pubspec (" .. vim.fs.basename(root) .. ")",
        })
      end
    end
    ::continue::
  end

  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

local function mise_item(name, detail, root)
  return {
    kind = "mise",
    name = name,
    label = name,
    detail = detail or "",
    cwd = root,
    cmd = { "mise", "run", name },
    source = "mise (" .. vim.fs.basename(root) .. ")",
  }
end

-- Authoritative: mise resolves [tasks.x] headers, the [tasks] inline table,
-- file tasks (mise-tasks/, .mise/tasks/), and included configs. Hand-parsing
-- the TOML only sees [tasks.x] headers, so it silently drops the rest.
local function mise_tasks_cli(root)
  if vim.fn.executable("mise") ~= 1 then return nil end
  local ok, res = pcall(function()
    return vim.system({ "mise", "tasks", "ls", "--json" }, { cwd = root, text = true }):wait()
  end)
  if not ok or res.code ~= 0 then return nil end
  local decoded_ok, decoded = pcall(vim.json.decode, res.stdout or "")
  if not decoded_ok or type(decoded) ~= "table" then return nil end
  local items = {}
  for _, task in ipairs(decoded) do
    if task.name and not task.hide then
      local task_root = task.source and vim.fs.dirname(task.source) or root
      table.insert(items, mise_item(task.name, task.description, task_root))
    end
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

-- Fallback for untrusted dirs, where `mise tasks ls` returns [] until trusted.
local function mise_tasks_toml(root)
  local config
  for _, name in ipairs({ "mise.toml", ".mise.toml", "mise.local.toml", ".mise.local.toml" }) do
    if vim.uv.fs_stat(root .. "/" .. name) then
      config = root .. "/" .. name
      break
    end
  end
  if not config then return {} end
  local data = read_file(config) or ""
  local tasks = {}
  local current

  for line in data:gmatch("[^\n]+") do
    local name = line:match("^%[tasks%.([%w%._%-]+)%]%s*$")
    if not name then
      name = line:match('^%[tasks%."([^"]+)"%]%s*$')
    end
    if name then
      current = { name = name, detail = "" }
      table.insert(tasks, current)
    elseif current then
      local detail = line:match('^description%s*=%s*"(.-)"%s*$')
      if detail then
        current.detail = detail
      end
    end
  end

  local items = {}
  for _, task in ipairs(tasks) do
    table.insert(items, mise_item(task.name, task.detail, root))
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

local function mise_tasks(root)
  if not root then return {} end
  local cli = mise_tasks_cli(root)
  if cli and #cli > 0 then return cli end
  return mise_tasks_toml(root)
end

local function flutter_tasks(pubspec)
  if not pubspec then return {} end
  local root = vim.fs.dirname(pubspec)
  local items = {
    {
      kind = "flutter",
      name = "pub get",
      label = "pub get",
      detail = "flutter pub get",
      cwd = root,
      cmd = { "flutter", "pub", "get" },
      source = "flutter (" .. vim.fs.basename(root) .. ")",
    },
    {
      kind = "flutter",
      name = "build",
      label = "build",
      detail = "flutter build apk",
      cwd = root,
      cmd = { "flutter", "build", "apk" },
      source = "flutter (" .. vim.fs.basename(root) .. ")",
    },
    {
      kind = "flutter",
      name = "test",
      label = "test",
      detail = "flutter test",
      cwd = root,
      cmd = { "flutter", "test" },
      source = "flutter (" .. vim.fs.basename(root) .. ")",
    },
    {
      kind = "flutter",
      name = "analyze",
      label = "analyze",
      detail = "flutter analyze",
      cwd = root,
      cmd = { "flutter", "analyze" },
      source = "flutter (" .. vim.fs.basename(root) .. ")",
    },
    {
      kind = "flutter",
      name = "devices",
      label = "devices",
      detail = "flutter devices",
      cwd = root,
      cmd = { "flutter", "devices" },
      source = "flutter (" .. vim.fs.basename(root) .. ")",
    },
    {
      kind = "flutter",
      name = "doctor",
      label = "doctor",
      detail = "flutter doctor",
      cwd = root,
      cmd = { "flutter", "doctor" },
      source = "flutter (" .. vim.fs.basename(root) .. ")",
    },
  }
  return items
end

local function go_tasks(gomod)
  if not gomod then return {} end
  local root = vim.fs.dirname(gomod)
  local items = {
    {
      kind = "go",
      name = "build",
      label = "build",
      detail = "go build ./...",
      cwd = root,
      cmd = { "go", "build", "./..." },
      source = "go (" .. vim.fs.basename(root) .. ")",
    },
    {
      kind = "go",
      name = "fmt",
      label = "fmt",
      detail = "go fmt ./...",
      cwd = root,
      cmd = { "go", "fmt", "./..." },
      source = "go (" .. vim.fs.basename(root) .. ")",
    },
    {
      kind = "go",
      name = "test",
      label = "test",
      detail = "go test ./...",
      cwd = root,
      cmd = { "go", "test", "./..." },
      source = "go (" .. vim.fs.basename(root) .. ")",
    },
    {
      kind = "go",
      name = "vet",
      label = "vet",
      detail = "go vet ./...",
      cwd = root,
      cmd = { "go", "vet", "./..." },
      source = "go (" .. vim.fs.basename(root) .. ")",
    },
  }
  return items
end

local function justfile_tasks(jf)
  if not jf then return {} end
  local root = vim.fs.dirname(jf)
  local data = read_file(jf) or ""
  local items = {}
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
  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

local function find_mise_root(start)
  local flat = find_up_any({ "mise.toml", ".mise.toml", "mise.local.toml", ".mise.local.toml" }, start)
  if flat then return vim.fs.dirname(flat) end
  local nested = vim.fs.find(function(name, path)
    return name == "config.toml" and path:match("[/\\]%.config[/\\]mise$")
  end, { upward = true, path = start, type = "file", limit = 1 })[1]
  if nested then
    return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(nested)))
  end
  local taskdir = vim.fs.find({ "mise-tasks" }, { upward = true, path = start, type = "directory", limit = 1 })[1]
  if taskdir then return vim.fs.dirname(taskdir) end
end

local function build_context(start)
  start = start or vim.uv.cwd()
  local justfile = find_up_any({ "justfile", "Justfile", ".justfile" }, start)
  return {
    start = start,
    package = read_package_json(start),
    mix = find_up("mix.exs", start),
    pubspec = find_up("pubspec.yaml", start),
    mise = find_mise_root(start),
    gomod = find_up("go.mod", start),
    justfile = justfile,
  }
end

function M.collect(start)
  local ctx = build_context(start)
  local items = {}
  local package_items = package_tasks(ctx.package)
  local package_names = {}
  for _, it in ipairs(package_items) do
    package_names[it.name] = true
    table.insert(items, it)
  end
  for _, it in ipairs(react_native_tasks(ctx.package, package_names)) do table.insert(items, it) end
  for _, it in ipairs(mix_tasks(ctx.mix)) do table.insert(items, it) end
  for _, it in ipairs(flutter_pub_tasks(ctx.pubspec)) do table.insert(items, it) end
  for _, it in ipairs(mise_tasks(ctx.mise)) do table.insert(items, it) end
  for _, it in ipairs(flutter_tasks(ctx.pubspec)) do table.insert(items, it) end
  for _, it in ipairs(go_tasks(ctx.gomod)) do table.insert(items, it) end
  for _, it in ipairs(justfile_tasks(ctx.justfile)) do table.insert(items, it) end
  return items
end

local registry = {}

local function gc()
  for buf in pairs(registry) do
    if not vim.api.nvim_buf_is_valid(buf) then registry[buf] = nil end
  end
end

-- nvim's env is frozen at launch, so a task would inherit a stale mise env.
-- Run every task through `mise exec` to resolve tools + [env] fresh for its cwd.
local function with_mise_env(cmd_args)
  if vim.fn.executable("mise") ~= 1 or cmd_args[1] == "mise" then return cmd_args end
  local wrapped = { "mise", "exec", "--" }
  for _, arg in ipairs(cmd_args) do
    table.insert(wrapped, arg)
  end
  return wrapped
end

local function spawn(kind, name, cmd_args, cwd)
  vim.cmd("botright vsplit")
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.jobstart(with_mise_env(cmd_args), {
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

function M.collect_async(cb, start)
  vim.schedule(function()
    cb(M.collect(start))
  end)
end

function M.pick()
  M.collect_async(function(items)
    if #items == 0 then
      vim.notify("tasks: no supported task file found", vim.log.levels.WARN)
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
      title = "Tasks",
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
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("Tasks", function() M.pick() end,
    { desc = "Pick and run project task" })

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
