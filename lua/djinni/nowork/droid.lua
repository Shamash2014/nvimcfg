local session = require("djinni.acp.session")
local log_buffer = require("djinni.nowork.log_buffer")
local turn = require("djinni.nowork.turn")
local templates = require("djinni.nowork.templates")
local lifecycle = require("djinni.nowork.state")
local tool_call = require("djinni.nowork.tool_call")

local M = {}
M.active = {}

local counter = 0

local function is_session_not_found(err)
  if not err then return false end
  if err.code == -32603 then return true end
  local msg = tostring(err.message or err or ""):lower()
  return msg:find("session not found", 1, true) ~= nil
end

local function recover_session_and_retry(droid, text_for_retry, reason_label)
  if (droid._session_recreate_attempts or 0) >= 1 then return false end
  droid._session_recreate_attempts = (droid._session_recreate_attempts or 0) + 1
  droid.log_buf:append("[" .. reason_label .. " — recreating session]")
  droid.session_id = nil
  droid.state.available_commands = nil
  droid.acp_modes = nil
  local cwd = droid.opts and droid.opts.cwd or vim.fn.getcwd()
  session.create_task_session(cwd, function(create_err, new_sid)
    if create_err or not new_sid then
      droid.log_buf:append("[error] failed to recreate session: " .. tostring((create_err and create_err.message) or create_err or "no session"))
      pcall(function() require("djinni.nowork.status_panel").update() end)
      return
    end
    droid.session_id = new_sid
    droid.log_buf:append("[session recreated: " .. tostring(new_sid) .. "]")
    M._turn(droid, text_for_retry)
  end, { provider = droid.provider_name, model = droid.model_name })
  return true
end

local function announce(droid)
  require("djinni.nowork.status_panel").update()
  pcall(function()
    require("djinni.nowork.overview").refresh_all()
  end)
end

local function next_id()
  counter = counter + 1
  return "nowork" .. counter
end

local function discussion(droid)
  return lifecycle.ensure_discussion(droid)
end

local function set_status(droid, status)
  lifecycle.set_droid_status(droid, status)
  pcall(vim.cmd, "redrawstatus")
end

local function set_discussion_phase(droid, phase)
  lifecycle.set_discussion_phase(droid, phase)
end

local function clear_interrupt_request(droid)
  if droid then droid._interrupt_requested = nil end
end

local function mark_interrupt_request(droid)
  if droid then droid._interrupt_requested = true end
end

local function interrupt_requested(droid)
  return droid and droid._interrupt_requested == true
end

local function apply_resume_preamble(droid, text)
  local preamble = lifecycle.take_resume_preamble(droid) or droid._resume_preamble
  if not preamble or preamble == "" then
    return text
  end
  droid._resume_preamble = nil
  return preamble .. "\n\nUser's next instruction:\n" .. text
end

function M.resolve(droid_or_id)
  if type(droid_or_id) == "string" then
    return M.active[droid_or_id]
  end
  return droid_or_id
end

function M.by_buf(bufnr)
  for _, d in pairs(M.active) do
    if d.log_buf and d.log_buf.buf == bufnr then
      return d
    end
  end
  return nil
end

function M.current(callback)
  local cur = vim.api.nvim_get_current_buf()
  local d = M.by_buf(cur)
  if not d then
    local ok, compose = pcall(require, "djinni.nowork.compose")
    if ok and compose.droid_for_buf then
      d = compose.droid_for_buf(cur)
    end
  end
  if d then
    if callback then callback(d) end
    return d
  end
  local candidates = {}
  for _, dr in pairs(M.active) do
    if not lifecycle.is_finished(dr) then
      candidates[#candidates + 1] = dr
    end
  end
  if #candidates == 0 then
    vim.notify("nowork: no active droid", vim.log.levels.WARN)
    if callback then callback(nil) end
    return nil
  end
  if #candidates == 1 then
    if callback then callback(candidates[1]) end
    return candidates[1]
  end
  table.sort(candidates, function(a, b) return (a.id or "") < (b.id or "") end)
  local labels = {}
  for _, dr in ipairs(candidates) do
    labels[#labels + 1] = string.format("[%s] %s %s", dr.id or "?", dr.mode or "?", dr.status or "?")
  end
  Snacks.picker.select(labels, { prompt = "select droid" }, function(choice)
    if not choice then
      if callback then callback(nil) end
      return
    end
    for i, label in ipairs(labels) do
      if label == choice then
        if callback then callback(candidates[i]) end
        return
      end
    end
    if callback then callback(nil) end
  end)
  return nil
end

function M._dispatch(droid, action)
  if action == "done" then
    if droid.status ~= lifecycle.droid.cancelled and droid.status ~= lifecycle.droid.blocked then
      set_status(droid, lifecycle.droid.done)
    end
    set_discussion_phase(droid, lifecycle.discussion.closed)
    vim.schedule(function() M.done(droid) end)
  elseif action == "await_user" then
    set_status(droid, lifecycle.droid.idle)
    set_discussion_phase(droid, lifecycle.discussion.awaiting_user)
    if lifecycle.should_close_session_on_idle(droid) and droid.session_id then
      droid._sink:close()
      lifecycle.clear_close_session_on_idle(droid)
    end
    local next_text = lifecycle.dequeue(droid)
    if next_text then
      droid.log_buf:append("[dequeued] " .. next_text:sub(1, 80):gsub("\n", " "))
      vim.schedule(function()
        M._turn(droid, next_text)
      end)
    end
  elseif action == "next" then
    local next_prompt = lifecycle.take_next_prompt(droid) or "Continue."
    vim.schedule(function()
      M._turn(droid, next_prompt)
    end)
  end
  announce(droid)
end

function M._resume(droid, action)
  vim.schedule(function()
    M._dispatch(droid, action)
  end)
end

local function attach_reconnect_handler(droid)
  if not droid or not droid.session_id then return end
  pcall(session.on_reconnect, droid.session_id, function()
    droid.log_buf:append("[session reconnected]")
    pcall(require("djinni.nowork.mailbox").drain_droid, droid, "cancelled")
  end)
end

local function recover_persistent_compose(droid)
  if not lifecycle.is_composer_persistent(droid) then
    return false
  end
  local ok, reopened = pcall(function()
    return require("djinni.nowork.compose").reopen(droid, nil, nil)
  end)
  if ok and reopened then
    set_status(droid, lifecycle.droid.idle)
    set_discussion_phase(droid, lifecycle.discussion.composing)
    return true
  end
  return false
end

local function extract_available_commands(result)
  if type(result) ~= "table" then return {} end
  return result.availableCommands or result.available_commands or result.commands or {}
end

local function extract_acp_modes(result)
  if type(result) ~= "table" then return nil, nil end
  local m = result.modes or result.modeInfo or result.mode_info
  if type(m) ~= "table" then
    local available = result.availableModes or result.available_modes
    local current = result.currentModeId or result.current_mode_id
    if available or current then return available or {}, current end
    return nil, nil
  end
  local available = m.availableModes or m.available_modes or {}
  local current = m.currentModeId or m.current_mode_id
  return available, current
end

local function mode_label(mode)
  if type(mode) ~= "table" then return tostring(mode) end
  return mode.name or mode.title or mode.label or mode.id or "?"
end

function M.apply_acp_modes(droid, available, current_id)
  if not droid then return end
  droid.acp_modes = droid.acp_modes or { available = {}, current_id = nil }
  if available then droid.acp_modes.available = available end
  if current_id then droid.acp_modes.current_id = current_id end

  local should_auto = droid.mode == "planner" or droid.initial_acp_mode ~= nil
  if should_auto
      and not droid.acp_modes._auto_applied
      and droid.session_id
      and droid.acp_modes.available
      and #droid.acp_modes.available > 0 then
    droid.acp_modes._auto_applied = true
    local preferred = droid.initial_acp_mode or "plan"
    local target
    for _, m in ipairs(droid.acp_modes.available) do
      if m.id == preferred then target = m.id; break end
    end
    if not target then
      for _, m in ipairs(droid.acp_modes.available) do
        if m.id == "readonly" then target = m.id; break end
      end
    end
    if target and target ~= droid.acp_modes.current_id then
      vim.schedule(function()
        require("djinni.nowork.acp_mode").set(droid, target)
      end)
    end
  end

  pcall(function() require("djinni.nowork.status_panel").update() end)
  pcall(vim.cmd, "redrawstatus")
end

function M.set_acp_mode_id(droid, mode_id)
  if not droid or not mode_id then return end
  droid.acp_modes = droid.acp_modes or { available = {}, current_id = nil }
  if droid.acp_modes.current_id == mode_id then return end
  droid.acp_modes.current_id = mode_id
  local label = mode_id
  for _, m in ipairs(droid.acp_modes.available or {}) do
    if m.id == mode_id then label = mode_label(m); break end
  end
  if droid.log_buf and droid.log_buf.append then
    droid.log_buf:append("[acp mode → " .. label .. "]")
  end
  pcall(function() require("djinni.nowork.status_panel").update() end)
  pcall(vim.cmd, "redrawstatus")
end

function M._turn(droid, text)
  local original_text = text
  local pre_output_tokens = (droid.state and droid.state.tokens and droid.state.tokens.output) or 0
  if droid.session_id and session.get_client and not session.get_client(droid.session_id) then
    local cwd = droid.opts and droid.opts.cwd or vim.fn.getcwd()
    session.create_or_resume_session(cwd, droid.session_id, function(err, session_id, result)
      if err then
        if recover_session_and_retry(droid, original_text, "resume failed") then return end
        droid.log_buf:append("[error] session unavailable: " .. tostring(err.message or err))
        set_status(droid, lifecycle.droid.blocked)
        set_discussion_phase(droid, lifecycle.discussion.closed)
        announce(droid)
        return
      end
      droid.session_id = session_id or droid.session_id
      droid.state.available_commands = extract_available_commands(result)
      do
        local available, current = extract_acp_modes(result)
        if available or current then M.apply_acp_modes(droid, available, current) end
      end
      attach_reconnect_handler(droid)
      M._turn(droid, text)
    end, { provider = droid.provider_name, model = droid.model_name })
    return
  end
  droid.state.turn_n = (droid.state.turn_n or 0) + 1
  local ts = os.date("%H:%M:%S")
  droid.log_buf:append("")
  droid.log_buf:append(string.format("─── turn %d · %s ───────────────", droid.state.turn_n, ts))
  droid.log_buf:append("agent:")

  local final_prompt
  text = apply_resume_preamble(droid, text)
  if droid.policy.template_wrap then
    final_prompt = droid.policy.template_wrap(text, droid.state, droid.opts)
  else
    final_prompt = text
  end

  set_status(droid, lifecycle.droid.running)
  set_discussion_phase(droid, lifecycle.discussion.sending)
  announce(droid)

  local tc_state = {}
  local stream_to_log = droid.policy.tail_stream and not droid.policy.log_render
  local turn_opts = {
    provider_name = droid.provider_name,
    on_chunk = function(kind, chunk)
      if kind ~= "agent_message_chunk" then return end
      if stream_to_log then
        droid.log_buf:append(chunk)
      end
    end,
    on_usage = function(usage, cost)
      droid.state.tokens = droid.state.tokens or { input = 0, output = 0, cache_read = 0, cache_write = 0, cost = 0 }
      local t = droid.state.tokens
      if usage then
        t.input = math.max(t.input, usage.inputTokens or usage.input_tokens or usage.input or t.input)
        t.output = math.max(t.output, usage.outputTokens or usage.output_tokens or usage.output or t.output)
        t.cache_read = math.max(t.cache_read, usage.cacheReadInputTokens or usage.cache_read_input_tokens or usage.cacheRead or t.cache_read)
        t.cache_write = math.max(t.cache_write, usage.cacheCreationInputTokens or usage.cache_creation_input_tokens or usage.cacheWrite or t.cache_write)
      end
      if cost then
        t.cost = math.max(t.cost, tonumber(cost) or t.cost)
      end
      require("djinni.nowork.status_panel").update()
    end,
    on_commands = function(commands)
      droid.state.available_commands = commands or {}
    end,
    on_mode = function(payload)
      if payload.available_modes then
        M.apply_acp_modes(droid, payload.available_modes, payload.current_mode_id)
      end
      if payload.current_mode_id then
        M.set_acp_mode_id(droid, payload.current_mode_id)
      end
    end,
    on_tool_call = function(su)
      local tc = su.toolCall or su.tool_call or su
      tool_call.append_log(droid.log_buf, tc, tc_state)
    end,
    on_permission = function(params, respond)
      droid.policy.on_permission(params, respond, droid)
    end,
  }

  turn.run(droid, final_prompt, turn_opts, function(err, res)
    if err or droid.cancelled then
      if interrupt_requested(droid) then
        clear_interrupt_request(droid)
        droid.log_buf:append("[cancelled]")
        set_status(droid, lifecycle.droid.idle)
        if not recover_persistent_compose(droid) then
          set_discussion_phase(droid, lifecycle.discussion.idle)
        end
      elseif droid.cancelled then
        droid.log_buf:append("[cancelled]")
        set_status(droid, lifecycle.droid.cancelled)
        set_discussion_phase(droid, lifecycle.discussion.closed)
      elseif is_session_not_found(err) and recover_session_and_retry(droid, original_text, "session expired") then
        return
      else
        droid.log_buf:append("[error] " .. tostring(err.message or err))
        set_status(droid, lifecycle.droid.blocked)
      end
      pcall(require("djinni.nowork.mailbox").drain_droid, droid, "cancelled")
      recover_persistent_compose(droid)
      announce(droid)
      return
    end

    droid._session_recreate_attempts = 0

    if res.stop_reason == "cancelled" then
      droid.log_buf:append("[cancelled]")
      if interrupt_requested(droid) then
        clear_interrupt_request(droid)
        set_status(droid, lifecycle.droid.idle)
        if not recover_persistent_compose(droid) then
          set_discussion_phase(droid, lifecycle.discussion.idle)
        end
      else
        set_status(droid, lifecycle.droid.cancelled)
        set_discussion_phase(droid, lifecycle.discussion.closed)
        recover_persistent_compose(droid)
      end
      announce(droid)
      return
    end
    if res.stop_reason == "error" then
      droid.log_buf:append("[error] turn failed")
      set_status(droid, lifecycle.droid.blocked)
      recover_persistent_compose(droid)
      announce(droid)
      return
    end

    local post_output_tokens = (droid.state and droid.state.tokens and droid.state.tokens.output) or 0
    local empty_text = (res.text or "") == ""
    local empty_tools = not res.tool_calls or #res.tool_calls == 0
    if empty_text and empty_tools and post_output_tokens == pre_output_tokens then
      if recover_session_and_retry(droid, original_text, "empty turn — session may be broken") then
        return
      end
    end

    if droid.policy.log_render then
      droid.policy.log_render(res.text or "", droid.log_buf)
    elseif not droid.policy.tail_stream then
      droid.log_buf:append(res.text or "")
    end

    local action = droid.policy.on_turn_end(res.text or "", droid, res.tool_calls or {})
    if action ~= "suspend" then
      M._dispatch(droid, action)
    end
  end)
end

function M.new(mode_name, initial_prompt, opts)
  opts = opts or {}
  local policy = require("djinni.nowork.modes." .. mode_name)
  local id = next_id()
  local cwd = opts.cwd or vim.fn.getcwd()

  local droid = {
    id = id,
    started_at = os.time(),
    mode = mode_name,
    policy = policy,
    session_id = nil,
    parent_id = opts.parent_id,
    on_finish = opts.on_finish,
    initial_prompt = initial_prompt,
    initial_acp_mode = opts.initial_acp_mode,
    provider_name = opts.provider or "claude",
    model_name = opts.model,
    log_buf = nil,
    _log_fh = nil,
    _log_path = nil,
    state = {
      phase = (mode_name == "autorun" or mode_name == "planner") and "plan" or nil,
      tasks = nil,
      topo_order = nil,
      current_task_id = nil,
      turns_on_task = 0,
      pending_retry = false,
      sticky_permissions = {},
      pending_events = {},
      eval_feedback = {},
      sprint_retries = {},
      discussion = {
        phase = lifecycle.discussion.idle,
        queue = {},
        composer = { persistent = false },
      },
    },
    opts = {
      cwd = cwd,
      copen = opts.copen ~= false,
      allow_kinds = opts.autorun and opts.autorun.allow_kinds or opts.allow_kinds or { "edit", "execute" },
      turns_per_task_cap = opts.autorun and opts.autorun.turns_per_task_cap or opts.turns_per_task_cap or 8,
      sprint_retry_cap = opts.autorun and opts.autorun.sprint_retry_cap or opts.sprint_retry_cap or 3,
      grade_threshold = opts.autorun and opts.autorun.grade_threshold or opts.grade_threshold or 3,
      test_cmd = (opts.autorun and opts.autorun.test_cmd)
        or (opts.routine and opts.routine.test_cmd)
        or opts.test_cmd
        or "make test",
      skills = (opts.routine and opts.routine.skills) or opts.skills or {},
      model = opts.model,
    },
    status = lifecycle.droid.booting,
    cancelled = false,
  }

  discussion(droid)

  if opts.restore and type(opts.restore) == "table" then
    local r = opts.restore
    local s = droid.state
    s.phase = r.phase or s.phase
    s.tasks = r.tasks or s.tasks
    s.topo_order = r.topo_order or s.topo_order
    s.current_task_id = r.current_task_id or s.current_task_id
    s.turns_on_task = 0
    s.sprint_retries = r.sprint_retries or s.sprint_retries
    s.eval_feedback = r.eval_feedback or s.eval_feedback
    s.sticky_permissions = r.sticky_permissions or s.sticky_permissions
    if r.opts then
      local ro = r.opts
      droid.opts.cwd = ro.cwd or droid.opts.cwd
      droid.opts.allow_kinds = ro.allow_kinds or droid.opts.allow_kinds
      droid.opts.turns_per_task_cap = ro.turns_per_task_cap or droid.opts.turns_per_task_cap
      droid.opts.sprint_retry_cap = ro.sprint_retry_cap or droid.opts.sprint_retry_cap
      droid.opts.grade_threshold = ro.grade_threshold or droid.opts.grade_threshold
      droid.opts.test_cmd = ro.test_cmd or droid.opts.test_cmd
      droid.opts.model = ro.model or droid.opts.model
      if ro.provider_name then droid.provider_name = ro.provider_name end
      if ro.model_name then droid.model_name = ro.model_name end
    end
    droid._resume_origin = r.id
  end

  local date = os.date("%Y-%m-%d", droid.started_at)
  local stamp = os.date("%H%M%S", droid.started_at)
  local logs_dir = cwd .. "/.nowork/logs/" .. date
  vim.fn.mkdir(logs_dir, "p")
  droid._log_path = string.format("%s/%s-%s-%s.log", logs_dir, stamp, id, mode_name)
  droid._log_fh = io.open(droid._log_path, "a")
  if droid._log_fh then
    local initial = (initial_prompt or ""):gsub("\n", " ")
    pcall(function()
      droid._log_fh:write("# nowork session ", id, "\n")
      droid._log_fh:write("# mode: ", mode_name, "\n")
      droid._log_fh:write("# started_at: ", os.date("%Y-%m-%dT%H:%M:%S", droid.started_at), "\n")
      if droid.model_name and droid.model_name ~= "" then
        droid._log_fh:write("# model: ", droid.model_name, "\n")
      end
      droid._log_fh:write("# initial_prompt: ", initial, "\n")
      droid._log_fh:write("\n")
      droid._log_fh:flush()
    end)
  end

  droid.log_buf = log_buffer.new({
    split = opts.log_buffer and opts.log_buffer.split or "below",
    height = opts.log_buffer and opts.log_buffer.height or 15,
    on_append = function(line)
      if droid._log_fh then
        pcall(function()
          droid._log_fh:write(line, "\n")
          droid._log_fh:flush()
        end)
      end
    end,
  })
  local lb = droid.log_buf
  lb:set_statusline_provider(function()
    return require("djinni.nowork.status_text").compact(droid)
  end)

  droid._plan_path = opts.plan_path
  droid._sink = require("djinni.nowork.sink").new(droid)

  M.active[id] = droid
  announce(droid)

  lb:append("[mode] " .. mode_name)
  if initial_prompt and initial_prompt ~= "" then
    lb:append("[prompt] " .. initial_prompt)
  end

  local function open_compose()
    local alt_buf = vim.fn.bufnr("#")
    require("djinni.nowork.compose").open(droid, { alt_buf = alt_buf })
  end

  vim.keymap.set("n", "i", open_compose, { buffer = lb.buf, desc = "nowork: open compose" })
  vim.keymap.set("n", "a", open_compose, { buffer = lb.buf, desc = "nowork: open compose" })
  vim.keymap.set("n", "<CR>", open_compose, { buffer = lb.buf, desc = "nowork: open compose" })
  vim.keymap.set("n", "<C-c>", function() M.cancel_request(droid) end, { buffer = lb.buf, desc = "nowork: cancel active request" })
  vim.keymap.set("n", "<S-Tab>", function()
    require("djinni.nowork.acp_mode").pick(droid)
  end, { buffer = lb.buf, desc = "nowork: switch ACP mode" })
  vim.keymap.set("n", "<C-l>", function()
    require("djinni.nowork.model_picker").pick(droid)
  end, { buffer = lb.buf, desc = "nowork: switch ACP model" })
  vim.keymap.set("n", "Q", function()
    require("djinni.nowork.qfix_share").populate(droid)
  end, { buffer = lb.buf, desc = "nowork: populate quickfix from droid" })
  vim.keymap.set("n", "R", function()
    M.restart(droid)
  end, { buffer = lb.buf, desc = "nowork: restart from saved state" })
  vim.keymap.set("n", "r", function() M.reopen_prompt(droid) end, { buffer = lb.buf, desc = "nowork: reopen pending prompt" })
  vim.keymap.set("n", ".", function()
    require("djinni.nowork.picker").run_action(droid)
  end, { buffer = lb.buf, desc = "nowork: droid actions menu" })
  vim.keymap.set("n", "?", function()
    require("djinni.nowork.help").show("droid log", {
      { key = "i / a / <CR>", desc = "open compose" },
      { key = "<C-c>",        desc = "cancel active request" },
      { key = "<S-Tab>",      desc = "switch ACP mode (default/plan/accept_edits/…)" },
      { key = "<C-l>",        desc = "switch ACP model (LLM)" },
      { key = "Q",            desc = "populate quickfix from this droid (touched + tasks)" },
      { key = "R",            desc = "restart from saved state (after done/cancel)" },
      { key = ".",            desc = "actions menu (cancel / done / switch mode / …)" },
      { key = "r",            desc = "reopen pending prompt (ask/question)" },
      { key = "]t / [t",      desc = "next / prev turn" },
      { key = "<leader>ap",   desc = "permissions mailbox (global)" },
      { key = "<leader>av",   desc = "review routine droid diff (normal)" },
      { key = "?",            desc = "this help" },
    })
  end, { buffer = lb.buf, desc = "nowork: droid log keys help" })

  local function jump_turn(dir)
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(lb.buf, 0, -1, false)
    if dir == "next" then
      for i = cur + 1, #lines do
        if lines[i]:match("^─── turn") then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          return
        end
      end
    else
      for i = cur - 2, 1, -1 do
        if lines[i]:match("^─── turn") then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          return
        end
      end
    end
  end

  vim.keymap.set("n", "]t", function() jump_turn("next") end, { buffer = lb.buf, desc = "nowork: next turn" })
  vim.keymap.set("n", "[t", function() jump_turn("prev") end, { buffer = lb.buf, desc = "nowork: prev turn" })

  session.create_task_session(cwd, function(err, session_id, result)
    if err then
      lb:append("[error] session create failed: " .. tostring(err.message or err))
      set_status(droid, lifecycle.droid.blocked)
      set_discussion_phase(droid, lifecycle.discussion.closed)
      announce(droid)
      return
    end
    droid.session_id = session_id
    droid.state.available_commands = extract_available_commands(result)
    do
      local available, current = extract_acp_modes(result)
      if available or current then M.apply_acp_modes(droid, available, current) end
    end
    set_status(droid, lifecycle.droid.idle)
    attach_reconnect_handler(droid)
    if opts.preamble and opts.preamble ~= "" then
      lb:append("[resume] restoring from " .. (opts.restore and opts.restore.id or "?"))
      if opts.defer_preamble then
        lifecycle.set_resume_preamble(droid, opts.preamble)
        droid._resume_preamble = opts.preamble
        local pending_initial = lifecycle.take_pending_initial(droid)
        if pending_initial then
          M._turn(droid, pending_initial)
        else
          vim.schedule(function()
            require("djinni.nowork.compose").open(droid, { alt_buf = vim.fn.bufnr("#") })
          end)
        end
      else
        M._turn(droid, opts.preamble)
      end
    elseif initial_prompt and initial_prompt ~= "" then
      M._turn(droid, initial_prompt)
    else
      local pending_initial = lifecycle.take_pending_initial(droid)
      if pending_initial then
        M._turn(droid, pending_initial)
      else
        vim.schedule(function()
          require("djinni.nowork.compose").open(droid, { alt_buf = vim.fn.bufnr("#") })
        end)
      end
    end
  end, { provider = droid.provider_name, model = droid.model_name })

  return id
end

function M.cancel_request(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  if droid.status ~= lifecycle.droid.running then
    vim.notify("nowork: no active request on " .. droid.id, vim.log.levels.INFO)
    return
  end
  if not droid.session_id then
    vim.notify("nowork: no session to interrupt on " .. droid.id, vim.log.levels.WARN)
    return
  end
  mark_interrupt_request(droid)
  droid._sink:cancel()
  droid.log_buf:append("[cancel requested]")
end

function M.say(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  if droid.status == lifecycle.droid.running then
    droid.log_buf:append("[warn] droid is running, ignoring say")
    return
  end
  M._turn(droid, text)
end

function M.stage(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid or not text or text == "" then return end
  lifecycle.set_staged_input(droid, text)
  droid.log_buf:append("[staged]")
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    droid.log_buf:append("  " .. line)
  end
  require("djinni.nowork.status_panel").update()
end

function M.stage_append(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid or not text or text == "" then return end
  local existing = lifecycle.staged_input(droid)
  if existing and existing ~= "" then
    lifecycle.set_staged_input(droid, existing .. "\n\n" .. text)
  else
    lifecycle.set_staged_input(droid, text)
  end
  droid.log_buf:append("[staged+]")
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    droid.log_buf:append("  " .. line)
  end
  require("djinni.nowork.status_panel").update()
end

function M.submit_staged(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  local text = lifecycle.take_staged_input(droid)
  if not text or text == "" then
    vim.notify("nowork: no staged input on " .. droid.id, vim.log.levels.WARN)
    return
  end
  M.say(droid, text)
end

function M.clear_queue(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  local count = lifecycle.clear_queue(droid)
  if count == 0 then
    vim.notify("nowork: queue empty on " .. droid.id, vim.log.levels.INFO)
    return
  end
  droid.log_buf:append("[queue cleared] " .. count .. " items dropped")
  require("djinni.nowork.status_panel").update()
end

function M.enqueue(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid or not text or text == "" then return end
  lifecycle.enqueue(droid, text)
  droid.log_buf:append("[queued] " .. text:sub(1, 80):gsub("\n", " "))
  require("djinni.nowork.status_panel").update()
end

function M.send(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid or not text or text == "" then return end
  if not droid.initial_prompt or droid.initial_prompt == "" then
    droid.initial_prompt = text
    droid.log_buf:append("[prompt] " .. text)
    if droid.session_id then
      M._turn(droid, text)
    else
      lifecycle.set_pending_initial(droid, text)
    end
    return
  end
  if droid.status == lifecycle.droid.running then
    M.enqueue(droid, text)
  else
    M.say(droid, text)
  end
end

function M.reopen_prompt(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  local pending = lifecycle.pending_prompt(droid)
  if not pending or not pending.show then
    vim.notify("nowork: no pending prompt on " .. droid.id, vim.log.levels.WARN)
    return
  end
  pending.show()
end

M.history = M.history or {}
local HISTORY_MAX = 50

local function render_autorun_task_qf(droid, open)
  if droid.mode ~= "autorun" then return end
  local order = droid.state and droid.state.topo_order or {}
  if #order == 0 then return end
  local items = {}
  for _, id in ipairs(order) do
    local t = (droid.state.tasks or {})[id]
    if t then
      items[#items + 1] = {
        text = ("[%s] %-10s %s"):format(id, t.status or "open", t.desc or ""),
        valid = 0,
      }
    end
  end
  if #items == 0 then return end
  pcall(function()
    require("djinni.nowork.qfix").set(items, {
      mode = "replace",
      open = open == true,
      title = "nowork autorun tasks: " .. (droid.initial_prompt or droid.id),
    })
  end)
end

local function finalize(droid)
  if droid._finalized then return end
  droid._finalized = true
  pcall(function()
    require("djinni.nowork.compose").close(droid)
  end)
  if droid._log_fh then
    pcall(function() droid._log_fh:close() end)
    droid._log_fh = nil
  end
  if droid._log_path and droid.log_buf and vim.api.nvim_buf_is_valid(droid.log_buf.buf) then
    pcall(function()
      local lines = vim.api.nvim_buf_get_lines(droid.log_buf.buf, 0, -1, false)
      local fh = io.open(droid._log_path, "w")
      if fh then
        local initial = (droid.initial_prompt or ""):gsub("\n", " ")
        fh:write("# nowork session ", droid.id, "\n")
        fh:write("# mode: ", droid.mode or "?", "\n")
        fh:write("# status: ", droid.status or "?", "\n")
        fh:write("# started_at: ", os.date("%Y-%m-%dT%H:%M:%S", droid.started_at or os.time()), "\n")
        fh:write("# initial_prompt: ", initial, "\n\n")
        fh:write(table.concat(lines, "\n"))
        fh:close()
      end
    end)
  end
  pcall(function()
    require("djinni.nowork.archive").write_state(droid)
  end)
  table.insert(M.history, 1, {
    id = droid.id,
    mode = droid.mode,
    initial_prompt = droid.initial_prompt,
    started_at = droid.started_at,
    ended_at = os.time(),
    status = droid.status,
    log_buf = droid.log_buf,
    archive_path = droid._log_path,
  })
  while #M.history > HISTORY_MAX do
    table.remove(M.history)
  end
  M.active[droid.id] = nil
  pcall(function()
    require("djinni.nowork.overview").refresh_all()
  end)
  if droid.on_finish then
    pcall(droid.on_finish, droid)
  end
end

function M.cancel(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  pcall(require("djinni.nowork.mailbox").drain_droid, droid, "cancelled")
  droid.cancelled = true
  if droid.session_id and droid._sink then
    droid._sink:cancel()
  end
  droid.log_buf:append("[cancelled]")
  set_status(droid, lifecycle.droid.cancelled)
  set_discussion_phase(droid, lifecycle.discussion.closed)
  announce(droid)
  finalize(droid)
  require("djinni.nowork.status_panel").update()
end

function M.done(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  pcall(require("djinni.nowork.mailbox").drain_droid, droid, "cancelled")
  local show_diff = false
  if droid.mode == "autorun" then
    local order = droid.state and droid.state.topo_order or {}
    local has_open = false
    for _, id in ipairs(order) do
      local t = (droid.state.tasks or {})[id]
      if t and t.status ~= "done" then
        has_open = true
        break
      end
    end
    if has_open then
      local choice = vim.fn.confirm(
        "nowork: autorun has open sprints — finish unit of work?",
        "&Continue editing\n&Force done\n&Cancel",
        1
      )
      if choice == 1 then return end
      if choice == 3 then return end
    end
  elseif droid.mode == "routine" then
    local choice = vim.fn.confirm(
      "nowork: routine done — review diff before closing?",
      "&Done\nDone + &diff\n&Cancel",
      1
    )
    if choice == 3 then return end
    show_diff = choice == 2
  end
  if droid.session_id then
    droid._sink:close()
  end
  finalize(droid)
  if show_diff then
    require("djinni.nowork.routine_review").open(droid, { readonly = true })
  end
  require("djinni.nowork.status_panel").update()
end

function M.checkpoint(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  pcall(function()
    require("djinni.nowork.archive").write_state(droid)
  end)
end

local function infer_archive_meta(log_path)
  local meta = {
    mode = "routine",
    initial_prompt = "",
    cwd = log_path and log_path:match("^(.-)/%.nowork/") or nil,
  }
  local fh = log_path and io.open(log_path, "r") or nil
  if not fh then
    return meta
  end
  for _ = 1, 12 do
    local line = fh:read("*l")
    if not line then break end
    local mode = line:match("^# mode:%s*(.+)$")
    if mode and mode ~= "" then meta.mode = vim.trim(mode) end
    local initial = line:match("^# initial_prompt:%s*(.*)$")
    if initial then meta.initial_prompt = initial end
  end
  fh:close()
  return meta
end

function M.restart(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then
    vim.notify("nowork: droid not found", vim.log.levels.WARN)
    return
  end
  if droid._finalized then
    vim.notify("nowork: " .. droid.id .. " already restarted — open the new session", vim.log.levels.WARN)
    return
  end
  if droid.status == lifecycle.droid.running then
    vim.notify("nowork: cannot restart " .. droid.id .. " while running — cancel first", vim.log.levels.WARN)
    return
  end
  local log_path = droid._log_path
  if not log_path or log_path == "" then
    vim.notify("nowork: " .. droid.id .. " has no log path to restart from", vim.log.levels.WARN)
    return
  end
  pcall(function()
    require("djinni.nowork.archive").write_state(droid)
  end)
  if droid.session_id then
    pcall(function() droid._sink:close() end)
  end
  pcall(function() finalize(droid) end)
  M.restart_from_archive(log_path)
end

function M.restart_from_archive(log_path)
  local archive = require("djinni.nowork.archive")
  local resume = require("djinni.nowork.resume")
  local state, err = archive.read_state(log_path)
  if not state then
    vim.notify("nowork: cannot restart — " .. (err or "no sidecar"), vim.log.levels.WARN)
    return nil
  end
  local preamble = resume.build_preamble(state, log_path)
  local opts = {
    restore = state,
    preamble = preamble,
    defer_preamble = state.mode == "routine" and state.status ~= lifecycle.droid.running,
    cwd = state.opts and state.opts.cwd,
    provider = state.opts and state.opts.provider_name,
    allow_kinds = state.opts and state.opts.allow_kinds,
    turns_per_task_cap = state.opts and state.opts.turns_per_task_cap,
    sprint_retry_cap = state.opts and state.opts.sprint_retry_cap,
    grade_threshold = state.opts and state.opts.grade_threshold,
    test_cmd = state.opts and state.opts.test_cmd,
    skills = state.opts and state.opts.skills,
  }
  local id = M.new(state.mode, state.initial_prompt, opts)
  local droid = M.active[id]
  if droid and droid.log_buf then
    droid.log_buf:append("[resume] from " .. log_path)
  end
  return id
end

local function extract_refs(text, cwd)
  if not text or text == "" then return {} end
  local seen, out = {}, {}
  for tok in text:gmatch("%S+") do
    if tok:sub(1, 1) == "@" and #tok > 1 then
      local path = tok:sub(2):gsub("[,%.%):%]]+$", "")
      if path ~= "" and not seen[path] then
        local abs = path
        if cwd and not path:match("^/") then
          abs = cwd .. "/" .. path
        end
        local ok, stat = pcall(vim.loop.fs_stat, abs)
        if ok and stat then
          seen[path] = true
          out[#out + 1] = "@" .. path
        end
      end
    end
  end
  return out
end

function M.fork_from_archive(log_path)
  local archive = require("djinni.nowork.archive")
  local resume = require("djinni.nowork.resume")
  local state = archive.read_state(log_path)
  local meta = infer_archive_meta(log_path)
  local source = state or {
    mode = meta.mode,
    initial_prompt = meta.initial_prompt,
    opts = { cwd = meta.cwd },
  }
  local ref_cwd = (source.opts and source.opts.cwd) or meta.cwd
  local carried_refs = extract_refs(source.initial_prompt or meta.initial_prompt or "", ref_cwd)
  local preamble = resume.build_preamble(source, log_path, { carried_refs = carried_refs })
  local opts = {
    preamble = preamble,
    defer_preamble = source.mode == "routine",
    cwd = source.opts and source.opts.cwd or meta.cwd,
    provider = source.opts and source.opts.provider_name,
    allow_kinds = source.opts and source.opts.allow_kinds,
    turns_per_task_cap = source.opts and source.opts.turns_per_task_cap,
    sprint_retry_cap = source.opts and source.opts.sprint_retry_cap,
    grade_threshold = source.opts and source.opts.grade_threshold,
    test_cmd = source.opts and source.opts.test_cmd,
    skills = source.opts and source.opts.skills,
  }
  local mode = source.mode or "routine"
  local initial_prompt = source.initial_prompt or meta.initial_prompt or ""
  local id = M.new(mode, initial_prompt, opts)
  local droid = M.active[id]
  if droid and droid.log_buf then
    droid.log_buf:append("[fork] from " .. log_path)
  end
  if droid and mode == "routine" then
    vim.schedule(function()
      local prefill
      if #carried_refs > 0 then
        prefill = {
          summary = "Files carried over from the prior session — re-check these:\n" .. table.concat(carried_refs, "\n"),
        }
      end
      require("djinni.nowork.compose").open(droid, {
        prefill = prefill,
      })
    end)
  end
  return id
end

return M
