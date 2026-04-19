local M = {}

local inline_ns = vim.api.nvim_create_namespace("neowork_summary_inline")

M._text = {}

function M.set(buf, text)
  local value = text or ""
  M._text[buf] = value
  M.render_inline(buf)
end

function M.preview(buf, text)
  local value = text or ""
  M._text[buf] = value
  M.render_inline(buf)
end

function M.get(buf)
  if M._text[buf] ~= nil then return M._text[buf] end
  M._text[buf] = ""
  return ""
end

function M.clear(buf)
  M._text[buf] = ""
  M.render_inline(buf)
end

local function truncate(s, w)
  if #s <= w then return s end
  return s:sub(1, w - 1) .. "…"
end

local function worktree_context()
  local ok, wt = pcall(require, "djinni.integrations.worktrunk")
  if not ok or type(wt.statusline) ~= "function" then return nil end
  local value = wt.statusline()
  if type(value) ~= "string" or value == "" then return nil end
  return value
end

function M.chips(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return "" end
  if not vim.b[buf].neowork_chat then return "" end

  local document = require("neowork.document")
  local bridge = require("neowork.bridge")

  local sid = document.read_frontmatter_field(buf, "session") or ""
  local provider = document.read_frontmatter_field(buf, "provider") or "?"
  local status = bridge.get_status and select(1, bridge.get_status(buf)) or document.read_frontmatter_field(buf, "status") or "?"
  local tokens = document.read_frontmatter_field(buf, "tokens") or ""
  local cost = document.read_frontmatter_field(buf, "cost") or ""
  local elapsed = document.read_frontmatter_field(buf, "elapsed") or ""
  local ok, mode = pcall(bridge.get_mode, buf)
  local mode_label = (ok and mode and (mode.name or mode.id)) or "?"
  local sid_short = sid ~= "" and sid:sub(1, 8) or "—"
  local wt = worktree_context()

  local chips = { "● " .. sid_short, provider, mode_label, status }
  if wt then chips[#chips + 1] = wt end
  if tokens ~= "" then chips[#chips + 1] = tokens end
  if cost ~= "" and cost ~= "0.00" and cost ~= "0.0000" then chips[#chips + 1] = "$" .. cost end
  if elapsed ~= "" then chips[#chips + 1] = elapsed end
  return table.concat(chips, " │ ")
end

function M.statusline()
  return M.pills(vim.api.nvim_get_current_buf())
end

M._tool_count = {}

function M.bump_tool_count(sid)
  if not sid or sid == "" then return end
  M._tool_count[sid] = (M._tool_count[sid] or 0) + 1
end

function M.reset_tool_count(sid)
  if sid then M._tool_count[sid] = 0 end
end

local function _fmt_k(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(n)
end

local function _fmt_elapsed(ms)
  ms = tonumber(ms) or 0
  local seconds = math.floor(ms / 1000)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  seconds = seconds % 60
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, seconds)
  end
  return string.format("%d:%02d", minutes, seconds)
end

function M.pills(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return "" end
  if not vim.b[buf].neowork_chat then return "" end
  local document = require("neowork.document")
  local bridge = require("neowork.bridge")

  local turns = document.count_turns(buf) or 0
  local status = bridge.get_status and select(1, bridge.get_status(buf)) or document.read_frontmatter_field(buf, "status") or "idle"
  local sid = document.read_frontmatter_field(buf, "session") or ""
  local ok_mode, mode = pcall(bridge.get_mode, buf)
  local mode_label = (ok_mode and mode and (mode.name or mode.id)) or nil
  local wt = worktree_context()

  if sid ~= "" and M._tool_count[sid] == nil then
    local ok, store = pcall(require, "neowork.store")
    if ok then
      local root = document.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
      local count = 0
      for _, ev in ipairs(store.read_transcript(sid, root)) do
        if ev.type == "tool_call" then count = count + 1 end
      end
      M._tool_count[sid] = count
    end
  end
  local tool_calls = M._tool_count[sid] or 0

  local streaming = bridge._streaming and bridge._streaming[buf] == true
  local started = bridge._turn_started_at and bridge._turn_started_at[buf]
  local elapsed_ms
  if started then
    elapsed_ms = math.floor((vim.uv.hrtime() - started) / 1e6)
  else
    elapsed_ms = bridge._turn_elapsed_ms and bridge._turn_elapsed_ms[buf] or 0
  end

  local usage = (bridge._usage and bridge._usage[buf]) or {}
  local input_tokens = usage.input_tokens or 0
  local output_tokens = usage.output_tokens or 0
  local cost = usage.cost or 0

  local diff = (bridge._diff_stats and bridge._diff_stats[buf]) or {}

  local pill = function(s) return "%#NeoworkPill# " .. s .. " %*" end
  local parts = {}
  if mode_label then parts[#parts + 1] = pill(mode_label) end
  if wt then parts[#parts + 1] = pill(wt) end
  if streaming then
    local chars = bridge._spinner_chars or { "·" }
    local idx = ((bridge._spinner_frame or 0) % #chars) + 1
    parts[#parts + 1] = "%#NeoworkStatus#" .. chars[idx] .. "%*"
  end
  local queue_depth = (bridge.queue_depth and bridge.queue_depth(buf)) or 0
  if queue_depth > 0 then
    parts[#parts + 1] = "%#NeoworkStatus# ⏳ " .. queue_depth .. " queued %*"
  end
  parts[#parts + 1] = pill(turns .. " turns")
  parts[#parts + 1] = pill(tool_calls .. " tools")
  if elapsed_ms > 0 then
    parts[#parts + 1] = pill(_fmt_elapsed(elapsed_ms))
  end
  if input_tokens + output_tokens > 0 then
    parts[#parts + 1] = pill("↓" .. _fmt_k(input_tokens) .. " ↑" .. _fmt_k(output_tokens))
  end
  if (diff.files or 0) > 0 or (diff.added or 0) > 0 or (diff.deleted or 0) > 0 then
    parts[#parts + 1] = pill("Δ" .. (diff.files or 0) .. " +" .. (diff.added or 0) .. " -" .. (diff.deleted or 0))
  end
  if cost > 0 then
    parts[#parts + 1] = pill(string.format("$%.2f", cost))
  end
  local right
  if status == "awaiting" then
    right = "%#NeoworkStatus#! permission%*"
  elseif status == "tool" then
    right = "%#NeoworkStatus#● tool%*"
  elseif status == "submitting" then
    right = "%#NeoworkStatus#● submitting%*"
  elseif status == "streaming" or streaming or status == "running" then
    right = "%#NeoworkStatus#● streaming%*"
  elseif status == "connecting" then
    right = "%#NeoworkStatus#● connecting%*"
  elseif status == "interrupted" then
    right = "%#NeoworkStatus#● interrupted%*"
  elseif status == "error" then
    right = "%#NeoworkStatus#● error%*"
  else
    right = "%#NeoworkBtn#[gt transcript]%*"
  end
  return table.concat(parts, " ") .. "%=" .. right
end

function M.winbar()
  return M.pills(vim.api.nvim_get_current_buf())
end

function M.render_inline(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local document = require("neowork.document")

  pcall(vim.api.nvim_buf_clear_namespace, buf, inline_ns, 0, -1)

  local fm_end = document.get_fm_end(buf)
  if not fm_end then return end

  local lc = vim.api.nvim_buf_line_count(buf)
  local row = math.max(0, math.min(fm_end, lc - 1))

  local summary = M.get(buf)

  local width = math.max(40, vim.o.columns - 10)
  local virt_lines = {}

  virt_lines[#virt_lines + 1] = { { "", "NeoworkWindow" } }
  if summary ~= "" then
    virt_lines[#virt_lines + 1] = {
      { "  ▎ SUMMARY  ", "NeoworkSummaryLabel" },
      { truncate(summary, width - 14), "NeoworkSummaryText" },
    }
  else
    virt_lines[#virt_lines + 1] = { { "  ▎ (no summary)", "NeoworkSummaryEmpty" } }
  end

  local ok_plan, plan = pcall(require, "neowork.plan")
  if ok_plan then
    local entries = plan._entries and plan._entries[buf]
    if entries and #entries > 0 then
      virt_lines[#virt_lines + 1] = { { "", "NeoworkWindow" } }
      virt_lines[#virt_lines + 1] = { { "  ▎ PLAN  ", "NeoworkSummaryLabel" }, { (plan.status(buf) or ""), "NeoworkMeta" } }
      virt_lines[#virt_lines + 1] = { { "  [gp] toggle plan", "NeoworkMeta" } }
    end
  end

  virt_lines[#virt_lines + 1] = { { "", "NeoworkWindow" } }

  pcall(vim.api.nvim_buf_set_extmark, buf, inline_ns, row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = true,
  })
end

return M
