local M = {}

local tool_utils = require("ai_repl.tool_utils")

local NS = vim.api.nvim_create_namespace("ai_repl_render")
local NS_ANIM = vim.api.nvim_create_namespace("ai_repl_anim")
local NS_DIFF = vim.api.nvim_create_namespace("ai_repl_diff")
local NS_PROMPT = vim.api.nvim_create_namespace("ai_repl_prompt")

local PROMPT_MARKER = "$> "

local buffer_state = {}

local SPINNERS = {
  generating = { "|", "/", "-", "\\" },
  thinking = { ".", "..", "..." },
  executing = { "[=  ]", "[ = ]", "[  =]", "[ = ]" },
  compacting = { "◜", "◠", "◝", "◞", "◡", "◟" }
}
local SPIN_TIMING = { generating = 100, thinking = 400, executing = 150, compacting = 120 }

local animation = {
  active = false,
  state = nil,
  timer = nil,
  frame = 1,
  extmark_id = nil,
  idle_timer = nil,
  buf = nil,
}

local function get_state(buf)
  if not buffer_state[buf] then
    buffer_state[buf] = {
      prompt_extmark = nil,
      prompt_line = nil,
    }
  end
  return buffer_state[buf]
end

function M.init_buffer(buf)
  local state = get_state(buf)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = true
  vim.bo[buf].modifiable = true

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })

  M.render_prompt(buf)

  local ok, syntax = pcall(require, "ai_repl.syntax")
  if ok then
    syntax.apply_to_buffer(buf)
  end

  return state
end

function M.render_prompt(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local state = get_state(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  state.prompt_line = line_count

  state.prompt_extmark = vim.api.nvim_buf_set_extmark(buf, NS_PROMPT, line_count - 1, 0, {
    id = state.prompt_extmark,
    virt_text = { { PROMPT_MARKER, "AIReplPrompt" } },
    virt_text_pos = "inline",
    right_gravity = false,
  })
end

function M.cleanup_buffer(buf)
  buffer_state[buf] = nil
  pcall(vim.api.nvim_buf_clear_namespace, buf, NS, 0, -1)
  pcall(vim.api.nvim_buf_clear_namespace, buf, NS_ANIM, 0, -1)
  pcall(vim.api.nvim_buf_clear_namespace, buf, NS_DIFF, 0, -1)
  pcall(vim.api.nvim_buf_clear_namespace, buf, NS_PROMPT, 0, -1)
end

function M.get_prompt_line(buf)
  local state = get_state(buf)
  if state.prompt_extmark then
    local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, buf, NS_PROMPT, state.prompt_extmark, {})
    if ok and pos and #pos >= 1 then
      return pos[1] + 1
    end
  end
  return state.prompt_line or vim.api.nvim_buf_line_count(buf)
end

function M.append_content(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local to_append = {}
  if type(lines) == "string" then
    for line in lines:gmatch("[^\r\n]*") do
      table.insert(to_append, line)
    end
  elseif type(lines) == "table" then
    for _, l in ipairs(lines) do
      if type(l) == "string" then
        for line in l:gmatch("[^\r\n]*") do
          table.insert(to_append, line)
        end
      end
    end
  end

  if #to_append == 0 then return end

  vim.schedule(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true

    local prompt_ln = M.get_prompt_line(buf)
    local insert_at = prompt_ln - 1

    vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, to_append)
    M.render_prompt(buf)
  end)
end

function M.update_streaming(buf, text, process_ui)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  process_ui.streaming_response = process_ui.streaming_response .. text

  vim.schedule(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true

    local prompt_ln = M.get_prompt_line(buf)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local user_input = vim.api.nvim_buf_get_lines(buf, prompt_ln - 1, line_count, false)

    local lines = {}
    for line in process_ui.streaming_response:gmatch("[^\r\n]*") do
      table.insert(lines, line)
    end

    if not process_ui.streaming_start_line then
      local prev_line = ""
      if prompt_ln > 1 then
        prev_line = vim.api.nvim_buf_get_lines(buf, prompt_ln - 2, prompt_ln - 1, false)[1] or ""
      end
      if prev_line == "" then
        process_ui.streaming_start_line = prompt_ln - 1
      else
        vim.api.nvim_buf_set_lines(buf, prompt_ln - 1, prompt_ln - 1, false, { "" })
        process_ui.streaming_start_line = prompt_ln
      end
    end

    table.insert(lines, "")
    for _, input_line in ipairs(user_input) do
      table.insert(lines, input_line)
    end

    vim.api.nvim_buf_set_lines(buf, process_ui.streaming_start_line, -1, false, lines)
    M.render_prompt(buf)
  end)
end

function M.finish_streaming(buf, process_ui)
  process_ui.streaming_response = ""
  process_ui.streaming_start_line = nil
end

function M.get_prompt_input(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return "" end
  local prompt_ln = M.get_prompt_line(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, prompt_ln - 1, line_count, false)
  if #lines == 0 then return "" end
  return table.concat(lines, "\n")
end

function M.clear_prompt_input(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local prompt_ln = M.get_prompt_line(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, prompt_ln - 1, -1, false, { "" })
  M.render_prompt(buf)
end

function M.set_prompt_input(buf, text)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local prompt_ln = M.get_prompt_line(buf)
  vim.bo[buf].modifiable = true

  local lines = {}
  for line in text:gmatch("[^\r\n]*") do
    table.insert(lines, line)
  end
  if #lines == 0 then lines = { "" } end

  vim.api.nvim_buf_set_lines(buf, prompt_ln - 1, -1, false, lines)
  M.render_prompt(buf)
end

local TOOL_DISPLAY = {
  Read = { icon = "📄", name = "Read" },
  Edit = { icon = "✏️", name = "Edit" },
  Write = { icon = "📝", name = "Write" },
  Bash = { icon = "⚡", name = "Run" },
  Glob = { icon = "🔍", name = "Find" },
  Grep = { icon = "🔎", name = "Search" },
  Task = { icon = "🤖", name = "Agent" },
  WebFetch = { icon = "🌐", name = "Fetch" },
  WebSearch = { icon = "🔍", name = "Search Web" },
  TodoWrite = { icon = "📋", name = "Plan" },
  LSP = { icon = "💡", name = "LSP" },
  NotebookEdit = { icon = "📓", name = "Notebook" },
  ExitPlanMode = { icon = "▶️", name = "Execute" },
  EnterPlanMode = { icon = "📝", name = "Plan Mode" },
  AskUserQuestion = { icon = "❓", name = "Question" },
}

local function get_tool_description(tool)
  local input = tool.rawInput or {}
  local title = tool.title or ""
  return tool_utils.get_tool_description(title, input, tool.locations, { path_format = ":t", max_cmd_len = 50 })
end

function M.render_tool(buf, tool)
  if tool.status == "pending" or tool.status == "in_progress" then
    return
  end

  local status = tool_utils.STATUS_ICONS[tool.status] or "○"
  local title = tool.title or tool.kind or "tool"
  local display = TOOL_DISPLAY[title] or { icon = "•", name = title }
  local desc = get_tool_description(tool)

  local line = status .. " " .. display.name
  if desc ~= "" then
    line = line .. ": " .. desc
  end

  M.append_content(buf, { line })
end

function M.render_plan(buf, plan)
  if #plan == 0 then return end
  local lines = { "", "━━━ Plan ━━━" }
  for i, item in ipairs(plan) do
    local icon = tool_utils.STATUS_ICONS[item.status] or "○"
    local pri = item.priority == "high" and "! " or ""
    local text = item.content or item.text or item.activeForm or item.description or tostring(item)
    table.insert(lines, string.format(" %s %d. %s%s", icon, i, pri, text))
  end
  table.insert(lines, "━━━━━━━━━━━━")
  table.insert(lines, "")
  M.append_content(buf, lines)
end

function M.parse_markdown_plan(text)
  local plan = {}
  for line in text:gmatch("[^\r\n]+") do
    local checkbox, content = line:match("^%s*[%-*]%s*%[([%sx ])%]%s*(.+)")
    if checkbox and content then
      local status = "pending"
      if checkbox == "x" or checkbox == "X" then
        status = "completed"
      end
      table.insert(plan, { content = content, status = status })
    else
      local num, content2 = line:match("^%s*(%d+)[%.%)%s]+(.+)")
      if num and content2 and not content2:match("^%s*$") then
        local clean = content2:gsub("^%*%*(.-)%*%*", "%1"):gsub("^__(.-)__", "%1")
        if #clean > 0 and #clean < 200 then
          table.insert(plan, { content = clean, status = "pending" })
        end
      end
    end
  end
  return plan
end

function M.render_diff(buf, file_path, old_content, new_content)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local function compute_diff(old_text, new_text)
    if type(old_text) ~= "string" then old_text = "" end
    if type(new_text) ~= "string" then new_text = "" end
    local old_lines = vim.split(old_text, "\n", { plain = true })
    local new_lines = vim.split(new_text, "\n", { plain = true })
    local result = {}
    local hunks = vim.diff(old_text or "", new_text or "", { result_type = "indices" })
    local old_idx = 1

    for _, hunk in ipairs(hunks or {}) do
      local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]
      while old_idx < old_start do
        table.insert(result, { text = "  " .. (old_lines[old_idx] or ""), hl = nil })
        old_idx = old_idx + 1
      end
      for i = old_start, old_start + old_count - 1 do
        if old_lines[i] then
          table.insert(result, { text = "- " .. old_lines[i], hl = "DiffDelete" })
        end
      end
      old_idx = old_start + old_count
      for i = new_start, new_start + new_count - 1 do
        if new_lines[i] then
          table.insert(result, { text = "+ " .. new_lines[i], hl = "DiffAdd" })
        end
      end
    end
    while old_idx <= #old_lines do
      table.insert(result, { text = "  " .. (old_lines[old_idx] or ""), hl = nil })
      old_idx = old_idx + 1
    end
    return result
  end

  local diff_data = compute_diff(old_content, new_content)
  local lines = { "", "--- " .. vim.fn.fnamemodify(file_path, ":t") .. " ---" }
  for _, d in ipairs(diff_data) do
    table.insert(lines, d.text)
  end
  table.insert(lines, "---")
  table.insert(lines, "")

  vim.schedule(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true

    local prompt_ln = M.get_prompt_line(buf)
    local insert_at = prompt_ln - 1

    vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, lines)

    local diff_start = insert_at + 2
    for i, d in ipairs(diff_data) do
      if d.hl then
        pcall(vim.api.nvim_buf_set_extmark, buf, NS_DIFF, diff_start + i - 1, 0, {
          end_col = #d.text,
          hl_group = d.hl
        })
      end
    end
  end)
end

function M.render_history(buf, messages)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not messages or #messages == 0 then return end

  vim.schedule(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true

    local lines = {}
    for _, msg in ipairs(messages) do
      if msg.role == "user" then
        table.insert(lines, "> " .. msg.content)
        table.insert(lines, "")
      else
        if msg.tool_calls and #msg.tool_calls > 0 then
          for _, tc in ipairs(msg.tool_calls) do
            local status_icon = tc.status == "completed" and "[+]" or (tc.status == "failed" and "[!]" or "[?]")
            local title = tc.title or tc.kind or "tool"
            table.insert(lines, status_icon .. " " .. title)
          end
          table.insert(lines, "")
        end
        if msg.content and msg.content ~= "" then
          for line in msg.content:gmatch("[^\n]+") do
            table.insert(lines, line)
          end
        end
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
      end
    end

    local prompt_ln = M.get_prompt_line(buf)
    vim.api.nvim_buf_set_lines(buf, 0, prompt_ln - 1, false, lines)
  end)
end

local function stop_animation()
  animation.active = false
  animation.state = nil
  if animation.timer then
    pcall(vim.fn.timer_stop, animation.timer)
    animation.timer = nil
  end
  if animation.idle_timer then
    pcall(vim.fn.timer_stop, animation.idle_timer)
    animation.idle_timer = nil
  end
  if animation.extmark_id and animation.buf and vim.api.nvim_buf_is_valid(animation.buf) then
    pcall(vim.api.nvim_buf_del_extmark, animation.buf, NS_ANIM, animation.extmark_id)
    animation.extmark_id = nil
  end
end

local function render_anim_frame()
  if not animation.active or not animation.state then return end
  if not animation.buf or not vim.api.nvim_buf_is_valid(animation.buf) then
    stop_animation()
    return
  end

  local chars = SPINNERS[animation.state] or SPINNERS.generating
  local char = chars[animation.frame] or chars[1]
  animation.frame = (animation.frame % #chars) + 1

  local prompt_ln = M.get_prompt_line(animation.buf)
  local display = " " .. char .. " " .. animation.state .. " "

  animation.extmark_id = vim.api.nvim_buf_set_extmark(animation.buf, NS_ANIM, math.max(0, prompt_ln - 2), 0, {
    id = animation.extmark_id,
    virt_lines = { { { display, "Comment" } } },
    virt_lines_above = false
  })

  local delay = SPIN_TIMING[animation.state] or 100
  animation.timer = vim.fn.timer_start(delay, function()
    vim.schedule(render_anim_frame)
  end)
end

local function reset_idle_timer()
  if animation.idle_timer then
    pcall(vim.fn.timer_stop, animation.idle_timer)
  end
  animation.idle_timer = vim.fn.timer_start(1500, function()
    vim.schedule(stop_animation)
  end)
end

function M.start_animation(buf, anim_state)
  if animation.active and animation.state == anim_state and animation.buf == buf then
    reset_idle_timer()
    return
  end
  stop_animation()
  animation.active = true
  animation.state = anim_state
  animation.buf = buf
  reset_idle_timer()
  animation.frame = 1
  vim.schedule(render_anim_frame)
end

function M.stop_animation()
  stop_animation()
end

function M.setup_cursor_lock(buf)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = buf,
    callback = function()
      local prompt_ln = M.get_prompt_line(buf)
      local win = vim.fn.bufwinid(buf)
      if win == -1 then return end
      local cursor = vim.api.nvim_win_get_cursor(win)
      local row = cursor[1]
      if row < prompt_ln then
        vim.bo[buf].modifiable = false
      else
        vim.bo[buf].modifiable = true
      end
    end
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      local line_count = vim.api.nvim_buf_line_count(buf)
      local state = get_state(buf)
      if line_count == 0 or (state.prompt_extmark and not pcall(vim.api.nvim_buf_get_extmark_by_id, buf, NS_PROMPT, state.prompt_extmark, {})) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            M.render_prompt(buf)
          end
        end)
      end
    end
  })

  vim.keymap.set({ "n", "i" }, "<BS>", function()
    local prompt_ln = M.get_prompt_line(buf)
    local win = vim.fn.bufwinid(buf)
    if win == -1 then return end
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row, col = cursor[1], cursor[2]
    if row == prompt_ln and col == 0 then
      return
    end
    local mode = vim.fn.mode()
    if mode == "i" then
      return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<BS>", true, false, true), "n", false)
    else
      return vim.api.nvim_feedkeys("X", "n", false)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "dd", function()
    local prompt_ln = M.get_prompt_line(buf)
    local win = vim.fn.bufwinid(buf)
    if win == -1 then return end
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = cursor[1]
    local line_count = vim.api.nvim_buf_line_count(buf)
    if row == prompt_ln and line_count == prompt_ln then
      return
    end
    if row >= prompt_ln then
      return vim.api.nvim_feedkeys("dd", "n", false)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "x", function()
    local prompt_ln = M.get_prompt_line(buf)
    local win = vim.fn.bufwinid(buf)
    if win == -1 then return end
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = cursor[1]
    if row >= prompt_ln then
      return vim.api.nvim_feedkeys("x", "n", false)
    end
  end, { buffer = buf, silent = true })
end

function M.goto_prompt(buf, win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local prompt_ln = M.get_prompt_line(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local prompt_line = math.min(prompt_ln, line_count)
  local line = vim.api.nvim_buf_get_lines(buf, prompt_line - 1, prompt_line, false)[1] or ""

  vim.bo[buf].modifiable = true
  vim.api.nvim_win_set_cursor(win, { prompt_line, #line })
  vim.cmd("startinsert!")
end

return M
