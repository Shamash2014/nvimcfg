-- Task runner and command execution module inspired by command.nvim
local M = {}

-- Configuration
local config = {
  terminal_split = 'horizontal',  -- 'horizontal' or 'vertical'
  terminal_size = 0.3,  -- 30% of window
}

-- Command history (max 200 entries)
local command_history = {}
local max_history = 200
local last_command = nil

-- Project root detection patterns
local root_patterns = {
  '.git', '.svn', '.hg',
  '.envrc', '.mise.toml', '.tool-versions', '.env',
  'flake.nix', 'shell.nix', 'default.nix',
  'docker-compose.yml', 'docker-compose.yaml',
  'package.json', 'Cargo.toml', 'go.mod', 'pom.xml',
  'build.gradle', 'CMakeLists.txt', 'Makefile',
  'setup.py', 'pyproject.toml', 'tsconfig.json',
  'composer.json', '.project', '.vscode', '.idea',
  'mix.exs', 'pubspec.yaml', 'justfile', 'Justfile',
  '.nvmrc', '.python-version', '.ruby-version', '.java-version'
}

-- Detect project root (always tab-local)
function M.get_project_root(path)
  path = path or vim.fn.expand('%:p:h')
  if path == '' then
    -- Always prefer tab-local directory
    path = vim.fn.getcwd(0, 0)
  end

  -- Check for git repository first
  local git_root = vim.fn.system('cd ' .. vim.fn.shellescape(path) .. " && git rev-parse --show-toplevel 2>/dev/null")
      :gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end

  -- Search for project markers
  local current = path
  while current ~= '/' do
    for _, marker in ipairs(root_patterns) do
      local marker_path = current .. '/' .. marker
      if vim.fn.isdirectory(marker_path) == 1 or vim.fn.filereadable(marker_path) == 1 then
        return current
      end
    end
    local parent = vim.fn.fnamemodify(current, ':h')
    if parent == current then
      break
    end
    current = parent
  end

  -- Fallback to tab-local directory
  return vim.fn.getcwd(0, 0)
end

-- Environment detection functions
local function has_mise(project_root)
  return vim.fn.filereadable(project_root .. '/.mise.toml') == 1
end

local function has_direnv(project_root)
  return vim.fn.filereadable(project_root .. '/.envrc') == 1
end

local function has_nix(project_root)
  return vim.fn.filereadable(project_root .. '/flake.nix') == 1 or
         vim.fn.filereadable(project_root .. '/shell.nix') == 1 or
         vim.fn.filereadable(project_root .. '/default.nix') == 1
end

local function has_tool_versions(project_root)
  return vim.fn.filereadable(project_root .. '/.tool-versions') == 1 or
         vim.fn.filereadable(project_root .. '/.nvmrc') == 1 or
         vim.fn.filereadable(project_root .. '/.python-version') == 1 or
         vim.fn.filereadable(project_root .. '/.ruby-version') == 1 or
         vim.fn.filereadable(project_root .. '/.java-version') == 1
end


-- Load command history from cache
local function load_history()
  local cache_file = vim.fn.stdpath('data') .. '/task_history.json'
  if vim.fn.filereadable(cache_file) == 1 then
    local content = vim.fn.readfile(cache_file)
    if #content > 0 then
      local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
      if ok and data then
        command_history = data
      end
    end
  end
end

-- Save command history to cache
local function save_history()
  local cache_file = vim.fn.stdpath('data') .. '/task_history.json'
  local content = vim.json.encode(command_history)
  vim.fn.writefile({ content }, cache_file)
end

-- Add command to history
local function add_to_history(cmd)
  -- Remove duplicates
  for i = #command_history, 1, -1 do
    if command_history[i] == cmd then
      table.remove(command_history, i)
    end
  end

  -- Add to front
  table.insert(command_history, 1, cmd)

  -- Trim to max size
  while #command_history > max_history do
    table.remove(command_history)
  end

  save_history()
  last_command = cmd
end

-- Detect available tasks from project files
local function detect_project_tasks()
  local tasks = {}
  local root = M.get_project_root()

  -- Check for package.json
  local package_json = root .. '/package.json'
  if vim.fn.filereadable(package_json) == 1 then
    local content = vim.fn.readfile(package_json)
    local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
    if ok and data and data.scripts then
      for name, _ in pairs(data.scripts) do
        table.insert(tasks, { name = "npm run " .. name, cmd = "npm run " .. name, type = "npm" })
      end
    end
  end

  -- Check for Makefile
  local makefile = root .. '/Makefile'
  if vim.fn.filereadable(makefile) == 1 then
    local targets = vim.fn.system('make -qp 2>/dev/null | awk -F":" "/^[a-zA-Z0-9][^$#\\/\\t=]*:([^=]|$)/ {print \\$1}" | sort -u')
    for target in targets:gmatch("[^\r\n]+") do
      if not target:match("^%.") and target ~= "" then
        table.insert(tasks, { name = "make " .. target, cmd = "make " .. target, type = "make" })
      end
    end
  end

  -- Check for Cargo.toml
  local cargo_toml = root .. '/Cargo.toml'
  if vim.fn.filereadable(cargo_toml) == 1 then
    local cargo_commands = { "build", "run", "test", "check", "clippy", "fmt" }
    for _, cmd in ipairs(cargo_commands) do
      table.insert(tasks, { name = "cargo " .. cmd, cmd = "cargo " .. cmd, type = "cargo" })
    end
  end

  -- Check for go.mod
  local go_mod = root .. '/go.mod'
  if vim.fn.filereadable(go_mod) == 1 then
    local go_commands = { "build", "run .", "test ./...", "fmt ./...", "vet ./..." }
    for _, cmd in ipairs(go_commands) do
      table.insert(tasks, { name = "go " .. cmd, cmd = "go " .. cmd, type = "go" })
    end
  end

  -- Check for mix.exs
  local mix_exs = root .. '/mix.exs'
  if vim.fn.filereadable(mix_exs) == 1 then
    local mix_commands = { "compile", "test", "format", "deps.get", "phx.server" }
    for _, cmd in ipairs(mix_commands) do
      table.insert(tasks, { name = "mix " .. cmd, cmd = "mix " .. cmd, type = "mix" })
    end
  end

  -- Check for pubspec.yaml (Flutter/Dart)
  local pubspec = root .. '/pubspec.yaml'
  if vim.fn.filereadable(pubspec) == 1 then
    local flutter_commands = { "run", "build apk", "build ios", "test", "analyze", "pub get" }
    for _, cmd in ipairs(flutter_commands) do
      table.insert(tasks, { name = "flutter " .. cmd, cmd = "flutter " .. cmd, type = "flutter" })
    end
  end

  -- Check for docker-compose
  local docker_compose = root .. '/docker-compose.yml'
  local docker_compose_yaml = root .. '/docker-compose.yaml'
  if vim.fn.filereadable(docker_compose) == 1 or vim.fn.filereadable(docker_compose_yaml) == 1 then
    local docker_commands = { "up -d", "down", "build", "logs -f", "ps" }
    for _, cmd in ipairs(docker_commands) do
      table.insert(tasks, { name = "docker compose " .. cmd, cmd = "docker compose " .. cmd, type = "docker" })
    end
  end

  -- Check for justfile
  local justfile = root .. '/justfile'
  local justfile_cap = root .. '/Justfile'
  if vim.fn.filereadable(justfile) == 1 or vim.fn.filereadable(justfile_cap) == 1 then
    local just_output = vim.fn.system('cd ' .. vim.fn.shellescape(root) .. ' && just --list --unsorted 2>/dev/null')
    if vim.v.shell_error == 0 and just_output ~= "" then
      for line in just_output:gmatch("[^\r\n]+") do
        -- Parse lines with format: "    recipe-name  # description" or just "    recipe-name"
        local recipe = line:match("^%s*(%S+)")
        if recipe and recipe ~= "" and recipe ~= "Available" and not recipe:match("^%-") then
          table.insert(tasks, { name = "just " .. recipe, cmd = "just " .. recipe, type = "just" })
        end
      end
    end
  end

  return tasks
end

-- Run command in terminal
function M.run_command(cmd)
  if not cmd or cmd == '' then
    return
  end

  -- Add to history
  add_to_history(cmd)

  -- Get tab-aware project root for ALL commands
  local root = M.get_project_root()
  local final_cmd = 'cd ' .. vim.fn.shellescape(root) .. ' && ' .. cmd

  -- Configure window options based on split type
  local win_opts = {}
  if config.terminal_split == 'vertical' then
    win_opts = {
      style = 'split',
      position = 'right',
      width = config.terminal_size,
    }
  else
    win_opts = {
      style = 'split',
      position = 'bottom',
      height = config.terminal_size,
    }
  end

  -- Use Snacks terminal to execute the command directly
  local terminal = require('snacks').terminal

  -- Get current environment with mise PATH
  local full_env = vim.fn.environ()

  local term = terminal.open(final_cmd, {
    cwd = root,  -- Tab-aware project root
    env = full_env,  -- Pass full environment including mise PATH
    win = win_opts,
    interactive = true,  -- Keep terminal open after command
    auto_close = false,  -- Don't auto-close on exit
    on_exit = function(term_obj, exit_code)
      -- Parse errors immediately when command completes
      if term_obj and term_obj.buf and vim.api.nvim_buf_is_valid(term_obj.buf) then
        local lines = vim.api.nvim_buf_get_lines(term_obj.buf, 0, -1, false)
        local qflist = {}

        -- Enhanced error patterns (similar to Emacs compilation-error-regexp-alist)
        local error_patterns = {
          -- Standard: file:line:col: message
          { pattern = "([^:]+):(%d+):(%d+):%s*(.+)", file = 1, lnum = 2, col = 3, text = 4, type = 'E' },
          -- Standard: file:line: message
          { pattern = "([^:]+):(%d+):%s*(.+)", file = 1, lnum = 2, text = 3, type = 'E' },
          -- Go: file:line:col: message
          { pattern = "([^:]+%.go):(%d+):(%d+):%s*(.+)", file = 1, lnum = 2, col = 3, text = 4, type = 'E' },
          -- Rust: --> file:line:col
          { pattern = "%-%->%s+([^:]+):(%d+):(%d+)", file = 1, lnum = 2, col = 3, text = "Rust error", type = 'E' },
          -- Python: File "file", line N
          { pattern = 'File "([^"]+)", line (%d+)', file = 1, lnum = 2, text = "Python error", type = 'E' },
          -- TypeScript/ESLint: file(line,col): message
          { pattern = "([^%(]+)%((%d+),(%d+)%):%s*(.+)", file = 1, lnum = 2, col = 3, text = 4, type = 'E' },
          -- Maven/Gradle: [ERROR] file:[line,col] message
          { pattern = "%[ERROR%]%s+([^:]+):(%d+):(%d+)%s+(.+)", file = 1, lnum = 2, col = 3, text = 4, type = 'E' },
          -- GCC/Clang: file:line:col: error: message
          { pattern = "([^:]+):(%d+):(%d+):%s*error:%s*(.+)", file = 1, lnum = 2, col = 3, text = 4, type = 'E' },
          -- GCC/Clang warnings
          { pattern = "([^:]+):(%d+):(%d+):%s*warning:%s*(.+)", file = 1, lnum = 2, col = 3, text = 4, type = 'W' },
          -- Jest/Testing: at file:line:col
          { pattern = "at%s+([^:]+):(%d+):(%d+)", file = 1, lnum = 2, col = 3, text = "Test failure", type = 'E' },
          -- Make errors: make: *** [target] Error N
          { pattern = "make:%s*%*%*%*%s*%[([^%]]+)%]%s*Error%s*(%d+)", file = 1, text = "Make error", type = 'E' },
        }

        for _, line in ipairs(lines) do
          for _, pattern_info in ipairs(error_patterns) do
            local matches = { line:match(pattern_info.pattern) }
            if #matches > 0 then
              local entry = {
                filename = matches[pattern_info.file] or "",
                lnum = tonumber(matches[pattern_info.lnum]) or 1,
                col = pattern_info.col and tonumber(matches[pattern_info.col]) or 1,
                text = matches[pattern_info.text] or line,
                type = pattern_info.type or 'E',
                bufnr = 0,
              }

              -- Skip if filename is empty or looks like a flag
              if entry.filename ~= "" and not entry.filename:match("^%-") then
                table.insert(qflist, entry)
              end
              break -- Found a match, don't try other patterns
            end
          end
        end

        -- Limit to last 20 errors
        if #qflist > 20 then
          local start_idx = #qflist - 19
          local limited_qflist = {}
          for i = start_idx, #qflist do
            table.insert(limited_qflist, qflist[i])
          end
          qflist = limited_qflist
        end

        if #qflist > 0 then
          vim.fn.setqflist(qflist, 'r')
          -- Auto-open quickfix like Emacs compilation mode
          vim.cmd('copen')
          vim.notify(string.format("Found %d errors/warnings (showing last 20)", #qflist), vim.log.levels.WARN)

          -- Jump to first error (like Emacs next-error)
          vim.cmd('cfirst')
        elseif exit_code == 0 then
          vim.notify("Command completed successfully", vim.log.levels.INFO)
        else
          vim.notify(string.format("Command exited with code %d", exit_code), vim.log.levels.WARN)
        end
      end
    end,
  })
end

-- Show task picker
function M.show_task_picker()
  load_history()

  local items = {}

  -- ALWAYS add custom command option FIRST
  table.insert(items, {
    text = "Enter custom command...",
    cmd = "custom",
    type = "custom",
    icon = "✎",
  })

  -- Add detected project tasks
  local project_tasks = detect_project_tasks()
  if #project_tasks > 0 then
    -- Add separator before project tasks
    table.insert(items, {
      text = "─────── Project Tasks ────────",
      cmd = nil,
      type = "separator",
      icon = "",
    })

    for _, task in ipairs(project_tasks) do
      table.insert(items, {
        text = task.name,
        cmd = task.cmd,
        type = task.type,
        icon = "▶",
      })
    end
  end

  -- Add recent commands if any exist
  if #command_history > 0 then
    -- Add separator before history
    table.insert(items, {
      text = "─────── Recent Commands ──────",
      cmd = nil,
      type = "separator",
      icon = "",
    })

    for i, cmd in ipairs(command_history) do
      if i <= 10 then -- Show only last 10
        table.insert(items, {
          text = cmd,
          cmd = cmd,
          type = "history",
          icon = "↺",
        })
      end
    end
  end

  -- Show picker using correct API
  vim.ui.select(items, {
    prompt = "Select task to run:",
    format_item = function(item)
      if item.type == "separator" then
        return item.text
      end
      return string.format("%s %s", item.icon or "", item.text)
    end,
  }, function(item)
    if not item or not item.cmd then
      return
    end

    if item.cmd == "custom" then
      -- Prompt for custom command
      vim.ui.input({
        prompt = "Command: ",
      }, function(cmd)
        if cmd and cmd ~= "" then
          M.run_command(cmd)
        end
      end)
    else
      M.run_command(item.cmd)
    end
  end)
end

-- Run last command
function M.run_last_command()
  if last_command then
    M.run_command(last_command)
  else
    load_history()
    if #command_history > 0 then
      M.run_command(command_history[1])
    else
      vim.notify("No command history", vim.log.levels.WARN)
    end
  end
end

-- Show terminal buffers picker
function M.show_terminal_buffers()
  local term_bufs = {}

  -- Find all terminal buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
      if buftype == 'terminal' then
        local name = vim.api.nvim_buf_get_name(buf)
        if name == "" then
          name = "[Terminal " .. buf .. "]"
        else
          name = vim.fn.fnamemodify(name, ":t")
        end
        table.insert(term_bufs, {
          text = name,
          bufnr = buf,
        })
      end
    end
  end

  if #term_bufs == 0 then
    vim.notify("No terminal buffers", vim.log.levels.INFO)
    return
  end

  -- Show picker using vim.ui.select (which uses Snacks)
  vim.ui.select(term_bufs, {
    prompt = "Select terminal:",
    format_item = function(item)
      return item.text
    end,
  }, function(item)
    if item then
      vim.api.nvim_set_current_buf(item.bufnr)
    end
  end)
end

-- Set terminal split type
function M.set_terminal_split(split_type)
  if split_type == 'vertical' or split_type == 'horizontal' then
    config.terminal_split = split_type
  end
end

-- Set terminal size
function M.set_terminal_size(size)
  if type(size) == 'number' and size > 0 and size <= 1 then
    config.terminal_size = size
  end
end

-- Get current configuration
function M.get_config()
  return config
end

-- Initialize
load_history()

return M