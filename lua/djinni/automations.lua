local M = {}

local ui = require("djinni.integrations.snacks_ui")

local function find_chat_buf(preferred)
  if preferred and vim.api.nvim_buf_is_valid(preferred) and vim.b[preferred].neowork_chat then
    return preferred
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].neowork_chat then
      return buf
    end
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].neowork_chat then
      return buf
    end
  end

  return nil
end

local function add_agent_items(items, chat_buf)
  if not chat_buf then return end

  local ok, stream = pcall(require, "neowork.stream")
  if not ok or not stream then return end

  for _, cmd in ipairs(stream.get_available_commands(chat_buf) or {}) do
    local name = cmd.name or cmd.id
    if name and name ~= "" then
      items[#items + 1] = {
        kind = "agent_command",
        source = "acp",
        label = "/" .. name,
        desc = cmd.description or "ACP command",
        chat_buf = chat_buf,
        command = cmd,
      }
    end
  end
end

local function add_history_items(items, history)
  for i = 1, math.min(5, #(history or {})) do
    local entry = history[i]
    items[#items + 1] = {
      kind = "history_command",
      source = "history",
      label = entry.name,
      desc = entry.cmd,
      task = {
        name = entry.name,
        cmd = entry.cmd,
        desc = entry.desc,
      },
    }
  end
end

local function add_task_items(items, tasks)
  for _, task in ipairs(tasks or {}) do
    items[#items + 1] = {
      kind = "task",
      source = "task",
      label = task.name,
      desc = task.desc or task.cmd or "",
      task = task,
    }
  end
end

local function read_schedule_state(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].neowork_chat then
    return nil
  end

  local document = require("neowork.document")
  return {
    enabled = document.read_frontmatter_field(buf, "schedule_enabled") == "true",
    interval = document.read_frontmatter_field(buf, "schedule_interval") or "",
    command = document.read_frontmatter_field(buf, "schedule_command") or "",
    next_run = document.read_frontmatter_field(buf, "schedule_next_run") or "",
    last_error = document.read_frontmatter_field(buf, "schedule_last_error") or "",
  }
end

local function schedule_desc(state)
  local parts = {}
  if state.interval ~= "" then
    parts[#parts + 1] = "every " .. state.interval
  end
  if state.command ~= "" then
    parts[#parts + 1] = state.command
  end
  if state.enabled and state.next_run ~= "" then
    parts[#parts + 1] = "next " .. state.next_run
  end
  if state.last_error ~= "" then
    parts[#parts + 1] = "error: " .. state.last_error
  end
  return table.concat(parts, " • ")
end

local function add_scheduler_items(items, chat_buf)
  local state = read_schedule_state(chat_buf)
  if not state then return end

  local desc = schedule_desc(state)
  items[#items + 1] = {
    kind = "schedule_configure",
    source = "schedule",
    label = state.command ~= "" and "update schedule" or "set schedule",
    desc = desc ~= "" and desc or "Configure recurring Ex command",
    chat_buf = chat_buf,
  }
  items[#items + 1] = {
    kind = "schedule_toggle",
    source = "schedule",
    label = state.enabled and "disable schedule" or "enable schedule",
    desc = desc ~= "" and desc or "Toggle scheduled automation",
    chat_buf = chat_buf,
  }
  items[#items + 1] = {
    kind = "schedule_run",
    source = "schedule",
    label = "run schedule now",
    desc = desc ~= "" and desc or "Run the scheduled command immediately",
    chat_buf = chat_buf,
  }
  items[#items + 1] = {
    kind = "schedule_clear",
    source = "schedule",
    label = "clear schedule",
    desc = "Remove all stored schedule metadata",
    chat_buf = chat_buf,
  }
end

local function prompt_for_agent_args(item, callback)
  local cmd = item.command or {}
  local wants_args = cmd.arguments ~= nil
    or cmd.inputSchema ~= nil
    or cmd.params ~= nil
    or cmd.acceptsArguments == true
    or cmd.takesArguments == true

  if not wants_args then
    callback("")
    return
  end

  vim.ui.input({ prompt = "Arguments for " .. item.label .. ": " }, function(input)
    if input == nil then
      callback(nil)
      return
    end
    callback(vim.trim(input))
  end)
end

local function run_agent_command(item)
  local buf = find_chat_buf(item.chat_buf)
  if not buf then
    vim.notify("djinni: no active neowork session for ACP automations", vim.log.levels.WARN)
    return
  end

  prompt_for_agent_args(item, function(args)
    if args == nil then return end

    local text = item.label
    if args ~= "" then
      text = text .. " " .. args
    end

    local document = require("neowork.document")
    local bridge = require("neowork.bridge")
    document.insert_turn(buf, "You", text)
    bridge.send(buf, text)
  end)
end

local function run_task_item(item)
  if item.kind == "custom_command" then
    require("core.tasks").run_custom_command()
    return
  end

  if not item.task then return end
  require("core.tasks").run_task(item.task)
end

function M.configure_schedule(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].neowork_chat then
    vim.notify("djinni: no active neowork session for schedule automation", vim.log.levels.WARN)
    return
  end

  local document = require("neowork.document")
  local scheduler = require("neowork.scheduler")
  local current_interval = document.read_frontmatter_field(buf, "schedule_interval") or ""
  local current_command = document.read_frontmatter_field(buf, "schedule_command") or ""
  vim.ui.input({ prompt = "Schedule interval (e.g. 30m, 1h, 1d): ", default = current_interval }, function(interval)
    if not interval or vim.trim(interval) == "" then return end
    vim.ui.input({ prompt = "Schedule Ex command: ", default = current_command }, function(command)
      if not command or vim.trim(command) == "" then return end
      local ok, err = scheduler.enable(buf, interval, command)
      if ok then
        vim.notify("neowork: schedule enabled", vim.log.levels.INFO)
      else
        vim.notify("neowork: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.toggle_schedule(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].neowork_chat then
    vim.notify("djinni: no active neowork session for schedule automation", vim.log.levels.WARN)
    return
  end

  local document = require("neowork.document")
  local scheduler = require("neowork.scheduler")
  local enabled = document.read_frontmatter_field(buf, "schedule_enabled") == "true"
  local ok, err
  if enabled then
    ok, err = scheduler.disable(buf)
    if ok then
      vim.notify("neowork: schedule disabled", vim.log.levels.INFO)
    end
  else
    local interval = document.read_frontmatter_field(buf, "schedule_interval") or ""
    local command = document.read_frontmatter_field(buf, "schedule_command") or ""
    ok, err = scheduler.enable(buf, interval, command)
    if ok then
      vim.notify("neowork: schedule enabled", vim.log.levels.INFO)
    end
  end
  if not ok then
    vim.notify("neowork: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.run_schedule_now(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].neowork_chat then
    vim.notify("djinni: no active neowork session for schedule automation", vim.log.levels.WARN)
    return
  end

  local ok, err = require("neowork.scheduler").run_now(buf)
  if ok then
    vim.notify("neowork: schedule ran", vim.log.levels.INFO)
  else
    vim.notify("neowork: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.clear_schedule(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].neowork_chat then
    vim.notify("djinni: no active neowork session for schedule automation", vim.log.levels.WARN)
    return
  end

  require("neowork.scheduler").clear(buf)
  vim.notify("neowork: schedule cleared", vim.log.levels.INFO)
end

function M.run(item)
  if not item then return end

  if item.kind == "agent_command" then
    run_agent_command(item)
    return
  end

  if item.kind == "schedule_configure" then
    M.configure_schedule(find_chat_buf(item.chat_buf))
    return
  end

  if item.kind == "schedule_toggle" then
    M.toggle_schedule(find_chat_buf(item.chat_buf))
    return
  end

  if item.kind == "schedule_run" then
    M.run_schedule_now(find_chat_buf(item.chat_buf))
    return
  end

  if item.kind == "schedule_clear" then
    M.clear_schedule(find_chat_buf(item.chat_buf))
    return
  end

  if item.kind == "task" or item.kind == "history_command" or item.kind == "custom_command" then
    run_task_item(item)
  end
end

function M.collect(opts, callback)
  opts = opts or {}
  local chat_buf = find_chat_buf(opts.buf)
  local items = {}
  local include_agent = opts.include_agent ~= false
  local include_custom = opts.include_custom ~= false
  local include_history = opts.include_history ~= false
  local include_tasks = opts.include_tasks ~= false
  local include_scheduler = opts.include_scheduler ~= false

  if include_agent then
    add_agent_items(items, chat_buf)
  end

  if include_scheduler then
    add_scheduler_items(items, chat_buf)
  end

  if not include_custom and not include_history and not include_tasks then
    callback(items)
    return
  end

  local ok, tasks = pcall(require, "core.tasks")
  if not ok or not tasks then
    callback(items)
    return
  end

  if include_custom then
    items[#items + 1] = {
      kind = "custom_command",
      source = "task",
      label = "custom command",
      desc = "Run an arbitrary shell command",
    }
  end

  if include_history then
    add_history_items(items, tasks.command_history or {})
  end

  tasks.get_tasks(function(available_tasks)
    if include_tasks then
      add_task_items(items, available_tasks)
    end
    callback(items)
  end)
end

function M.pick(opts)
  opts = opts or {}

  M.collect(opts, function(items)
    if not items or #items == 0 then
      vim.notify("djinni: no automations available", vim.log.levels.WARN)
      return
    end

    ui.select(items, {
      prompt = "Automation:",
      format_item = function(item)
        local source = item.source and ("[" .. item.source .. "] ") or ""
        if item.desc and item.desc ~= "" then
          return source .. item.label .. " • " .. item.desc
        end
        return source .. item.label
      end,
    }, function(choice)
      M.run(choice)
    end)
  end)
end

return M
