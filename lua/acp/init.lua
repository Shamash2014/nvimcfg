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
end

-- Returns "provider/model-name" from live session configOptions, or just "provider"
local function current_label(cwd)
  local provider = require("acp.agents").provider_label(cwd)
  local opts     = require("acp.session").get_config_options(cwd)
  for _, opt in ipairs(opts) do
    if opt.category == "model" and opt.currentValue then
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

local function acp_prompt(cwd)
  return "[" .. current_label(cwd) .. "] ACP: "
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

function M.cancel(cwd)
  require("acp.session").close(cwd or vim.fn.getcwd())
  vim.notify("ACP session closed", vim.log.levels.INFO, { title = "acp" })
end

-- Cycle to next value of the model config option on the live session.
-- Falls through to mode option if no model option exists.
function M.cycle_model(cwd)
  cwd = cwd or vim.fn.getcwd()
  local sess_opts = require("acp.session").get_config_options(cwd)

  local target_opt
  for _, opt in ipairs(sess_opts) do
    if opt.category == "model" then target_opt = opt; break end
  end
  if not target_opt then
    for _, opt in ipairs(sess_opts) do
      if opt.category == "mode" then target_opt = opt; break end
    end
  end

  if not target_opt then
    vim.notify("No active session — send a prompt first", vim.log.levels.WARN, { title = "acp" }); return
  end

  local options = target_opt.options or {}
  if #options < 2 then return end

  local cur_idx = 1
  for i, o in ipairs(options) do
    if o.value == target_opt.currentValue then cur_idx = i; break end
  end
  local next_opt = options[(cur_idx % #options) + 1]

  require("acp.session").set_config_option(cwd, target_opt.id, next_opt.value, function(err)
    if err then return end
    local provider = require("acp.agents").provider_label(cwd)
    vim.notify(provider .. "/" .. (next_opt.name or next_opt.value), vim.log.levels.INFO, { title = "acp" })
  end)
end

-- Full picker over all configOptions (model, mode, thought_level, other) for the live session.
-- If no session exists yet, creates one first.
function M.pick_model(cwd)
  cwd = cwd or vim.fn.getcwd()
  local function show_picker(config_opts)
    if #config_opts == 0 then
      vim.notify("No config options from this provider", vim.log.levels.WARN, { title = "acp" }); return
    end

    local items, labels = {}, {}
    for _, opt in ipairs(config_opts) do
      for _, o in ipairs(opt.options or {}) do
        local is_current = o.value == opt.currentValue
        table.insert(items,  { opt_id = opt.id, value = o.value, opt_name = opt.name })
        table.insert(labels, (opt.name or opt.id) .. "  /  " .. (o.name or o.value)
                             .. (is_current and "  ✓" or ""))
      end
    end

    local function on_choice(_, idx)
      if not idx then return end
      local item = items[idx]
      require("acp.session").set_config_option(cwd, item.opt_id, item.value, function(err)
        if err then return end
        local provider = require("acp.agents").provider_label(cwd)
        vim.notify(provider .. "/" .. (item.value), vim.log.levels.INFO, { title = "acp" })
      end)
    end

    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.select(labels, { prompt = "ACP config:" }, on_choice)
    else
      vim.ui.select(labels, { prompt = "ACP config: " }, on_choice)
    end
  end

  local existing = require("acp.session").get_config_options(cwd)
  if #existing > 0 then
    show_picker(existing)
  else
    -- No session yet — create one to discover options
    require("acp.session").get_or_create(cwd, function(err, sess)
      if err then vim.notify(err, vim.log.levels.ERROR, { title = "acp" }); return end
      show_picker(sess.config_options or {})
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
