local state = require("android.state")

local M = {}

M._job = nil
M._buf = nil
M._win = nil
M._paused = false
M._pending_lines = {}
M._flush_timer = nil
M._level_filter = nil
M._text_filter = nil
M._package_filter = nil
M._retry_count = 0
M._max_retries = 3
M._explicit_stop = false
M._max_lines = 10000

local level_highlights = {
  V = "LogcatVerbose",
  D = "LogcatDebug",
  I = "LogcatInfo",
  W = "LogcatWarn",
  E = "LogcatError",
  F = "LogcatFatal",
}

local function setup_highlights()
  vim.api.nvim_set_hl(0, "LogcatVerbose", { fg = "#6c7086", default = true })
  vim.api.nvim_set_hl(0, "LogcatDebug", { fg = "#89b4fa", default = true })
  vim.api.nvim_set_hl(0, "LogcatInfo", { fg = "#a6e3a1", default = true })
  vim.api.nvim_set_hl(0, "LogcatWarn", { fg = "#f9e2af", default = true })
  vim.api.nvim_set_hl(0, "LogcatError", { fg = "#f38ba8", default = true })
  vim.api.nvim_set_hl(0, "LogcatFatal", { fg = "#f38ba8", bold = true, default = true })
end

local function get_adb()
  local tools = state.get("tools") or {}
  return tools.adb or vim.fn.exepath("adb") or "adb"
end

local function create_buffer()
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    return M._buf
  end

  M._buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M._buf, "android://logcat")
  vim.bo[M._buf].buftype = "nofile"
  vim.bo[M._buf].swapfile = false
  vim.bo[M._buf].modifiable = false
  vim.bo[M._buf].filetype = "logcat"

  local buf = M._buf
  local map = function(key, fn, desc)
    vim.keymap.set("n", key, fn, { buffer = buf, desc = desc })
  end

  map("<CR>", M.jump_to_source, "Jump to source")
  map("c", M.clear, "Clear logcat")
  map("f", M.set_text_filter, "Set text filter")
  map("l", M.set_level_filter, "Set level filter")
  map("p", M.set_package_filter, "Set package filter")
  map("q", function() M.toggle() end, "Close logcat")
  map("<Space>", function()
    M._paused = not M._paused
    vim.notify("Logcat " .. (M._paused and "paused" or "resumed"), vim.log.levels.INFO)
  end, "Pause/Resume")

  return M._buf
end

local function apply_highlights(buf, start_line, lines)
  for i, line in ipairs(lines) do
    local level = line:match("^%d%d%-%d%d%s+%d%d:%d%d:%d%d%.%d+%s+%d+%s+%d+%s+(%a)")
      or line:match("^(%a)/")
    if level and level_highlights[level] then
      pcall(vim.api.nvim_buf_add_highlight, buf, -1, level_highlights[level], start_line + i - 1, 0, -1)
    end
  end
end

local function flush_lines()
  if #M._pending_lines == 0 then return end
  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then return end
  if M._paused then return end

  local lines = {}
  for _, line in ipairs(M._pending_lines) do
    if M._text_filter then
      if line:match(M._text_filter) then
        table.insert(lines, line)
      end
    else
      table.insert(lines, line)
    end
  end
  M._pending_lines = {}

  if #lines == 0 then return end

  local buf = M._buf
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

  local line_count = vim.api.nvim_buf_line_count(buf)
  local is_empty = line_count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""

  if is_empty then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    apply_highlights(buf, 0, lines)
  else
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    apply_highlights(buf, line_count, lines)
  end

  local new_count = vim.api.nvim_buf_line_count(buf)
  if new_count > M._max_lines then
    local trim = new_count - M._max_lines
    vim.api.nvim_buf_set_lines(buf, 0, trim, false, {})
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  if M._win and vim.api.nvim_win_is_valid(M._win) then
    local final_count = vim.api.nvim_buf_line_count(buf)
    pcall(vim.api.nvim_win_set_cursor, M._win, { final_count, 0 })
  end
end

local function start_flush_timer()
  if M._flush_timer then return end
  M._flush_timer = vim.loop.new_timer()
  M._flush_timer:start(100, 100, vim.schedule_wrap(function()
    flush_lines()
  end))
end

local function stop_flush_timer()
  if M._flush_timer then
    M._flush_timer:stop()
    M._flush_timer:close()
    M._flush_timer = nil
  end
end

function M.start(opts)
  opts = opts or {}
  M.stop()

  create_buffer()
  setup_highlights()
  start_flush_timer()

  local adb = get_adb()
  local args = { "logcat" }

  if opts.clear_first ~= false then
    table.insert(args, "-c")
  end

  args = { "logcat" }

  if M._level_filter then
    table.insert(args, "*:" .. M._level_filter)
  end

  if M._package_filter then
    table.insert(args, "--pid")
    local serial = state.get("selected_device")
    local pid_args = serial
      and { "-s", serial, "shell", "pidof", "-s", M._package_filter }
      or { "shell", "pidof", "-s", M._package_filter }

    local Job = require("plenary.job")
    local pid_job = Job:new({
      command = adb,
      args = pid_args,
    })
    pid_job:sync(5000)
    local pid = (pid_job:result()[1] or ""):match("^(%d+)")
    if pid then
      table.insert(args, pid)
    end
  end

  local serial = state.get("selected_device")
  local full_args = {}
  if serial then
    vim.list_extend(full_args, { "-s", serial })
  end
  vim.list_extend(full_args, args)

  M._explicit_stop = false
  M._retry_count = 0

  local Job = require("plenary.job")
  M._job = Job:new({
    command = adb,
    args = full_args,
    on_stdout = function(_, data)
      if data then
        table.insert(M._pending_lines, data)
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if not M._explicit_stop and M._retry_count < M._max_retries then
          M._retry_count = M._retry_count + 1
          vim.notify(
            string.format("Logcat disconnected, retrying (%d/%d)...", M._retry_count, M._max_retries),
            vim.log.levels.WARN
          )
          vim.defer_fn(function()
            M.start({ clear_first = false })
          end, 2000)
        end
      end)
    end,
  })
  M._job:start()
end

function M.stop()
  M._explicit_stop = true
  stop_flush_timer()
  if M._job then
    pcall(function() M._job:shutdown() end)
    M._job = nil
  end
end

function M.clear()
  local adb = get_adb()
  local args = {}
  local serial = state.get("selected_device")
  if serial then
    vim.list_extend(args, { "-s", serial })
  end
  vim.list_extend(args, { "logcat", "-c" })

  require("plenary.job"):new({
    command = adb,
    args = args,
    on_exit = function()
      vim.schedule(function()
        if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
          vim.api.nvim_set_option_value("modifiable", true, { buf = M._buf })
          vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, {})
          vim.api.nvim_set_option_value("modifiable", false, { buf = M._buf })
        end
        vim.notify("Logcat cleared", vim.log.levels.INFO)
      end)
    end,
  }):start()
end

function M.toggle()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
    M._win = nil
    return
  end

  create_buffer()

  if not M._job then
    M.start()
  end

  local height = math.floor(vim.o.lines * 0.4)
  vim.cmd("botright " .. height .. "split")
  M._win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M._win, M._buf)
  vim.wo[M._win].number = false
  vim.wo[M._win].relativenumber = false
  vim.wo[M._win].signcolumn = "no"
  vim.wo[M._win].winfixheight = true
  vim.wo[M._win].wrap = false

  local line_count = vim.api.nvim_buf_line_count(M._buf)
  if line_count > 0 then
    pcall(vim.api.nvim_win_set_cursor, M._win, { line_count, 0 })
  end
end

function M.set_level_filter(level)
  if level then
    M._level_filter = level
    M.start({ clear_first = false })
    return
  end

  vim.ui.select({ "V (Verbose)", "D (Debug)", "I (Info)", "W (Warning)", "E (Error)", "F (Fatal)", "None" }, {
    prompt = "Log level filter:",
  }, function(selected)
    if not selected then return end
    if selected == "None" then
      M._level_filter = nil
    else
      M._level_filter = selected:sub(1, 1)
    end
    M.start({ clear_first = false })
  end)
end

function M.set_text_filter()
  vim.ui.input({
    prompt = "Text filter (regex, empty to clear): ",
    default = M._text_filter or "",
  }, function(input)
    if input == nil then return end
    M._text_filter = input ~= "" and input or nil
    vim.notify(
      M._text_filter and ("Filter: " .. M._text_filter) or "Filter cleared",
      vim.log.levels.INFO
    )
  end)
end

function M.set_package_filter(package)
  if package then
    M._package_filter = package
    M.start({ clear_first = false })
    return
  end

  local app_id = state.get("application_id")
  vim.ui.input({
    prompt = "Package filter: ",
    default = app_id or "",
  }, function(input)
    if input == nil then return end
    M._package_filter = input ~= "" and input or nil
    M.start({ clear_first = false })
  end)
end

function M.jump_to_source()
  local line = vim.api.nvim_get_current_line()

  local file, lnum = line:match("%((%w+%.%w+):(%d+)%)")
  if not file then
    file, lnum = line:match("at%s+[%w%.]+%((%w+%.%w+):(%d+)%)")
  end

  if not file then
    vim.notify("No source reference found on this line", vim.log.levels.INFO)
    return
  end

  local found = vim.fn.findfile(file, "**")
  if found == "" then
    vim.notify("File not found: " .. file, vim.log.levels.WARN)
    return
  end

  local main_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= M._win then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].buftype == "" then
        main_win = win
        break
      end
    end
  end

  if main_win then
    vim.api.nvim_set_current_win(main_win)
  end

  vim.cmd("edit " .. found)
  local target_line = tonumber(lnum) or 1
  pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
  vim.cmd("normal! zz")
end

return M
