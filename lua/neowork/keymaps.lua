local M = {}

M._keymaps_set = M._keymaps_set or {}

function M.detach(buf)
  M._keymaps_set[buf] = nil
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
      local function go(name)
        local fp = require("neowork.util").new_session(root, name)
        if fp then document.open(fp, { split = "edit" }) end
      end
      if args and args ~= "" then go(args)
      else vim.ui.input({ prompt = "New session name: " }, function(n) if n and n ~= "" then go(n) end end) end
    end,
    help = function() require("neowork.commands").open_help() end,
    ["?"] = function() require("neowork.commands").open_help() end,
  }

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

  map("n", "<C-c>", function() vim.cmd("NwInterrupt") end, "interrupt")

  vim.keymap.set("n", "r", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    if line:match("^@You") or line:match("^@Djinni") then
      document.fork_at_cursor(buf)
    else
      vim.api.nvim_feedkeys("r", "n", false)
    end
  end, { buffer = buf, silent = true, nowait = true, desc = "neowork: fork on role line / replace char" })

  map("n", "<Tab>", function()
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
