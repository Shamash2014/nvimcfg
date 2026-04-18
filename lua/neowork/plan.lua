local M = {}

M._entries = {}
M._section_lines = {}

local QF_TITLE_PREFIX = "Neowork Plan"

local STATUS_RANK = { pending = 0, completed = 1, in_progress = 2 }

local function dedup(entries)
  local order, seen = {}, {}
  for _, e in ipairs(entries or {}) do
    local key = (e.text or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if key ~= "" then
      local idx = seen[key]
      if not idx then
        seen[key] = #order + 1
        order[#order + 1] = { text = e.text, status = e.status, priority = e.priority }
      else
        local existing = order[idx]
        if (STATUS_RANK[e.status] or 0) > (STATUS_RANK[existing.status] or 0) then
          existing.status = e.status
        end
      end
    end
  end
  return order
end

local function qf_title(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local short = name ~= "" and vim.fn.fnamemodify(name, ":t") or ("buf " .. buf)
  return QF_TITLE_PREFIX .. " — " .. short
end

local function status_type(status)
  if status == "in_progress" then return "W" end
  if status == "completed" then return "I" end
  return "E"
end

local function status_mark(status)
  if status == "completed" then return "[x]" end
  if status == "in_progress" then return "[~]" end
  return "[ ]"
end

local function section_mark(status)
  if status == "completed" then return "[x]" end
  if status == "in_progress" then return "[>]" end
  return "[ ]"
end

local function build_section_lines(entries)
  local lines = { "### Plan" }
  for _, e in ipairs(entries) do
    lines[#lines + 1] = "- " .. section_mark(e.status) .. " " .. (e.text or "")
  end
  lines[#lines + 1] = ""
  return lines
end

function M.render_section(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local entries = M._entries[buf]
  if not entries or #entries == 0 then return end

  local ok, document = pcall(require, "neowork.document")
  if not ok then return end
  local compose = document.find_compose_line(buf)
  if not compose then return end

  local new_lines = build_section_lines(entries)
  local cached = M._section_lines[buf]

  if cached then
    local first = vim.api.nvim_buf_get_lines(buf, cached.start, cached.start + 1, false)[1]
    if first == "### Plan" and cached["end"] <= vim.api.nvim_buf_line_count(buf) then
      vim.api.nvim_buf_set_lines(buf, cached.start, cached["end"], false, new_lines)
      M._section_lines[buf] = { start = cached.start, ["end"] = cached.start + #new_lines }
      return
    end
  end

  local insert_row = compose - 1
  vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, new_lines)
  M._section_lines[buf] = { start = insert_row, ["end"] = insert_row + #new_lines }
end

local function build_items(buf, entries)
  local items = {}
  local section = M._section_lines[buf]
  for i, entry in ipairs(entries) do
    local lnum = 1
    local valid = 0
    if section then
      lnum = section.start + 1 + i
      valid = 1
    end
    items[#items + 1] = {
      bufnr = buf,
      lnum = lnum,
      col = 1,
      text = string.format("%s %s", status_mark(entry.status), entry.text or ""),
      type = status_type(entry.status),
      valid = valid,
      nr = i,
    }
  end
  return items
end

local function qf_shows_plan(buf)
  local info = vim.fn.getqflist({ title = 0 })
  return info.title == qf_title(buf)
end

local function set_qflist(buf, entries)
  local items = build_items(buf, entries)
  vim.fn.setqflist({}, " ", { title = qf_title(buf), items = items })
end

local function qf_is_open()
  for _, win in ipairs(vim.fn.getwininfo()) do
    if win.quickfix == 1 then return true end
  end
  return false
end

function M.on_plan_event(buf, entries)
  entries = dedup(entries)
  local unchanged = vim.deep_equal(M._entries[buf], entries)
  M._entries[buf] = entries

  if not unchanged then
    pcall(require("neowork.summary").render_inline, buf)
    local document = require("neowork.document")
    local sid = document.read_frontmatter_field(buf, "session")
    local root = document.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
    if sid and sid ~= "" then
      require("neowork.store").append_event(sid, root, { type = "plan", entries = entries })
    end
  end

  pcall(M.render_section, buf)

  if qf_shows_plan(buf) then
    set_qflist(buf, entries)
  end
end

function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local entries = M._entries[buf]

  if qf_shows_plan(buf) and qf_is_open() then
    vim.cmd("cclose")
    return
  end

  if not entries or #entries == 0 then
    vim.notify("No plan available", vim.log.levels.INFO)
    return
  end

  set_qflist(buf, entries)
  vim.cmd("botright copen")
end

function M.status(buf)
  local entries = M._entries[buf]
  if not entries or #entries == 0 then return nil end
  local done = 0
  for _, e in ipairs(entries) do
    if e.status == "completed" then done = done + 1 end
  end
  return done .. "/" .. #entries .. " done"
end

function M.detach(buf)
  M._entries[buf] = nil
  M._section_lines[buf] = nil
end

return M
