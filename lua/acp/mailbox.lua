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
  M._open_or_refresh()
  snacks_notify("ACP permission: " .. entry.tool_title, "warn")
end

-- Open the permission loclist and install <CR> bindings.
function M._open_or_refresh()
  local items = {}
  for _, e in ipairs(queue) do
    if e.state == "pending" then
      local preview = e.tool_input and vim.json.encode(e.tool_input):sub(1,60) or ""
      table.insert(items, {
        lnum = #items + 1, col = 1, bufnr = 0,
        text = "[" .. e.tool_kind .. "] " .. e.tool_title
               .. (preview ~= "" and ("  " .. preview) or ""),
        _id  = e.id,
      })
    end
  end
  vim.fn.setloclist(0, items, "r", { title = "ACP Permissions" })

  local lwin = vim.fn.getloclist(0, { winid = 0 }).winid
  if lwin == 0 then
    vim.cmd("lopen")
    lwin = vim.fn.getloclist(0, { winid = 0 }).winid
  end

  -- <CR> = pick first allow option; <Tab> cycles options; <BS> = reject
  local buf = vim.api.nvim_win_get_buf(lwin)
  vim.keymap.set("n", "<CR>", function()
    local e = M._entry_at_cursor()
    if e then M.respond(e.id, "allow_once") end
  end, { buffer = buf, desc = "Allow once" })
  vim.keymap.set("n", "<BS>", function()
    local e = M._entry_at_cursor()
    if e then M.respond(e.id, "reject_once") end
  end, { buffer = buf, desc = "Reject" })
  vim.keymap.set("n", "a", function()
    local e = M._entry_at_cursor()
    if e then M.respond(e.id, "allow_always") end
  end, { buffer = buf, desc = "Allow always" })
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

function M.respond(id, kind)
  for _, e in ipairs(queue) do
    if e.id == id and e.state == "pending" then
      -- Find the optionId matching the requested kind
      local option_id = kind  -- fallback: use kind directly
      for _, o in ipairs(e.options or {}) do
        if o.kind == kind then option_id = o.optionId; break end
      end
      e.rpc:respond(e.msg_id, { optionId = option_id })
      e.state = kind:find("allow") and "approved" or "rejected"
      snacks_notify((e.state == "approved" and "✓" or "✗") .. " " .. e.tool_title)
      M._open_or_refresh()
      return
    end
  end
end


return M
