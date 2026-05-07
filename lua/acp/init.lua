local M = {}
local _active_key     = {}
local _session_counter = 0

function M.setup(opts)
  opts = opts or {}
  for _, p in ipairs(opts.providers or {}) do require("acp.agents").register(p) end

  vim.keymap.set("n", "<C-c>", function()
    if #require("acp.session").active() > 0 then M.cancel() end
  end, { desc = "Cancel ACP work" })

  _G._acp_op = function()
    local s = vim.api.nvim_buf_get_mark(0, "[")
    local e = vim.api.nvim_buf_get_mark(0, "]")
    M.trigger_op(
      vim.api.nvim_buf_get_lines(0, s[1]-1, e[1], false),
      vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.") .. ":" .. s[1] .. "-" .. e[1]
    )
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      pcall(function() require("acp.spinner").stop() end)
      pcall(function() require("acp.diff")._stop_all_timers() end)
      pcall(function() require("acp.workbench")._stop_all_timers() end)
      pcall(function() require("acp.neogit_workbench")._stop_all_timers() end)
      require("acp.session").close_all()
    end,
  })

  pcall(function() require("acp.neogit_workbench").setup_hl() end)
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      pcall(function() require("acp.neogit_workbench").setup_hl() end)
    end,
  })

  vim.opt.statusline = "%!v:lua.require'acp.statusline'.build()"

  vim.api.nvim_create_user_command("ACPLog", function()
    vim.cmd("tabnew " .. vim.fn.fnameescape(vim.fn.stdpath("cache") .. "/acp.log"))
    vim.bo.filetype = "log"
    vim.cmd("normal! G")
  end, { desc = "Open ACP log" })
end

local function sess_label(sess)
  if not sess then return "acp" end
  local provider = sess.provider or "acp"
  for _, opt in ipairs(sess.config_options or {}) do
    if (opt.category == "model" or opt.id == "model") and opt.currentValue then
      for _, o in ipairs(opt.options or {}) do
        if o.value == opt.currentValue then
          return provider .. "/" .. (o.name or opt.currentValue)
        end
      end
      return provider .. "/" .. opt.currentValue
    end
  end
  return provider
end

local function active_session_for(cwd)
  local session_mod = require("acp.session")
  local key = _active_key[cwd]
  if key then
    local s = session_mod.get(key)
    if s then return s end
    _active_key[cwd] = nil
  end
  local s = session_mod.find_ready_for_cwd(cwd)
  if s then _active_key[cwd] = s.key end
  return s
end

local function acp_prompt(cwd)
  return "[" .. sess_label(active_session_for(cwd)) .. "] ACP: "
end

local function make_prompt(cwd, text)
  local sess = active_session_for(cwd)
  local items = require("acp.workbench").drain_context(cwd, { sess = sess })
  table.insert(items, { type = "text", text = text })
  return items
end

local function dispatch_prompt(sess, prompt)
  sess.rpc:request("session/prompt", {
    sessionId = sess.session_id,
    prompt    = prompt,
  }, function(req_err, res)
    if req_err then
      vim.schedule(function()
        vim.notify("ACP: " .. vim.inspect(req_err), vim.log.levels.ERROR, { title = "acp" })
      end)
    elseif res and res.stopReason and res.stopReason ~= "end_turn" then
      vim.schedule(function()
        vim.notify("ACP: " .. res.stopReason, vim.log.levels.WARN, { title = "acp" })
      end)
    end
  end)
end

local function send(cwd, prompt)
  local sess = active_session_for(cwd)
  if sess then
    dispatch_prompt(sess, prompt)
  else
    require("acp.session").get_or_create(cwd, function(err, new_sess)
      if err then vim.notify(err, vim.log.levels.ERROR, { title = "acp" }); return end
      _active_key[cwd] = new_sess.key
      dispatch_prompt(new_sess, prompt)
    end)
  end
end

local function snacks_input(prompt, on_confirm)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.input then snacks.input({ prompt = prompt }, on_confirm)
  else vim.ui.input({ prompt = prompt }, on_confirm) end
end

function M.work_set()  require("acp.workbench").set() end
function M.workbench() require("acp.workbench").open() end
function M.mailbox()   require("acp.mailbox").open() end

function M.pick_provider(cwd)
  cwd = cwd or vim.fn.getcwd()
  local sess = active_session_for(cwd)
  require("acp.agents").choose_provider(cwd, function(err, picked)
    if err or not picked then return end
    _active_key[cwd] = nil
    M.pick_model(cwd)
  end, sess and { key = sess.key } or nil)
end

function M.cancel(cwd)
  cwd = cwd or vim.fn.getcwd()
  pcall(function() require("acp.spinner").stop() end)
  pcall(function() require("acp.diff").refresh_winbar() end)
  local diff = require("acp.diff")
  for _, entry in ipairs(diff.get_threads(cwd)) do
    if entry.thread and entry.thread._subscribed then
      diff.append_thread_msg(cwd, entry.file, entry.row, { role="system", type="info", text="--- canceled ---" })
    end
  end
  require("acp.session").cancel_for_cwd(cwd)
  vim.notify("ACP turn cancelled", vim.log.levels.INFO, { title = "acp" })
end

function M.cycle_model(cwd)
  cwd = cwd or vim.fn.getcwd()
  local sess = active_session_for(cwd)
  if not sess then
    vim.notify("No active session — send a prompt first", vim.log.levels.WARN, { title = "acp" }); return
  end

  local target_opt
  for _, opt in ipairs(sess.config_options) do
    if opt.category == "model" then target_opt = opt; break end
  end
  if not target_opt then
    for _, opt in ipairs(sess.config_options) do
      if opt.category == "mode" then target_opt = opt; break end
    end
  end

  if not target_opt then
    vim.notify("No model options for this session", vim.log.levels.WARN, { title = "acp" }); return
  end

  local options = target_opt.options or {}
  if #options < 2 then return end

  local cur_idx = 1
  for i, o in ipairs(options) do
    if o.value == target_opt.currentValue then cur_idx = i; break end
  end
  local next_opt = options[(cur_idx % #options) + 1]

  require("acp.session").set_config_option(sess.key, target_opt.id, next_opt.value, function(err)
    if err then
      vim.notify("set model failed: " .. vim.inspect(err), vim.log.levels.ERROR, { title = "acp" }); return
    end
    require("acp.agents").set_model_for_key(sess.key, next_opt.value)
    require("acp.agents").set_model_for_cwd(cwd, next_opt.value)
    vim.notify(sess_label(sess), vim.log.levels.INFO, { title = "acp" })
    vim.schedule(function()
      require("acp.workbench").render()
    end)
  end)
end

local function show_model_picker(sess, on_done)
  local model_opts = {}
  for _, opt in ipairs(sess.config_options or {}) do
    if opt.category == "model" or opt.id == "model" then
      table.insert(model_opts, opt)
    end
  end
  if #model_opts == 0 then
    vim.notify("No model options from this provider", vim.log.levels.WARN, { title = "acp" }); return
  end

  local items, labels = {}, {}
  for _, opt in ipairs(model_opts) do
    for _, o in ipairs(opt.options or {}) do
      local is_current = o.value == opt.currentValue
      table.insert(items,  { opt_id = opt.id, value = o.value })
      table.insert(labels, (o.name or o.value) .. (is_current and "  ✓" or ""))
    end
  end

  local function on_choice(_, idx)
    if not idx then return end
    local item = items[idx]
    require("acp.agents").set_model_for_key(sess.key, item.value)
    if sess.cwd then require("acp.agents").set_model_for_cwd(sess.cwd, item.value) end
    require("acp.session").set_config_option(sess.key, item.opt_id, item.value, function(err)
      if err then
        vim.notify("set model failed: " .. vim.inspect(err), vim.log.levels.ERROR, { title = "acp" }); return
      end
      vim.notify(sess_label(sess), vim.log.levels.INFO, { title = "acp" })
      if on_done then on_done() end
    end)
  end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker.select(labels, { prompt = "ACP model:" }, on_choice)
  else
    vim.ui.select(labels, { prompt = "ACP model: " }, on_choice)
  end
end

-- Picker over the live session's model options. If no session exists yet, creates one first.
function M.pick_model(cwd, on_done)
  cwd = cwd or vim.fn.getcwd()
  local existing = active_session_for(cwd)
  if existing then
    show_model_picker(existing, on_done)
  else
    require("acp.session").get_or_create(cwd, function(err, sess)
      if err then vim.notify(err, vim.log.levels.ERROR, { title = "acp" }); return end
      _active_key[cwd] = sess.key
      show_model_picker(sess, on_done)
    end)
  end
end

function M.add_session(cwd)
  cwd = cwd or vim.fn.getcwd()
  _session_counter = _session_counter + 1
  local key = cwd .. "::s" .. _session_counter
  require("acp.agents").choose_provider(cwd, function(err, picked)
    if err or not picked then return end
    require("acp.session").get_or_create({ cwd = cwd, key = key }, function(sess_err, sess)
      if sess_err then
        vim.notify(sess_err, vim.log.levels.ERROR, { title = "acp" }); return
      end
      _active_key[cwd] = sess.key
      show_model_picker(sess, nil)
    end)
  end, { key = key })
end

function M.select_session(cwd)
  cwd = cwd or vim.fn.getcwd()
  local all = require("acp.session").find_all_ready_for_cwd(cwd)
  if #all == 0 then
    vim.notify("No active sessions", vim.log.levels.WARN, { title = "acp" }); return
  end
  if #all == 1 then
    _active_key[cwd] = all[1].key
    vim.notify("Active: " .. sess_label(all[1]), vim.log.levels.INFO, { title = "acp" }); return
  end
  local labels = {}
  for _, s in ipairs(all) do
    local mark = (_active_key[cwd] == s.key) and "  ✓" or ""
    table.insert(labels, sess_label(s) .. mark)
  end
  local function on_choice(_, idx)
    if not idx then return end
    _active_key[cwd] = all[idx].key
    vim.notify("Active: " .. sess_label(all[idx]), vim.log.levels.INFO, { title = "acp" })
    vim.schedule(function() require("acp.workbench").render() end)
  end
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker.select(labels, { prompt = "Active session:" }, on_choice)
  else
    vim.ui.select(labels, { prompt = "Active session: " }, on_choice)
  end
end

function M.trigger_op(lines, source)
  local cwd = vim.fn.getcwd()
  snacks_input(acp_prompt(cwd), function(instruction)
    if not instruction or instruction == "" then return end
    send(cwd, make_prompt(cwd, source .. "\n\n" .. table.concat(lines, "\n")
                          .. "\n\nInstruction: " .. instruction))
  end)
end

function M.show_sessions()
  local all = require("acp.session").active()
  if #all == 0 then
    vim.notify("No active sessions", vim.log.levels.WARN, { title = "acp" })
    return
  end

  -- Try to get worktree info for each cwd
  local wt_mod = nil
  do local ok, m = pcall(require, "config.wt") wt_mod = m end

  local items = {}
  for _, sess in ipairs(all) do
    local name
    if wt_mod and wt_mod.available() then
      name = wt_mod.session_name(sess.cwd)
    else
      name = sess_label(sess)
    end

    local project = vim.fn.fnamemodify(sess.cwd, ":~")
    local branch = ""
    if wt_mod and wt_mod.available() then
      local b = wt_mod.current_branch(sess.cwd)
      branch = b ~= "" and (" " .. b) or ""
    end

    local model = ""
    for _, opt in ipairs(sess.config_options or {}) do
      if (opt.category == "model" or opt.id == "model") and opt.currentValue then
        for _, o in ipairs(opt.options or {}) do
          if o.value == opt.currentValue then
            model = (" [" .. (o.name or opt.currentValue) .. "]"):gsub("^%s+", "")
            break
          end
        end
        if model ~= "" then break end
      end
    end

    local is_active = (_active_key[sess.cwd] == sess.key)
    items[#items + 1] = {
      key   = sess.key,
      cwd   = sess.cwd,
      label = (is_active and "✓ " or "") .. name .. branch .. model .. "  |  " .. project,
    }
  end

  local function on_choice(_, idx)
    if not idx then return end
    _active_key[all[idx].cwd] = all[idx].key
    vim.notify("Active: " .. items[idx].label:gsub("^%s*(.-)%s*$", "%1"), vim.log.levels.INFO, { title = "acp" })
    vim.schedule(function() require("acp.workbench").render() end)
  end

  local labels = {}
  for _, it in ipairs(items) do table.insert(labels, it.label) end

  if wt_mod and wt_mod.available() then
    -- Also show available worktrees without active sessions
    wt_mod.list({ branches = true }, function(entries, err)
      if not entries then return end
      local cwds = {}
      for _, sess in ipairs(all) do cwds[sess.cwd] = true end

      local added = 0
      for _, e in ipairs(entries) do
        if e.path and e.kind == "worktree" and not cwds[e.path] then
          local label = ("wt:" .. (e.branch or "?")) .. "  |  " .. vim.fn.fnamemodify(e.path, ":~")
          added = added + 1
          items[#items + 1] = { key = nil, cwd = e.path, label = label, branch = e.branch }
        end
      end

      if added > 0 then
        labels = {}
        for _, it in ipairs(items) do table.insert(labels, it.label) end
        local ok2, sn = pcall(require, "snacks")
        if ok2 and sn.picker then
          sn.picker.select(labels, { prompt = "ACP AI Sessions (" .. #all .. ")" }, on_choice)
        else
          vim.ui.select(labels, { prompt = "ACP AI Sessions" }, on_choice)
        end
      else
        local ok3, sn = pcall(require, "snacks")
        if ok3 and sn.picker then
          sn.picker.select(labels, { prompt = "ACP AI Sessions (" .. #all .. ")" }, on_choice)
        else
          vim.ui.select(labels, { prompt = "ACP AI Sessions" }, on_choice)
        end
      end
    end)
  else
    local ok, sn = pcall(require, "snacks")
    if ok and sn.picker then
      sn.picker.select(labels, { prompt = "ACP AI Sessions (" .. #all .. ")" }, on_choice)
    else
      vim.ui.select(labels, { prompt = "ACP AI Sessions" }, on_choice)
    end
  end
end

return M
