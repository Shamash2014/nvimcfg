local M = {}

-- Track running tasks
M.running_tasks = {}

-- Track unique terminal instances for toggle
M.terminals = {}

-- Command history
M.command_history = {}
M.max_history = 50

-- Build full terminal environment for task execution
local function build_terminal_env(extra, cwd)
  local mise = require("core.mise")
  local mise_env = mise.get_env(cwd)

  local shell = vim.env.SHELL or "/bin/zsh"
  local env = {
    TERM = vim.env.TERM or "xterm-256color",
    COLORTERM = vim.env.COLORTERM or "truecolor",
    LANG = vim.env.LANG or "en_US.UTF-8",
    HOME = vim.env.HOME,
    USER = vim.env.USER,
    SHELL = shell,
    PATH = vim.env.PATH,
    EDITOR = vim.env.EDITOR or "nvim",
    VISUAL = vim.env.VISUAL or "nvim",
  }

  local dev_vars = {
    "NVM_DIR", "PYENV_ROOT", "GOPATH", "GOROOT", "CARGO_HOME", "RUSTUP_HOME",
    "ASDF_DIR", "VOLTA_HOME", "FNM_DIR", "BUN_INSTALL", "PNPM_HOME",
    "MIX_HOME", "HEX_HOME", "MISE_HOME",
  }
  for _, var in ipairs(dev_vars) do
    if vim.env[var] then
      env[var] = vim.env[var]
    end
  end

  env = vim.tbl_extend("force", env, mise_env)

  if extra then
    for k, v in pairs(extra) do
      env[k] = v
    end
  end

  return env
end

-- Wrap command in login shell for full environment
local function wrap_cmd_with_shell(cmd)
  local shell = vim.env.SHELL or "/bin/zsh"
  return string.format("%s -l -c %s", shell, vim.fn.shellescape(cmd))
end

-- Add command to history
local function add_to_history(task)
  local entry = {
    name = task.name,
    cmd = task.cmd,
    desc = task.desc,
    timestamp = os.time(),
  }

  for i = #M.command_history, 1, -1 do
    if M.command_history[i].cmd == task.cmd then
      table.remove(M.command_history, i)
      break
    end
  end

  table.insert(M.command_history, 1, entry)

  while #M.command_history > M.max_history do
    table.remove(M.command_history)
  end
end

-- Folders to skip when scanning for nested projects
local skip_folders = {
  node_modules = true,
  [".git"] = true,
  _build = true,
  deps = true,
  build = true,
  dist = true,
  target = true,
  vendor = true,
  [".elixir_ls"] = true,
  [".next"] = true,
}

-- Find nested project folders
local function find_project_folders(root, max_depth)
  max_depth = max_depth or 3
  local projects = {}
  local seen = {}

  local patterns = {
    "package.json",
    "mix.exs",
    "Cargo.toml",
    "go.mod",
    "pyproject.toml",
    "Justfile",
    "justfile",
    "Makefile",
    "makefile",
  }

  local function scan_dir(dir, depth)
    if depth > max_depth then return end
    if seen[dir] then return end
    seen[dir] = true

    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end

      if type == "directory" and not skip_folders[name] then
        scan_dir(dir .. "/" .. name, depth + 1)
      elseif type == "file" then
        for _, pattern in ipairs(patterns) do
          if name == pattern and dir ~= root then
            table.insert(projects, { path = dir, file = name })
            break
          end
        end
      end
    end
  end

  scan_dir(root, 0)
  return projects
end

-- Define common tasks for different project types
local tasks = {
  javascript = {
    { name = "dev", cmd = "npm run dev", desc = "Start dev server" },
    { name = "build", cmd = "npm run build", desc = "Build project" },
    { name = "test", cmd = "npm test", desc = "Run tests" },
    { name = "lint", cmd = "npm run lint", desc = "Run linter" },
    { name = "install", cmd = "npm install", desc = "Install dependencies" },
  },
  python = {
    { name = "run", cmd = "python %", desc = "Run current file" },
    { name = "test", cmd = "pytest", desc = "Run tests" },
    { name = "lint", cmd = "ruff check .", desc = "Run linter" },
    { name = "format", cmd = "black .", desc = "Format code" },
  },
  rust = {
    { name = "build", cmd = "cargo build", desc = "Build project" },
    { name = "run", cmd = "cargo run", desc = "Run project" },
    { name = "test", cmd = "cargo test", desc = "Run tests" },
    { name = "check", cmd = "cargo check", desc = "Check project" },
  },
  go = {
    { name = "run", cmd = "go run .", desc = "Run project" },
    { name = "build", cmd = "go build", desc = "Build project" },
    { name = "test", cmd = "go test ./...", desc = "Run tests" },
    { name = "mod", cmd = "go mod tidy", desc = "Tidy modules" },
  },
  elixir = {
    { name = "run", cmd = "mix run", desc = "Run project" },
    { name = "test", cmd = "mix test", desc = "Run tests" },
    { name = "deps", cmd = "mix deps.get", desc = "Get dependencies" },
    { name = "compile", cmd = "mix compile", desc = "Compile project" },
    { name = "server", cmd = "mix phx.server", desc = "Start Phoenix server" },
  },
  make = {
    { name = "make", cmd = "make", desc = "Run make" },
    { name = "make-clean", cmd = "make clean", desc = "Clean build" },
    { name = "make-test", cmd = "make test", desc = "Run tests" },
  },
  flutter = {
    { name = "run", cmd = "flutter run", desc = "Run app" },
    { name = "test", cmd = "flutter test", desc = "Run tests" },
    { name = "clean", cmd = "flutter clean", desc = "Clean build" },
    { name = "pub-get", cmd = "flutter pub get", desc = "Get dependencies" },
    { name = "doctor", cmd = "flutter doctor", desc = "Check setup" },
  },
}

-- Detect project type based on files in root
local function detect_project_type()
  local root = vim.fs.root(0, { ".git" }) or vim.fn.getcwd()

  local checks = {
    { files = { "pubspec.yaml" }, type = "flutter" },
    { files = { "package.json" }, type = "javascript" },
    { files = { "Cargo.toml" }, type = "rust" },
    { files = { "go.mod", "go.sum" }, type = "go" },
    { files = { "requirements.txt", "setup.py", "pyproject.toml", "Pipfile" }, type = "python" },
    { files = { "mix.exs" }, type = "elixir" },
    { files = { "Makefile", "makefile" }, type = "make" },
  }

  for _, check in ipairs(checks) do
    for _, file in ipairs(check.files) do
      if vim.fn.filereadable(root .. "/" .. file) == 1 then
        return check.type
      end
    end
  end

  return nil
end

-- Load tasks from .vscode/tasks.json
function M.load_vscode_tasks()
  local root = vim.fs.root(0, { ".git" }) or vim.fn.getcwd()
  local tasks_file = root .. "/.vscode/tasks.json"

  if vim.fn.filereadable(tasks_file) == 0 then
    return {}
  end

  local content = vim.fn.readfile(tasks_file)
  local ok, json = pcall(vim.json.decode, table.concat(content, "\n"))

  if not ok or not json.tasks then
    return {}
  end

  local custom_tasks = {}
  for _, task in ipairs(json.tasks) do
    if task.command or task.type == "shell" then
      local cmd = task.command

      -- Handle shell type tasks
      if task.type == "shell" and not cmd then
        if task.args then
          cmd = table.concat(task.args, " ")
        end
      end

      if cmd then
        table.insert(custom_tasks, {
          name = task.label or "custom",
          cmd = cmd,
          desc = task.detail or task.problemMatcher and "Task with problem matcher" or "VSCode task"
        })
      end
    end
  end

  return custom_tasks
end

-- Parse npm scripts from package.json
local function load_npm_tasks(cwd)
  cwd = cwd or vim.fn.getcwd()
  local result = {}
  local package_json = cwd .. "/package.json"

  if vim.fn.filereadable(package_json) == 1 then
    local ok, content = pcall(vim.fn.readfile, package_json)
    if not ok then return {} end

    local json_str = table.concat(content, '\n')
    local ok2, package = pcall(vim.json.decode, json_str)
    if not ok2 or not package.scripts then
      return {}
    end

    for name, command in pairs(package.scripts) do
      table.insert(result, {
        name = "npm: " .. name,
        cmd = "npm run " .. name,
        desc = command:sub(1, 50),
        type = "npm",
        cwd = cwd,
      })
    end
  end

  return result
end

-- Parse Justfile for recipes
local function load_justfile_tasks(cwd)
  cwd = cwd or vim.fn.getcwd()
  local result = {}
  local justfile_path = cwd .. "/justfile"

  if vim.fn.filereadable(justfile_path) == 0 then
    justfile_path = cwd .. "/Justfile"
  end

  if vim.fn.filereadable(justfile_path) == 1 then
    local lines = vim.fn.readfile(justfile_path)
    for _, line in ipairs(lines) do
      local recipe = line:match("^([%w%-_]+)[^:]*:")
      if recipe then
        table.insert(result, {
          name = "just: " .. recipe,
          cmd = "just " .. recipe,
          type = "justfile",
          cwd = cwd,
        })
      end
    end
  end

  return result
end

-- Parse Makefile for targets
local function load_makefile_tasks(cwd)
  cwd = cwd or vim.fn.getcwd()
  local result = {}
  local makefile_path = cwd .. "/Makefile"

  if vim.fn.filereadable(makefile_path) == 0 then
    makefile_path = cwd .. "/makefile"
  end

  if vim.fn.filereadable(makefile_path) == 1 then
    local lines = vim.fn.readfile(makefile_path)
    for _, line in ipairs(lines) do
      local target = line:match("^([%w%-_]+):")
      if target and not target:match("^%.") then
        table.insert(result, {
          name = "make: " .. target,
          cmd = "make " .. target,
          type = "makefile",
          cwd = cwd,
        })
      end
    end
  end

  return result
end

-- Parse mix.exs for aliases and provide common mix tasks
local function load_mix_tasks(cwd)
  cwd = cwd or vim.fn.getcwd()
  local result = {}
  local mix_exs_path = cwd .. "/mix.exs"

  if vim.fn.filereadable(mix_exs_path) == 0 then
    return {}
  end

  local content = table.concat(vim.fn.readfile(mix_exs_path), "\n")
  local is_phoenix = content:match(":phoenix") ~= nil

  local aliases_block = content:match("defp?%s+aliases[^d].-do%s*%[(.-)%]")
  if aliases_block then
    for alias_name in aliases_block:gmatch('%s*([%w_%.]+)%s*:') do
      if not alias_name:match("^#") then
        table.insert(result, {
          name = "mix: " .. alias_name,
          cmd = "mix " .. alias_name,
          type = "mix",
          cwd = cwd,
        })
      end
    end
  end

  local common_tasks = {
    { name = "test", cmd = "mix test", desc = "Run tests" },
    { name = "test.watch", cmd = "mix test.watch", desc = "Run tests in watch mode" },
    { name = "compile", cmd = "mix compile", desc = "Compile project" },
    { name = "deps.get", cmd = "mix deps.get", desc = "Get dependencies" },
    { name = "deps.compile", cmd = "mix deps.compile", desc = "Compile dependencies" },
    { name = "format", cmd = "mix format", desc = "Format code" },
    { name = "credo", cmd = "mix credo", desc = "Run Credo linter" },
    { name = "dialyzer", cmd = "mix dialyzer", desc = "Run Dialyzer" },
  }

  if is_phoenix then
    table.insert(common_tasks, { name = "phx.server", cmd = "mix phx.server", desc = "Start Phoenix server" })
    table.insert(common_tasks, { name = "phx.routes", cmd = "mix phx.routes", desc = "Show routes" })
    table.insert(common_tasks, { name = "ecto.migrate", cmd = "mix ecto.migrate", desc = "Run migrations" })
    table.insert(common_tasks, { name = "ecto.rollback", cmd = "mix ecto.rollback", desc = "Rollback migration" })
    table.insert(common_tasks, { name = "ecto.reset", cmd = "mix ecto.reset", desc = "Reset database" })
    table.insert(common_tasks, { name = "ecto.setup", cmd = "mix ecto.setup", desc = "Setup database" })
  end

  for _, task in ipairs(common_tasks) do
    local exists = false
    for _, t in ipairs(result) do
      if t.cmd == task.cmd then
        exists = true
        break
      end
    end
    if not exists then
      table.insert(result, {
        name = "mix: " .. task.name,
        cmd = task.cmd,
        desc = task.desc,
        type = "mix",
        cwd = cwd,
      })
    end
  end

  return result
end

-- Load tasks from a specific folder based on detected file
local function load_tasks_for_folder(folder, file)
  if file == "package.json" then
    return load_npm_tasks(folder)
  elseif file == "mix.exs" then
    return load_mix_tasks(folder)
  elseif file == "Justfile" or file == "justfile" then
    return load_justfile_tasks(folder)
  elseif file == "Makefile" or file == "makefile" then
    return load_makefile_tasks(folder)
  end
  return {}
end

-- Get available tasks for current project
function M.get_tasks()
  local project_tasks = {}
  local root = vim.fn.getcwd()

  -- Load root-level tasks
  for _, task in ipairs(load_npm_tasks()) do
    table.insert(project_tasks, task)
  end
  for _, task in ipairs(M.load_vscode_tasks()) do
    table.insert(project_tasks, task)
  end
  for _, task in ipairs(load_justfile_tasks()) do
    table.insert(project_tasks, task)
  end
  for _, task in ipairs(load_makefile_tasks()) do
    table.insert(project_tasks, task)
  end
  for _, task in ipairs(load_mix_tasks()) do
    table.insert(project_tasks, task)
  end

  -- Scan for nested projects (monorepo support)
  local nested = find_project_folders(root, 3)
  for _, project in ipairs(nested) do
    local rel_path = project.path:gsub("^" .. root .. "/", "")
    local folder_tasks = load_tasks_for_folder(project.path, project.file)

    for _, task in ipairs(folder_tasks) do
      task.name = rel_path .. ": " .. task.name
      table.insert(project_tasks, task)
    end
  end

  -- Add tasks based on detected project type
  local project_type = detect_project_type()
  if project_type and tasks[project_type] then
    for _, task in ipairs(tasks[project_type]) do
      table.insert(project_tasks, task)
    end
  end

  return project_tasks
end

-- Run a specific task
function M.run_task(task, opts)
  if not task then
    return
  end

  opts = opts or {}

  -- Record to history
  add_to_history(task)

  -- Replace % with current file
  local cmd = task.cmd:gsub("%%", vim.fn.expand("%"))
  local cwd = task.cwd or vim.fs.root(0, { ".git" }) or vim.fn.getcwd()

  -- Default to splits (smaller vertical for custom commands, horizontal for others)
  -- Check if this is a custom command (starts with "custom:")
  local is_custom = task.name:match("^custom:") ~= nil
  local win_config = not opts.background and {
    position = is_custom and "right" or "bottom",
    height = not is_custom and 0.3 or nil,
    width = is_custom and 0.3 or nil,
  } or nil

  local timestamp = tostring(vim.loop.hrtime())
  local unique_cmd = wrap_cmd_with_shell(cmd)
  local env = build_terminal_env({
    SNACKS_TASK_ID = timestamp,
    TASK_NAME = task.name,
  }, cwd)
  local term = require("snacks").terminal(unique_cmd, {
    cwd = cwd,
    interactive = not opts.background,
    hidden = opts.background or false,
    win = win_config,
    env = env,
  })

  if not opts.background then
    term:show()
    term:focus()  -- Focus the terminal for foreground tasks
  else
    -- For background tasks, ensure the buffer persists
    if term.buf and type(term.buf) == "number" and term.buf > 0 then
      local ok, is_valid = pcall(vim.api.nvim_buf_is_valid, term.buf)
      if ok and is_valid then
        vim.api.nvim_buf_set_option(term.buf, 'bufhidden', 'hide')
      end
    end
  end

  -- Track running task with truly unique identifier for same-name tasks
  -- Use timestamp with microseconds and a counter for uniqueness
  M.task_counter = (M.task_counter or 0) + 1
  local task_id = string.format("%s_%d_%d_%d", task.name, os.time(), vim.loop.hrtime(), M.task_counter)
  local task_entry = {
    name = task.name,
    id = task_id,  -- Truly unique identifier even for same-name tasks run simultaneously
    cmd = cmd,
    term = term,
    background = opts.background or false,
    start_time = os.time(),
    -- Function to attach and make interactive
    attach = function(self)
      if self.term then
        -- Check if terminal buffer still exists
        if not vim.api.nvim_buf_is_valid(self.term.buf) then
          vim.notify(string.format("Task '%s' has terminated", self.name), vim.log.levels.WARN)
          return false
        end

        -- Restore buffer options for visible state
        vim.api.nvim_buf_set_option(self.term.buf, 'buflisted', true)

        -- Make terminal interactive again
        self.term.opts.interactive = true

        -- Open in a natural split (Neovim decides based on available space)
        -- Use default split behavior without specifying position
        self.term:show()

        self.term:focus()
        self.background = false
        vim.notify(string.format("Attached to task '%s'", self.name), vim.log.levels.INFO)
        return true
      end
      return false
    end,
    -- Function to detach and run in background
    detach = function(self)
      if self.term and self.term.buf then
        -- Ensure the terminal buffer persists when hidden
        if vim.api.nvim_buf_is_valid(self.term.buf) then
          -- Critical: Set buffer to persist when hidden - don't unload it
          vim.api.nvim_buf_set_option(self.term.buf, 'bufhidden', 'hide')
          -- Also make sure the buffer stays loaded
          vim.api.nvim_buf_set_option(self.term.buf, 'buflisted', false)
        end

        -- Hide the terminal window but keep process running
        self.term:hide()
        -- Mark as background but keep terminal alive
        self.background = true
        -- Keep interactive false to prevent input when hidden
        self.term.opts.interactive = false

        vim.notify(string.format("Task '%s' detached (continues running in background)", self.name), vim.log.levels.INFO)
      end
    end,
    -- Check if task is still alive
    is_alive = function(self)
      if not self.term then
        return false
      end

      -- Ensure buf is a valid number before checking
      local buf = self.term.buf
      if type(buf) ~= "number" or buf <= 0 then
        return false
      end

      -- Safely check if buffer is valid
      local ok, is_valid = pcall(vim.api.nvim_buf_is_valid, buf)
      return ok and is_valid
    end
  }

  table.insert(M.running_tasks, task_entry)

  local running_count = 0
  for _, t in ipairs(M.running_tasks) do
    if t:is_alive() then
      running_count = running_count + 1
    end
  end

  if opts.background then
    vim.notify(string.format("Task '%s' started in background (%d tasks running, use <leader>ra to attach)", task.name, running_count), vim.log.levels.INFO)
  else
    vim.notify(string.format("Task '%s' started (%d total tasks running)", task.name, running_count), vim.log.levels.INFO)
  end

  return task_entry
end

-- Function to list and attach to background tasks
function M.attach_to_task()
  local attachable_tasks = {}

  for i, task in ipairs(M.running_tasks) do
    -- Include tasks that are alive and either:
    -- 1. Marked as background, or
    -- 2. Have no visible windows (detached)
    if task:is_alive() then
      local is_visible = false
      if task.term and task.term.buf then
        local wins = vim.fn.win_findbuf(task.term.buf)
        is_visible = #wins > 0
      end

      if task.background or not is_visible then
        local status = task.background and "Background" or "Detached"
        -- For custom commands, show the actual command in the description
        local desc_text = "Started " .. os.date("%H:%M:%S", task.start_time)
        if task.name:match("^custom:") then
          -- Show the actual command for custom tasks
          local cmd_preview = task.cmd
          if #cmd_preview > 40 then
            cmd_preview = cmd_preview:sub(1, 37) .. "..."
          end
          desc_text = cmd_preview .. " • " .. desc_text
        end
        table.insert(attachable_tasks, {
          text = string.format("[%s] %s", status, task.name),
          desc = desc_text,
          index = i,
          task = task
        })
      end
    end
  end

  if #attachable_tasks == 0 then
    vim.notify("No background or detached tasks available", vim.log.levels.INFO)
    return
  end

  vim.ui.select(attachable_tasks, {
    prompt = "Attach to task:",
    format_item = function(item)
      return item.text .. " • " .. item.desc
    end,
  }, function(item)
    if item and item.task then
      item.task:attach()
    end
  end)
end

-- Detach current terminal to background
function M.detach_current_terminal()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Find the task associated with current buffer
  for _, task in ipairs(M.running_tasks) do
    if task.term and task.term.buf == bufnr then
      task:detach()
      return
    end
  end

  -- Check if current buffer is a terminal
  if vim.bo[bufnr].buftype == "terminal" then
    -- Try to get the Snacks terminal instance
    local ok, term = pcall(function()
      return require('snacks').terminal.get({ buf = bufnr })
    end)

    if ok and term then
      term:hide()
      vim.notify("Terminal detached to background", vim.log.levels.INFO)
    else
      -- Just hide the window if it's a terminal but not a Snacks terminal
      vim.cmd("hide")
      vim.notify("Terminal hidden", vim.log.levels.INFO)
    end
  else
    vim.notify("Not in a terminal buffer", vim.log.levels.WARN)
  end
end

-- Add keybinding for attaching to tasks
vim.keymap.set("n", "<leader>ra", M.attach_to_task, { desc = "Attach to background task" })

-- Run custom command
function M.run_custom_command()
  -- Use vim.ui.input which should be overridden by Snacks
  vim.ui.input({
    prompt = "Command: ",
    default = M.last_custom_command or "",
  }, function(input)
    if input and input ~= "" then
      M.last_custom_command = input
      -- Create a more descriptive name for the custom task
      -- Use the first word of the command or up to first 20 chars
      local task_name = input:match("^(%S+)") or "custom"
      if #input <= 20 then
        task_name = input
      elseif #task_name > 20 then
        task_name = task_name:sub(1, 20)
      end

      local task = {
        name = "custom: " .. task_name,  -- More descriptive name
        cmd = input,
        desc = "Command: " .. input
      }
      M.run_task(task)
      M.last_task = task
    end
  end)
end

-- Show task picker
function M.pick_task()
  local available_tasks = M.get_tasks()

  -- Create items for picker, with custom command first
  local items = {
    {
      text = "Enter custom command...",
      desc = "",
      task = { cmd = "custom" }
    }
  }

  -- Add last 3 commands from history
  for i = 1, math.min(3, #M.command_history) do
    local entry = M.command_history[i]
    local time_ago = os.difftime(os.time(), entry.timestamp)
    local time_str
    if time_ago < 60 then
      time_str = "just now"
    elseif time_ago < 3600 then
      time_str = math.floor(time_ago / 60) .. "m ago"
    else
      time_str = math.floor(time_ago / 3600) .. "h ago"
    end
    table.insert(items, {
      text = "[" .. i .. "] " .. entry.name,
      desc = time_str .. " - " .. entry.cmd,
      task = { name = entry.name, cmd = entry.cmd, desc = entry.desc },
      is_history = true
    })
  end

  -- Add separator if we have history
  if #M.command_history > 0 then
    table.insert(items, {
      text = "──────────────",
      desc = "",
      task = nil
    })
  end

  -- Add all other tasks from configuration files
  for _, task in ipairs(available_tasks) do
    if task.type == "npm" then
      local name = task.name:gsub("^npm: ", "")
      table.insert(items, {
        text = name,
        desc = task.desc,
        task = task
      })
    else
      table.insert(items, {
        text = task.name,
        desc = task.desc,
        task = task
      })
    end
  end

  -- Use vim.ui.select (which Snacks overrides)
  vim.ui.select(items, {
    prompt = "Select task to run:",
    format_item = function(item)
      if item.desc and item.desc ~= "" then
        return item.text .. " • " .. item.desc
      else
        return item.text
      end
    end,
  }, function(item)
    if not item or not item.task then
      return
    end

    if item.task.cmd == "custom" then
      M.run_custom_command()
    else
      M.run_task(item.task)
      M.last_task = item.task
    end
  end)
end

-- Combined picker for buffers, tabs, and running tasks
function M.pick_buffers_tabs_tasks()
  local snacks = require("snacks")
  local items = {}

  -- Running tasks section (if any)
  local active_tasks = {}
  for _, task in ipairs(M.running_tasks) do
    if task.term and task.term.buf and vim.api.nvim_buf_is_valid(task.term.buf) then
      table.insert(active_tasks, task)
    end
  end
  M.running_tasks = active_tasks

  if #active_tasks > 0 then
    for i, task in ipairs(active_tasks) do
      local runtime = os.difftime(os.time(), task.start_time)
      local runtime_str = string.format("%dm %ds", math.floor(runtime / 60), runtime % 60)
      local status = task.background and "BG" or "FG"
      table.insert(items, {
        text = string.format("[%s] %s", status, task.name),
        desc = runtime_str,
        is_task = true,
        task_index = i,
      })
    end
    table.insert(items, { text = "── Tabs ──", is_separator = true })
  end

  -- Tabs section
  local tab_count = vim.fn.tabpagenr("$")
  if tab_count > 1 then
    for i = 1, tab_count do
      local bufnr = vim.fn.tabpagebuflist(i)[1]
      local name = vim.fn.fnamemodify(vim.fn.bufname(bufnr), ":t")
      if name == "" then name = "[No Name]" end
      local is_current = i == vim.fn.tabpagenr()
      table.insert(items, {
        text = string.format("Tab %d: %s", i, name),
        desc = is_current and "current" or "",
        is_tab = true,
        tab_nr = i,
      })
    end
    table.insert(items, { text = "── Buffers ──", is_separator = true })
  end

  -- Buffers section
  local buffers = vim.fn.getbufinfo({ buflisted = 1 })
  local current_buf = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(buffers) do
    local name = buf.name ~= "" and vim.fn.fnamemodify(buf.name, ":t") or "[No Name]"
    local modified = buf.changed == 1 and " [+]" or ""
    local is_current = buf.bufnr == current_buf
    table.insert(items, {
      text = name .. modified,
      desc = is_current and "current" or vim.fn.fnamemodify(buf.name, ":~:."),
      is_buffer = true,
      bufnr = buf.bufnr,
    })
  end

  snacks.picker.pick({
    source = "select",
    items = items,
    prompt = "Switch",
    layout = { preset = "vscode" },
    format = function(item)
      if item.is_separator then
        return { { item.text, "Comment" } }
      elseif item.desc and item.desc ~= "" then
        return { { item.text }, { " " .. item.desc, "Comment" } }
      else
        return { { item.text } }
      end
    end,
    confirm = function(picker, item)
      picker:close()
      if not item or item.is_separator then return end
      if item.is_task then
        local task = active_tasks[item.task_index]
        if task.background then
          task:attach()
        elseif task.term then
          task.term:focus()
        end
      elseif item.is_tab then
        vim.cmd("tabnext " .. item.tab_nr)
      elseif item.is_buffer then
        vim.api.nvim_set_current_buf(item.bufnr)
      end
    end,
  })
end

-- Combined picker for tasks and Vim commands
function M.pick_tasks_and_commands()
  local snacks = require("snacks")
  local items = {}

  table.insert(items, {
    text = "New AI Session",
    desc = "Create a new AI REPL session",
    is_ai = true,
  })

  table.insert(items, {
    text = "Restart AI Session",
    desc = "Restart current AI REPL session in .chat buffer",
    is_ai_restart = true,
  })

  table.insert(items, {
    text = "Toggle REPL",
    desc = "Toggle code REPL window",
    is_repl = true,
  })

  table.insert(items, {
    text = "Enter custom command...",
    task = { cmd = "custom" },
    is_task = true,
  })

  for i = 1, math.min(3, #M.command_history) do
    local entry = M.command_history[i]
    local time_ago = os.difftime(os.time(), entry.timestamp)
    local time_str
    if time_ago < 60 then
      time_str = "just now"
    elseif time_ago < 3600 then
      time_str = math.floor(time_ago / 60) .. "m ago"
    else
      time_str = math.floor(time_ago / 3600) .. "h ago"
    end
    table.insert(items, {
      text = "[" .. i .. "] " .. entry.name,
      desc = time_str .. " - " .. entry.cmd,
      task = { name = entry.name, cmd = entry.cmd, desc = entry.desc },
      is_task = true,
      is_history = true,
    })
  end

  local available_tasks = M.get_tasks()
  for _, task in ipairs(available_tasks) do
    local name = task.type == "npm" and task.name:gsub("^npm: ", "") or task.name
    table.insert(items, {
      text = name,
      desc = task.desc or "",
      task = task,
      is_task = true,
    })
  end

  table.insert(items, {
    text = "── Vim Commands ──",
    is_separator = true,
  })

  local commands = vim.fn.getcompletion("", "command")
  for _, cmd in ipairs(commands) do
    table.insert(items, {
      text = cmd,
      is_command = true,
    })
  end

  snacks.picker.pick({
    source = "select",
    items = items,
    prompt = "Run",
    layout = { preset = "vscode" },
    format = function(item)
      if item.is_separator then
        return { { item.text, "Comment" } }
      elseif item.desc and item.desc ~= "" then
        return { { item.text }, { " " .. item.desc, "Comment" } }
      else
        return { { item.text } }
      end
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      if item.is_separator then return end
      if item.is_ai then
        vim.schedule(function()
          require("ai_repl").new_session()
        end)
      elseif item.is_ai_restart then
        vim.schedule(function()
          require("ai_repl").restart_session()
        end)
      elseif item.is_repl then
        require("code_repl").toggle_repl()
      elseif item.is_task then
        if item.task.cmd == "custom" then
          M.run_custom_command()
        else
          M.run_task(item.task)
          M.last_task = item.task
        end
      elseif item.is_command then
        vim.cmd(item.text)
      end
    end,
  })
end

-- Get command history
function M.get_history()
  return M.command_history
end

-- Show running tasks
function M.show_running_tasks()
  -- Clean up finished tasks
  local active_tasks = {}
  for _, task in ipairs(M.running_tasks) do
    -- Check if terminal is still valid
    if task.term and task.term.buf and vim.api.nvim_buf_is_valid(task.term.buf) then
      table.insert(active_tasks, task)
    end
  end
  M.running_tasks = active_tasks

  if #M.running_tasks == 0 then
    vim.notify("No running tasks", vim.log.levels.INFO)
    return
  end

  -- Create items for picker
  local items = {}
  for i, task in ipairs(M.running_tasks) do
    local runtime = os.difftime(os.time(), task.start_time)
    local runtime_str = string.format("%dm %ds", math.floor(runtime / 60), runtime % 60)
    local status = task.background and "[BG]" or "[FG]"

    table.insert(items, {
      text = string.format("%s [%d] %s", status, i, task.name),
      desc = string.format("Running for %s - %s", runtime_str, task.cmd),
      task = task,
      index = i
    })
  end

  -- Add kill all option
  table.insert(items, {
    text = "── Kill All Tasks ──",
    desc = "Terminate all running tasks",
    action = "kill_all"
  })

  -- Use vim.ui.select to show running tasks
  vim.ui.select(items, {
    prompt = "Running Tasks:",
    format_item = function(item)
      if item.desc and item.desc ~= "" then
        return item.text .. " • " .. item.desc
      else
        return item.text
      end
    end,
  }, function(item)
    if not item then
      return
    end

    if item.action == "kill_all" then
      for _, task in ipairs(M.running_tasks) do
        if task.term then
          pcall(function() task.term:close() end)
        end
      end
      M.running_tasks = {}
      vim.notify("All tasks killed", vim.log.levels.INFO)
    elseif item.task then
      -- If background task, attach it; if foreground, focus it
      if item.task.background then
        item.task:attach()
      elseif item.task.term then
        item.task.term:focus()
      end
    end
  end)
end

-- Quick npm commands
function M.run_npm_script(script_name)
  local npm_tasks = load_npm_tasks()
  for _, task in ipairs(npm_tasks) do
    if task.name == "npm: " .. script_name then
      M.run_task(task)
      return true
    end
  end
  return false
end

function M.npm_dev()
  if not M.run_npm_script('dev') then
    if not M.run_npm_script('start') then
      vim.notify('No "dev" or "start" npm script found', vim.log.levels.WARN)
    end
  end
end

function M.npm_test()
  if not M.run_npm_script('test') then
    vim.notify('No "test" npm script found', vim.log.levels.WARN)
  end
end

function M.npm_build()
  if not M.run_npm_script('build') then
    vim.notify('No "build" npm script found', vim.log.levels.WARN)
  end
end

function M.npm_lint()
  if not M.run_npm_script('lint') then
    vim.notify('No "lint" npm script found', vim.log.levels.WARN)
  end
end

-- Run last task
M.last_task = nil
M.last_custom_command = nil

function M.run_last_task()
  if M.last_task then
    M.run_task(M.last_task)
  else
    M.pick_task()
  end
end

-- Kill all tasks (used on exit)
function M.kill_all_tasks()
  -- Kill ALL tasks - background and foreground
  for _, task in ipairs(M.running_tasks) do
    pcall(function()
      -- Handle background tasks
      if task.background and task.job_id then
        vim.fn.jobstop(task.job_id)
      end

      -- Handle terminal tasks (foreground)
      if task.term then
        -- Send interrupt signal first
        if task.term.buf and type(task.term.buf) == "number" and vim.api.nvim_buf_is_valid(task.term.buf) then
          local chan = vim.api.nvim_buf_get_var(task.term.buf, "terminal_job_id")
          if chan then
            vim.fn.chansend(chan, "\x03") -- Send Ctrl+C
            vim.wait(100, function() return false end)
            vim.fn.jobstop(chan) -- Force stop
          end
          vim.api.nvim_buf_delete(task.term.buf, { force = true })
        elseif task.term.close then
          task.term:close()
        end
      end
    end)
  end

  -- Kill any detached/orphaned terminals
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ok, buftype = pcall(vim.api.nvim_buf_get_option, buf, 'buftype')
      if ok and buftype == 'terminal' then
        local ok2, chan = pcall(vim.api.nvim_buf_get_var, buf, 'terminal_job_id')
        if ok2 and chan then
          vim.fn.jobstop(chan)
        end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end

  -- Kill all Neovim jobs
  local jobs = vim.fn.jobwait({}, 0)
  if jobs and type(jobs) == 'table' then
    for _, job_id in ipairs(jobs) do
      if job_id > 0 then
        vim.fn.jobstop(job_id)
      end
    end
  end

  -- Kill child processes
  vim.fn.system('pkill -P ' .. vim.fn.getpid())

  M.running_tasks = {}
end

-- Toggle terminal with unique instance
function M.toggle_terminal()
  if M.terminal_instance and M.terminal_instance.buf and vim.api.nvim_buf_is_valid(M.terminal_instance.buf) then
    local wins = vim.fn.win_findbuf(M.terminal_instance.buf)
    if #wins > 0 then
      M.terminal_instance:hide()
    else
      M.terminal_instance:show()
      M.terminal_instance:focus()
    end
  else
    M.terminal_instance = require("snacks").terminal(nil, {
      win = {
        position = "bottom",
        height = 0.3,
      },
      env = build_terminal_env(),
    })
    M.terminal_instance:show()
    M.terminal_instance:focus()
  end
end

-- Set keymaps
function M.setup()
  -- Auto-detach terminals when their windows are closed
  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(args)
      local winid = tonumber(args.match)
      if winid then
        -- Check all running tasks to see if any terminal window was closed
        for _, task in ipairs(M.running_tasks) do
          if task.term and not task.background then
            -- Ensure buf is a valid number before checking
            local buf = task.term.buf
            if type(buf) == "number" and buf > 0 then
              -- Check if this terminal's window was closed
              local ok, is_valid = pcall(vim.api.nvim_buf_is_valid, buf)
              if ok and is_valid then
                local term_wins = vim.fn.win_findbuf(buf)
                if #term_wins == 0 then
                  -- Terminal window was closed but buffer still exists
                  task:detach()
                end
              end
            end
          end
        end
      end
    end,
  })

  vim.keymap.set("n", "<leader>rl", function()
    M.run_last_task()
  end, { desc = "Run Last Task" })

  vim.keymap.set("n", "<leader>rb", function()
    -- Detach running tasks to background
    local visible_tasks = {}

    for i, task in ipairs(M.running_tasks) do
      if task:is_alive() then
        local is_visible = false
        if task.term and task.term.buf then
          local wins = vim.fn.win_findbuf(task.term.buf)
          is_visible = #wins > 0
        end

        -- Only show visible foreground tasks
        if is_visible and not task.background then
          table.insert(visible_tasks, {
            text = task.name,
            desc = "Started " .. os.date("%H:%M:%S", task.start_time),
            task = task
          })
        end
      end
    end

    if #visible_tasks == 0 then
      vim.notify("No visible tasks to send to background", vim.log.levels.INFO)
      return
    end

    vim.ui.select(visible_tasks, {
      prompt = "Send task to background:",
      format_item = function(item)
        return item.text .. " • " .. item.desc
      end,
    }, function(item)
      if item and item.task then
        item.task:detach()
      end
    end)
  end, { desc = "Send Task to Background" })

  -- Terminal toggle
  vim.keymap.set({"n", "t"}, "<C-\\>", function()
    M.toggle_terminal()
  end, { desc = "Toggle Terminal" })

  -- Kill all tasks on Neovim exit
  vim.api.nvim_create_autocmd({ "VimLeavePre", "VimLeave" }, {
    group = vim.api.nvim_create_augroup("TaskRunnerCleanup", { clear = true }),
    callback = function()
      M.kill_all_tasks()
    end,
    desc = "Kill all running tasks on exit"
  })

  -- Also try to clean up on unexpected exit/crash
  vim.api.nvim_create_autocmd({ "ExitPre" }, {
    group = vim.api.nvim_create_augroup("TaskRunnerEmergencyCleanup", { clear = true }),
    callback = function()
      M.kill_all_tasks()
    end,
    desc = "Emergency cleanup of running tasks"
  })
end

return M