local M = {}

local chat_parser = require("ai_repl.chat_parser")
local chat_state = require("ai_repl.chat_state")

-- Helper function to update folds for a buffer
local function update_folds(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    pcall(vim.cmd, "silent! foldupdate")
  end
end

local NS_ROLE = vim.api.nvim_create_namespace("chat_role")
local NS_RULER = vim.api.nvim_create_namespace("chat_ruler")
local NS_SPIN = vim.api.nvim_create_namespace("chat_spin")
local NS_TOKENS = vim.api.nvim_create_namespace("chat_tokens")
local NS_LINE_HL = vim.api.nvim_create_namespace("chat_line_hl")
local NS_TOOL_STATUS = vim.api.nvim_create_namespace("chat_tool_status")

local SPINNERS = {
  generating = { "|", "/", "-", "\\" },
  thinking = { ".", "..", "..." },
  executing = { "[=  ]", "[ = ]", "[  =]", "[ = ]" },
}
local SPIN_TIMING = { generating = 100, thinking = 400, executing = 150 }

local ROLE_HL = {
  user = "ChatRoleYou",
  djinni = "ChatRoleDjinni",
  system = "ChatRoleSystem",
}

local ROLE_SIGN = {
  user = ">>",
  djinni = "🧞",
  system = "SY",
}

local spinner_state = {}
local redecorate_timers = {}

local function apply_role_highlights(buf)
  -- DISABLED: Highlighting was causing 91% of processing time
  -- This function was too expensive and has been disabled for performance
  return
end

local function apply_rulers(buf)
  -- Rulers disabled by default for performance - re-enable with config
  -- Use schedule_redecorate() for throttled updates
  return
end

function M.redecorate(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  apply_role_highlights(buf)
  apply_rulers(buf)
end

function M.schedule_redecorate(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  -- Skip redecoration for very large buffers (>1000 lines) during active editing
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count > 1000 then
    local mode = vim.api.nvim_get_mode().mode
    if mode:match("i") or mode:match("R") then
      -- Skip redecoration in insert/replace mode for large buffers
      return
    end
  end

  if redecorate_timers[buf] then
    redecorate_timers[buf]:stop()
    redecorate_timers[buf]:close()
    redecorate_timers[buf] = nil
  end

  -- Use longer debounce for large buffers
  local debounce = line_count > 1000 and 1000 or 200

  local timer = vim.uv.new_timer()
  redecorate_timers[buf] = timer
  timer:start(debounce, 0, vim.schedule_wrap(function()
    timer:stop()
    timer:close()
    redecorate_timers[buf] = nil
    M.redecorate(buf)
  end))
end

function M.start_spinner(buf, kind)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  M.stop_spinner(buf)

  local frames = SPINNERS[kind] or SPINNERS.generating
  local interval = SPIN_TIMING[kind] or 100
  local frame_idx = 1

  local timer = vim.uv.new_timer()
  spinner_state[buf] = { timer = timer, kind = kind }

  timer:start(0, interval, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      M.stop_spinner(buf)
      return
    end

    -- Check if we should hide spinner
    local should_hide = false
    local line_count = vim.api.nvim_buf_line_count(buf)

    -- Check if @You: is the last role marker (user input phase)
    local last_role_line = nil
    local last_role = nil
    for i = line_count, 1, -1 do
      local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
      if line and line:match("^@%w+:") then
        last_role_line = i
        last_role = line:match("^@(%w+):")
        break
      end
    end

    -- Hide spinner if user is typing (last role is @You:)
    if last_role == "You" then
      should_hide = true
    end

    -- Also hide if cursor is in insert mode on a user message
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      local cursor = vim.api.nvim_win_get_cursor(win)
      local cursor_line = cursor[1]
      local mode = vim.api.nvim_get_mode().mode

      -- Check if cursor is in user message section
      if mode:match("i") then -- insert mode
        -- Find which section cursor is in
        for i = cursor_line, 1, -1 do
          local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
          if line and line:match("^@%w+:") then
            local role = line:match("^@(%w+):")
            if role == "You" then
              should_hide = true
            end
            break
          end
        end
      end
    end

    -- Clear spinner if we should hide it
    if should_hide then
      vim.api.nvim_buf_clear_namespace(buf, NS_SPIN, 0, -1)
      return
    end

    -- Show spinner on last djinni line
    vim.api.nvim_buf_clear_namespace(buf, NS_SPIN, 0, -1)

    local last_line = math.max(0, line_count - 1)

    for i = last_line, 0, -1 do
      local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
      if line and line ~= "" then
        last_line = i
        break
      end
    end

    local frame = frames[frame_idx]
    vim.api.nvim_buf_set_extmark(buf, NS_SPIN, last_line, 0, {
      virt_text = { { " " .. frame .. " ", "ChatSpinner" } },
      virt_text_pos = "eol",
      priority = 60,
    })

    frame_idx = frame_idx % #frames + 1
  end))
end

function M.stop_spinner(buf)
  local state = spinner_state[buf]
  if state then
    if state.timer then
      state.timer:stop()
      state.timer:close()
    end
    spinner_state[buf] = nil
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS_SPIN, 0, -1)
  end
end

function M.show_tokens(buf, usage)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not usage then return end

  vim.api.nvim_buf_clear_namespace(buf, NS_TOKENS, 0, -1)

  local input_tokens = usage.inputTokens or usage.input_tokens or 0
  local output_tokens = usage.outputTokens or usage.output_tokens or 0

  local function fmt(n)
    if n >= 1000 then
      return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
  end

  local text = "In: " .. fmt(input_tokens) .. "  Out: " .. fmt(output_tokens)

  local line_count = vim.api.nvim_buf_line_count(buf)
  local target_line = math.max(0, line_count - 1)

  for i = line_count, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if line and line:match("^@You:") then
      target_line = math.max(0, i - 2)
      break
    end
  end

  vim.api.nvim_buf_set_extmark(buf, NS_TOKENS, target_line, 0, {
    virt_text = { { text, "ChatTokenInfo" } },
    virt_text_pos = "right_align",
    priority = 30,
  })

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, NS_TOKENS, 0, -1)
    end
  end, 10000)
end

function M.foldexpr(lnum)
  -- Validate line number
  if not lnum or lnum < 1 then
    return "="
  end

  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return "="
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  if lnum > line_count then
    return "="
  end

  local lines = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)
  if not lines or #lines == 0 then
    return "="
  end

  local line = lines[1] or ""

  if chat_parser.parse_role_marker(line) then
    return ">1"
  end

  if line:match("^<thinking>") then
    return ">2"
  end

  if line:match("^</thinking>") then
    return "<2"
  end

  if lnum == 1 and line:match("^```") then
    return ">2"
  end

  return "="
end

function M.foldtext()
  local foldstart = vim.v.foldstart
  local foldend = vim.v.foldend

  -- Validate fold bounds
  if not foldstart or not foldend or foldstart < 1 or foldend < foldstart then
    return "..."
  end

  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return "..."
  end

  local line_count = foldend - foldstart + 1

  -- Safely get the fold start line
  local lines = pcall(vim.api.nvim_buf_get_lines, buf, foldstart - 1, foldstart, false)
  local line = ""
  if lines then
    line = lines[1] or ""
  end

  local role = chat_parser.parse_role_marker(line)
  if role then
    local preview_lines = pcall(vim.api.nvim_buf_get_lines, buf, foldstart, foldstart + 1, false)
    local preview_line = ""
    if preview_lines then
      preview_line = preview_lines[1] or ""
    end
    local preview = preview_line:gsub("%s+", " "):sub(1, 72)
    if #preview_line > 72 then
      preview = preview .. "..."
    end
    preview = preview:gsub("\n", "⤶")
    return line .. " " .. preview .. " [" .. line_count .. " lines]"
  end

  if line:match("^<thinking>") then
    return "<thinking> [" .. line_count .. " lines]"
  end

  if line:match("^```") then
    return "frontmatter [" .. line_count .. " lines]"
  end

  return line .. " [" .. line_count .. " lines]"
end

function M.show_tool_spinner(buf, tool_id, line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local state = chat_state.get_buffer_state(buf)

  if not state.tool_indicators then
    state.tool_indicators = {}
  end

  local frames = { "◐", "◓", "◑", "◒" }
  local frame_idx = 1

  local extmark_id = vim.api.nvim_buf_set_extmark(buf, NS_TOOL_STATUS, line - 1, 0, {
    virt_text = { { frames[frame_idx] .. " Executing...", "Comment" } },
    virt_text_pos = "eol",
    priority = 250,
  })

  local timer = vim.uv.new_timer()
  timer:start(0, 100, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      timer:stop()
      timer:close()
      return
    end

    frame_idx = (frame_idx % #frames) + 1
    pcall(vim.api.nvim_buf_set_extmark, buf, NS_TOOL_STATUS, line - 1, 0, {
      id = extmark_id,
      virt_text = { { frames[frame_idx] .. " Executing...", "Comment" } },
      virt_text_pos = "eol",
      priority = 250,
    })
  end))

  state.tool_indicators[tool_id] = {
    extmark_id = extmark_id,
    timer = timer,
    line = line,
  }
end

function M.complete_tool_spinner(buf, tool_id, success)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local state = chat_state.get_buffer_state(buf)
  local indicator = state.tool_indicators and state.tool_indicators[tool_id]

  if not indicator then
    return
  end

  indicator.timer:stop()
  indicator.timer:close()

  local symbol = success and "✓ Complete" or "✗ Failed"
  local hl = success and "DiagnosticOk" or "DiagnosticError"

  pcall(vim.api.nvim_buf_set_extmark, buf, NS_TOOL_STATUS, indicator.line - 1, 0, {
    id = indicator.extmark_id,
    virt_text = { { symbol, hl } },
    virt_text_pos = "eol",
    priority = 250,
  })

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_del_extmark, buf, NS_TOOL_STATUS, indicator.extmark_id)
    end
  end, 2000)

  state.tool_indicators[tool_id] = nil
end

function M.cleanup_tool_spinners(buf)
  local chat_state = require("ai_repl.chat_state")
  local state = chat_state.get_buffer_state(buf)
  if not state.tool_indicators then return end
  for tool_id, indicator in pairs(state.tool_indicators) do
    if indicator.timer then
      indicator.timer:stop()
      indicator.timer:close()
    end
    state.tool_indicators[tool_id] = nil
  end
end

function M.setup_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end

  local line_count = vim.api.nvim_buf_line_count(buf)

  vim.wo[win].foldmethod = "expr"
  vim.wo[win].foldexpr = "v:lua.require'ai_repl.chat_decorations'.foldexpr(v:lnum)"
  vim.wo[win].foldtext = "v:lua.require'ai_repl.chat_decorations'.foldtext()"
  vim.wo[win].foldlevel = 99
  vim.wo[win].signcolumn = "yes:1"

  -- For very large buffers, only do minimal setup
  if line_count > 1000 then
    -- Skip initial redecoration for large buffers
    vim.schedule(function()
      M.redecorate(buf)
    end)
  else
    M.redecorate(buf)
  end

  vim.api.nvim_create_autocmd("TextChanged", {
    buffer = buf,
    callback = function()
      M.schedule_redecorate(buf)
      -- DISABLED: Fold updates on every text change were too expensive
      -- Folds will only update on WinEnter and InsertLeave
    end,
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    callback = function()
      -- DISABLED: Fold updates in insert mode were too expensive
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = buf,
    callback = function()
      -- Update folds when entering window
      update_folds(buf)
    end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = buf,
    callback = function()
      -- Update folds when leaving insert mode (important for large buffers)
      vim.schedule(function()
        update_folds(buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    callback = function()
      M.stop_spinner(buf)
      M.cleanup_tool_spinners(buf)
      if redecorate_timers[buf] then
        redecorate_timers[buf]:stop()
        redecorate_timers[buf]:close()
        redecorate_timers[buf] = nil
      end
    end,
  })
end

-- Export update_folds for external use
M.update_folds = update_folds

return M
