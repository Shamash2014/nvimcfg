local M = {}

-- Track running tasks
M.running_tasks = {}

-- Track unique terminal instances for toggle
M.terminals = {}

-- Command history
M.command_history = {}
M.max_history = 50

-- Add command to history
local function add_to_history(task)
  local entry = {
    name = task.name,
    cmd = task.cmd,
    desc = task.desc,
    timestamp = os.time(),
  }

  -- Remove duplicate if exists (same cmd)
  for i = #M.command_history, 1, -1 do
    if M.command_history[i].cmd == task.cmd then
      table.remove(M.command_history, i)
      break
    end
  end

  -- Add to front of history
  table.insert(M.command_history, 1, entry)

  -- Trim to max size
  while #M.command_history > M.max_history do
    table.remove(M.command_history)
  end
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
local function load_npm_tasks()
  local tasks = {}
  local package_json = vim.fn.getcwd() .. "/package.json"

  if vim.fn.filereadable(package_json) == 1 then
    local ok, content = pcall(vim.fn.readfile, package_json)
    if not ok then return {} end

    local json_str = table.concat(content, '\n')
    local ok2, package = pcall(vim.json.decode, json_str)
    if not ok2 or not package.scripts then
      return {}
    end

    for name, command in pairs(package.scripts) do
      table.insert(tasks, {
        name = "npm: " .. name,
        cmd = "npm run " .. name,
        desc = command:sub(1, 50),  -- Show first 50 chars of command
        type = "npm"
      })
    end
  end

  return tasks
end

-- Parse Justfile for recipes
local function load_justfile_tasks()
  local tasks = {}
  local justfile_path = vim.fn.getcwd() .. "/justfile"

  -- Also check for Justfile with capital J
  if vim.fn.filereadable(justfile_path) == 0 then
    justfile_path = vim.fn.getcwd() .. "/Justfile"
  end

  if vim.fn.filereadable(justfile_path) == 1 then
    local lines = vim.fn.readfile(justfile_path)
    for _, line in ipairs(lines) do
      -- Match recipe definitions (lines that start with a recipe name followed by optional parameters and colon)
      -- Skip lines that start with @ or whitespace (commands) or # (comments)
      local recipe = line:match("^([%w%-_]+)[^:]*:")
      if recipe then
        table.insert(tasks, {
          name = "just: " .. recipe,
          cmd = "just " .. recipe,
          type = "justfile",
        })
      end
    end
  end

  return tasks
end

-- Parse Makefile for targets
local function load_makefile_tasks()
  local tasks = {}
  local makefile_path = vim.fn.getcwd() .. "/Makefile"

  -- Also check for makefile with lowercase m
  if vim.fn.filereadable(makefile_path) == 0 then
    makefile_path = vim.fn.getcwd() .. "/makefile"
  end

  if vim.fn.filereadable(makefile_path) == 1 then
    local lines = vim.fn.readfile(makefile_path)
    for _, line in ipairs(lines) do
      -- Match target definitions (lines that start with a target name followed by colon)
      -- Skip special targets that start with . and PHONY declarations
      local target = line:match("^([%w%-_]+):")
      if target and not target:match("^%.") then
        table.insert(tasks, {
          name = "make: " .. target,
          cmd = "make " .. target,
          type = "makefile",
        })
      end
    end
  end

  return tasks
end

-- Get available tasks for current project
function M.get_tasks()
  local project_tasks = {}

  -- First, load npm scripts if package.json exists
  local npm_tasks = load_npm_tasks()
  for _, task in ipairs(npm_tasks) do
    table.insert(project_tasks, task)
  end

  -- Load VSCode tasks if they exist
  local vscode_tasks = M.load_vscode_tasks()
  for _, task in ipairs(vscode_tasks) do
    table.insert(project_tasks, task)
  end

  -- Load Justfile recipes
  local justfile_tasks = load_justfile_tasks()
  for _, task in ipairs(justfile_tasks) do
    table.insert(project_tasks, task)
  end

  -- Load Makefile targets
  local makefile_tasks = load_makefile_tasks()
  for _, task in ipairs(makefile_tasks) do
    table.insert(project_tasks, task)
  end

  -- Then add tasks based on detected project type
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
  local cwd = vim.fs.root(0, { ".git" }) or vim.fn.getcwd()

  -- Default to splits (smaller vertical for custom commands, horizontal for others)
  -- Check if this is a custom command (starts with "custom:")
  local is_custom = task.name:match("^custom:") ~= nil
  local win_config = not opts.background and {
    position = is_custom and "right" or "bottom",
    height = not is_custom and 0.3 or nil,
    width = is_custom and 0.3 or nil,  -- Smaller width for vertical splits
  } or nil

  -- Create a unique terminal using a wrapper command to ensure uniqueness
  -- Add timestamp to make each command unique for Snacks
  local unique_cmd = cmd
  local timestamp = tostring(vim.loop.hrtime())

  -- For custom commands, wrap in a shell with unique environment variable
  if task.name:match("^custom:") then
    -- Use shell -c to run the command with a unique env var
    local shell = vim.o.shell or "/bin/sh"
    unique_cmd = string.format("%s -c 'TASK_ID=%s %s'", shell, timestamp, cmd)
  end

  -- Use Snacks terminal but force it to see each as unique
  local term = require("snacks").terminal(unique_cmd, {
    cwd = cwd,
    interactive = not opts.background,
    hidden = opts.background or false,
    win = win_config,
    -- Add unique identifier to prevent caching
    env = {
      SNACKS_TASK_ID = timestamp,
      TASK_NAME = task.name,
    },
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
  -- Check if terminal instance exists
  if M.terminal_instance and M.terminal_instance.buf and vim.api.nvim_buf_is_valid(M.terminal_instance.buf) then
    -- Check if terminal is visible
    local wins = vim.fn.win_findbuf(M.terminal_instance.buf)
    if #wins > 0 then
      -- Terminal is visible, hide it
      M.terminal_instance:hide()
    else
      -- Terminal is hidden, show it
      M.terminal_instance:show()
      M.terminal_instance:focus()
    end
  else
    -- Create new terminal instance
    M.terminal_instance = require("snacks").terminal(nil, {
      win = {
        position = "bottom",
        height = 0.3,
      }
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

  vim.keymap.set("n", "<leader>rr", function()
    M.pick_task()
  end, { desc = "Run Task" })

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

  vim.keymap.set("n", "<leader>br", function()
    M.show_running_tasks()
  end, { desc = "Show Running Tasks" })

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