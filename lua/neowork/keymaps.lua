local M = {}

M._keymaps_set = M._keymaps_set or {}

function M.detach(buf)
  M._keymaps_set[buf] = nil
end

local slash_commands = {
  clear = function(buf, args)
    local purge = args == "purge"
    require("neowork.document").clear(buf, { purge_transcript = purge })
    vim.notify("neowork: cleared" .. (purge and " (+transcript)" or ""), vim.log.levels.INFO)
  end,
  summary = function(buf, args)
    local text = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    require("neowork.summary").set(buf, text)
    vim.notify("neowork: summary " .. (text == "" and "cleared" or "set"), vim.log.levels.INFO)
  end,
  plan = function(buf)
    require("neowork.plan").toggle(buf)
  end,
}

function M.setup_document_keymaps(buf)
  if M._keymaps_set[buf] then return end
  M._keymaps_set[buf] = true
  local document = require("neowork.document")

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = "neowork: " .. desc })
  end

  local function do_send()
    document.ensure_composer(buf)
    local text = document.get_compose_text(buf)
    if not text or text == "" then
      vim.notify("neowork: compose area is empty", vim.log.levels.WARN)
      return
    end
    local name, args = text:match("^/(%S+)%s*(.-)%s*$")
    if name then
      document.clear_compose(buf)
      local handler = slash_commands[name]
      if handler then
        handler(buf, args or "")
      else
        vim.notify("neowork: unknown command /" .. name, vim.log.levels.WARN)
      end
      return
    end
    document.clear_compose(buf)
    document.insert_turn(buf, "You", text)
    require("neowork.bridge").send(buf, text)
  end

  local function do_send_from_insert()
    vim.cmd("stopinsert")
    vim.schedule(do_send)
  end

  map("n", "<CR>", do_send, "send")

  local util = require("neowork.util")
  map("n", "]]", function() util.jump_to_marker(buf, 1) end, "next turn")
  map("n", "[[", function() util.jump_to_marker(buf, -1) end, "previous turn")

  local function in_compose_area()
    local compose = document.find_compose_line(buf)
    if not compose then return false end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    return row >= compose
  end

  local function smart_insert(cmd)
    return function()
      if in_compose_area() then
        vim.cmd(cmd)
      else
        document.ensure_composer(buf)
        document.goto_compose(buf)
        vim.cmd(cmd == "startinsert!" and "startinsert!" or "startinsert")
      end
    end
  end

  map("n", "i", smart_insert("startinsert"), "insert")
  map("n", "a", smart_insert("startinsert!"), "append")
  map("n", "o", function()
    if in_compose_area() then
      vim.cmd("normal! o")
      vim.cmd("startinsert")
    else
      document.ensure_composer(buf)
      document.goto_compose(buf)
      vim.cmd("startinsert")
    end
  end, "open line")

  map("n", "G", function()
    local last = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(0, { last, 0 })
    require("neowork.stream")._auto_scroll[buf] = true
  end, "go to end")

  map("n", "<C-c>", function()
    require("neowork.bridge").interrupt(buf)
  end, "interrupt")

  map("n", "s", function()
    require("neowork.bridge").permission_action(buf, "select")
  end, "permission select")

  map("n", "ya", function()
    require("neowork.bridge").permission_action(buf, "allow")
  end, "permission allow")

  map("n", "yn", function()
    require("neowork.bridge").permission_action(buf, "deny")
  end, "permission deny")

  map("n", "yA", function()
    require("neowork.bridge").permission_action(buf, "always")
  end, "permission always")

  map("n", "gp", function()
    require("neowork.plan").toggle(buf)
  end, "toggle plan")

  map("n", "gt", function()
    require("neowork.transcript").open(buf)
  end, "show transcript (doc)")

  map("n", "gT", function()
    require("neowork.transcript").open_full(buf)
  end, "show full transcript (events)")

  map("n", "<leader>nt", function()
    require("neowork.transcript").open(buf, { split = "vsplit" })
  end, "show transcript (vsplit)")

  map("n", "<leader>nT", function()
    require("neowork.transcript").open_full(buf, { split = "vsplit" })
  end, "show full transcript (vsplit)")

  map("n", "gi", function()
    vim.ui.input({ prompt = "Quick message: " }, function(text)
      if text and text ~= "" then
        local document = require("neowork.document")
        document.insert_turn(buf, "You", text)
        require("neowork.bridge").send(buf, text)
      end
    end)
  end, "quick input")

  map("n", "gS", function()
    local current = require("neowork.summary").get(buf)
    vim.ui.input({ prompt = "Summary: ", default = current }, function(text)
      if text == nil then return end
      require("neowork.summary").set(buf, text)
    end)
  end, "edit summary")

  map("n", "gc", function()
    require("neowork.document").compact(buf)
  end, "compact")

  vim.keymap.set("n", "r", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    if line:match("^@You") or line:match("^@Djinni") then
      document.fork_at_cursor(buf)
    else
      vim.api.nvim_feedkeys("r", "n", false)
    end
  end, { buffer = buf, silent = true, nowait = true, desc = "neowork: fork on role line / replace char" })

  map("n", "gn", function()
    local document = require("neowork.document")
    local root = document.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
    vim.ui.input({ prompt = "New session name: " }, function(name)
      local filepath = require("neowork.util").new_session(root, name)
      if filepath then document.open(filepath, { split = "edit" }) end
    end)
  end, "new session")

  local function cycle_mode()
    local bridge = require("neowork.bridge")
    local modes = (bridge._modes or {})[buf]
    if not modes or not modes.available or #modes.available == 0 then
      vim.notify("neowork: agent has not reported modes yet", vim.log.levels.WARN)
      return
    end
    if #modes.available == 1 then
      local only = modes.available[1]
      vim.notify("neowork: only one mode available (" .. (only.name or only.id) .. ")", vim.log.levels.INFO)
      return
    end
    bridge.set_mode(buf)
  end

  map("n", "<S-Tab>", cycle_mode, "cycle mode")
  map("n", "gm",      cycle_mode, "cycle mode")

  map("n", "gM", function()
    local bridge = require("neowork.bridge")
    local modes = (bridge._modes or {})[buf]
    if not modes or not modes.available or #modes.available == 0 then
      vim.notify("neowork: no modes reported", vim.log.levels.WARN)
      return
    end
    local labels = {}
    for _, m in ipairs(modes.available) do labels[#labels + 1] = m.name or m.id end
    vim.ui.select(labels, { prompt = "Mode:" }, function(_, idx)
      if not idx then return end
      if bridge.set_mode_id then
        bridge.set_mode_id(buf, modes.available[idx].id)
      end
    end)
  end, "pick mode")

  map("n", "gP", function()
    require("neowork.bridge").switch_provider(buf)
  end, "switch provider")

  map("n", "q", function()
    vim.api.nvim_win_close(0, false)
  end, "close")

  map("n", "?", function()
    M._show_doc_help()
  end, "help")

  map("i", "<C-CR>", do_send_from_insert, "send from insert")
  map("i", "<S-CR>", do_send_from_insert, "send from insert")
  map("i", "<C-s>", do_send_from_insert, "send from insert")
end

function M._show_doc_help()
  local lines = {
    "Neowork Prompt Document",
    "",
    "<CR>     Send (normal mode)",
    "<C-s>    Send (insert mode)",
    "<S-CR>   Send (insert mode, terminal-dependent)",
    "<C-CR>   Send (insert mode, GUI only)",
    "]]       Next turn",
    "[[       Previous turn",
    "G        Go to end + auto-scroll",
    "<C-c>    Interrupt",
    "",
    "s        Permission: pick",
    "ya       Permission: allow",
    "yn       Permission: deny",
    "yA       Permission: always",
    "",
    "gi       Quick input",
    "gc       Compact old turns",
    "/clear   Clear session to pristine state (append 'purge' to delete transcript)",
    "gn       New session",
    "gt       Show transcript",
    "gp       Toggle plan",
    "gS       Edit summary",
    "gP       Switch provider",
    "gm       Cycle mode",
    "gM       Pick mode",
    "<S-Tab>  Cycle mode (terminal permitting)",
    "q        Close",
    "?        This help",
  }
  local helpbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(helpbuf, 0, -1, false, lines)
  vim.bo[helpbuf].modifiable = false
  vim.bo[helpbuf].bufhidden = "wipe"
  local width = 36
  local height = #lines
  local win = vim.api.nvim_open_win(helpbuf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Help ",
    title_pos = "center",
  })
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = helpbuf })
  end
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = helpbuf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end,
  })
end

return M
