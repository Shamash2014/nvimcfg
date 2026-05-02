local M = {}

local ns   = vim.api.nvim_create_namespace("acp_activity")
local sign = "AcpAgent"
vim.fn.sign_define(sign, { text = "⟳", texthl = "Comment" })

local KIND_ICON = {
  read    = "r ",  edit    = "e ",  delete = "d ",
  move    = "mv ", search  = "/ ",  execute = "$ ",
  think   = "~ ",  fetch   = "f ",  write  = "w ",
  other   = "? ",
}

-- active[session_id][tool_call_id] = { bufnr, extmark_id, sign_id }
local active   = {}
-- collect all locations seen this session for the changed-files summary
local _locs    = {}

local function icon(kind) return KIND_ICON[kind] or "? " end

-- Called from session/update subscriber when sessionUpdate == "tool_call"
function M.on_tool_call(session_id, update)
  active[session_id] = active[session_id] or {}
  _locs[session_id]  = _locs[session_id]  or {}
  local tid = update.toolCallId
  if not tid then return end

  local loc   = update.locations and update.locations[1]
  local path  = loc and loc.path
  local lnum  = loc and (loc.startLine or 1) or 1
  local bufnr = path and vim.fn.bufnr(path) or -1

  -- Collect for post-session summary
  if loc then table.insert(_locs[session_id], loc) end

  local text = icon(update.kind) .. (update.title or update.kind or "…")

  local extmark_id, sign_id
  if bufnr ~= -1 then
    extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
      virt_text     = { { text, "Comment" } },
      virt_text_pos = "eol",
      priority      = 100,
    })
    sign_id = vim.fn.sign_place(0, "acp", sign, bufnr, { lnum = lnum })
  end

  active[session_id][tid] = { bufnr = bufnr, extmark_id = extmark_id, sign_id = sign_id }
end

-- Clear extmark + sign when tool finishes
function M.on_tool_call_update(session_id, update)
  local tid   = update.toolCallId
  local entry = active[session_id] and active[session_id][tid]
  if not entry then return end

  if update.status == "completed" or update.status == "failed" then
    if entry.extmark_id then
      pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, ns, entry.extmark_id)
    end
    if entry.sign_id then
      pcall(vim.fn.sign_unplace, "acp", { id = entry.sign_id, buffer = entry.bufnr })
    end
    active[session_id][tid] = nil
  end
end

-- Clear all activity for a session; return accumulated locations for summary.
function M.clear(session_id)
  for _, entry in pairs(active[session_id] or {}) do
    if entry.extmark_id then
      pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, ns, entry.extmark_id)
    end
    if entry.sign_id then
      pcall(vim.fn.sign_unplace, "acp", { id = entry.sign_id, buffer = entry.bufnr })
    end
  end
  active[session_id] = nil
  local locs = _locs[session_id] or {}
  _locs[session_id] = nil
  return locs
end

return M
