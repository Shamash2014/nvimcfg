local M = {}

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

local function acp_prompt(cwd)
  return "[" .. require("acp.agents").current_model_label(cwd) .. "] ACP: "
end

local function make_prompt(text)
  local items = require("acp.workbench").drain_context()
  table.insert(items, { type = "text", text = text })
  return items
end

local function send(cwd, prompt)
  require("acp.session").get_or_create(cwd, function(err, sess)
    if err then vim.notify(err, vim.log.levels.ERROR, { title = "acp" }); return end
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
  end)
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
  require("acp.agents").choose_provider(cwd or vim.fn.getcwd())
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
  local sess = require("acp.session").find_ready_for_cwd(cwd)
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
    local provider = require("acp.agents").provider_label(cwd)
    vim.notify(provider .. "/" .. (next_opt.name or next_opt.value), vim.log.levels.INFO, { title = "acp" })
    vim.schedule(function()
      require("acp.workbench").render()
    end)
  end)
end

-- Picker over the live session's model options. If no session exists yet, creates one first.
function M.pick_model(cwd, on_done)
  cwd = cwd or vim.fn.getcwd()
  local function show_picker(sess)
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
        table.insert(items,  { opt_id = opt.id, value = o.value, opt_name = opt.name })
        table.insert(labels, (o.name or o.value) .. (is_current and "  ✓" or ""))
      end
    end

    local function on_choice(_, idx)
      if not idx then return end
      local item = items[idx]
      require("acp.agents").set_model_for_key(sess.key, item.value)
      require("acp.session").set_config_option(sess.key, item.opt_id, item.value, function(err)
        if err then
          vim.notify("set model failed: " .. vim.inspect(err), vim.log.levels.ERROR, { title = "acp" }); return
        end
        local provider = require("acp.agents").provider_label(cwd)
        vim.notify(provider .. "/" .. item.value, vim.log.levels.INFO, { title = "acp" })
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

  local existing = require("acp.session").find_ready_for_cwd(cwd)
  if existing then
    show_picker(existing)
  else
    require("acp.session").get_or_create(cwd, function(err, sess)
      if err then vim.notify(err, vim.log.levels.ERROR, { title = "acp" }); return end
      show_picker(sess)
    end)
  end
end

function M.trigger_op(lines, source)
  local cwd = vim.fn.getcwd()
  snacks_input(acp_prompt(cwd), function(instruction)
    if not instruction or instruction == "" then return end
    send(cwd, make_prompt(source .. "\n\n" .. table.concat(lines, "\n")
                          .. "\n\nInstruction: " .. instruction))
  end)
end

function M.trigger_visual()
  vim.schedule(function()
    local l1 = vim.fn.line("'<"); local l2 = vim.fn.line("'>")
    M.trigger_op(
      vim.api.nvim_buf_get_lines(0, l1-1, l2, false),
      vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.") .. ":" .. l1 .. "-" .. l2
    )
  end)
end

function M.trigger_codebase()
  local cwd = vim.fn.getcwd()
  snacks_input(acp_prompt(cwd), function(instruction)
    if not instruction or instruction == "" then return end
    send(cwd, make_prompt("cwd: " .. cwd .. "\n\nInstruction: " .. instruction
      .. "\n\nExplore the codebase using your tools."))
  end)
end

return M
