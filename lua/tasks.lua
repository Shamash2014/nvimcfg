-- Task runner and command execution module inspired by command.nvim
local M = {}

-- Configuration
local config = {
  terminal_split = 'horizontal',  -- 'horizontal' or 'vertical'
  terminal_size = 0.3,  -- 30% of window (capped at this value unless overridden)
  vertical_terminal_size = 0.2,  -- 20% width for vertical splits
}

-- Validate terminal size to ensure it doesn't exceed limits unless explicitly allowed
local function validate_terminal_size(size, allow_override, is_vertical)
  if type(size) == 'number' and size > 0 and size <= 1 then
    local max_size = is_vertical and 0.5 or 0.3  -- Allow up to 50% for vertical, 30% for horizontal
    if not allow_override and size > max_size then
      return max_size
    end
    return size
  end
  -- Default fallback based on split type
  return is_vertical and 0.2 or 0.3
end

-- Get appropriate terminal size based on split type
local function get_terminal_size(is_vertical)
  return is_vertical and config.vertical_terminal_size or config.terminal_size
end

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

-- Parse errors from lines using error patterns
function M.parse_errors_from_lines(lines, root)
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

  local qflist = {}
  root = root or M.get_project_root()

  for _, line in ipairs(lines) do
    for _, pattern_info in ipairs(error_patterns) do
      local matches = { line:match(pattern_info.pattern) }
      if #matches > 0 then
        local filename = matches[pattern_info.file] or ""

        -- Skip if filename is empty or looks like a flag
        if filename ~= "" and not filename:match("^%-") then
          -- Resolve file path to absolute path relative to project root
          local absolute_path = filename
          if not vim.startswith(filename, '/') then
            -- If relative path, make it relative to project root
            absolute_path = root .. '/' .. filename
          end

          -- Normalize path (remove ./ and resolve ../)
          absolute_path = vim.fs.normalize(absolute_path)

          -- Check if file exists, if not try current working directory
          if vim.fn.filereadable(absolute_path) == 0 then
            local cwd_path = vim.fn.getcwd() .. '/' .. filename
            cwd_path = vim.fs.normalize(cwd_path)
            if vim.fn.filereadable(cwd_path) == 1 then
              absolute_path = cwd_path
            end
          end

          local entry = {
            filename = absolute_path,
            lnum = tonumber(matches[pattern_info.lnum]) or 1,
            col = pattern_info.col and tonumber(matches[pattern_info.col]) or 1,
            text = matches[pattern_info.text] or line,
            type = pattern_info.type or 'E',
          }

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

  return qflist
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

  -- Configure window options based on split type with size validation
  local is_vertical = config.terminal_split == 'vertical'
  local size = get_terminal_size(is_vertical)
  local validated_size = validate_terminal_size(size, false, is_vertical)
  local win_opts = {}
  if is_vertical then
    win_opts = {
      style = 'split',
      position = 'right',
      width = validated_size,
    }
  else
    win_opts = {
      style = 'split',
      position = 'bottom',
      height = validated_size,
    }
  end

  -- Use Snacks terminal for command execution
  local ok, snacks = pcall(require, 'snacks')
  if not ok then
    vim.notify('Snacks not available', vim.log.levels.ERROR)
    return
  end

  -- Build Snacks terminal options
  local snacks_opts = {
    cwd = root,
    win = {
      position = is_vertical and 'right' or 'bottom',
      width = is_vertical and validated_size or nil,
      height = is_vertical and nil or validated_size,
    },
  }

  -- Create terminal using new module
  local term = snacks.terminal.open(final_cmd, snacks_opts)

  -- Return focus to original window
  if current_win and vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end
end

-- Run command in background terminal
function M.run_command_background(cmd)
  if not cmd or cmd == '' then
    return
  end

  -- Add to history
  add_to_history(cmd)

  -- Get tab-aware project root
  local root = M.get_project_root()
  local final_cmd = 'cd ' .. vim.fn.shellescape(root) .. ' && ' .. cmd

  -- Run in background with notification
  vim.notify("Running in background: " .. cmd, vim.log.levels.INFO)

  -- Store current buffer to return focus
  local current_buf = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  -- Use Snacks terminal for background execution
  local ok, snacks = pcall(require, 'snacks')
  if not ok then
    vim.notify('Snacks not available', vim.log.levels.ERROR)
    return
  end

  local snacks_opts = {
    cwd = root,
    win = {
      position = 'bottom',
      height = 0.2,
    },
  }

  -- Create terminal using new module
  local term = snacks.terminal.open(final_cmd, snacks_opts)

  -- Return focus to original window
  if current_win and vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end
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

-- Show background task picker
function M.show_background_task_picker()
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
        text = task.name .. " (background)",
        cmd = task.cmd,
        type = task.type,
        icon = "⚡",
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
          text = cmd .. " (background)",
          cmd = cmd,
          type = "history",
          icon = "⚡",
        })
      end
    end
  end

  -- Show picker using correct API
  vim.ui.select(items, {
    prompt = "Select task to run in background:",
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
        prompt = "Background command: ",
      }, function(cmd)
        if cmd and cmd ~= "" then
          M.run_command_background(cmd)
        end
      end)
    else
      M.run_command_background(item.cmd)
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

-- Restart command in current terminal buffer if it's a Snacks terminal
function M.restart_terminal_command()
  local buf = vim.api.nvim_get_current_buf()
  local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')

  if buftype ~= 'terminal' then
    vim.notify("Not in a terminal buffer", vim.log.levels.WARN)
    return
  end

  -- Check if it's a Snacks terminal
  local terminal_info = vim.b[buf].snacks_terminal
  if not terminal_info or not terminal_info.cmd then
    vim.notify("No command to restart in this terminal", vim.log.levels.WARN)
    return
  end

  local cmd = terminal_info.cmd
  if type(cmd) == "table" then
    cmd = table.concat(cmd, " ")
  end

  -- Send Ctrl+C to interrupt current process
  vim.api.nvim_feedkeys("\x03", "n", false)

  -- Wait for process to terminate, then clear and restart
  vim.defer_fn(function()
    vim.api.nvim_feedkeys("clear\n", "n", false)

    vim.defer_fn(function()
      vim.api.nvim_feedkeys(cmd .. "\n", "n", false)
      vim.notify("Restarted: " .. cmd, vim.log.levels.INFO)
    end, 100)
  end, 200)
end

-- Check if a terminal job is still running
local function is_terminal_job_running(bufnr)
  local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, 'terminal_job_id')
  if not ok or not job_id then
    return false
  end

  -- Use jobwait with timeout 0 to check if job is still running
  -- Returns 0 if job is still running, job_id if it has exited
  local result = vim.fn.jobwait({job_id}, 0)
  return result[1] == -1 -- -1 means job is still running
end

-- Parse errors from terminal buffer and populate quickfix
function M.parse_terminal_errors(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check if buffer is valid and is a terminal
  if not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("Invalid buffer", vim.log.levels.ERROR)
    return
  end

  local buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
  if buftype ~= 'terminal' then
    vim.notify("Not a terminal buffer", vim.log.levels.WARN)
    return
  end

  -- Get buffer lines and parse errors
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local qflist = M.parse_errors_from_lines(lines)

  if #qflist > 0 then
    vim.fn.setqflist(qflist, 'r')
    vim.cmd('copen')
    vim.notify(string.format("Found %d errors/warnings in terminal buffer", #qflist), vim.log.levels.INFO)
    vim.cmd('cfirst')
  else
    vim.notify("No errors found in terminal buffer", vim.log.levels.INFO)
  end
end

-- Show terminal buffers picker
function M.show_terminal_buffers()
  local term_bufs = {}

  -- Find all active terminal buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
      if buftype == 'terminal' then
        -- Only include running terminals (filter out exited ones)
        local is_running = is_terminal_job_running(buf)
        if is_running then
          local name = vim.api.nvim_buf_get_name(buf)
          if name == "" then
            name = "[Terminal " .. buf .. "]"
          else
            name = vim.fn.fnamemodify(name, ":t")
          end

          -- Add pin indicator if available
          local pin_indicator = ""
          if _G.buffer_pin and _G.buffer_pin.get_pin_indicator then
            pin_indicator = _G.buffer_pin.get_pin_indicator(buf)
          end

          -- Add running status indicator
          local status_indicator = "🟢 "

          table.insert(term_bufs, {
            text = pin_indicator .. status_indicator .. name,
            bufnr = buf,
          })
        end
      end
    end
  end

  if #term_bufs == 0 then
    vim.notify("No active terminal buffers", vim.log.levels.INFO)
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
      -- Create new split based on terminal configuration
      local is_vertical = config.terminal_split == 'vertical'
      local size = get_terminal_size(is_vertical)
      local validated_size = validate_terminal_size(size, false, is_vertical)

      if is_vertical then
        vim.cmd('vsplit')
        vim.api.nvim_win_set_width(0, math.floor(vim.o.columns * validated_size))
      else
        vim.cmd('split')
        vim.api.nvim_win_set_height(0, math.floor(vim.o.lines * validated_size))
      end

      -- Set the terminal buffer in the new split
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

-- Set terminal size with appropriate caps unless explicitly overridden
function M.set_terminal_size(size, allow_override, split_type)
  split_type = split_type or config.terminal_split
  if type(size) == 'number' and size > 0 and size <= 1 then
    local is_vertical = split_type == 'vertical'
    local max_size = is_vertical and 0.5 or 0.3  -- 50% for vertical, 30% for horizontal

    if not allow_override and size > max_size then
      vim.notify(string.format("Terminal size capped at %d%%. Use allow_override=true to bypass.", max_size * 100), vim.log.levels.WARN)
      size = max_size
    end

    if is_vertical then
      config.vertical_terminal_size = size
    else
      config.terminal_size = size
    end
  end
end

-- Set vertical terminal size specifically
function M.set_vertical_terminal_size(size, allow_override)
  M.set_terminal_size(size, allow_override, 'vertical')
end

-- Get current configuration
function M.get_config()
  return config
end

-- Initialize
load_history()

return M