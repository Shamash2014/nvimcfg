local lifecycle = require("djinni.nowork.state")
local mode_switch = require("djinni.nowork.mode_switch")
local compose_chrome = require("djinni.nowork.compose_chrome")

local M = {}

local DEFAULT_SECTIONS = {}
local ROUTINE_CHAT_TITLE = " routine chat — <C-CR> send · <C-n> new · <C-c> close "
local FOOTER_BASE = " <C-CR> send · <S-Tab> ACP mode · <C-l> model · <C-s> local policy · . actions · Q populate · R restart · clear→/clear · <C-q> qflist · <C-b> buffer · <C-d> diff · <C-n> new · <C-c> close "

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

  -- Sections (metadata moved to winbar)
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

local function resolve_window_opts(opts)
  local settings = {}
  local ok, nowork = pcall(require, "djinni.nowork")
  if ok and nowork and nowork.config and nowork.config.compose then
    settings = nowork.config.compose
  end
  return vim.tbl_deep_extend("force", {
    floating = true,
    width = math.floor(vim.o.columns * 0.40),
    height = math.floor(vim.o.lines * 0.40),
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
      footer = " ",
      footer_pos = "left",
    })
  end
  apply_window_local_opts(win)
  return win, opts
end

local function render_chrome(state)
  if not state.alive then return end
  if state.window_opts.floating == false then return end
  local win = state.win
  if not vim.api.nvim_win_is_valid(win) then return end

  local droid = state.droid
  local iso = (droid and droid.opts and droid.opts.isolate) and "on" or "off"
  local provider = (droid and droid.provider_name) or "claude"

  local chunks = {
    { " args ", "Comment" },
    { "-i ", "Comment" },
    { iso, iso == "on" and "NoworkQfEdit" or "Comment" },
    { "  -p ", "Comment" },
    { provider, "NoworkQfReview" },
    { "   ·   ", "Comment" },
    { "^CR send · ^C close · ? help", "Comment" },
  }

  if droid and droid._plan_path then
    local basename = vim.fn.fnamemodify(droid._plan_path, ":t")
    chunks[#chunks + 1] = { "  ·  plan: ", "Comment" }
    chunks[#chunks + 1] = { basename .. " ", "NeogitGraphAuthor" }
  else
    chunks[#chunks + 1] = { " ", "Comment" }
  end

  local cfg = vim.api.nvim_win_get_config(win)
  cfg.footer = chunks
  cfg.footer_pos = "left"
  pcall(vim.api.nvim_win_set_config, win, cfg)
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
  render_chrome(state)
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

function M.open(droid, opts)
  opts = opts or {}
  if droid then
    if opts.persistent == nil then opts.persistent = true end
    if opts.on_submit == nil then
      opts.on_submit = function(text) require("djinni.nowork.droid").send(droid, text) end
    end
    if opts.alt_buf == nil then opts.alt_buf = vim.fn.bufnr("#") end
    if opts.sections == nil then opts.sections = {} end
    if opts.title == nil and droid.mode == "planner" and droid._plan_path then
      opts.title = " planner · plan: " .. vim.fn.fnamemodify(droid._plan_path, ":t") .. " "
    elseif opts.title == nil and droid.mode == "routine" then
      opts.title = " routine · " .. (droid.id and ("[" .. tostring(droid.id) .. "]") or "") .. " "
    end
  end
  local alt_buf = opts.alt_buf or vim.fn.bufnr("#")
  local sections = opts.sections or DEFAULT_SECTIONS
  local persistent = opts.persistent == true
  local key = droid_key(droid)

  if persistent and key and state_by_droid[key] then
    local s = state_by_droid[key]
    if s.alive and vim.api.nvim_win_is_valid(s.win) then
      vim.api.nvim_set_current_win(s.win)
      vim.cmd("startinsert")
      return s
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
  local win, window_opts = open_window(buf, title, nil, opts.window or opts.compose)

  if window_opts.floating == false then
    local label_w = opts.label or (droid and droid.mode) or "compose"
    local scope_w = opts.cwd or (droid and droid.opts and droid.opts.cwd) or vim.fn.getcwd()
    local parts = { "%#NeogitSectionHeader# " .. label_w .. " " }
    if scope_w and scope_w ~= "" then
      parts[#parts + 1] = "%#Comment# · " .. vim.fn.fnamemodify(scope_w, ":~")
    end
    if droid and droid.id then
      parts[#parts + 1] = "%#Comment# · " .. tostring(droid.id):sub(1, 8)
    end
    pcall(function() vim.wo[win].winbar = table.concat(parts, "") end)
  end

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

  local non_floating = window_opts.floating == false

  if non_floating then
    compose_chrome.apply_highlights()
    compose_chrome.apply_neogit_chrome(buf, win)
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
    callback = function() render_chrome(state) end,
  })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      if not state.alive or not vim.api.nvim_win_is_valid(state.win) then return end
      if state.window_opts.floating ~= false then
        local user_width = (opts.window and opts.window.width)
          or (require("djinni.nowork").config and require("djinni.nowork").config.compose and require("djinni.nowork").config.compose.width)
        local user_height = (opts.window and opts.window.height)
          or (require("djinni.nowork").config and require("djinni.nowork").config.compose and require("djinni.nowork").config.compose.height)
        local width = user_width or math.floor(vim.o.columns * 0.80)
        local height = user_height or math.floor(vim.o.lines * 0.80)
        local row = math.floor((vim.o.lines - height) / 2) - 1
        local col = math.floor((vim.o.columns - width) / 2)
        local cfg = vim.api.nvim_win_get_config(state.win)
        cfg.row, cfg.col, cfg.width, cfg.height = row, col, width, height
        pcall(vim.api.nvim_win_set_config, state.win, cfg)
        state.window_opts.width, state.window_opts.height = width, height
      end
      render_chrome(state)
    end,
  })
  render_chrome(state)

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
    if opts.on_close then pcall(opts.on_close, state.last_action) end
  end

  local function reseed(prefill, raw)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    set_buffer_body(state.buf, build_scaffold(droid, { sections = state.sections, prefill = prefill, raw = raw, label = opts.label }), true)
    state.busy = false
    if droid then lifecycle.set_discussion_phase(droid, lifecycle.discussion.composing) end
    refresh_window_chrome(state)
    if non_floating then compose_chrome.apply_section_overlay(state.buf) end
    place_cursor_first_blank(state.buf, state.win, state.sections)
  end

  state.reseed = reseed
  state.close = close

  local saved_body = nil

  local function mark_busy(label)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    saved_body = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    state.busy = true
    if droid then lifecycle.set_discussion_phase(droid, lifecycle.discussion.sending) end
    set_buffer_body(state.buf, { "## " .. (label or "sending…"), "", "(waiting for agent reply)" }, false)
    if non_floating then compose_chrome.apply_section_overlay(state.buf) end
  end

  local function release(new_body)
    if not state.alive or not vim.api.nvim_buf_is_valid(state.buf) then return end
    state.busy = false
    if droid then lifecycle.set_discussion_phase(droid, lifecycle.discussion.composing) end
    local lines
    if new_body and new_body ~= "" then
      lines = vim.split(new_body, "\n", { plain = true })
    elseif saved_body then
      lines = saved_body
    else
      lines = { "" }
    end
    set_buffer_body(state.buf, lines, true)
    saved_body = nil
    refresh_window_chrome(state)
    if non_floating then compose_chrome.apply_section_overlay(state.buf) end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      pcall(vim.api.nvim_win_set_cursor, state.win, { #lines, #(lines[#lines] or "") })
    end
  end

  state.mark_busy = mark_busy
  state.release = release

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
  state.insert_token = insert_token

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

  local function peek_plan()
    if not droid or not droid._plan_path then
      vim.notify("nowork: no plan attached", vim.log.levels.WARN)
      return
    end
    if vim.fn.filereadable(droid._plan_path) ~= 1 then
      vim.notify("nowork: plan file unreadable: " .. droid._plan_path, vim.log.levels.WARN)
      return
    end
    local plans = require("djinni.nowork.plans")
    local body = plans.read(droid._plan_path) or ""
    local lines = vim.split(body, "\n", { plain = true })
    local pbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[pbuf].buftype = "nofile"
    vim.bo[pbuf].bufhidden = "wipe"
    vim.bo[pbuf].swapfile = false
    vim.bo[pbuf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
    vim.bo[pbuf].modifiable = false
    vim.bo[pbuf].readonly = true
    local pwidth = math.floor(vim.o.columns * 0.70)
    local pheight = math.floor(vim.o.lines * 0.70)
    local prow = math.floor((vim.o.lines - pheight) / 2) - 1
    local pcol = math.floor((vim.o.columns - pwidth) / 2)
    local pwin = vim.api.nvim_open_win(pbuf, true, {
      relative = "editor",
      row = prow,
      col = pcol,
      width = pwidth,
      height = pheight,
      style = "minimal",
      border = "rounded",
      title = " plan: " .. vim.fn.fnamemodify(droid._plan_path, ":t") .. " ",
      title_pos = "center",
    })
    vim.wo[pwin].wrap = true
    vim.wo[pwin].linebreak = true
    local close_peek = function()
      if vim.api.nvim_win_is_valid(pwin) then
        vim.api.nvim_win_close(pwin, true)
      end
    end
    local pkm = { buffer = pbuf, nowait = true }
    vim.keymap.set("n", "q", close_peek, pkm)
    vim.keymap.set("n", "<Esc>", close_peek, pkm)
    vim.keymap.set("n", "<C-c>", close_peek, pkm)
    vim.keymap.set("n", "<C-p>", close_peek, pkm)
  end

  local km = { buffer = buf, nowait = true }
  vim.keymap.set({ "n", "i" }, "<C-CR>", submit, km)
  if non_floating then
    vim.keymap.set("n", "<Tab>", function() compose_chrome.toggle_section_fold(buf) end, km)
  end
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
  vim.keymap.set({ "n", "i" }, "<C-p>", peek_plan, km)
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
      { key = "<C-p>", desc = "peek plan (read-only)" },
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

  return state
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

function M.has_open()
  for _, state in pairs(state_by_droid) do
    if state and state.alive == true and vim.api.nvim_buf_is_valid(state.buf) then
      return true
    end
  end
  return false
end

function M.append_text(text, opts)
  opts = opts or {}
  local target
  if opts.droid then
    local key = nil
    for k, state in pairs(state_by_droid) do
      if state and state.droid == opts.droid then key = k; break end
    end
    if key then target = state_by_droid[key] end
  end
  if not target then
    for _, state in pairs(state_by_droid) do
      if state and state.alive == true and vim.api.nvim_buf_is_valid(state.buf) then
        target = state
        break
      end
    end
  end
  if not target or not target.alive or not vim.api.nvim_buf_is_valid(target.buf) or not target.insert_token then
    return false
  end

  if target.win and vim.api.nvim_win_is_valid(target.win) then
    vim.api.nvim_set_current_win(target.win)
  end

  local line_count = vim.api.nvim_buf_line_count(target.buf)
  local last_line = vim.api.nvim_buf_get_lines(target.buf, line_count - 1, line_count, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { line_count, #last_line })

  local prefix = ""
  if last_line ~= "" then
    prefix = "\n\n"
  end
  target.insert_token(prefix .. (text or ""))
  return true
end

return M
