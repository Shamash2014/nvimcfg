local M = {}

local ns = vim.api.nvim_create_namespace("nowork_qf_marks")
local marks = {}

local function current_id()
  local info = vim.fn.getqflist({ id = 0 })
  return info.id or 0
end

local function refresh_signs(buf, id)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local set = marks[id] or {}
  for lnum in pairs(set) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum - 1, 0, {
      sign_text = "●",
      sign_hl_group = "DiagnosticOk",
      line_hl_group = "CursorLineNr",
    })
  end
end

function M.toggle(lnum)
  local id = current_id()
  marks[id] = marks[id] or {}
  if marks[id][lnum] then
    marks[id][lnum] = nil
  else
    marks[id][lnum] = true
  end
  refresh_signs(vim.api.nvim_get_current_buf(), id)
end

function M.toggle_range(l1, l2)
  local id = current_id()
  marks[id] = marks[id] or {}
  local any_unmarked = false
  for lnum = l1, l2 do
    if not marks[id][lnum] then any_unmarked = true break end
  end
  for lnum = l1, l2 do
    marks[id][lnum] = any_unmarked or nil
  end
  refresh_signs(vim.api.nvim_get_current_buf(), id)
end

function M.clear()
  local id = current_id()
  marks[id] = nil
  refresh_signs(vim.api.nvim_get_current_buf(), id)
end

function M.has_marks()
  local id = current_id()
  return marks[id] and next(marks[id]) ~= nil
end

function M.marked_items()
  local id = current_id()
  local set = marks[id] or {}
  local items = vim.fn.getqflist({ items = 0 }).items or {}
  local out = {}
  local lnums = {}
  for lnum in pairs(set) do lnums[#lnums + 1] = lnum end
  table.sort(lnums)
  for _, lnum in ipairs(lnums) do
    if items[lnum] then out[#out + 1] = items[lnum] end
  end
  return out
end

function M.count()
  local id = current_id()
  local n = 0
  for _ in pairs(marks[id] or {}) do n = n + 1 end
  return n
end

return M
