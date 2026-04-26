local lifecycle = require("djinni.nowork.state")
local mode_switch = require("djinni.nowork.mode_switch")

local M = {}

local DEFAULT_SECTIONS = { "Summary", "Review", "Observation", "Tasks" }
local ROUTINE_CHAT_TITLE = " routine chat — <C-CR> send · <C-n> new · <C-c> close "
local FOOTER = " <C-CR> send · <S-Tab> ACP mode · <C-l> model · <C-s> local policy · . actions · Q populate · R restart · clear→/clear · <C-q> qflist · <C-b> buffer · <C-d> diff · <C-n> new · <C-c> close "

local state_by_droid = {}
local autorun_title

local function droid_key(droid)
  if not droid then return nil end
  return droid.id or tostring(droid)
end

local function build_scaffold(droid, opts)
  local sections = opts.sections or DEFAULT_SECTIONS
  local prefill = opts.prefill or {}
  local raw = opts.raw
  local label = opts.label or (droid and droid.mode) or "compose"
  local scope = opts.cwd or (droid and droid.opts and droid.opts.cwd) or vim.fn.getcwd()
  
  local lines = {}
  
  -- 1. Metadata Header (Overview style)
  lines[#lines + 1] = "  Nowork Status"
  lines[#lines + 1] = string.format("  %-8s %s", "Head", label)
  lines[#lines + 1] = string.format("  %-8s %s", "Root", scope)
  if droid and droid.id then
    lines[#lines + 1] = string.format("  %-8s %s", "Session", droid.id)
  end
  lines[#lines + 1] = "  " .. string.rep("─", 70)
  lines[#lines + 1] = ""

  -- 2. Sections
  for i, s in ipairs(sections) do
    lines[#lines + 1] = "## " .. s
    local body = prefill[s:lower()]
    if body and body ~= "" then
      for _, l in ipairs(vim.split(body, "\n", { plain = true })) do
        lines[#lines + 1] = l
      end
    else
      lines[#lines + 1] = ""
    end
    if i < #sections then lines[#lines + 1] = "" end
  end
  if raw and raw ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Raw"
    lines[#lines + 1] = "```"
    for _, l in ipairs(vim.split(raw, "\n", { plain = true })) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = "```"
  end
  return lines
end

local function available_commands(droid)
  if not droid or not droid.state then return {} end
  return droid.state.available_commands or {}
end

local function command_name(cmd)
  local raw = cmd and (cmd.name or cmd.id or cmd.command or cmd.label) or nil
  if type(raw) ~= "string" then return nil end
  local name = vim.trim(raw):gsub("^/+", "")
  if name == "" then return nil end
  return name
end

local function format_footer(droid)
  local prefix = ""
  if droid then
    local status = require("djinni.nowork.status_text").compact(droid)
    if status ~= "" then prefix = " " .. status .. " │" end
  end
  return prefix .. FOOTER
end

local function resolve_window_opts(opts)
  local settings = {}
  local ok, nowork = pcall(require, "djinni.nowork")
  if ok and nowork and nowork.config and nowork.config.compose then
    settings = nowork.config.compose
  end
  return vim.tbl_deep_extend("force", {
    floating = true,
    width = math.min(120, math.floor(vim.o.columns * 0.95)),
    height = math.min(45, math.floor(vim.o.lines * 0.85)),
    split = "below",
  }, settings, opts or {})
end

local function apply_window_local_opts(win)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].cursorline = false
end

local function open_window(buf, title, footer, opts)
  opts = resolve_window_opts(opts)
  local win
  if opts.floating == false then
    local cmd_map = {
      below = string.format("below %dsplit", opts.height),
      above = string.format("above %dsplit", opts.height),
      right = string.format("vertical rightbelow %dsplit", opts.width),
      left = string.format("vertical leftabove %dsplit", opts.width),
    }
    vim.cmd(cmd_map[opts.split] or cmd_map.below)
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  else
    local row = math.floor((vim.o.lines - opts.height) / 2) - 1
    local col = math.floor((vim.o.columns - opts.width) / 2)
    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = row,
      col = col,
      width = opts.width,
      height = opts.height,
      style = "minimal",
      border = opts.border or "rounded",
      title = title or " nowork compose ",
      title_pos = "center",
    })
  end
  apply_window_local_opts(win)
  return win, opts
end

local function render_dashboard(state)
  if not state.alive then return end
  local droid = state.droid
  local buf = state.buf
  local win = state.win
  if not vim.api.nvim_win_is_valid(win) then return end

  local ns = vim.api.nvim_create_namespace("nowork_compose_dash")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  
  local line_count = vim.api.nvim_buf_line_count(buf)
  local width = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)
  
  local dash_lines = {}
  
  -- Separator
  table.insert(dash_lines, { { string.rep("─", width - 8), "Comment" } })
  table.insert(dash_lines, { { "", "" } })

  -- 1. Arguments (Flags)
  table.insert(dash_lines, { { "Arguments", "Bold" } })
  local arg_line = { { "  " } }
  local iso = (droid and droid.opts and droid.opts.isolate) and "on" or "off"
  table.insert(arg_line, { "-i ", "Comment" })
  table.insert(arg_line, { "Isolate (", "None" })
  table.insert(arg_line, { iso, iso == "on" and "NoworkQfEdit" or "Comment" })
  table.insert(arg_line, { ")   ", "None" })
  
  table.insert(arg_line, { "-p ", "Comment" })
  table.insert(arg_line, { "Provider (", "None" })
  table.insert(arg_line, { (droid and droid.provider_name) or "claude", "NoworkQfReview" })
  table.insert(arg_line, { ")", "None" })
  table.insert(dash_lines, arg_line)
  table.insert(dash_lines, { { "", "" } })

  -- 2. Commands (Grouped Columns)
  local groups = {
    { title = "Session", cmds = { { "r", "restart" }, { "k", "stop" }, { "c", "clear" } } },
    { title = "Context", cmds = { { "b", "buffer" }, { "d", "diff" }, { "q", "qflist" } } },
    { title = "Multi", cmds = { { "m", "mul" }, { "i", "isolate" }, { "s", "staged" } } },
  }

  local mode = (droid and droid.mode) or (state.opts and state.opts.label) or ""
  if mode == "planner" or mode == "explore" then
    table.insert(groups, { title = "Plan", cmds = { { "a", "approve" }, { "v", "revise" }, { "t", "tasks" } } })
  else
    table.insert(groups, { title = "Global", cmds = { { "^CR", "Send" }, { "^C", "Close" }, { "^Q", "Qflist" } } })
  end
  
  local col_width = 24
  
  -- Header Row
  local header = {}
  for _, g in ipairs(groups) do
    table.insert(header, { g.title .. string.rep(" ", col_width - #g.title), "Bold" })
  end
  table.insert(dash_lines, header)
  
  -- Body Rows
  local max_rows = 0
  for _, g in ipairs(groups) do max_rows = math.max(max_rows, #g.cmds) end
  
  for r = 1, max_rows do
    local row = {}
    for _, g in ipairs(groups) do
      local pair = g.cmds[r]
      if pair then
        local key, name = pair[1], pair[2]
        table.insert(row, { " " .. key .. " ", "NoworkQfNext" })
        local label = name .. string.rep(" ", col_width - #name - 4)
        table.insert(row, { label, "None" })
      else
        table.insert(row, { string.rep(" ", col_width), "None" })
      end
    end
    table.insert(dash_lines, row)
  end

  -- Padding logic to keep dashboard at bottom
  local total_dash_lines = #dash_lines
  local current_lines = vim.api.nvim_buf_line_count(buf)
  local target_padding = win_height - total_dash_lines - current_lines - 1
  
  local final_virt = {}
  if target_padding > 0 then
    for i = 1, target_padding do table.insert(final_virt, { { "", "" } }) end
  end
  for _, l in ipairs(dash_lines) do table.insert(final_virt, l) end
  
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, line_count - 1, 0, {
    virt_lines = final_virt,
    virt_lines_above = false,
  })
end

local function place_cursor_first_blank(buf, win, sections)
  local name = sections and sections[1] or "Summary"
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, l in ipairs(lines) do
    if l == "## " .. name then
      if lines[i + 1] == "" then
        vim.api.nvim_win_set_cursor(win, { i + 1, 0 })
      else
        vim.api.nvim_win_set_cursor(win, { i, #l })
      end
      return
    end
  end
end

local function set_buffer_body(buf, lines, editable)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = editable ~= false
end

local function refresh_window_chrome(state)
  if not state or not vim.api.nvim_win_is_valid(state.win) or state.window_opts.floating == false then return end
  local cfg = vim.api.nvim_win_get_config(state.win)
  cfg.title = state.opts.title or autorun_title(state.droid) or " nowork compose "
  cfg.title_pos = "center"
  pcall(vim.api.nvim_win_set_config, state.win, cfg)
end

autorun_title = function(droid)
  if not droid or droid.mode ~= "autorun" then return nil end
  local s = droid.state or {}
  local order = s.topo_order or {}
  if #order == 0 then return nil end
  local done, total = 0, #order
  for _, id in ipairs(order) do
    local t = (s.tasks or {})[id]
    if t and t.status == "done" then done = done + 1 end
  end
  local id = s.current_task_id
  if id and s.tasks and s.tasks[id] then
    local t = s.tasks[id]
    local idx
    for i, tid in ipairs(order) do
      if tid == id then idx = i break end
    end
    local desc = (t.desc or ""):sub(1, 40)
    return string.format(" autorun %d/%d · sprint %s — %s ", idx or done, total, id, desc)
  end
  if done == total then
    return string.format(" autorun %d/%d · all sprints done ", done, total)
  end
  return string.format(" autorun %d/%d · no active sprint ", done, total)
end

function M.routine_chat_config(droid, opts)
  opts = opts or {}
  local config = vim.tbl_deep_extend("force", {
    title = ROUTINE_CHAT_TITLE,
    alt_buf = vim.fn.bufnr("#"),
    persistent = true,
    sections = DEFAULT_SECTIONS,
  }, opts)
  if droid and config.on_submit == nil then
    config.on_submit = function(text)
      require("djinni.nowork.droid").send(droid, text)
    end
  end
  return config
end

function M.open_routine_chat(droid, opts)
  return M.open(droid, M.routine_chat_config(droid, opts))
end

function M.open(droid, opts)
  opts = opts or {}
  local alt_buf = opts.alt_buf or vim.fn.bufnr("#")
  local sections = opts.sections or DEFAULT_SECTIONS
  local persistent = opts.persistent == true
  local key = droid_key(droid)

  if persistent and key and state_by_droid[key] then
    local s = state_by_droid[key]
    if s.alive and vim.api.nvim_win_is_valid(s.win) then
      vim.api.nvim_set_current_win(s.win)
      vim.cmd("startinsert")
      return
    end
    state_by_droid[key] = nil
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.b[buf].nowork_compose = true
  if droid and droid.id then
    vim.b[buf].nowork_droid = droid.id
    if droid.opts and droid.opts.cwd then
      vim.b[buf].nowork_cwd = droid.opts.cwd
    end
  end

  local title = opts.title or autorun_title(droid)
  local win, window_opts = open_window(buf, title, format_footer(droid), opts.window or opts.compose)

  local initial
  local structured = opts.sections ~= nil
  if opts.initial then
    initial = vim.split(opts.initial, "\n", { plain = true })
  elseif structured then
    initial = build_scaffold(droid, opts)
  else
    initial = { "" }
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial)

  -- Apply highlights for the header (only when structured scaffold is present)
  if #initial > 4 then
    local nns = vim.api.nvim_create_namespace("nowork_compose_hl")
    pcall(vim.api.nvim_buf_add_highlight, buf, nns, "NeoworkIdxTitle", 0, 2, -1)
    for i = 1, math.min(3, #initial - 1) do
      local line = initial[i + 1]
      if line and line:match("^  ") then
        pcall(vim.api.nvim_buf_add_highlight, buf, nns, "NeoworkIdxSection", i, 2, 10)
        pcall(vim.api.nvim_buf_add_highlight, buf, nns, "NeoworkIdxMuted", i, 11, -1)
      end
    end
    local rule_idx = nil
    for idx, l in ipairs(initial) do
      if l:match("^  ─") then rule_idx = idx - 1; break end
    end
    if rule_idx then
      pcall(vim.api.nvim_buf_add_highlight, buf, nns, "NeoworkIdxRule", rule_idx, 0, -1)
    end
  end

  place_cursor_first_blank(buf, win, sections)
  vim.cmd("startinsert")

  local state = {
    buf = buf,
    win = win,
    alive = true,
    persistent = persistent,
    sections = sections,
    alt_buf = alt_buf,
    opts = opts,
    window_opts = window_opts,
    droid = droid,
    busy = false,
  }
  if persistent and key and droid then
    state_by_droid[key] = state
    lifecycle.set_composer_persistent(droid, true)
    lifecycle.set_discussion_phase(droid, lifecycle.discussion.composing)
  end

  local group = vim.api.nvim_create_augroup("nowork_compose_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function() render_dashboard(state) end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function() 
      if vim.api.nvim_get_current_buf() == buf then
        render_dashboard(state) 
      end
    end,
  })
  render_dashboard(state)

  local function close()
    if not state.alive then return end
    state.alive = false
    if vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
    if key and state_by_droid[key] == state then
      state_by_droid[key] = nil
    end
    if persistent and droid then
      lifecycle.set_composer_persistent(droid, false)
      lifecycle.set_discussion_phase(droid, lifecycle.discussion.closed)
    end
    if opts.on_close then pcall(opts.on_close) end
  end

  local function reseed(prefill, raw)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    set_buffer_body(state.buf, build_scaffold(droid, { sections = state.sections, prefill = prefill, raw = raw, label = opts.label }), true)
    state.busy = false
    if droid then lifecycle.set_discussion_phase(droid, lifecycle.discussion.composing) end
    refresh_window_chrome(state)
    place_cursor_first_blank(state.buf, state.win, state.sections)
  end

  state.reseed = reseed
  state.close = close

  local function mark_busy(label)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    state.busy = true
    if droid then lifecycle.set_discussion_phase(droid, lifecycle.discussion.sending) end
    set_buffer_body(state.buf, { "## " .. (label or "sending…"), "", "(waiting for agent reply)" }, false)
  end

  state.mark_busy = mark_busy

  local function submit()
    if state.busy then return end
    local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    local text = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
      vim.notify("nowork: empty message", vim.log.levels.WARN)
      return
    end
    if droid and text == "clear" then
      text = "/clear"
    end
    if text:match("^/mul%s") then
      local isolate = text:match("^/mul%s+%-%-isolate")
      local prompt = text:gsub("^/mul%s+%-?%-?%w*%s*", "")
      local expanded = require("djinni.nowork.expand").expand(prompt, { alt_buf = state.alt_buf })
      require("djinni.nowork").multitask(expanded, { 
        cwd = droid and droid.opts and droid.opts.cwd,
        isolate = isolate ~= nil
      })
      close()
      return
    end
    local expanded = require("djinni.nowork.expand").expand(text, { alt_buf = state.alt_buf })

    if persistent then
      mark_busy("sending…")
      vim.schedule(function()
        if opts.on_submit then
          opts.on_submit(expanded)
        else
          local droid_mod = require("djinni.nowork.droid")
          droid_mod.send(droid, expanded)
        end
      end)
    else
      close()
      vim.schedule(function()
        if opts.on_submit then
          opts.on_submit(expanded)
        else
          local droid_mod = require("djinni.nowork.droid")
          droid_mod.send(droid, expanded)
        end
      end)
    end
  end

  local function insert_token(token)
    if state.busy then return end
    local mode = vim.api.nvim_get_mode().mode
    if mode == "i" then
      vim.api.nvim_feedkeys(token, "n", false)
    else
      local pos = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_buf_get_lines(state.buf, pos[1] - 1, pos[1], false)[1] or ""
      local new_line = line:sub(1, pos[2]) .. token .. line:sub(pos[2] + 1)
      vim.bo[state.buf].modifiable = true
      vim.api.nvim_buf_set_lines(state.buf, pos[1] - 1, pos[1], false, { new_line })
      vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + #token })
    end
  end

  local function new_empty()
    reseed(nil, nil)
  end

  local function switch_local_policy()
    if not droid then
      vim.notify("nowork: compose is not attached to a droid", vim.log.levels.WARN)
      return
    end
    mode_switch.select(droid, {
      prompt = "switch local policy",
      after_switch = function()
        refresh_window_chrome(state)
      end,
    })
  end

  local function switch_acp_mode()
    if not droid then
      vim.notify("nowork: compose is not attached to a droid", vim.log.levels.WARN)
      return
    end
    require("djinni.nowork.acp_mode").pick(droid)
  end

  local function switch_model()
    if not droid then
      vim.notify("nowork: compose is not attached to a droid", vim.log.levels.WARN)
      return
    end
    require("djinni.nowork.model_picker").pick(droid)
  end

  local km = { buffer = buf, nowait = true }
  vim.keymap.set({ "n", "i" }, "<C-CR>", submit, km)
  vim.keymap.set({ "n", "i" }, "<S-Tab>", switch_acp_mode, km)
  vim.keymap.set({ "n", "i" }, "<C-l>", switch_model, km)
  vim.keymap.set({ "n", "i" }, "<C-c>", close, km)
  vim.keymap.set({ "n", "i" }, "<C-s>", switch_local_policy, km)
  vim.keymap.set("n", ".", function()
    if droid then require("djinni.nowork.picker").run_action(droid) end
  end, km)
  vim.keymap.set("n", "Q", function()
    if droid then require("djinni.nowork.qfix_share").populate(droid) end
  end, km)
  vim.keymap.set("n", "R", function()
    if droid then require("djinni.nowork.droid").restart(droid) end
  end, km)
  vim.keymap.set({ "n", "i" }, "<C-q>", function() insert_token("#{qflist}") end, km)
  vim.keymap.set({ "n", "i" }, "<C-b>", function() insert_token("#{buffer}") end, km)
  vim.keymap.set({ "n", "i" }, "<C-d>", function() insert_token("#{diff}") end, km)
  vim.keymap.set({ "n", "i" }, "<C-n>", new_empty, km)
  vim.keymap.set("n", "q", close, km)
  vim.keymap.set("n", "<Esc>", close, km)
  vim.keymap.set("n", "?", function()
    local entries = {
      { key = "<C-CR>", desc = "send" },
      { key = "<S-Tab>", desc = "switch ACP mode (default/plan/accept_edits/…)" },
      { key = "<C-l>", desc = "switch ACP model (LLM)" },
      { key = ".", desc = "actions menu (cancel / done / populate / restart / …)" },
      { key = "Q", desc = "populate quickfix from this droid" },
      { key = "R", desc = "restart from saved state (after done/cancel)" },
      { key = "clear", desc = "send /clear to attached droid" },
      { key = "<C-s>", desc = "switch local policy (routine/autorun/explore)" },
      { key = "<C-q>", desc = "insert #{qflist}" },
      { key = "<C-b>", desc = "insert #{buffer}" },
      { key = "<C-d>", desc = "insert #{diff}" },
      { key = "<C-n>", desc = "new empty sections" },
      { key = "<C-c>", desc = "close" },
      { key = "q / <Esc>", desc = "close (normal mode)" },
      { key = "?",     desc = "this help" },
    }
    for _, cmd in ipairs(available_commands(droid)) do
      local name = command_name(cmd)
      if name and name ~= "" then
        entries[#entries + 1] = {
          key = "/" .. name,
          desc = cmd.description or "ACP slash command",
        }
      end
    end
    require("djinni.nowork.help").show("compose", entries)
  end, km)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      state.alive = false
      if key and state_by_droid[key] == state then
        state_by_droid[key] = nil
      end
      if persistent and droid then
        lifecycle.set_composer_persistent(droid, false)
        lifecycle.set_discussion_phase(droid, lifecycle.discussion.closed)
      end
    end,
  })
end

function M.reopen(droid, prefill, raw)
  local key = droid_key(droid)
  if not key then return false end
  local state = state_by_droid[key]
  if not state or not state.alive or not vim.api.nvim_buf_is_valid(state.buf) then
    return false
  end
  state.reseed(prefill, raw)
  return true
end

function M.close(droid)
  local key = droid_key(droid)
  if not key then return end
  local state = state_by_droid[key]
  if state and state.close then state.close() end
end

function M.is_open(droid)
  local key = droid_key(droid)
  if not key then return false end
  local state = state_by_droid[key]
  return state ~= nil and state.alive == true
end

function M.toggle(droid, opts)
  if M.is_open(droid) then
    M.close(droid)
    return false
  end
  M.open(droid, opts)
  return true
end

function M.droid_for_buf(buf)
  if not buf then return nil end
  for _, state in pairs(state_by_droid) do
    if state and state.buf == buf and state.alive ~= false then
      return state.droid
    end
  end
  return nil
end

return M
