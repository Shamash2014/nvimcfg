local M = {}

local chat_parser = require("ai_repl.chat_parser")
local chat_state = require("ai_repl.chat_state")
local cost_mod = require("ai_repl.cost")
local render_mod -- lazy to avoid circular require
local function get_render()
  if not render_mod then render_mod = require("ai_repl.render") end
  return render_mod
end

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

local NS_TOOL_PREVIEW = vim.api.nvim_create_namespace("chat_tool_preview")
local NS_CURSOR_BLEND = vim.api.nvim_create_namespace("chat_cursor_blend")
local NS_ROLE = vim.api.nvim_create_namespace("chat_role")
local NS_RULER = vim.api.nvim_create_namespace("chat_ruler")
local NS_SPIN = vim.api.nvim_create_namespace("chat_spin")
local NS_TOKENS = vim.api.nvim_create_namespace("chat_tokens")
local NS_LINE_HL = vim.api.nvim_create_namespace("chat_line_hl")

local NS_MODEL = vim.api.nvim_create_namespace("chat_model")
local NS_STATUS = vim.api.nvim_create_namespace("chat_status")
local NS_PERM_BLINK = vim.api.nvim_create_namespace("chat_perm_blink")
local NS_DIFF = vim.api.nvim_create_namespace("chat_diff")

local SPINNERS = {
  generating = { "|", "/", "-", "\\" },
  thinking = { "·", "··", "···", "··" },
  executing = { "[=  ]", "[ = ]", "[  =]", "[ = ]" },
}
local SPIN_TIMING = { generating = 200, thinking = 200, executing = 200 }

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

local function safe_close_timer(timer)
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
  end
end

-- Cache for last role detection to avoid scanning entire buffer on every spinner tick
local last_role_cache = {} -- buf -> { last_role = string, line_count = number }
local fold_cache = {} -- buf -> { line_count=N, levels={} }


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

local function highlight_diffs(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, NS_DIFF, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local in_diff = false

  for i, line in ipairs(lines) do
    local lnum = i - 1

    if line:match("^%-%-%-.*%+%d.*%-%d.*%-%-%-$") then
      in_diff = true
      vim.api.nvim_buf_set_extmark(buf, NS_DIFF, lnum, 0, {
        end_col = #line, hl_group = "AIReplDiffHeader", priority = 100,
      })
    elseif in_diff then
      if line:match("^@@ .* @@") then
        vim.api.nvim_buf_set_extmark(buf, NS_DIFF, lnum, 0, {
          end_col = #line, hl_group = "AIReplDiffHunk", priority = 100,
        })
      elseif line:match("^%-%s*%d") then
        vim.api.nvim_buf_set_extmark(buf, NS_DIFF, lnum, 0, {
          end_col = #line, hl_group = "AIReplDiffDelete", priority = 100,
        })
      elseif line:match("^%+%s*%d") then
        vim.api.nvim_buf_set_extmark(buf, NS_DIFF, lnum, 0, {
          end_col = #line, hl_group = "AIReplDiffAdd", priority = 100,
        })
      elseif line:match("^%s+%d+%s") then
        vim.api.nvim_buf_set_extmark(buf, NS_DIFF, lnum, 0, {
          end_col = #line, hl_group = "AIReplDiffContext", priority = 100,
        })
      elseif line == "" or line:match("^%[") or line:match("^@%u") then
        in_diff = false
      end
    end
  end
end

function M.redecorate(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  apply_role_highlights(buf)
  apply_rulers(buf)
  highlight_diffs(buf)
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

  local debounce = line_count > 1000 and 1000 or 200

  local timer = redecorate_timers[buf]
  if timer then
    timer:stop()
  else
    timer = vim.uv.new_timer()
    redecorate_timers[buf] = timer
  end
  timer:start(debounce, 0, vim.schedule_wrap(function()
    timer:stop()
    M.redecorate(buf)
  end))
end

-- Invalidate role cache when buffer content changes
function M.invalidate_role_cache(buf)
  last_role_cache[buf] = nil
  fold_cache[buf] = nil
end

-- Get cached last role, only re-scanning if line count changed
local function get_last_role_cached(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local cached = last_role_cache[buf]
  if cached and cached.line_count == line_count then
    return cached.last_role
  end

  -- Only scan last 50 lines — role markers are always near the end
  local scan_start = math.max(1, line_count - 50)
  local lines = vim.api.nvim_buf_get_lines(buf, scan_start - 1, line_count, false)
  local last_role = nil
  for i = #lines, 1, -1 do
    local role = lines[i] and lines[i]:match("^@(%w+):")
    if role then
      last_role = role
      break
    end
  end

  last_role_cache[buf] = { last_role = last_role, line_count = line_count }
  return last_role
end

function M.start_spinner(buf, kind)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  M.stop_spinner(buf)

  local frames = SPINNERS[kind] or SPINNERS.generating
  local base_interval = SPIN_TIMING[kind] or 100
  local frame_idx = 1

  local active_count = 0
  for _ in pairs(spinner_state) do
    active_count = active_count + 1
  end
  local interval = active_count > 1 and math.max(base_interval, 300) or base_interval

  if get_render().is_streaming() then
    interval = math.max(interval, 500)
  end

  local timer = vim.uv.new_timer()
  spinner_state[buf] = { timer = timer, kind = kind }

  timer:start(0, interval, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      M.stop_spinner(buf)
      return
    end

    local win = vim.fn.bufwinid(buf)
    if win == -1 then
      return
    end

    local last_role = get_last_role_cached(buf)
    if last_role == 'You' then
      vim.api.nvim_buf_clear_namespace(buf, NS_SPIN, 0, -1)
      return
    end

    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = math.max(0, line_count - 1)
    local check_from = math.max(0, last_line - 5)
    for i = last_line, check_from, -1 do
      local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
      if line and line ~= '' then
        last_line = i
        break
      end
    end

    vim.api.nvim_buf_clear_namespace(buf, NS_SPIN, 0, -1)
    local frame = frames[frame_idx]

    local elapsed_str = ""
    local elapsed = chat_state.get_activity_elapsed(buf)
    if elapsed and elapsed >= 1 then
      elapsed_str = " " .. math.floor(elapsed) .. "s"
    end

    local bstate = chat_state.get_buffer_state(buf)
    local tool_info = ""
    if bstate.activity_tool_index > 0 and kind == "executing" then
      tool_info = " | " .. bstate.activity_tool_index .. "/" .. bstate.activity_tool_total
      if bstate.activity_tool_name then
        tool_info = " " .. bstate.activity_tool_name .. tool_info
      end
    end

    vim.api.nvim_buf_set_extmark(buf, NS_SPIN, last_line, 0, {
      virt_text = { { " " .. frame .. elapsed_str .. tool_info .. " ", "ChatSpinner" } },
      virt_text_pos = "eol",
      priority = 60,
    })

    frame_idx = frame_idx % #frames + 1
  end))
end

function M.stop_spinner(buf)
  local state = spinner_state[buf]
  if state then
    safe_close_timer(state.timer)
    spinner_state[buf] = nil
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS_SPIN, 0, -1)
  end
end

function M.show_tokens(buf, usage, session_cost)
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
  if session_cost and session_cost > 0 then
    text = text .. "  " .. (cost_mod.format(session_cost) or "")
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local target_line = math.max(0, line_count - 1)

  local scan_from = math.max(0, line_count - 30)
  local scan_lines = vim.api.nvim_buf_get_lines(buf, scan_from, line_count, false)
  for i = #scan_lines, 1, -1 do
    if scan_lines[i] and scan_lines[i]:match("^@You:") then
      target_line = math.max(0, scan_from + i - 2)
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
  if not lnum or lnum < 1 then return "=" end
  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return "=" end

  local line_count = vim.api.nvim_buf_line_count(buf)
  if lnum > line_count then return "=" end

  local fc = fold_cache[buf]
  if not fc or fc.line_count ~= line_count then
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, line_count, false)
    local levels = {}
    local in_tool_block = false
    local in_frontmatter = false
    for i, line in ipairs(all_lines) do
      if i == 1 and line:match("^```") then
        levels[i] = ">2"
        in_frontmatter = true
      elseif in_frontmatter then
        if line:match("^```") then
          levels[i] = "1"
          in_frontmatter = false
        else
          levels[i] = "2"
        end
      elseif chat_parser.parse_role_marker(line) then
        levels[i] = "="
        in_tool_block = false
      elseif line:match("^<thinking>") then
        levels[i] = ">2"
        in_tool_block = false
      elseif line:match("^</thinking>") then
        levels[i] = "<2"
        in_tool_block = false
      elseif line:match("^%[.%] ") or line:match("^  \xe2\x8e\xbf") then
        if not in_tool_block then
          levels[i] = ">2"
          in_tool_block = true
        else
          levels[i] = "2"
        end
      else
        if in_tool_block then
          if line == "" then
            levels[i] = "2"
          else
            levels[i] = "1"
            in_tool_block = false
          end
        else
          levels[i] = "="
        end
      end
    end
    fold_cache[buf] = { line_count = line_count, levels = levels }
    fc = fold_cache[buf]
  end

  return fc.levels[lnum] or "="
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

  if line:match("^%[.%] ") then
    return "[tools] " .. line_count .. " lines"
  end

  if line:match("^```") then
    return "frontmatter [" .. line_count .. " lines]"
  end

  return line .. " [" .. line_count .. " lines]"
end

function M.cleanup_buffer(buf)
  M.stop_spinner(buf)
  M.stop_permission_blink(buf)
  M.clear_status_line(buf)
  last_role_cache[buf] = nil
  fold_cache[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_clear_namespace, buf, NS_CURSOR_BLEND, 0, -1)
    pcall(vim.api.nvim_buf_clear_namespace, buf, NS_TOOL_PREVIEW, 0, -1)
    pcall(vim.api.nvim_buf_clear_namespace, buf, NS_DIFF, 0, -1)
  end

  safe_close_timer(redecorate_timers[buf])
  redecorate_timers[buf] = nil
end

function M.shutdown()
  for buf, _ in pairs(spinner_state) do
    M.stop_spinner(buf)
  end
  for buf, timer in pairs(redecorate_timers) do
    safe_close_timer(timer)
    redecorate_timers[buf] = nil
  end
  for buf, timer in pairs(status_timers) do
    safe_close_timer(timer)
    status_timers[buf] = nil
  end
  for buf, timer in pairs(perm_blink_timers) do
    safe_close_timer(timer)
    perm_blink_timers[buf] = nil
  end
end

local status_timers = {}

function M.show_status_line(buf, text, timeout)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  timeout = timeout or 3000

  vim.api.nvim_buf_clear_namespace(buf, NS_STATUS, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(buf)
  local last_line = math.max(0, line_count - 1)

  vim.api.nvim_buf_set_extmark(buf, NS_STATUS, last_line, 0, {
    virt_lines = { { { "  " .. text, "Comment" } } },
    virt_lines_above = false,
    priority = 55,
  })

  safe_close_timer(status_timers[buf])

  local timer = vim.uv.new_timer()
  status_timers[buf] = timer
  timer:start(timeout, 0, vim.schedule_wrap(function()
    safe_close_timer(timer)
    status_timers[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, NS_STATUS, 0, -1)
    end
  end))
end

function M.clear_status_line(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, NS_STATUS, 0, -1)
  safe_close_timer(status_timers[buf])
  status_timers[buf] = nil
end

local NS_PLAN_DISCUSS = vim.api.nvim_create_namespace("chat_plan_discuss")

function M.show_plan_discuss_indicator(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, NS_PLAN_DISCUSS, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(buf)
  local scan_start = math.max(0, line_count - 30)
  local lines = vim.api.nvim_buf_get_lines(buf, scan_start, line_count, false)

  for i = #lines, 1, -1 do
    if lines[i]:match("^@You:") then
      vim.api.nvim_buf_set_extmark(buf, NS_PLAN_DISCUSS, scan_start + i - 1, 0, {
        virt_lines_above = true,
        virt_lines = { { { "  📋 Discussing plan — /approve when ready", "Comment" } } },
        priority = 45,
      })
      return
    end
  end
end

function M.clear_plan_discuss_indicator(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, NS_PLAN_DISCUSS, 0, -1)
end

local perm_blink_timers = {}

function M.start_permission_blink(buf, line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  M.stop_permission_blink(buf)

  local on = true
  local blink_count = 0
  local max_blinks = 20
  local timer = vim.uv.new_timer()
  perm_blink_timers[buf] = timer

  timer:start(0, 500, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      M.stop_permission_blink(buf)
      return
    end

    blink_count = blink_count + 1
    if blink_count > max_blinks then
      safe_close_timer(timer)
      perm_blink_timers[buf] = nil
      pcall(vim.api.nvim_buf_set_extmark, buf, NS_PERM_BLINK, math.max(0, line - 1), 0, {
        line_hl_group = "ChatPermissionAlert",
        priority = 200,
      })
      return
    end

    vim.api.nvim_buf_clear_namespace(buf, NS_PERM_BLINK, 0, -1)
    if on then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS_PERM_BLINK, math.max(0, line - 1), 0, {
        line_hl_group = "ChatPermissionAlert",
        priority = 200,
      })
    end
    on = not on
  end))
end

function M.stop_permission_blink(buf)
  safe_close_timer(perm_blink_timers[buf])
  perm_blink_timers[buf] = nil
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS_PERM_BLINK, 0, -1)
  end
end

function M.show_model_info(buf, proc)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not proc then return end

  vim.api.nvim_buf_clear_namespace(buf, NS_MODEL, 0, -1)

  local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
  if not first_line:match("^```") then return end

  local parts = {}

  local provider_id = proc.data.provider or "unknown"
  local providers = require("ai_repl.providers")
  local provider_cfg = providers.get(provider_id) or {}
  local provider_name = provider_cfg.name or provider_id

  local profile_id = proc.data.profile_id
  if profile_id then
    table.insert(parts, provider_name .. ":" .. profile_id)
  else
    table.insert(parts, provider_name)
  end

  local agent_name = proc.state.agent_info and proc.state.agent_info.name
  if agent_name then
    agent_name = agent_name:gsub("^@[^/]+/", "")
    local friendly = { ["claude-code-acp"] = "Claude Code" }
    agent_name = friendly[agent_name] or agent_name
    table.insert(parts, agent_name)
  end

  if proc.state.mode then
    table.insert(parts, proc.state.mode)
  end

  local label = table.concat(parts, " | ")

  if proc.ui and proc.ui.plan_mode then
    label = label .. " | 📋 PLAN"
  end

  if proc.ui and proc.ui.session_cost and proc.ui.session_cost > 0 then
    label = label .. " | " .. (cost_mod.format(proc.ui.session_cost) or "")
  end

  vim.api.nvim_buf_set_extmark(buf, NS_MODEL, 0, 0, {
    virt_text = { { "  " .. label, "Comment" } },
    virt_text_pos = "eol",
    priority = 40,
  })
end

local CURSOR_HL_MAP = {
  user = "ChatCursorLineYou", You = "ChatCursorLineYou", User = "ChatCursorLineYou",
  djinni = "ChatCursorLineDjinni", Djinni = "ChatCursorLineDjinni",
  system = "ChatCursorLineSystem", System = "ChatCursorLineSystem",
}

local function fold_tool_blocks(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end
  local fc = fold_cache[buf]
  if not fc then return end
  pcall(vim.api.nvim_win_call, win, function()
    for i, level in ipairs(fc.levels) do
      if level == ">2" and i > 1 then
        pcall(vim.cmd, i .. "foldclose")
      end
    end
  end)
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
    vim.schedule(function()
      M.redecorate(buf)
      vim.schedule(function() fold_tool_blocks(buf) end)
    end)
  else
    M.redecorate(buf)
    vim.schedule(function() fold_tool_blocks(buf) end)
  end

  vim.api.nvim_create_autocmd("TextChanged", {
    buffer = buf,
    callback = function()
      if get_render().is_streaming() then return end
      M.invalidate_role_cache(buf)
      M.schedule_redecorate(buf)
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

  -- CursorLine blending
  local last_cursor_row = -1
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = buf,
    callback = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      if row == last_cursor_row then return end
      last_cursor_row = row
      vim.api.nvim_buf_clear_namespace(buf, NS_CURSOR_BLEND, 0, -1)
      local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
      local role = chat_parser.parse_role_marker(line)
      local hl = role and CURSOR_HL_MAP[role]
      if hl then
        vim.api.nvim_buf_set_extmark(buf, NS_CURSOR_BLEND, row - 1, 0, {
          line_hl_group = hl,
          priority = 125,
        })
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    callback = function()
      M.cleanup_buffer(buf)
    end,
  })
end

-- Tool inline previews
function M.show_tool_preview(buf, line, preview_lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return nil end
  if not preview_lines or #preview_lines == 0 then return nil end

  local virt_lines = {}
  for _, text in ipairs(preview_lines) do
    table.insert(virt_lines, { { text, "ChatToolPreview" } })
  end

  local ok, mark_id = pcall(vim.api.nvim_buf_set_extmark, buf, NS_TOOL_PREVIEW, line, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
  })
  return ok and mark_id or nil
end

function M.clear_tool_preview(buf, extmark_id)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  pcall(vim.api.nvim_buf_del_extmark, buf, NS_TOOL_PREVIEW, extmark_id)
end

-- Export update_folds for external use
M.update_folds = update_folds

return M
