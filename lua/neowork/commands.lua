local M = {}

M._setup = {}

local function send(buf, text)
  local document = require("neowork.document")
  local bridge = require("neowork.bridge")
  text = text and vim.trim(text) or ""
  if text == "" then
    document.ensure_composer(buf)
    text = document.get_compose_text(buf)
    if not text or text == "" then
      vim.notify("neowork: compose area is empty", vim.log.levels.WARN)
      return
    end
    document.clear_compose(buf)
  end
  document.insert_turn(buf, "You", text)
  bridge.send(buf, text)
end

local function mode_names(buf)
  local bridge = require("neowork.bridge")
  local modes = (bridge._modes or {})[buf]
  local out = {}
  if modes and modes.available then
    for _, m in ipairs(modes.available) do out[#out + 1] = m.name or m.id end
  end
  return out
end

local function set_mode_by_name(buf, name)
  local bridge = require("neowork.bridge")
  local modes = (bridge._modes or {})[buf]
  if not modes or not modes.available then
    vim.notify("neowork: agent has not reported modes yet", vim.log.levels.WARN)
    return
  end
  for _, m in ipairs(modes.available) do
    if m.id == name or m.name == name then
      if bridge.set_mode_id then bridge.set_mode_id(buf, m.id) end
      return
    end
  end
  vim.notify("neowork: unknown mode " .. tostring(name), vim.log.levels.WARN)
end

M.open_help = function()
  local lines = {
    "Neowork — Commands",
    "",
    ":NwSend [text]        Send (or <CR> in normal mode)",
    ":NwClear[!]           Clear session (! also purges transcript)",
    ":NwSummary [text]     Set / clear session summary",
    ":NwPlan               Toggle plan view",
    ":NwMode [name]        Cycle / set mode (<Tab> completes)  [<S-Tab>]",
    ":NwModel              Pick model (vim.ui.select)           [gM]",
    ":NwProvider           Switch provider                      [gP]",
    ":NwNew [name]         New session",
    ":NwRestart           Kill client process and start fresh session  [gR, /restart]",
    ":NwInterrupt          Interrupt current turn",
    ":NwFork               Fork conversation at cursor",
    ":NwCompact            Compact old turns",
    ":NwTranscript[!]      Transcript (! = full); honors <mods>",
    ":NwSchedule           Configure scheduled Ex command",
    ":NwScheduleToggle     Enable / disable schedule",
    ":NwScheduleRun        Run scheduled command now",
    ":NwScheduleClear      Clear schedule metadata",
    ":NwPerm {allow|deny|always|select}",
    ":NwHelp               This help",
    "",
    "Navigation",
    "",
    "]]  [[                Next / previous turn",
    "a@  i@                Turn text-objects (e.g. da@, ci@, yi@)",
    "G                     Tail + auto-scroll",
    "<CR>                  Send compose area",
    "<C-s> / <C-CR>        Send from insert mode",
    "<C-c>                 Interrupt",
    "r (on role line)      Fork at cursor",
    "",
    "Press q or <Esc> to close.",
  }
  vim.cmd("keepalt botright " .. #lines .. "split")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "help"
  vim.bo[buf].modifiable = false
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.wrap = false
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<cmd>close<cr>", { buffer = buf, silent = true, nowait = true })
  end
end

function M.setup(buf)
  if M._setup[buf] then return end
  M._setup[buf] = true

  local function cmd(name, fn, opts)
    opts = opts or {}
    vim.api.nvim_buf_create_user_command(buf, name, function(args)
      fn(args)
    end, opts)
  end

  cmd("NwSend", function(a) send(buf, a.args) end, { nargs = "*" })

  cmd("NwSendFresh", function(a)
    local document = require("neowork.document")
    local bridge = require("neowork.bridge")
    local text = a.args and vim.trim(a.args) or ""
    if text == "" then
      document.ensure_composer(buf)
      text = document.get_compose_text(buf)
    end
    document.insert_turn(buf, "You", text)
    bridge.send_fresh(buf, text)
  end, { nargs = "*" })

  cmd("NwRestart", function() require("neowork.bridge").restart(buf) end, {})

  cmd("NwClear", function(a)
    require("neowork.document").clear(buf, { purge_transcript = a.bang })
    vim.notify("neowork: cleared" .. (a.bang and " (+transcript)" or ""), vim.log.levels.INFO)
  end, { bang = true })

  cmd("NwSummary", function(a)
    require("neowork.summary").set(buf, vim.trim(a.args or ""))
  end, { nargs = "*" })

  cmd("NwPlan", function() require("neowork.plan").toggle(buf) end, {})

  cmd("NwMode", function(a)
    local bridge = require("neowork.bridge")
    local name = vim.trim(a.args or "")
    if name == "" then
      bridge.set_mode(buf)
    else
      set_mode_by_name(buf, name)
    end
  end, {
    nargs = "?",
    complete = function(lead) return vim.tbl_filter(function(n) return vim.startswith(n, lead) end, mode_names(buf)) end,
  })

  cmd("NwProvider", function() require("neowork.bridge").switch_provider(buf) end, {})

  cmd("NwModel", function() require("neowork.bridge").switch_model(buf) end, {})

  cmd("NwNew", function(a)
    local document = require("neowork.document")
    local root = document.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
    require("neowork.util").new_session_interactive(root, {
      name = a.args,
      prompt = "New session name: ",
    }, function(filepath)
      if filepath then document.open(filepath, { split = "edit" }) end
    end)
  end, { nargs = "?" })

  cmd("NwInterrupt", function() require("neowork.bridge").interrupt(buf) end, {})

  cmd("NwFork", function() require("neowork.document").fork_at_cursor(buf) end, {})

  cmd("NwCompact", function() require("neowork.document").compact(buf) end, {})

  cmd("NwTranscript", function(a)
    local t = require("neowork.transcript")
    if a.bang then
      t.open_full(buf, { mods = a.mods })
    else
      t.open(buf, { mods = a.mods })
    end
  end, { bang = true })

  cmd("NwSchedule", function()
    local document = require("neowork.document")
    local scheduler = require("neowork.scheduler")
    local current_interval = document.read_frontmatter_field(buf, "schedule_interval") or ""
    local current_command = document.read_frontmatter_field(buf, "schedule_command") or ""
    vim.ui.input({ prompt = "Schedule interval (e.g. 30m, 1h, 1d): ", default = current_interval }, function(interval)
      if not interval or vim.trim(interval) == "" then return end
      vim.ui.input({ prompt = "Schedule Ex command: ", default = current_command }, function(command)
        if not command or vim.trim(command) == "" then return end
        local ok, err = scheduler.enable(buf, interval, command)
        if ok then
          vim.notify("neowork: schedule enabled", vim.log.levels.INFO)
        else
          vim.notify("neowork: " .. tostring(err), vim.log.levels.ERROR)
        end
      end)
    end)
  end, {})

  cmd("NwScheduleToggle", function()
    local document = require("neowork.document")
    local scheduler = require("neowork.scheduler")
    local enabled = document.read_frontmatter_field(buf, "schedule_enabled") == "true"
    local ok, err
    if enabled then
      ok, err = scheduler.disable(buf)
      if ok then
        vim.notify("neowork: schedule disabled", vim.log.levels.INFO)
      end
    else
      local interval = document.read_frontmatter_field(buf, "schedule_interval") or ""
      local command = document.read_frontmatter_field(buf, "schedule_command") or ""
      ok, err = scheduler.enable(buf, interval, command)
      if ok then
        vim.notify("neowork: schedule enabled", vim.log.levels.INFO)
      end
    end
    if not ok then
      vim.notify("neowork: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, {})

  cmd("NwScheduleRun", function()
    local scheduler = require("neowork.scheduler")
    local ok, err = scheduler.run_now(buf)
    if ok then
      vim.notify("neowork: schedule ran", vim.log.levels.INFO)
    else
      vim.notify("neowork: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, {})

  cmd("NwScheduleClear", function()
    require("neowork.scheduler").clear(buf)
    vim.notify("neowork: schedule cleared", vim.log.levels.INFO)
  end, {})

  cmd("NwPerm", function(a)
    local action = vim.trim(a.args or "")
    if action == "" then action = "select" end
    require("neowork.bridge").permission_action(buf, action)
  end, {
    nargs = "?",
    complete = function(lead)
      return vim.tbl_filter(function(n) return vim.startswith(n, lead) end, { "allow", "deny", "always", "select" })
    end,
  })

  cmd("NwHelp", function() M.open_help() end, {})

  cmd("NwModeInfo", function()
    local bridge = require("neowork.bridge")
    local document = require("neowork.document")
    local provider_name = document.read_frontmatter_field(buf, "provider") or require("neowork.config").get("provider")
    local sid = bridge._sessions[buf]
    local m = bridge._modes[buf] or {}
    local available = m.available or {}
    local lines = {
      "provider: " .. tostring(provider_name),
      "session:  " .. tostring(sid),
      "streaming:" .. tostring(bridge._streaming[buf] == true),
      "current:  " .. tostring(m.current_id),
      "available (" .. #available .. "):",
    }
    for _, mode in ipairs(available) do
      lines[#lines + 1] = "  - " .. tostring(mode.id) .. " (" .. tostring(mode.name) .. ")"
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, {})
end

function M.detach(buf) M._setup[buf] = nil end

return M
