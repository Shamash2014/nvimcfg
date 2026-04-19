local M = {}

M._keymaps_set = M._keymaps_set or {}
M._complete_fns = M._complete_fns or {}

function M._complete(findstart, base)
  local buf = vim.api.nvim_get_current_buf()
  local fn = M._complete_fns[buf]
  if type(fn) ~= "function" then
    return findstart == 1 and -3 or {}
  end
  return fn(findstart, base)
end

function M.detach(buf)
  M._keymaps_set[buf] = nil
  M._complete_fns[buf] = nil
end


function M.setup_document_keymaps(buf)
  if M._keymaps_set[buf] then return end
  M._keymaps_set[buf] = true
  local document = require("neowork.document")

  require("neowork.commands").setup(buf)
  require("neowork.textobjects").setup(buf)

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = "neowork: " .. desc })
  end

  local local_slash = {
    clear = function(args)
      document.clear_compose(buf)
      document.clear(buf, {
        purge_transcript = args and args:match("purge") ~= nil,
      })
    end,
    fork = function() document.fork_at_cursor(buf) end,
    new = function(args)
      local root = document.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
      require("neowork.util").new_session_interactive(root, {
        name = args,
        prompt = "New session name: ",
      }, function(fp)
        if fp then document.open(fp, { split = "edit" }) end
      end)
    end,
    restart = function() require("neowork.bridge").restart(buf) end,
    help = function() require("neowork.commands").open_help() end,
    ["?"] = function() require("neowork.commands").open_help() end,
  }

  local function agent_commands()
    local ok, stream = pcall(require, "neowork.stream")
    if not ok then return {} end
    return stream.get_available_commands(buf) or {}
  end

  local function slash_completion(findstart, base)
    if findstart == 1 then
      local line = vim.api.nvim_get_current_line()
      local col = vim.api.nvim_win_get_cursor(0)[2]
      local prefix = line:sub(1, col)
      local slash = prefix:find("/[%w%?%-_]*$")
      if not slash then return -3 end
      return slash - 1
    end
    local needle = base:gsub("^/", ""):lower()
    local items = {}
    local seen = {}
    for name, _ in pairs(local_slash) do
      local lname = name:lower()
      if lname:find(needle, 1, true) then
        items[#items + 1] = { word = "/" .. name, menu = "local", abbr = "/" .. name }
        seen[lname] = true
      end
    end
    for _, c in ipairs(agent_commands()) do
      local lname = (c.name or ""):lower()
      if lname ~= "" and not seen[lname] and lname:find(needle, 1, true) then
        items[#items + 1] = {
          word = "/" .. c.name,
          abbr = "/" .. c.name,
          menu = "agent",
          info = c.description or "",
        }
        seen[lname] = true
      end
    end
    table.sort(items, function(a, b) return a.word < b.word end)
    return items
  end

  M._complete_fns[buf] = slash_completion
  _G.__neowork_slash_complete = function(findstart, base)
    return M._complete(findstart, base)
  end
  vim.bo[buf].completefunc = "v:lua.__neowork_slash_complete"

  vim.keymap.set("i", "/", function()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    if col == 0 or line:sub(1, col):match("^%s*$") then
      return "/" .. vim.api.nvim_replace_termcodes("<C-x><C-u>", true, false, true)
    end
    return "/"
  end, { buffer = buf, expr = true, desc = "neowork: slash completion" })

  local function do_send()
    document.ensure_composer(buf)
    local text = document.get_compose_text(buf)
    if not text or text == "" then
      vim.notify("neowork: compose area is empty", vim.log.levels.WARN)
      return
    end

    local first_nl = text:find("\n", 1, true)
    local head = first_nl and text:sub(1, first_nl - 1) or text
    local name, args = head:match("^/([%w%?%-_]+)%s*(.-)%s*$")
    local lname = name and name:lower() or nil

    if lname and not first_nl and local_slash[lname] then
      local_slash[lname](args ~= "" and args or nil)
      return
    end

    document.commit_compose(buf)
    require("neowork.bridge").send(buf, text)
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
      vim.api.nvim_buf_call(buf, function() pcall(vim.cmd, "silent! write") end)
    end
  end

  local function do_send_from_insert()
    vim.cmd("stopinsert")
    vim.schedule(do_send)
  end

  map("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local ok, tool_row = pcall(require, "neowork.tool_row")
    if ok and tool_row.is_tool_row(buf, row - 1) then
      tool_row.preview_at_cursor(buf)
      return
    end
    do_send()
  end, "send / preview tool")

  map("n", "K", function()
    local ok, tool_row = pcall(require, "neowork.tool_row")
    if ok and tool_row.preview_at_cursor(buf) then return end
    vim.api.nvim_feedkeys("K", "n", false)
  end, "preview tool output")

  local util = require("neowork.util")
  map("n", "]]", function() util.jump_to_marker(buf, 1) end, "next turn")
  map("n", "[[", function() util.jump_to_marker(buf, -1) end, "previous turn")

  map("n", "gL", function() require("neowork.transcript").open_full(buf, { debug = true }) end, "full session log + debug")

  local function plan_section()
    return require("neowork.plan")._section_lines[buf]
  end

  map("n", "gp", function()
    local section = plan_section()
    if section then
      vim.api.nvim_win_set_cursor(0, { section.start + 1, 0 })
    else
      vim.cmd("NwPlan")
    end
  end, "jump to plan")

  local function jump_entry(direction)
    local section = plan_section()
    if not section then return end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(buf, section.start, section["end"], false)
    local target
    if direction > 0 then
      for i, l in ipairs(lines) do
        local abs = section.start + i
        if abs > row and l:match("^%- %[") then target = abs; break end
      end
    else
      for i, l in ipairs(lines) do
        local abs = section.start + i
        if abs < row and l:match("^%- %[") then target = abs end
      end
    end
    if target then vim.api.nvim_win_set_cursor(0, { target, 0 }) end
  end

  map("n", "]p", function() jump_entry(1) end, "next plan entry")
  map("n", "[p", function() jump_entry(-1) end, "previous plan entry")

  local function compose_bounds()
    document.ensure_composer(buf)
    local compose = document.find_compose_line(buf)
    if not compose then return nil, nil end
    local lc = vim.api.nvim_buf_line_count(buf)
    for i = compose, lc do
      local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
      if line == "---" then
        return compose, i
      end
    end
    return compose, lc + 1
  end

  local function in_compose_area()
    local compose, term_row = compose_bounds()
    if not compose or not term_row then return false end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    return row >= compose and row < term_row
  end

  local function focus_compose()
    local compose, term_row = compose_bounds()
    if not compose or not term_row then return end
    local target = math.max(compose, term_row - 1)
    local line = vim.api.nvim_buf_get_lines(buf, target - 1, target, false)[1] or ""
    vim.api.nvim_win_set_cursor(0, { target, #line })
    vim.cmd("startinsert!")
  end

  map("n", "o", function()
    if in_compose_area() then
      vim.cmd("normal! o")
      vim.cmd("startinsert")
    else
      focus_compose()
    end
  end, "open line (join compose if outside)")

  map("n", "<C-i>", focus_compose, "focus compose")

  map("n", "G", function()
    local last = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(0, { last, 0 })
    require("neowork.stream")._auto_scroll[buf] = true
  end, "go to end")

  local function interrupt() require("neowork.bridge").interrupt(buf) end
  map("n", "<C-c>", interrupt, "interrupt")
  map("i", "<C-c>", function() vim.cmd("stopinsert"); interrupt() end, "interrupt")

  local function on_role_line()
    local ast = require("neowork.ast")
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local role = ast.role_of_line(line)
    return role == "You" or role == "Djinni"
  end

  vim.keymap.set("n", "r", function()
    if on_role_line() then
      require("neowork.bridge").restart(buf)
    else
      vim.api.nvim_feedkeys("r", "n", false)
    end
  end, { buffer = buf, silent = true, nowait = true, desc = "neowork: restart on role line / replace char" })

  vim.keymap.set("n", "f", function()
    if on_role_line() then
      document.fork_at_cursor(buf)
    else
      vim.api.nvim_feedkeys("f", "n", false)
    end
  end, { buffer = buf, silent = true, nowait = true, desc = "neowork: fork on role line / find char" })

  map("n", "<Tab>", function()
    if not in_compose_area() then
      focus_compose()
      return
    end
    if vim.fn.foldclosed(".") ~= -1 then
      vim.cmd("normal! zo")
    elseif vim.fn.foldlevel(".") > 0 then
      vim.cmd("silent! normal! zc")
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false)
    end
  end, "toggle fold")
  map("n", "<S-Tab>", function() vim.cmd("NwMode") end, "cycle mode")
  map("n", "gM", function() vim.cmd("NwModel") end, "pick model")
  map("n", "gP", function() vim.cmd("NwProvider") end, "pick provider")
  map("n", "gR", function() vim.cmd("NwRestart") end, "restart session")
  map("n", "gA", function() require("djinni.automations").pick({ buf = buf }) end, "automations picker")

  map("n", "q", function()
    vim.api.nvim_win_close(0, false)
  end, "close")

  map("n", "?", function() vim.cmd("NwHelp") end, "help")

  map("i", "<C-CR>", do_send_from_insert, "send from insert")
  map("i", "<S-CR>", do_send_from_insert, "send from insert")
  map("i", "<C-s>", do_send_from_insert, "send from insert")

  local function perm(action, fallback)
    return function()
      local bridge = require("neowork.bridge")
      if bridge.has_pending_permission and bridge.has_pending_permission(buf) then
        bridge.permission_action(buf, action)
      else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(fallback, true, false, true), "n", false)
      end
    end
  end
  map("n", "s",  perm("select", "s"),  "permission select")
  map("n", "ya", perm("allow",  "ya"), "permission allow")
  map("n", "yn", perm("deny",   "yn"), "permission deny")
  map("n", "yA", perm("always", "yA"), "permission always")
end

return M
