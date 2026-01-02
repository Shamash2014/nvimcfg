local M = {}

local config = {
  window = {
    width = 0.45,
    border = "rounded",
    title = "AI REPL"
  },
  provider = {
    cmd = "claude-code-acp",
    args = {},
    env = {}
  },
  adapter = "claude",
  history_size = 1000,
  approvals = "ask",  -- "ask" = show when requested, "always" = always prompt, "never" = auto-approve
  show_tool_calls = true,
  debug = false,
  reconnect = true,
  max_reconnect_attempts = 3,
  sessions_file = vim.fn.stdpath("data") .. "/ai_repl_sessions.json",
  max_sessions_per_project = 20
}

local adapters = {}
local function get_adapter()
  if not config.adapter then return nil end
  if not adapters[config.adapter] then
    local ok, adapter = pcall(require, "ai_repl.adapters." .. config.adapter)
    if ok then adapters[config.adapter] = adapter end
  end
  return adapters[config.adapter]
end

local PROMPT_MARKER = "$> "

local prompt = {
  extmark_id = nil,
  line = nil
}

local state = {
  active = false,
  buf = nil,
  win = nil,
  process = nil,
  session_id = nil,
  pending_requests = {},
  message_id = 1,
  current_mode = "plan",
  modes = {},
  sessions = {},
  current_session_id = nil,
  streaming_response = "",
  streaming_start_line = nil,
  agent_info = nil,
  initialized = false,
  slash_commands = {},
  current_plan = {},
  active_tools = {},
  terminals = {},
  sessions_list = {},
  supports_load_session = false,
  project_root = nil,
  source_buf = nil,
  agent_capabilities = {},
  client_capabilities = {},
  reconnect_count = 0,
  pending_files = nil,
  busy = false,
  prompt_queue = {}
}

local SPINNERS = {
  generating = { "|", "/", "-", "\\" },
  thinking = { ".", "..", "..." },
  executing = { "[=  ]", "[ = ]", "[  =]", "[ = ]" }
}
local SPIN_TIMING = { generating = 100, thinking = 400, executing = 150 }
local NS_ANIM = vim.api.nvim_create_namespace("ai_repl_anim")
local NS_DIFF = vim.api.nvim_create_namespace("ai_repl_diff")
local NS_PROMPT = vim.api.nvim_create_namespace("ai_repl_prompt")

local animation = {
  active = false,
  anim_state = nil,
  timer = nil,
  frame = 1,
  extmark_id = nil,
  idle_timer = nil
}

local function stop_animation()
  animation.active = false
  animation.anim_state = nil
  if animation.timer then
    pcall(vim.fn.timer_stop, animation.timer)
    animation.timer = nil
  end
  if animation.idle_timer then
    pcall(vim.fn.timer_stop, animation.idle_timer)
    animation.idle_timer = nil
  end
  if animation.extmark_id and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_del_extmark, state.buf, NS_ANIM, animation.extmark_id)
    animation.extmark_id = nil
  end
end

local function render_anim_frame()
  if not animation.active or not animation.anim_state then return end
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    stop_animation()
    return
  end
  local chars = SPINNERS[animation.anim_state] or SPINNERS.generating
  local char = chars[animation.frame] or chars[1]
  animation.frame = (animation.frame % #chars) + 1
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  local display = " " .. char .. " " .. animation.anim_state .. " "
  animation.extmark_id = vim.api.nvim_buf_set_extmark(state.buf, NS_ANIM, math.max(0, line_count - 2), 0, {
    id = animation.extmark_id,
    virt_lines = { { { display, "Comment" } } },
    virt_lines_above = false
  })
  local delay = SPIN_TIMING[animation.anim_state] or 100
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

local function start_animation(anim_state)
  if animation.active and animation.anim_state == anim_state then
    reset_idle_timer()
    return
  end
  stop_animation()
  animation.active = true
  animation.anim_state = anim_state
  reset_idle_timer()
  animation.frame = 1
  vim.schedule(render_anim_frame)
end

local function render_prompt()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  prompt.line = line_count
  prompt.extmark_id = vim.api.nvim_buf_set_extmark(state.buf, NS_PROMPT, line_count - 1, 0, {
    id = prompt.extmark_id,
    virt_text = { { PROMPT_MARKER, "AIReplPrompt" } },
    virt_text_pos = "inline",
    right_gravity = false
  })
end

local function get_prompt_line()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return nil end
  if prompt.extmark_id then
    local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, state.buf, NS_PROMPT, prompt.extmark_id, {})
    if ok and pos and #pos >= 1 then
      return pos[1] + 1
    end
  end
  return prompt.line or vim.api.nvim_buf_line_count(state.buf)
end

local function json_encode(obj)
  return vim.json.encode(obj)
end

local function json_decode(str)
  local ok, result = pcall(vim.json.decode, str)
  if ok then return result end
  return nil
end

local function get_project_root(buf)
  local file = buf and vim.api.nvim_buf_get_name(buf) or vim.api.nvim_buf_get_name(0)
  local dir = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]
  if vim.v.shell_error == 0 and git_root and git_root ~= "" then
    return git_root
  end
  return dir
end

local function get_current_project_root()
  if state.project_root then
    return state.project_root
  end
  return get_project_root(state.source_buf)
end

local function get_system_context()
  local root = get_current_project_root()
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(root) .. " rev-parse --show-toplevel 2>/dev/null")[1]
  local is_git = vim.v.shell_error == 0
  return {
    os = vim.loop.os_uname().sysname,
    shell = vim.env.SHELL or "unknown",
    date = os.date("%Y-%m-%d"),
    cwd = root,
    git_root = is_git and git_root or nil,
    nvim_version = vim.version().major .. "." .. vim.version().minor
  }
end

local function load_sessions_from_disk()
  local f = io.open(config.sessions_file, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local data = json_decode(content)
  return data and data.sessions or {}
end

local function save_sessions_to_disk(sessions)
  local f = io.open(config.sessions_file, "w")
  if not f then return end
  f:write(json_encode({ sessions = sessions }))
  f:close()
end

local function get_project_name(cwd)
  return vim.fn.fnamemodify(cwd, ":t")
end

local function format_session_name(cwd, timestamp)
  local project = get_project_name(cwd)
  local date = os.date("%Y-%m-%d %H:%M", timestamp)
  return project .. " @ " .. date
end

local function add_session_to_disk(session_id, cwd)
  local sessions = load_sessions_from_disk()
  local now = os.time()
  for _, s in ipairs(sessions) do
    if s.id == session_id then
      s.last_used = now
      save_sessions_to_disk(sessions)
      return
    end
  end
  table.insert(sessions, 1, {
    id = session_id,
    cwd = cwd,
    name = format_session_name(cwd, now),
    created_at = now,
    last_used = now
  })
  local by_project = {}
  local kept = {}
  for _, s in ipairs(sessions) do
    by_project[s.cwd] = (by_project[s.cwd] or 0) + 1
    if by_project[s.cwd] <= config.max_sessions_per_project then
      table.insert(kept, s)
    end
  end
  save_sessions_to_disk(kept)
end

local function get_sessions_for_project(cwd)
  local sessions = load_sessions_from_disk()
  local result = {}
  for _, s in ipairs(sessions) do
    if s.cwd == cwd then
      table.insert(result, s)
    end
  end
  return result
end

local function append_to_buffer(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
    vim.bo[state.buf].modifiable = true
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
    if #to_append > 0 then
      local prompt_ln = get_prompt_line()
      local insert_at = prompt_ln and (prompt_ln - 1) or vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_buf_set_lines(state.buf, insert_at, insert_at, false, to_append)
      render_prompt()
    end
  end)
end

local function clear_buffer()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "" })
    render_prompt()
  end)
end

local function render_session_history(messages)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  if not messages or #messages == 0 then return end
  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
    vim.bo[state.buf].modifiable = true
    local lines = {}
    for _, msg in ipairs(messages) do
      if msg.role == "user" then
        table.insert(lines, "> " .. msg.content)
        table.insert(lines, "")
      else
        for line in msg.content:gmatch("[^\n]+") do
          table.insert(lines, line)
        end
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
      end
    end
    table.insert(lines, "")
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    render_prompt()
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_cursor(state.win, { line_count, 0 })
    end
  end)
end

local function send_jsonrpc(method, params, is_notification)
  if not state.process then return nil end
  local msg = {
    jsonrpc = "2.0",
    method = method,
    params = params or {}
  }
  if not is_notification then
    msg.id = state.message_id
    state.message_id = state.message_id + 1
  end
  local encoded = json_encode(msg) .. "\n"
  vim.fn.chansend(state.process, encoded)
  return msg.id
end

local function render_plan()
  if #state.current_plan == 0 then return end
  local lines = { "", "Plan:" }
  for _, item in ipairs(state.current_plan) do
    local icons = { pending = "[ ]", in_progress = "[>]", completed = "[x]" }
    local icon = icons[item.status] or "[ ]"
    local pri = item.priority == "high" and "!" or ""
    local text = item.content or item.text or item.activeForm or item.description or tostring(item)
    table.insert(lines, pri .. icon .. " " .. text)
  end
  table.insert(lines, "")
  append_to_buffer(lines)
end

local pending_tool_render = nil

local function flush_pending_tools()
  if not pending_tool_render then return end
  local tools = {}
  for _, tool in pairs(state.active_tools) do
    if tool.status == "pending" or tool.status == "in_progress" then
      table.insert(tools, tool)
    end
  end
  if #tools > 0 then
    local names = {}
    for _, t in ipairs(tools) do
      table.insert(names, t.title or t.kind or "tool")
    end
    append_to_buffer({ "... " .. table.concat(names, ", ") })
  end
  pending_tool_render = nil
end

local function render_tool(tool, immediate)
  local icons = { pending = "[~]", in_progress = "[>]", completed = "[+]", failed = "[!]" }
  local kind_short = { read = "R", edit = "E", delete = "D", search = "S", execute = "X", think = "T", fetch = "F" }
  if tool.status == "pending" or tool.status == "in_progress" then
    if not immediate then
      if pending_tool_render then
        vim.fn.timer_stop(pending_tool_render)
      end
      pending_tool_render = vim.fn.timer_start(100, function()
        vim.schedule(flush_pending_tools)
      end)
    end
    return
  end
  local s = icons[tool.status] or "[?]"
  local k = kind_short[tool.kind] or "-"
  local title = tool.title or tool.kind or "tool"
  local loc = ""
  if tool.locations and #tool.locations > 0 then
    local l = tool.locations[1]
    loc = " -> " .. (l.path or l.uri or "")
    if l.line then loc = loc .. ":" .. l.line end
  end
  append_to_buffer({ s .. " " .. k .. " " .. title .. loc })
end

local function update_streaming_response(text)
  state.streaming_response = state.streaming_response .. text
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
    vim.bo[state.buf].modifiable = true
    local lines = {}
    for line in state.streaming_response:gmatch("[^\r\n]*") do
      table.insert(lines, line)
    end
    local prompt_ln = get_prompt_line()
    if not state.streaming_start_line then
      if prompt_ln then
        local prev_line = vim.api.nvim_buf_get_lines(state.buf, prompt_ln - 2, prompt_ln - 1, false)[1] or ""
        if prev_line == "" then
          state.streaming_start_line = prompt_ln - 1
        else
          vim.api.nvim_buf_set_lines(state.buf, prompt_ln - 1, prompt_ln - 1, false, { "" })
          state.streaming_start_line = prompt_ln
        end
      else
        state.streaming_start_line = vim.api.nvim_buf_line_count(state.buf)
      end
    end
    table.insert(lines, "")
    vim.api.nvim_buf_set_lines(state.buf, state.streaming_start_line, -1, false, lines)
    render_prompt()
  end)
end

local function handle_session_update(params)
  local u = params.update
  if not u then return end
  local update_type = u.sessionUpdate
  if config.debug and update_type ~= "agent_message_chunk" then
    append_to_buffer({ "[debug] " .. (update_type or "unknown") })
  end
  if update_type == "agent_message_chunk" then
    start_animation("generating")
    local content = u.content
    if content and content.text then
      update_streaming_response(content.text)
    end
  elseif update_type == "tool_call" then
    local tool = { id = u.toolCallId, title = u.title, kind = u.kind, status = u.status or "pending", locations = u.locations, rawInput = u.rawInput, content = u.content }
    state.active_tools[u.toolCallId] = tool
    if u.title == "TodoWrite" and u.rawInput and u.rawInput.todos then
      state.current_plan = u.rawInput.todos
      render_plan()
      return
    elseif u.title == "ExitPlanMode" then
      append_to_buffer({ "[>] Exiting plan mode..." })
      return
    elseif u.title == "AskUserQuestion" or (u.rawInput and u.rawInput.questions) then
      stop_animation()
      local questions = u.rawInput and u.rawInput.questions or {}
      for _, q in ipairs(questions) do
        append_to_buffer({ "", "[?] " .. (q.question or "Question") })
        if q.options then
          for i, opt in ipairs(q.options) do
            append_to_buffer({ "  " .. i .. ". " .. (opt.label or opt) })
          end
        end
      end
      if #questions > 0 then
        vim.schedule(function()
          local q = questions[1]
          if q.options and #q.options > 0 then
            local labels = {}
            for _, opt in ipairs(q.options) do
              table.insert(labels, opt.label or opt)
            end
            vim.ui.select(labels, { prompt = q.question or "Select:" }, function(choice)
              if choice then
                M.send_prompt(choice)
              end
            end)
          else
            vim.ui.input({ prompt = (q.question or "Answer") .. ": " }, function(input)
              if input and input ~= "" then
                M.send_prompt(input)
              end
            end)
          end
        end)
      end
    elseif u.rawInput and u.rawInput.question then
      stop_animation()
      append_to_buffer({ "", "[?] " .. u.rawInput.question })
      vim.schedule(function()
        vim.ui.input({ prompt = u.rawInput.question .. ": " }, function(input)
          if input and input ~= "" then
            M.send_prompt(input)
          end
        end)
      end)
    else
      start_animation("executing")
      render_tool(tool)
    end
  elseif update_type == "tool_call_update" then
    local tool = state.active_tools[u.toolCallId] or {}
    tool.status = u.status or tool.status
    tool.title = u.title or tool.title
    tool.locations = u.locations or tool.locations
    tool.content = u.content or tool.content
    tool.rawOutput = u.rawOutput or tool.rawOutput
    state.active_tools[u.toolCallId] = tool
    if u.status == "completed" or u.status == "failed" then
      stop_animation()
      if tool.title ~= "AskUserQuestion" then
        render_tool(tool)
      end
      if u.status == "completed" and (tool.kind == "edit" or tool.kind == "write" or tool.title == "Edit" or tool.title == "Write") then
        local file_path = nil
        local old_text = nil
        local new_text = nil
        if tool.content and type(tool.content) == "table" then
          for _, block in ipairs(tool.content) do
            if block.type == "diff" then
              file_path = block.path
              old_text = block.oldText
              new_text = block.newText
              break
            end
          end
        end
        if not file_path and tool.rawInput then
          file_path = tool.rawInput.file_path or tool.rawInput.path
          old_text = tool.rawInput.old_string
          new_text = tool.rawInput.new_string
        end
        if not file_path and tool.locations and #tool.locations > 0 then
          file_path = tool.locations[1].path or tool.locations[1].uri
        end
        if file_path and (old_text or new_text) then
          render_inline_diff(file_path, old_text or "", new_text or "")
        end
      end
      if tool.title == "ExitPlanMode" and u.status == "completed" then
        append_to_buffer({ "[>] Starting execution..." })
        vim.defer_fn(function()
          M.send_prompt("proceed with the plan", { silent = true })
        end, 200)
      end
      state.active_tools[u.toolCallId] = nil
    end
  elseif update_type == "plan" then
    state.current_plan = u.entries or u.plan or {}
    if type(state.current_plan) == "table" and state.current_plan.entries then
      state.current_plan = state.current_plan.entries
    end
    if #state.current_plan == 0 then
      append_to_buffer({ "[plan update received but empty]" })
    end
    render_plan()
  elseif update_type == "available_commands_update" then
    state.slash_commands = u.availableCommands or {}
  elseif update_type == "stop" then
    stop_animation()
    state.busy = false
    if state.busy_timer then
      pcall(vim.fn.timer_stop, state.busy_timer)
      state.busy_timer = nil
    end
    state.current_plan = {}
    state.active_tools = {}
    state.streaming_response = ""
    state.streaming_start_line = nil
    local reason = u.stopReason or "end_turn"
    local reason_msgs = {
      end_turn = "---",
      max_tokens = "[!] Stopped: token limit",
      max_turn_requests = "[!] Stopped: turn limit",
      refusal = "[!] Agent refused",
      cancelled = "[x] Cancelled"
    }
    local mode_str = state.current_mode and (" [" .. state.current_mode .. "]") or ""
    append_to_buffer({ "", (reason_msgs[reason] or "---") .. mode_str, "" })
    vim.defer_fn(function()
      if #state.prompt_queue > 0 and not state.busy then
        local next_item = table.remove(state.prompt_queue, 1)
        if next_item then
          M.send_prompt(next_item.content, next_item.opts)
        end
      end
    end, 200)
  elseif update_type == "modes" then
    state.modes = u.modes or {}
    state.current_mode = u.currentModeId
  elseif update_type == "agent_thought_chunk" then
    start_animation("thinking")
    local content = u.content
    if content and content.text then
      append_to_buffer({ "[...] " .. content.text:sub(1, 100) })
    end
  else
    if config.debug and update_type then
      append_to_buffer({ "[debug] unknown update: " .. update_type })
    end
  end
end

local function compute_inline_diff(old_text, new_text)
  if type(old_text) ~= "string" then old_text = "" end
  if type(new_text) ~= "string" then new_text = "" end
  local old_lines = vim.split(old_text, "\n", { plain = true })
  local new_lines = vim.split(new_text, "\n", { plain = true })
  local result = {}
  local on = vim.diff(old_text or "", new_text or "", { result_type = "indices" })
  local old_idx, new_idx = 1, 1
  for _, hunk in ipairs(on or {}) do
    local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]
    while old_idx < old_start do
      table.insert(result, { text = "  " .. (old_lines[old_idx] or ""), hl = nil })
      old_idx = old_idx + 1
      new_idx = new_idx + 1
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
    new_idx = new_start + new_count
  end
  while old_idx <= #old_lines do
    table.insert(result, { text = "  " .. (old_lines[old_idx] or ""), hl = nil })
    old_idx = old_idx + 1
  end
  return result
end

render_inline_diff = function(file_path, old_content, new_content)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local diff_data = compute_inline_diff(old_content, new_content)
  local lines = { "", "--- " .. vim.fn.fnamemodify(file_path, ":t") .. " ---" }
  for _, d in ipairs(diff_data) do
    table.insert(lines, d.text)
  end
  table.insert(lines, "---")
  table.insert(lines, "")

  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
    vim.bo[state.buf].modifiable = true
    local prompt_ln = get_prompt_line()
    local insert_at = prompt_ln and (prompt_ln - 1) or vim.api.nvim_buf_line_count(state.buf)

    vim.api.nvim_buf_set_lines(state.buf, insert_at, insert_at, false, lines)
    render_prompt()

    local diff_start = insert_at + 2
    for i, d in ipairs(diff_data) do
      if d.hl then
        pcall(vim.api.nvim_buf_set_extmark, state.buf, NS_DIFF, diff_start + i - 1, 0, {
          end_col = #d.text,
          hl_group = d.hl
        })
      end
    end
  end)
end

local function handle_permission_request(id, params)
  stop_animation()
  vim.schedule(function()
    local tool = params.toolCall or {}
    local title = tool.title or tool.kind or "Unknown tool"
    local kind = tool.kind or ""
    local locations = tool.locations or {}
    local loc_str = ""
    if #locations > 0 then
      local l = locations[1]
      loc_str = " -> " .. (l.path or l.uri or "")
      if l.line then loc_str = loc_str .. ":" .. l.line end
    end
    local raw_input = tool.rawInput or {}

    local agent_options = params.options or {}
    local first_allow_id = nil
    for _, opt in ipairs(agent_options) do
      local oid = opt.optionId or opt.id
      local okind = opt.kind or ""
      if oid and (okind:match("allow") or oid:match("allow") or oid:match("yes") or oid:match("approve")) then
        first_allow_id = oid
        break
      end
    end
    if not first_allow_id and #agent_options > 0 then
      first_allow_id = agent_options[1].optionId or agent_options[1].id
    end

    if config.approvals == "never" then
      local opt_id = first_allow_id or "allow_always"
      local response = { jsonrpc = "2.0", id = id, result = { outcome = { outcome = "selected", optionId = opt_id } } }
      if config.show_tool_calls then
        append_to_buffer({ "[+] Auto-approved: " .. title .. loc_str })
      end
      vim.fn.chansend(state.process, json_encode(response) .. "\n")
      return
    end

    if config.show_tool_calls then
      local prompt_lines = { "[*] " .. title .. loc_str }
      if kind == "edit" or kind == "write" then
        local file_path = raw_input.file_path or raw_input.path or (locations[1] and locations[1].path)
        if file_path and raw_input.new_string then
          table.insert(prompt_lines, "  Old: " .. (raw_input.old_string or ""):sub(1, 50))
          table.insert(prompt_lines, "  New: " .. (raw_input.new_string or ""):sub(1, 50))
        end
      elseif kind == "execute" or kind == "bash" then
        if raw_input.command then
          table.insert(prompt_lines, "  $ " .. raw_input.command:sub(1, 80))
        end
      end
      for _, line in ipairs(prompt_lines) do
        append_to_buffer({ line })
      end
    end

    local options = {}
    local option_ids = {}
    for i, opt in ipairs(agent_options) do
      options[i] = opt.name or opt.label or opt.optionId or opt.id
      option_ids[i] = opt.optionId or opt.id
    end
    if #options == 0 then
      options = { "Allow once", "Allow always", "Reject" }
      option_ids = { "allow_once", "allow_always", "reject" }
    end

    local file_path = raw_input.file_path or raw_input.path or (locations[1] and locations[1].path)
    local can_show_diff = (kind == "edit" or kind == "write") and file_path and raw_input.new_string
    if can_show_diff then
      table.insert(options, 1, "View diff")
      table.insert(option_ids, 1, "__view_diff__")
    end

    local function show_picker()
      vim.ui.select(options, {
        prompt = title,
      }, function(choice, idx)
        if choice == nil then
          local response = { jsonrpc = "2.0", id = id, result = { outcome = { outcome = "cancelled" } } }
          append_to_buffer({ "[x] Cancelled" })
          vim.fn.chansend(state.process, json_encode(response) .. "\n")
          return
        end
        local opt_id = option_ids[idx] or "allow_once"
        if opt_id == "__view_diff__" then
          local old_content = raw_input.old_string or ""
          local new_content = raw_input.new_string or ""
          if raw_input.old_string and raw_input.new_string then
            if vim.fn.filereadable(file_path) == 1 then
              local f = io.open(file_path, "r")
              if f then
                local full_content = f:read("*a")
                f:close()
                old_content = full_content
                new_content = full_content:gsub(vim.pesc(raw_input.old_string), raw_input.new_string, 1)
              end
            else
              old_content = raw_input.old_string
              new_content = raw_input.new_string
            end
          end
          render_inline_diff(file_path, old_content, new_content)
          vim.schedule(show_picker)
          return
        end
        local response = { jsonrpc = "2.0", id = id, result = { outcome = { outcome = "selected", optionId = opt_id } } }
        vim.fn.chansend(state.process, json_encode(response) .. "\n")
      end)
    end

    show_picker()
  end)
end

local function handle_terminal_create(id, params)
  local cmd = params.command
  local args = params.args or {}
  local cwd = params.cwd or get_current_project_root()
  if not cmd or type(cmd) ~= "string" or cmd == "" then
    local response = { jsonrpc = "2.0", id = id, error = { code = -32602, message = "Invalid command" } }
    vim.fn.chansend(state.process, json_encode(response) .. "\n")
    return
  end
  local env = nil
  if params.env and type(params.env) == "table" and #params.env > 0 then
    env = {}
    for _, e in ipairs(params.env) do
      if type(e) == "table" and e.name and e.value then
        env[e.name] = e.value
      end
    end
  end
  local term_id = "term_" .. os.time() .. math.random(1000, 9999)
  local full_cmd = { cmd }
  if type(args) == "table" then
    for _, arg in ipairs(args) do
      if type(arg) == "string" then
        table.insert(full_cmd, arg)
      end
    end
  end
  local output = {}
  local job_opts = {
    cwd = cwd,
    on_stdout = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then table.insert(output, line) end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then table.insert(output, line) end
      end
    end,
    on_exit = function(_, code)
      if state.terminals[term_id] then
        state.terminals[term_id].exit_code = code
      end
    end
  }
  if env and next(env) then
    job_opts.env = env
  end
  local ok, job_id = pcall(vim.fn.jobstart, full_cmd, job_opts)
  if not ok or job_id <= 0 then
    local response = { jsonrpc = "2.0", id = id, error = { code = -32000, message = "Failed to start: " .. cmd } }
    vim.fn.chansend(state.process, json_encode(response) .. "\n")
    return
  end
  state.terminals[term_id] = { job_id = job_id, output = output, exit_code = nil }
  local response = { jsonrpc = "2.0", id = id, result = { terminalId = term_id } }
  vim.fn.chansend(state.process, json_encode(response) .. "\n")
end

local function handle_terminal_output(id, params)
  local term = state.terminals[params.terminalId]
  local response = { jsonrpc = "2.0", id = id }
  if term then
    response.result = {
      output = table.concat(term.output, "\n"),
      truncated = false,
      exitStatus = term.exit_code and { exitCode = term.exit_code } or vim.NIL
    }
  else
    response.error = { code = -32000, message = "Terminal not found" }
  end
  vim.fn.chansend(state.process, json_encode(response) .. "\n")
end

local function handle_terminal_wait(id, params)
  local term = state.terminals[params.terminalId]
  if not term then
    local response = { jsonrpc = "2.0", id = id, error = { code = -32000, message = "Terminal not found" } }
    vim.fn.chansend(state.process, json_encode(response) .. "\n")
    return
  end
  local function check()
    if term.exit_code ~= nil then
      local response = { jsonrpc = "2.0", id = id, result = { exitCode = term.exit_code } }
      vim.fn.chansend(state.process, json_encode(response) .. "\n")
    else
      vim.defer_fn(check, 100)
    end
  end
  check()
end

local function handle_terminal_kill(id, params)
  local term = state.terminals[params.terminalId]
  local response = { jsonrpc = "2.0", id = id }
  if term and term.job_id then
    vim.fn.jobstop(term.job_id)
    response.result = vim.NIL
  else
    response.error = { code = -32000, message = "Terminal not found" }
  end
  vim.fn.chansend(state.process, json_encode(response) .. "\n")
end

local function handle_terminal_release(id, params)
  local term = state.terminals[params.terminalId]
  local response = { jsonrpc = "2.0", id = id }
  if term then
    if term.job_id then pcall(vim.fn.jobstop, term.job_id) end
    state.terminals[params.terminalId] = nil
    response.result = vim.NIL
  else
    response.error = { code = -32000, message = "Terminal not found" }
  end
  vim.fn.chansend(state.process, json_encode(response) .. "\n")
end

local function handle_message(line)
  local msg = json_decode(line)
  if not msg then return end
  if config.debug and msg.method then
    local method_short = msg.method:gsub("session/", "")
    if method_short ~= "update" or (msg.params and msg.params.update and msg.params.update.sessionUpdate ~= "agent_message_chunk") then
      append_to_buffer({ "[debug] method: " .. method_short })
    end
  end
  if msg.method then
    if msg.method == "session/update" then
      handle_session_update(msg.params)
    elseif msg.method == "session/request_permission" then
      handle_permission_request(msg.id, msg.params)
    elseif msg.method == "terminal/create" then
      handle_terminal_create(msg.id, msg.params)
    elseif msg.method == "terminal/output" then
      handle_terminal_output(msg.id, msg.params)
    elseif msg.method == "terminal/wait_for_exit" then
      handle_terminal_wait(msg.id, msg.params)
    elseif msg.method == "terminal/kill" then
      handle_terminal_kill(msg.id, msg.params)
    elseif msg.method == "terminal/release" then
      handle_terminal_release(msg.id, msg.params)
    end
  elseif msg.id then
    local pending = state.pending_requests[msg.id]
    if pending and pending.callback and msg.result then
      local ok, err = pcall(pending.callback, msg.result)
      if not ok then
        append_to_buffer({ "Callback error: " .. tostring(err) })
      end
    end
    state.pending_requests[msg.id] = nil
    if msg.result then
      if msg.result.sessionId then
        state.session_id = msg.result.sessionId
      end
    end
    if msg.error then
      stop_animation()
      append_to_buffer({ "Error: " .. (msg.error.message or "Unknown error") })
    end
  end
end

local function start_process()
  local cmd = config.provider.cmd
  local args = vim.deepcopy(config.provider.args)
  state.process = vim.fn.jobstart({ cmd, unpack(args) }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data or {}) do
        if line and line ~= "" then
          handle_message(line)
        end
      end
    end,
    on_stderr = function(_, data)
      if not config.debug then return end
      for _, line in ipairs(data or {}) do
        if line and line ~= "" then
          if not line:match("^%s*$") and not line:match("Session not found") then
            append_to_buffer({ "[debug] " .. line })
          end
        end
      end
    end,
    on_exit = function(_, code)
      stop_animation()
      state.process = nil
      state.initialized = false
      state.session_id = nil
      if code ~= 0 then
        append_to_buffer({ "Process exited with code: " .. code })
        if config.reconnect and state.active and state.reconnect_count < config.max_reconnect_attempts then
          state.reconnect_count = state.reconnect_count + 1
          append_to_buffer({ "Reconnecting... (" .. state.reconnect_count .. "/" .. config.max_reconnect_attempts .. ")" })
          vim.defer_fn(function()
            if state.active and start_process() then
              vim.defer_fn(initialize, 100)
            end
          end, 1000)
        end
      else
        state.reconnect_count = 0
      end
    end,
    stdin = "pipe"
  })
  if state.process <= 0 then
    state.process = nil
    return false
  end
  return true
end

local function stop_process()
  if state.process then
    vim.fn.jobstop(state.process)
    state.process = nil
  end
  state.initialized = false
  state.session_id = nil
end

local create_session
local render_inline_diff

local function get_mime_type(path)
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  local mime_types = {
    lua = "text/x-lua", py = "text/x-python", js = "text/javascript",
    ts = "text/typescript", tsx = "text/typescript", jsx = "text/javascript",
    json = "application/json", md = "text/markdown", txt = "text/plain",
    html = "text/html", css = "text/css", sh = "text/x-shellscript",
    rs = "text/x-rust", go = "text/x-go", rb = "text/x-ruby",
    java = "text/x-java", c = "text/x-c", cpp = "text/x-c++",
    h = "text/x-c", hpp = "text/x-c++", yaml = "text/yaml", yml = "text/yaml",
    toml = "text/toml", xml = "text/xml", sql = "text/x-sql",
    ex = "text/x-elixir", exs = "text/x-elixir", erl = "text/x-erlang",
  }
  return mime_types[ext] or "text/plain"
end

local function create_resource_content(path, text, annotations)
  local abs_path = vim.fn.fnamemodify(path, ":p")
  return {
    type = "resource",
    resource = {
      uri = "file://" .. abs_path,
      text = text,
      mimeType = get_mime_type(path)
    },
    annotations = annotations
  }
end

local function create_resource_link(path, annotations)
  local abs_path = vim.fn.fnamemodify(path, ":p")
  local name = vim.fn.fnamemodify(path, ":t")
  return {
    type = "resource_link",
    uri = "file://" .. abs_path,
    name = name,
    mimeType = get_mime_type(path),
    annotations = annotations
  }
end

local function create_text_content(text)
  return { type = "text", text = text }
end

local function initialize()
  if not state.process then return end
  state.client_capabilities = {
    prompt = { text = true, embeddedContext = true, image = false, audio = false }
  }
  local id = send_jsonrpc("initialize", {
    protocolVersion = 1,
    clientInfo = {
      name = "ai_repl.nvim",
      title = "AI REPL for Neovim",
      version = "1.0.0"
    },
    clientCapabilities = state.client_capabilities
  })
  state.pending_requests[id] = {
    method = "initialize",
    callback = function(result)
      state.agent_info = result.agentInfo
      state.agent_capabilities = result.agentCapabilities or {}
      state.initialized = true
      if state.agent_capabilities.loadSession then
        state.supports_load_session = true
      end
      local caps = {}
      if state.agent_capabilities.loadSession then table.insert(caps, "sessions") end
      if state.agent_capabilities.modes then table.insert(caps, "modes") end
      if state.agent_capabilities.plans then table.insert(caps, "plans") end
      local agent_name = result.agentInfo and result.agentInfo.name or "Agent"
      local caps_str = #caps > 0 and " [" .. table.concat(caps, ", ") .. "]" or ""
      append_to_buffer({ "Connected: " .. agent_name .. caps_str })
      create_session()
    end
  }
end

create_session = function()
  if not state.process or not state.initialized then return end
  local root = get_current_project_root()
  local id = send_jsonrpc("session/new", {
    cwd = root,
    mcpServers = {}
  })
  append_to_buffer({ "Project: " .. root })
  state.pending_requests[id] = {
    method = "session/new",
    callback = function(result)
      state.session_id = result.sessionId
      add_session_to_disk(result.sessionId, root)
      append_to_buffer({ "Session: " .. result.sessionId:sub(1, 8) .. "..." })
      if result.modes then
        state.modes = result.modes.availableModes or {}
        state.current_mode = result.modes.currentModeId
      end
      if state.is_first_open then
        state.is_first_open = false
        vim.defer_fn(function()
          M.set_mode("plan")
        end, 100)
      else
        append_to_buffer({ "Mode: " .. (state.current_mode or "default") })
      end
    end
  }
end

local function process_prompt_queue()
  if #state.prompt_queue == 0 then return end
  if state.busy then return end
  local next_item = table.remove(state.prompt_queue, 1)
  if next_item then
    M.send_prompt(next_item.content, next_item.opts)
  end
end

function M.send_prompt(content, opts)
  opts = opts or {}
  if not state.process then
    append_to_buffer({ "Error: Agent not running" })
    return
  end
  if not state.session_id then
    append_to_buffer({ "Error: No active session" })
    return
  end
  if state.busy and not opts.force then
    table.insert(state.prompt_queue, { content = content, opts = opts })
    local queue_size = #state.prompt_queue
    append_to_buffer({ "[queued: " .. queue_size .. " pending]" })
    return
  end
  state.busy = true
  state.streaming_response = ""
  state.streaming_start_line = nil
  if state.busy_timer then
    pcall(vim.fn.timer_stop, state.busy_timer)
  end
  state.busy_timer = vim.fn.timer_start(5000, function()
    vim.schedule(function()
      if state.busy then
        state.busy = false
        if config.debug then
          append_to_buffer({ "[debug] busy timeout - reset" })
        end
      end
    end)
  end)
  local prompt
  if type(content) == "string" then
    prompt = { create_text_content(content) }
    if not opts.silent then
      append_to_buffer({ "", "> " .. content, "" })
    end
  elseif type(content) == "table" then
    prompt = content
    if not opts.silent then
      local preview = ""
      for _, block in ipairs(content) do
        if block.type == "text" then
          preview = preview .. block.text
        elseif block.type == "resource" then
          preview = preview .. "[" .. (block.resource.uri or "resource") .. "] "
        elseif block.type == "resource_link" then
          preview = preview .. "[@" .. (block.name or "file") .. "] "
        end
      end
      append_to_buffer({ "", "> " .. preview:sub(1, 100), "" })
    end
  else
    state.busy = false
    return
  end
  send_jsonrpc("session/prompt", {
    sessionId = state.session_id,
    prompt = prompt
  })
end

function M.set_mode(mode_id)
  if not state.process or not state.session_id then return end
  send_jsonrpc("session/set_mode", {
    sessionId = state.session_id,
    modeId = mode_id
  })
  state.current_mode = mode_id
  append_to_buffer({ "Mode set to: " .. mode_id })
end

function M.cancel()
  if not state.process or not state.session_id then return end
  send_jsonrpc("session/cancel", { sessionId = state.session_id }, true)
  state.busy = false
  state.prompt_queue = {}
  stop_animation()
  append_to_buffer({ "Cancelled" })
end

local function ensure_prompt()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  render_prompt()
end

local function find_prompt_line()
  return get_prompt_line()
end

local function get_prompt_input()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return "" end
  local prompt_ln = get_prompt_line()
  if not prompt_ln then return "" end
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  local lines = vim.api.nvim_buf_get_lines(state.buf, prompt_ln - 1, line_count, false)
  if #lines == 0 then return "" end
  return table.concat(lines, "\n")
end

local function clear_prompt_input()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local prompt_ln = get_prompt_line()
  if not prompt_ln then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, prompt_ln - 1, -1, false, { "" })
  render_prompt()
end

local function create_ui()
  local width = config.window.width < 1 and math.floor(vim.o.columns * config.window.width) or config.window.width
  vim.cmd("botright vsplit")
  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, width)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].modifiable = true
  vim.bo[state.buf].swapfile = false
  vim.wo[state.win].wrap = true
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  require("ai_repl.syntax").apply_to_buffer(state.buf)

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = state.buf,
    callback = function()
      local prompt_ln = get_prompt_line()
      if not prompt_ln then return end
      local cursor = vim.api.nvim_win_get_cursor(state.win)
      local row = cursor[1]
      if row < prompt_ln then
        vim.bo[state.buf].modifiable = false
      else
        vim.bo[state.buf].modifiable = true
      end
    end
  })

  local function submit()
    local text = get_prompt_input():gsub("^%s*(.-)%s*$", "%1")
    if text == "" then return end
    clear_prompt_input()
    if text:sub(1, 1) == "/" then
      M.handle_command(text:sub(2))
    else
      local pending = state.pending_files or {}
      state.pending_files = nil
      if #pending > 0 then
        local prompt = {}
        for _, file_path in ipairs(pending) do
          local f = io.open(file_path, "r")
          if f then
            local content = f:read("*a")
            f:close()
            table.insert(prompt, create_resource_content(file_path, content))
          end
        end
        table.insert(prompt, create_text_content(text))
        M.send_prompt(prompt)
      else
        M.send_prompt(text)
      end
    end
  end

  local function goto_prompt()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local prompt_ln = get_prompt_line()
      if prompt_ln then
        local line = vim.api.nvim_buf_get_lines(state.buf, prompt_ln - 1, prompt_ln, false)[1] or ""
        vim.api.nvim_win_set_cursor(state.win, { prompt_ln, #line })
      end
      vim.cmd("startinsert!")
    end
  end

  local opts = { buffer = state.buf, silent = true }
  vim.keymap.set("i", "<CR>", submit, opts)
  vim.keymap.set("n", "<CR>", submit, opts)
  vim.keymap.set("n", "q", M.hide, opts)
  vim.keymap.set("n", "<Esc>", M.hide, opts)
  vim.keymap.set("n", "<C-c>", M.cancel, opts)
  vim.keymap.set("i", "<C-c>", M.cancel, opts)
  vim.keymap.set({ "n", "i" }, "<S-Tab>", function() M.show_mode_picker() end, opts)
  vim.keymap.set("n", "i", goto_prompt, opts)
  vim.keymap.set("n", "a", goto_prompt, opts)
  vim.keymap.set("n", "G", goto_prompt, opts)
  vim.keymap.set("i", "@", function()
    local ok, snacks = pcall(require, "snacks")
    if not ok then
      vim.api.nvim_feedkeys("@", "n", false)
      return
    end
    snacks.picker.files({
      cwd = get_current_project_root(),
      confirm = function(picker, item)
        picker:close()
        if item and item.file then
          local file_path = vim.fn.fnamemodify(item.file, ":p")
          local file_name = vim.fn.fnamemodify(item.file, ":t")
          local prompt_ln = get_prompt_line()
          if prompt_ln then
            local line = vim.api.nvim_buf_get_lines(state.buf, prompt_ln - 1, prompt_ln, false)[1] or ""
            local new_line = line .. "@" .. file_name .. " "
            vim.api.nvim_buf_set_lines(state.buf, prompt_ln - 1, prompt_ln, false, { new_line })
            vim.api.nvim_win_set_cursor(state.win, { prompt_ln, #new_line })
            state.pending_files = state.pending_files or {}
            table.insert(state.pending_files, file_path)
          end
          vim.cmd("startinsert!")
        end
      end
    })
  end, opts)
end

function M.handle_command(cmd)
  local parts = vim.split(cmd, "%s+", { trimempty = true })
  local command = parts[1]
  if command == "help" then
    append_to_buffer({
      "",
      "----------------------------------------",
      "Commands",
      "----------------------------------------",
      " /help      This help",
      " /clear     Clear buffer",
      " /mode      Switch mode",
      " /modes     List modes",
      " /commands  Agent commands",
      " /plan      Current plan",
      " /sessions  Session picker",
      " /new       New session",
      " /root      Show project root",
      " /status    Show state",
      " /flush     Process queue",
      " /debug     Toggle debug",
      " /quit      Close",
      "",
      "----------------------------------------",
      "Keys",
      "----------------------------------------",
      " q          Close",
      " C-c        Cancel operation",
      " S-Tab      Mode picker",
      "----------------------------------------",
    })
  elseif command == "clear" then
    clear_buffer()
  elseif command == "quit" or command == "q" then
    M.close()
  elseif command == "cancel" then
    M.cancel()
  elseif command == "mode" then
    local mode = parts[2]
    if mode then
      M.set_mode(mode)
    else
      append_to_buffer({ "Current mode: " .. (state.current_mode or "default") })
    end
  elseif command == "modes" then
    if #state.modes == 0 then
      append_to_buffer({ "Modes: default, plan" })
    else
      append_to_buffer({ "Available modes:" })
      for _, m in ipairs(state.modes) do
        local current = m.id == state.current_mode and " (current)" or ""
        append_to_buffer({ "  " .. m.id .. ": " .. (m.description or "") .. current })
      end
    end
  elseif command == "commands" or command == "cmds" then
    if #state.slash_commands == 0 then
      append_to_buffer({ "No slash commands available yet" })
    else
      append_to_buffer({ "Slash commands:" })
      for _, c in ipairs(state.slash_commands) do
        append_to_buffer({ "  /" .. c.name .. " - " .. (c.description or "") })
      end
    end
  elseif command == "plan" then
    if #state.current_plan == 0 then
      append_to_buffer({ "No active plan" })
    else
      render_plan()
    end
  elseif command == "sessions" then
    M.open_session_picker()
  elseif command == "new" then
    M.new_session()
  elseif command == "root" or command == "cwd" then
    append_to_buffer({ "Project root: " .. get_current_project_root() })
  elseif command == "debug" then
    config.debug = not config.debug
    append_to_buffer({ "Debug: " .. (config.debug and "on" or "off") })
  elseif command == "status" then
    append_to_buffer({
      "busy: " .. tostring(state.busy),
      "queue: " .. #state.prompt_queue,
      "session: " .. (state.session_id and state.session_id:sub(1, 8) or "none"),
      "mode: " .. (state.current_mode or "default")
    })
  elseif command == "flush" then
    state.busy = false
    local count = #state.prompt_queue
    if count > 0 then
      append_to_buffer({ "Processing " .. count .. " queued messages..." })
      local next_item = table.remove(state.prompt_queue, 1)
      if next_item then
        M.send_prompt(next_item.content, next_item.opts)
      end
    else
      append_to_buffer({ "Queue is empty" })
    end
  else
    M.send_prompt("/" .. cmd)
  end
end

function M.show_mode_picker()
  local modes = state.modes
  if #modes == 0 then
    modes = {
      { id = "default", name = "Default", description = "Standard mode" },
      { id = "plan", name = "Plan", description = "Plan before executing" }
    }
  end
  local items = {}
  for _, m in ipairs(modes) do
    local prefix = m.id == state.current_mode and "[x] " or "[ ] "
    table.insert(items, prefix .. m.name .. ": " .. (m.description or ""))
  end
  vim.ui.select(items, { prompt = "Select mode:" }, function(_, idx)
    if idx then
      M.set_mode(modes[idx].id)
    end
  end)
end

function M.open()
  if state.active then return end
  state.source_buf = vim.api.nvim_get_current_buf()
  state.project_root = get_project_root(state.source_buf)
  state.active = true
  state.is_first_open = true
  create_ui()
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "AI REPL | /help for commands", "", "" })
  render_prompt()
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  vim.api.nvim_win_set_cursor(state.win, { line_count, 0 })
  vim.cmd("startinsert!")
  if start_process() then
    vim.defer_fn(initialize, 100)
  else
    append_to_buffer({ "Failed to start " .. config.provider.cmd })
  end
end

function M.close()
  state.active = false
  stop_process()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  prompt.extmark_id = nil
  prompt.line = nil
end

function M.hide()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
  end
  state.win = nil
end

function M.show()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    M.open()
    return
  end
  local width = config.window.width < 1 and math.floor(vim.o.columns * config.window.width) or config.window.width
  vim.cmd("botright vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, width)
  vim.wo[state.win].wrap = true
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  local prompt_ln = get_prompt_line()
  if prompt_ln then
    local line = vim.api.nvim_buf_get_lines(state.buf, prompt_ln - 1, prompt_ln, false)[1] or ""
    vim.api.nvim_win_set_cursor(state.win, { prompt_ln, #line })
  end
  vim.cmd("startinsert!")
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.hide()
  elseif state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    M.show()
  else
    M.open()
  end
end

function M.add_file_as_resource(file, text, message)
  if not file or file == "" then
    vim.notify("No file specified", vim.log.levels.WARN)
    return
  end
  local content = text or table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  local resource = create_resource_content(file, content)
  local prompt = { resource }
  if message then
    table.insert(prompt, 1, create_text_content(message))
  end
  local function try_send()
    if state.session_id and state.process then
      M.send_prompt(prompt)
    elseif state.active then
      vim.defer_fn(try_send, 200)
    end
  end
  if not state.active then
    M.open()
  end
  try_send()
end

function M.add_file_as_link(file, message)
  if not file or file == "" then
    vim.notify("No file specified", vim.log.levels.WARN)
    return
  end
  local link = create_resource_link(file)
  local prompt = { link }
  if message then
    table.insert(prompt, 1, create_text_content(message))
  end
  local function try_send()
    if state.session_id and state.process then
      M.send_prompt(prompt)
    elseif state.active then
      vim.defer_fn(try_send, 200)
    end
  end
  if not state.active then
    M.open()
  end
  try_send()
end

function M.add_current_file_to_context()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("No file open", vim.log.levels.WARN)
    return
  end
  local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  M.add_file_as_resource(file, content)
end

function M.add_selection_to_context()
  local mode = vim.fn.mode()
  local start_pos, end_pos
  if mode == "v" or mode == "V" or mode == "\22" then
    start_pos = vim.fn.getpos("v")
    end_pos = vim.fn.getpos(".")
    if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
      start_pos, end_pos = end_pos, start_pos
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  else
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")
  end
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then return end
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
  else
    lines[1] = lines[1]:sub(start_pos[3])
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
  end
  local content = table.concat(lines, "\n")
  local file = vim.api.nvim_buf_get_name(buf)
  local annotation = { range = { start_pos[2], end_pos[2] } }
  local resource = create_resource_content(file ~= "" and file or "selection", content, annotation)
  local prompt = { resource }
  local function try_send()
    if state.session_id and state.process then
      M.send_prompt(prompt)
    elseif state.active then
      vim.defer_fn(try_send, 200)
    end
  end
  if not state.active then
    M.open()
  end
  try_send()
end

function M.send_selection()
  local mode = vim.fn.mode()
  local start_pos, end_pos
  if mode == "v" or mode == "V" or mode == "\22" then
    start_pos = vim.fn.getpos("v")
    end_pos = vim.fn.getpos(".")
    if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
      start_pos, end_pos = end_pos, start_pos
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  else
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")
  end
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then return end
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
  else
    lines[1] = lines[1]:sub(start_pos[3])
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
  end
  local content = table.concat(lines, "\n")
  if content == "" then return end
  if not state.active then
    M.open()
  end
  local attempts = 0
  local function try_send()
    attempts = attempts + 1
    if state.session_id and state.process then
      M.send_prompt(content)
    elseif attempts < 50 then
      vim.defer_fn(try_send, 100)
    end
  end
  vim.defer_fn(try_send, 50)
end

function M.add_file_or_selection_to_context()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    M.add_selection_to_context()
  else
    M.add_current_file_to_context()
  end
end

function M.add_selection_to_prompt()
  local mode = vim.fn.mode()
  local start_pos, end_pos
  if mode == "v" or mode == "V" or mode == "\22" then
    start_pos = vim.fn.getpos("v")
    end_pos = vim.fn.getpos(".")
    if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
      start_pos, end_pos = end_pos, start_pos
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  else
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")
  end
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then return end
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
  else
    lines[1] = lines[1]:sub(start_pos[3])
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
  end
  local content = table.concat(lines, "\n")
  if content == "" then return end
  if not state.active then
    M.open()
  end
  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
    local prompt_ln = get_prompt_line()
    if not prompt_ln then return end
    vim.bo[state.buf].modifiable = true
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    local existing = vim.api.nvim_buf_get_lines(state.buf, prompt_ln - 1, line_count, false)
    local new_lines = vim.split(content, "\n", { plain = true })
    if #existing > 0 then
      existing[#existing] = existing[#existing] .. new_lines[1]
      for i = 2, #new_lines do
        table.insert(existing, new_lines[i])
      end
    else
      existing = new_lines
    end
    vim.api.nvim_buf_set_lines(state.buf, prompt_ln - 1, line_count, false, existing)
    render_prompt()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local new_count = vim.api.nvim_buf_line_count(state.buf)
      local last = vim.api.nvim_buf_get_lines(state.buf, new_count - 1, new_count, false)[1] or ""
      vim.api.nvim_win_set_cursor(state.win, { new_count, #last })
      vim.api.nvim_set_current_win(state.win)
      vim.cmd("startinsert!")
    end
  end)
end

local function save_current_session()
  if state.session_id then
    local exists = false
    for _, s in ipairs(state.sessions_list) do
      if s.id == state.session_id then exists = true break end
    end
    if not exists then
      table.insert(state.sessions_list, { id = state.session_id, name = "Session " .. (#state.sessions_list + 1), cwd = state.project_root })
    end
  end
end

function M.load_session(session_id)
  if not state.process or not state.initialized then
    append_to_buffer({ "Error: Not connected" })
    return
  end
  if not state.supports_load_session then
    append_to_buffer({ "Error: Agent doesn't support loading sessions" })
    return
  end
  save_current_session()
  state.current_plan = {}
  state.active_tools = {}
  state.streaming_response = ""
  state.streaming_start_line = nil
  local root = get_current_project_root()
  append_to_buffer({ "Loading session " .. session_id:sub(1, 8) .. "..." })
  local id = send_jsonrpc("session/load", {
    sessionId = session_id,
    cwd = root,
    mcpServers = {}
  })
  state.pending_requests[id] = {
    method = "session/load",
    callback = function(result)
      state.session_id = session_id
      if result then
        if result.modes then
          state.modes = result.modes.availableModes or {}
          state.current_mode = result.modes.currentModeId
        end
      end
      local adapter = get_adapter()
      if adapter and adapter.read_session_messages then
        local messages = adapter.read_session_messages(root, session_id)
        if messages and #messages > 0 then
          render_session_history(messages)
          return
        end
      end
      append_to_buffer({ "[+] Session loaded: " .. session_id:sub(1, 8) .. "...", "" })
    end
  }
end

function M.new_session(opts)
  opts = opts or {}
  if not state.process or not state.initialized then
    append_to_buffer({ "Error: Not connected" })
    return
  end
  save_current_session()
  if opts.cwd then
    state.project_root = opts.cwd
  end
  state.session_id = nil
  state.current_plan = {}
  state.active_tools = {}
  state.streaming_response = ""
  state.streaming_start_line = nil
  clear_buffer()
  append_to_buffer({ "Creating new session..." })
  create_session()
end

function M.open_session_picker()
  local root = get_current_project_root()
  local disk_sessions = get_sessions_for_project(root)
  local items = {}
  table.insert(items, { label = "+ New Session", action = "new" })
  for _, s in ipairs(disk_sessions) do
    local is_current = s.id == state.session_id
    local prefix = is_current and "[x] " or "[ ] "
    local action = is_current and "current" or (state.supports_load_session and "load" or "view")
    table.insert(items, { label = prefix .. s.name, action = action, id = s.id })
  end
  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label)
  end
  vim.ui.select(labels, { prompt = "Sessions:" }, function(_, idx)
    if not idx then return end
    local item = items[idx]
    if item.action == "new" then
      M.new_session()
    elseif item.action == "load" then
      M.load_session(item.id)
    elseif item.action == "current" then
      append_to_buffer({ "Already on this session" })
    elseif item.action == "view" then
      append_to_buffer({ "Session " .. item.id .. " (no resume support)" })
    end
  end)
end

function M.get_slash_commands()
  return state.slash_commands
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  local syntax = require("ai_repl.syntax")
  syntax.setup()
  vim.api.nvim_create_user_command("AIRepl", M.toggle, { desc = "Toggle AI REPL" })
  vim.api.nvim_create_user_command("AIReplOpen", M.open, { desc = "Open AI REPL" })
  vim.api.nvim_create_user_command("AIReplClose", M.close, { desc = "Close AI REPL" })
end

return M
