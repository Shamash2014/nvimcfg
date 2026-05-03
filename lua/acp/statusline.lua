local M = {}

function M.acp_indicator()
  local active = 0
  local ok, diff = pcall(require, "acp.diff")
  if ok then
    local cwd = vim.fn.getcwd()
    for _, entry in ipairs(diff.get_threads(cwd) or {}) do
      if diff.is_thread_active(entry.thread) then active = active + 1 end
    end
  end

  local pending = 0
  local ok_mb, mailbox = pcall(require, "acp.mailbox")
  if ok_mb then pending = mailbox.pending_count() or 0 end

  local parts = {}
  if active  > 0 then table.insert(parts, "%#DiagnosticOk#A("   .. active  .. ")%*") end
  if pending > 0 then table.insert(parts, "%#DiagnosticWarn#R(" .. pending .. ")%*") end
  return table.concat(parts, " ")
end

local LEVELS = {
  { sev = vim.diagnostic.severity.ERROR, hl = "DiagnosticError", icon = "E" },
  { sev = vim.diagnostic.severity.WARN,  hl = "DiagnosticWarn",  icon = "W" },
  { sev = vim.diagnostic.severity.INFO,  hl = "DiagnosticInfo",  icon = "I" },
  { sev = vim.diagnostic.severity.HINT,  hl = "DiagnosticHint",  icon = "H" },
}

function M.diagnostics()
  local parts = {}
  for _, l in ipairs(LEVELS) do
    local n = #vim.diagnostic.get(0, { severity = l.sev })
    if n > 0 then
      table.insert(parts, "%#" .. l.hl .. "#" .. l.icon .. ":" .. n .. "%*")
    end
  end
  return table.concat(parts, " ")
end

function M.build()
  local indicator = M.acp_indicator()
  local diags = M.diagnostics()
  local right = {}
  if indicator ~= "" then table.insert(right, indicator) end
  if diags ~= ""     then table.insert(right, diags)     end
  table.insert(right, "%y %l:%c ")
  return " %f %m%r%=" .. table.concat(right, "  ") .. " "
end

return M
