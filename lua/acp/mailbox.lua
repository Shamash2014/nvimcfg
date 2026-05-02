local M = {}

-- Mailbox is permission-only. No generic result queue.
local queue  = {}
local id_seq = 0

local function snacks_notify(msg, level)
  local ok, snacks = pcall(require, "snacks")
  if ok then
    snacks.notify(msg, { title = "acp", level = level or "info" })
  else
    vim.notify(msg, level or vim.log.levels.INFO, { title = "acp" })
  end
end


-- Count pending (unanswered) permissions — used by workbench render.
function M.pending_count()
  local n = 0
  for _, e in ipairs(queue) do
    if e.state == "pending" then n = n + 1 end
  end
  return n
end

-- open() is the reappear command: always re-opens the loclist with current pending items.
-- Bind to <leader>am. Safe to call when nothing is pending (closes empty loclist).
function M.open()
  M._open_or_refresh()
end

-- Mailbox holds ONLY session/request_permission entries.
-- entry: { id, rpc, msg_id, session_id, tool_kind, tool_title, tool_input, options, state }
function M.enqueue_permission(entry)
  id_seq = id_seq + 1
  entry.id    = id_seq
  entry.state = "pending"
  table.insert(queue, entry)
  M.open_permission_float(entry)
  vim.notify("ACP permission request: " .. entry.tool_title, vim.log.levels.WARN, { title = "acp" })
end

function M.open_permission_float(e)
  local lines = {
    "# Permission Request",
    "",
    "**Tool:** " .. e.tool_kind .. " (" .. e.tool_title .. ")",
    "",
    "**Input:**",
    "```json",
  }
  local input_str = vim.json.encode(e.tool_input or {})
  vim.list_extend(lines, vim.split(input_str, "\n", { plain = true }))
  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "  <CR> allow once  a allow always  <BS> reject")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.min(80, vim.o.columns - 4),
    height = math.min(20, #lines + 2),
    row = (vim.o.lines - 20) / 2,
    col = (vim.o.columns - 80) / 2,
    border = "rounded",
    title = " ACP Permission ",
    title_pos = "center",
  })

  local function respond(kind)
    M.respond(e.id, kind)
    pcall(vim.api.nvim_win_close, win, true)
  end

  vim.keymap.set("n", "<CR>", function() respond("allow_once") end, { buffer = buf })
  vim.keymap.set("n", "a",    function() respond("allow_always") end, { buffer = buf })
  vim.keymap.set("n", "<BS>", function() respond("reject_once") end, { buffer = buf })
  vim.keymap.set("n", "q",    function() pcall(vim.api.nvim_win_close, win, true) end, { buffer = buf })
end

function M._entry_at_cursor()
  local idx = vim.fn.getloclist(0, { idx = 0 }).idx
  for _, e in ipairs(queue) do
    if e.state == "pending" and e.id == idx then return e end
  end
  -- fallback: match by list position
  local ll = vim.fn.getloclist(0)
  local item = ll[vim.api.nvim_win_get_cursor(0)[1]]
  if not item then return nil end
  for _, e in ipairs(queue) do
    if e.state == "pending" and e.id == item._id then return e end
  end
  return nil
end

-- Respond to all pending permissions for a session with cancelled (used on session/cancel).
function M.cancel_for_session(session_id)
  for _, e in ipairs(queue) do
    if e.state == "pending" and e.session_id == session_id then
      e.rpc:respond(e.msg_id, { outcome = { outcome = "cancelled" } })
      e.state = "rejected"
    end
  end
  M._open_or_refresh()
end

function M.respond(id, kind)
  for _, e in ipairs(queue) do
    if e.id == id and e.state == "pending" then
      -- Find the optionId matching the requested kind
      local option_id = kind  -- fallback: use kind directly
      for _, o in ipairs(e.options or {}) do
        if o.kind == kind then option_id = o.optionId; break end
      end
      e.rpc:respond(e.msg_id, { outcome = { outcome = "selected", optionId = option_id } })
      e.state = kind:find("allow") and "approved" or "rejected"
      snacks_notify((e.state == "approved" and "✓" or "✗") .. " " .. e.tool_title)
      M._open_or_refresh()
      return
    end
  end
end


return M
