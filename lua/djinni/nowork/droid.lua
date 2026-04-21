local session = require("djinni.acp.session")
local log_buffer = require("djinni.nowork.log_buffer")
local turn = require("djinni.nowork.turn")
local templates = require("djinni.nowork.templates")

local M = {}
M.active = {}

local counter = 0

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

local function apply_resume_preamble(droid, text)
  local preamble = droid and droid._resume_preamble
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

function M._dispatch(droid, action)
  if action == "done" then
    if droid.status ~= "cancelled" and droid.status ~= "blocked" then
      droid.status = "done"
    end
    vim.schedule(function() M.done(droid) end)
  elseif action == "await_user" then
    droid.status = "idle"
    local q = droid.state.queue
    if q and #q > 0 then
      local next_text = table.remove(q, 1)
      droid.log_buf:append("[dequeued] " .. next_text:sub(1, 80):gsub("\n", " "))
      vim.schedule(function()
        M._turn(droid, next_text)
      end)
    end
  elseif action == "next" then
    local next_prompt = droid.state.next_prompt or "Continue."
    droid.state.next_prompt = nil
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

function M._turn(droid, text)
  droid.state.turn_n = (droid.state.turn_n or 0) + 1
  local ts = os.date("%H:%M:%S")
  droid.log_buf:append("")
  droid.log_buf:append(string.format("─── turn %d · %s ───────────────", droid.state.turn_n, ts))
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    droid.log_buf:append("user: " .. line)
  end
  droid.log_buf:append("")
  droid.log_buf:append("agent:")

  local final_prompt
  text = apply_resume_preamble(droid, text)
  if droid.policy.template_wrap then
    final_prompt = droid.policy.template_wrap(text, droid.state, droid.opts)
  else
    final_prompt = text
  end

  droid.status = "running"
  announce(droid)

  local tc_state = {}
  local function tc_log_line(tc)
    local id = tc.toolCallId or tc.id or tc.title or tostring(tc)
    local kind = tc.kind or (tc_state[id] and tc_state[id].kind) or "tool"
    local title = tc.title or tc.name or (tc_state[id] and tc_state[id].title) or kind
    local status = (tc.status or "pending"):lower()
    local prev = tc_state[id]
    if prev and prev.status == status then return end
    tc_state[id] = { kind = kind, title = title, status = status }
    local marker
    if status == "completed" then marker = "  ✓"
    elseif status == "failed" or status == "error" then marker = "  ✗"
    elseif status == "running" or status == "in_progress" then marker = "  …"
    else marker = "  ·"
    end
    droid.log_buf:append(string.format("%s [%s] %s · %s", marker, status, kind, title))
    local detail
    local raw_in = tc.rawInput or tc.raw_input or tc.input
    if not prev and type(raw_in) == "table" then
      local cmd = raw_in.command or raw_in.cmd
      if cmd then
        detail = "$ " .. tostring(cmd)
        if raw_in.description and raw_in.description ~= "" then
          detail = detail .. "  — " .. tostring(raw_in.description)
        end
      elseif (raw_in.path or raw_in.file_path) and raw_in.content then
        detail = "📝 " .. tostring(raw_in.path or raw_in.file_path)
      elseif raw_in.old_string or raw_in.new_string or raw_in.patch then
        detail = "✎ " .. tostring(raw_in.path or raw_in.file_path or "?")
      elseif raw_in.path or raw_in.file_path or raw_in.filePath then
        detail = tostring(raw_in.path or raw_in.file_path or raw_in.filePath)
      elseif raw_in.pattern then
        detail = "🔎 " .. tostring(raw_in.pattern)
      elseif raw_in.query then
        detail = "? " .. tostring(raw_in.query)
      elseif raw_in.url then
        detail = "↗ " .. tostring(raw_in.url)
      elseif raw_in.description then
        detail = tostring(raw_in.description)
      end
    end
    if not detail and not prev and tc.locations and tc.locations[1] then
      local parts = {}
      for i, l in ipairs(tc.locations) do
        if i > 3 then parts[#parts + 1] = "…"; break end
        local p = l.path or l.file or ""
        if l.line then p = p .. ":" .. tostring(l.line) end
        if p ~= "" then parts[#parts + 1] = p end
      end
      if #parts > 0 then detail = table.concat(parts, ", ") end
    end
    if detail then
      for _, l in ipairs(vim.split(detail, "\n", { plain = true })) do
        droid.log_buf:append("     " .. l)
      end
    end
    if status == "completed" or status == "failed" or status == "error" then
      local buf = {}
      for _, c in ipairs(tc.content or {}) do
        local text
        if c.type == "content" and c.content and c.content.text then text = c.content.text
        elseif c.text then text = c.text end
        if text and text ~= "" then buf[#buf + 1] = text end
      end
      local body = table.concat(buf, "\n")
      if body ~= "" then
        local lines = vim.split(body, "\n", { plain = true })
        local max = 6
        for i = 1, math.min(#lines, max) do
          droid.log_buf:append("     " .. lines[i])
        end
        if #lines > max then
          droid.log_buf:append(string.format("     … (%d more lines)", #lines - max))
        end
      end
    end
  end
  local turn_opts = {
    provider_name = droid.provider_name,
    on_chunk = (droid.policy.tail_stream and not droid.policy.log_render) and function(kind, chunk)
      if kind == "agent_message_chunk" then
        droid.log_buf:append(chunk)
      end
    end or nil,
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
    on_tool_call = function(su)
      local tc = su.toolCall or su.tool_call or su
      tc_log_line(tc)
    end,
    on_permission = function(params, respond)
      droid.policy.on_permission(params, respond, droid)
    end,
  }

  turn.run(droid.session_id, final_prompt, turn_opts, function(err, res)
    if err or droid.cancelled then
      if droid.cancelled then
        droid.log_buf:append("[cancelled]")
        droid.status = "cancelled"
      else
        droid.log_buf:append("[error] " .. tostring(err.message or err))
        droid.status = "blocked"
      end
      pcall(require("djinni.nowork.mailbox").drain_droid, droid, "cancelled")
      announce(droid)
      return
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
    initial_prompt = initial_prompt,
    provider_name = opts.provider or "claude",
    log_buf = nil,
    _log_fh = nil,
    _log_path = nil,
    state = {
      phase = mode_name == "autorun" and "plan" or nil,
      tasks = nil,
      topo_order = nil,
      current_task_id = nil,
      turns_on_task = 0,
      pending_retry = false,
      sticky_permissions = {},
      pending_permissions = {},
      next_prompt = nil,
      eval_feedback = {},
      sprint_retries = {},
      composer_persistent = false,
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
    },
    status = "idle",
    cancelled = false,
  }

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
      if ro.provider_name then droid.provider_name = ro.provider_name end
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
  vim.keymap.set("n", "r", function() M.reopen_prompt(droid) end, { buffer = lb.buf, desc = "nowork: reopen pending prompt" })
  vim.keymap.set("n", ".", function()
    require("djinni.nowork.picker").run_action(droid)
  end, { buffer = lb.buf, desc = "nowork: droid actions menu" })
  vim.keymap.set("n", "?", function()
    require("djinni.nowork.help").show("droid log", {
      { key = "i / a / <CR>", desc = "open compose" },
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

  session.create_task_session(cwd, function(err, session_id)
    if err then
      lb:append("[error] session create failed: " .. tostring(err.message or err))
      droid.status = "blocked"
      announce(droid)
      return
    end
    droid.session_id = session_id
    pcall(session.on_reconnect, session_id, function()
      droid.log_buf:append("[session reconnected]")
      pcall(require("djinni.nowork.mailbox").drain_droid, droid, "cancelled")
    end)
    if opts.preamble and opts.preamble ~= "" then
      lb:append("[resume] restoring from " .. (opts.restore and opts.restore.id or "?"))
      if opts.defer_preamble then
        droid._resume_preamble = opts.preamble
        if droid._pending_initial then
          local p = droid._pending_initial
          droid._pending_initial = nil
          M._turn(droid, p)
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
    elseif droid._pending_initial then
      local p = droid._pending_initial
      droid._pending_initial = nil
      M._turn(droid, p)
    else
      vim.schedule(function()
        require("djinni.nowork.compose").open(droid, { alt_buf = vim.fn.bufnr("#") })
      end)
    end
  end, { provider = droid.provider_name })

  return id
end

function M.say(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  if droid.status == "running" then
    droid.log_buf:append("[warn] droid is running, ignoring say")
    return
  end
  M._turn(droid, text)
end

function M.stage(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid or not text or text == "" then return end
  droid.state.staged_input = text
  droid.log_buf:append("[staged]")
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    droid.log_buf:append("  " .. line)
  end
  require("djinni.nowork.status_panel").update()
end

function M.stage_append(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid or not text or text == "" then return end
  local existing = droid.state.staged_input
  if existing and existing ~= "" then
    droid.state.staged_input = existing .. "\n\n" .. text
  else
    droid.state.staged_input = text
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
  local text = droid.state.staged_input
  if not text or text == "" then
    vim.notify("nowork: no staged input on " .. droid.id, vim.log.levels.WARN)
    return
  end
  droid.state.staged_input = nil
  M.say(droid, text)
end

function M.clear_queue(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  local q = droid.state.queue
  if not q or #q == 0 then
    vim.notify("nowork: queue empty on " .. droid.id, vim.log.levels.INFO)
    return
  end
  droid.log_buf:append("[queue cleared] " .. #q .. " items dropped")
  droid.state.queue = {}
  require("djinni.nowork.status_panel").update()
end

function M.enqueue(droid_or_id, text)
  local droid = M.resolve(droid_or_id)
  if not droid or not text or text == "" then return end
  droid.state.queue = droid.state.queue or {}
  droid.state.queue[#droid.state.queue + 1] = text
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
      droid._pending_initial = text
    end
    return
  end
  if droid.status == "running" then
    M.enqueue(droid, text)
  else
    M.say(droid, text)
  end
end

function M.reopen_prompt(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  local pending = droid.state and droid.state.pending_prompt
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
  render_autorun_task_qf(droid, false)
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
end

function M.cancel(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  pcall(require("djinni.nowork.mailbox").drain_droid, droid, "cancelled")
  droid.cancelled = true
  if droid.session_id then
    session.interrupt(nil, droid.session_id)
  end
  droid.log_buf:append("[cancelled]")
  droid.status = "cancelled"
  announce(droid)
  finalize(droid)
  require("djinni.nowork.status_panel").update()
end

function M.done(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  pcall(require("djinni.nowork.mailbox").drain_droid, droid, "cancelled")
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
  end
  local bag = droid.state and droid.state.touched
  if bag and bag.items and #bag.items > 0 then
    pcall(require("djinni.nowork.qfix_share").flush_touched, droid)
  end
  render_autorun_task_qf(droid, true)
  if droid.session_id then
    session.close_task_session(nil, droid.session_id)
  end
  finalize(droid)
  require("djinni.nowork.status_panel").update()
end

function M.checkpoint(droid_or_id)
  local droid = M.resolve(droid_or_id)
  if not droid then return end
  pcall(function()
    require("djinni.nowork.archive").write_state(droid)
  end)
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
    defer_preamble = state.mode == "routine" and state.status ~= "running",
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
  if droid and state.mode == "routine" then
    vim.schedule(function()
      require("djinni.nowork.compose").open(droid, {
        persistent = true,
        sections = { "Summary", "Review", "Observation", "Tasks" },
        title = " routine chat — <C-CR> send · <C-n> new · <C-c> close ",
        on_submit = function(text) M.send(droid, text) end,
      })
    end)
  end
  return id
end

return M
