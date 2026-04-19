local M = {}

local const = require("neowork.const")
local writequeue = require("neowork.writequeue")
local ast = require("neowork.ast")
local util = require("neowork.util")
local get_stream = util.lazy("neowork.stream")
local get_document = util.lazy("neowork.document")
local get_config = util.lazy("neowork.config")

M.ns = vim.api.nvim_create_namespace("neowork.tool_row")

M._state = {}
M._preview_win = nil
M._preview_buf = nil

local STATUS_GLYPH = {
  pending = "⋯",
  in_progress = "▹",
  completed = "▸",
  failed = "✗",
  error = "✗",
}

local STATUS_HL = {
  pending = "NeoworkToolRowPending",
  in_progress = "NeoworkToolRowRunning",
  completed = "NeoworkToolRow",
  failed = "NeoworkToolRowError",
  error = "NeoworkToolRowError",
}

local MAX_ROW = 200
local MAX_SUBJECT = 80

local function get_state(buf)
  M._state[buf] = M._state[buf] or { by_id = {}, by_lnum = {} }
  return M._state[buf]
end

function M.detach(buf)
  M._state[buf] = nil
end

local function truncate(s, max)
  s = tostring(s or "")
  s = s:gsub("\r?\n", " ")
  if vim.fn.strdisplaywidth(s) <= max then return s end
  return vim.fn.strcharpart(s, 0, max - 1) .. "…"
end

local function short_path(path)
  if not path or path == "" then return nil end
  local cwd = vim.fn.getcwd()
  if path:sub(1, #cwd) == cwd then
    path = path:sub(#cwd + 2)
  end
  return path
end

local function extract_subject(payload)
  local kind = payload.kind or ""
  local raw = payload.rawInput or {}
  local loc_path
  if payload.locations and payload.locations[1] then
    loc_path = payload.locations[1].path
  end

  if kind == "edit" or kind == "write" or kind == "create" then
    local path = loc_path or raw.file_path or raw.path
    if path then return short_path(path) end
  end

  if kind == "read" or kind == "fetch" then
    local path = loc_path or raw.file_path or raw.path or raw.url
    if path then return short_path(path) end
  end

  if kind == "execute" or kind == "bash" or kind == "shell" or kind == "run" then
    local cmd = raw.command or raw.cmd
    if cmd then return "`" .. truncate(cmd, MAX_SUBJECT) .. "`" end
  end

  if kind == "search" or kind == "grep" then
    local q = raw.pattern or raw.query
    if q then return "`" .. truncate(q, MAX_SUBJECT) .. "`" end
  end

  local cmd = raw.command or raw.cmd
  if cmd then return "`" .. truncate(cmd, MAX_SUBJECT) .. "`" end
  local path = loc_path or raw.file_path or raw.path or raw.url
  if path then return short_path(path) end
  local q = raw.pattern or raw.query
  if q then return "`" .. truncate(q, MAX_SUBJECT) .. "`" end

  return payload.title
end

local function verb_for(payload)
  local kind = payload.kind
  if kind and kind ~= "" and kind ~= "other" then return kind end
  if payload.title and payload.title ~= "" then
    return tostring(payload.title):match("^(%w+)") or "tool"
  end
  return "tool"
end

local function format_meta(entry)
  local parts = {}
  if entry.diff_added or entry.diff_deleted then
    local a, d = entry.diff_added or 0, entry.diff_deleted or 0
    if a > 0 or d > 0 then
      parts[#parts + 1] = string.format("+%d −%d", a, d)
    end
  end
  if entry.output_count and entry.output_count > 0 then
    parts[#parts + 1] = string.format("%d lines", entry.output_count)
  end
  local status = entry.status or ""
  if status == "failed" or status == "error" then
    parts[#parts + 1] = status
  elseif status == "in_progress" then
    parts[#parts + 1] = "running…"
  end
  if #parts == 0 then return "" end
  return table.concat(parts, " · ")
end

local function build_row_text(tool_id, entry)
  local status = entry.status or "pending"
  local glyph = STATUS_GLYPH[status] or "⋯"
  local verb = entry.verb or "tool"
  local subject = entry.subject or ""
  local meta = format_meta(entry)
  local parts = { "#### [", tool_id, "] ", glyph, " ", verb }
  if subject ~= "" then
    parts[#parts + 1] = "  "
    parts[#parts + 1] = truncate(subject, MAX_ROW)
  end
  if meta ~= "" then
    parts[#parts + 1] = "  --  "
    parts[#parts + 1] = meta
  end
  return table.concat(parts)
end

local function apply_line_hl(buf, entry, lnum)
  local hl = STATUS_HL[entry.status or "pending"] or "NeoworkToolRow"
  if not lnum and entry.extmark_id then
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, entry.extmark_id, {})
    if pos and pos[1] then lnum = pos[1] end
  end
  if not lnum then return end
  local opts = {
    line_hl_group = hl,
    right_gravity = false,
    priority = 80,
  }
  if entry.extmark_id then opts.id = entry.extmark_id end
  entry.extmark_id = vim.api.nvim_buf_set_extmark(buf, M.ns, lnum, 0, opts)
end

local function collect_text_sections(payload, max)
  local out = {}
  local total = 0
  local function push(text)
    for line in tostring(text or ""):gmatch("([^\n]*)\n?") do
      total = total + 1
      if total <= max then out[#out + 1] = line end
    end
  end
  local function walk(c)
    if type(c) ~= "table" then return end
    if c.type or c.text then c = { c } end
    for _, entry in ipairs(c) do
      if type(entry) == "table" then
        if entry.type == "content" and type(entry.content) == "table" then
          walk(entry.content)
        elseif entry.type ~= "image" and entry.type ~= "diff" and not entry.oldText and not entry.newText then
          local text = (entry.content and entry.content.text) or entry.text
          if text then push(text) end
        end
      end
    end
  end
  walk(payload.content)
  return out, total
end

local function collect_diff_sections(payload)
  local out = {}
  local files = {}
  local added, deleted = 0, 0
  local function walk(c)
    if type(c) ~= "table" then return end
    if c.type or c.oldText or c.newText then c = { c } end
    for _, entry in ipairs(c) do
      if type(entry) == "table" then
        if entry.type == "diff" or entry.oldText or entry.newText then
          local old_str = tostring(entry.oldText or "")
          local new_str = tostring(entry.newText or "")
          files[#files + 1] = {
            path = entry.path,
            old_text = old_str,
            new_text = new_str,
          }
          if entry.path then out[#out + 1] = "--- " .. entry.path end
          if old_str ~= "" and not old_str:match("\n$") then old_str = old_str .. "\n" end
          if new_str ~= "" and not new_str:match("\n$") then new_str = new_str .. "\n" end
          local ok, hunks = pcall(vim.diff, old_str, new_str, { result_type = "indices" })
          if ok and type(hunks) == "table" and #hunks > 0 then
            local old_lines, new_lines = {}, {}
            for l in old_str:gmatch("([^\n]*)\n") do old_lines[#old_lines + 1] = l end
            for l in new_str:gmatch("([^\n]*)\n") do new_lines[#new_lines + 1] = l end
            for _, h in ipairs(hunks) do
              out[#out + 1] = string.format("@@ -%d,%d +%d,%d @@", h[1], h[2], h[3], h[4])
              for i = h[1], h[1] + h[2] - 1 do
                out[#out + 1] = "-" .. (old_lines[i] or "")
                deleted = deleted + 1
              end
              for i = h[3], h[3] + h[4] - 1 do
                out[#out + 1] = "+" .. (new_lines[i] or "")
                added = added + 1
              end
            end
          else
            for line in old_str:gmatch("([^\n]*)\n") do out[#out + 1] = "-" .. line; deleted = deleted + 1 end
            for line in new_str:gmatch("([^\n]*)\n") do out[#out + 1] = "+" .. line; added = added + 1 end
          end
        elseif entry.type == "content" and type(entry.content) == "table" then
          walk(entry.content)
        end
      end
    end
  end
  walk(payload.content)
  return out, added, deleted, files
end

local function ensure_entry(buf, tool_id)
  local state = get_state(buf)
  state.by_id[tool_id] = state.by_id[tool_id] or {
    output = {},
    output_count = 0,
    diff = {},
    diff_added = 0,
    diff_deleted = 0,
    diff_files = {},
  }
  return state.by_id[tool_id]
end

local function update_entry_from_payload(entry, payload, max_output)
  entry.kind = payload.kind or entry.kind
  entry.title = payload.title or entry.title
  entry.verb = verb_for({ kind = entry.kind, title = entry.title })
  local subject = extract_subject(payload)
  if subject and subject ~= "" then entry.subject = subject end
  if payload.status and payload.status ~= "" then
    entry.status = payload.status
  end
  entry.rawInput = payload.rawInput or entry.rawInput
  entry.locations = payload.locations or entry.locations

  if payload.content then
    local text, total = collect_text_sections(payload, max_output)
    if total > 0 then
      entry.output = text
      entry.output_count = total
    end
    local diff, added, deleted, files = collect_diff_sections(payload)
    if #diff > 0 then
      entry.diff = diff
      entry.diff_added = added
      entry.diff_deleted = deleted
      entry.diff_files = files
    end
  end
end

local function build_tool_block(tool_id, entry, max_output)
  local out = { build_row_text(tool_id, entry) }
  local raw = entry.output
  local text = ""
  if type(raw) == "table" then
    text = table.concat(raw, "\n")
  elseif type(raw) == "string" then
    text = raw
  end
  text = text:gsub("%s+$", "")
  local count = 0
  if text ~= "" then
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
      if count >= max_output then break end
      out[#out + 1] = "> " .. line
      count = count + 1
    end
  end
  if entry.diff and #entry.diff > 0 and count < max_output then
    for _, line in ipairs(entry.diff) do
      if count >= max_output then break end
      out[#out + 1] = "> " .. line
      count = count + 1
    end
  end
  return out
end

local EXECUTE_KINDS = { execute = true, bash = true, shell = true, run = true }

local function tool_block_in_djinni(buf, tool_id)
  local s, e = ast.find_tool_block(buf, tool_id)
  if not s then return nil end
  local turn = ast.turn_at_line(buf, s)
  if not turn or turn.role ~= "Djinni" then return nil end
  return s, e
end

local function schedule_close_tool_folds(buf)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    pcall(require("neowork.fold").close_tool_folds, buf)
  end)
end

local function ensure_open_djinni_row(buf)
  local stream = get_stream()
  local turn = stream.active_djinni_turn(buf)
  if turn then
    local row = ast.append_row_for_turn(buf, turn)
    if row then return row end
  end
  local cur = ast.insertion_row_for_streaming(buf)
  if cur then return cur end
  get_document().insert_djinni_turn(buf)
  turn = stream.active_djinni_turn(buf)
  if turn then return ast.append_row_for_turn(buf, turn) end
  return ast.insertion_row_for_streaming(buf)
end

function M.render(buf, tool_id, payload)
  if not vim.api.nvim_buf_is_valid(buf) or not tool_id then return end
  local config = get_config()
  local stream = get_stream()
  local max_output = config.get("max_tool_output_lines") or 50

  local state = get_state(buf)
  local entry = ensure_entry(buf, tool_id)
  update_entry_from_payload(entry, payload, max_output)

  if entry.status == "pending" then return end
  if entry.status == "running" and not EXECUTE_KINDS[entry.kind or ""] then return end

  local block = build_tool_block(tool_id, entry, max_output)

  local existing_s, existing_e = ast.find_tool_block(buf, tool_id)
  if existing_s then
    local turn = ast.turn_at_line(buf, existing_s)
    if turn and turn.role == "Djinni" then
      local fold = require("neowork.fold")
      local was_open = fold.is_tool_fold_open(buf, tool_id)
      writequeue.enqueue(buf, function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local s, e = ast.find_tool_block(buf, tool_id)
        if not s then return end
        local t = ast.turn_at_line(buf, s)
        if not t or t.role ~= "Djinni" then return end
        vim.api.nvim_buf_set_lines(buf, s - 1, e, false, block)
        apply_line_hl(buf, entry, s - 1)
        entry.row_start = s
        entry.row_end = s + #block - 1
        state.by_lnum[s - 1] = tool_id
        ast.assert_invariant(buf, "tool_row.update")
      end)
      if was_open then
        fold.mark_user_opened(buf, tool_id)
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          fold.restore_tool_fold_open(buf, tool_id)
        end)
      end
      schedule_close_tool_folds(buf)
      return
    end
    writequeue.enqueue(buf, function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local s, e = ast.find_tool_block(buf, tool_id)
      if not s then return end
      local t = ast.turn_at_line(buf, s)
      if t and t.role == "Djinni" then return end
      vim.api.nvim_buf_set_lines(buf, s - 1, e, false, {})
    end)
  end

  stream._flush_now(buf)
  if not ensure_open_djinni_row(buf) then return end

  writequeue.enqueue(buf, function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local cur = ensure_open_djinni_row(buf)
    if not cur then return end
    vim.api.nvim_buf_set_lines(buf, cur - 1, cur - 1, false, block)
    apply_line_hl(buf, entry, cur - 1)
    entry.row_start = cur
    entry.row_end = cur + #block - 1
    state.by_lnum[cur - 1] = tool_id
    stream._invalidate_tail(buf)
    ast.assert_invariant(buf, "tool_row.insert")
  end)
  schedule_close_tool_folds(buf)
end

local function find_tool_at(buf, lnum)
  local state = M._state[buf]
  if not state then return nil end
  local marks = vim.api.nvim_buf_get_extmarks(buf, M.ns, { lnum, 0 }, { lnum, 0 }, { overlap = true })
  if #marks == 0 then return nil end
  for _, m in ipairs(marks) do
    for tool_id, entry in pairs(state.by_id) do
      if entry.extmark_id == m[1] then
        return tool_id, entry
      end
    end
  end
  return nil
end

function M.is_tool_row(buf, lnum)
  local tool_id = find_tool_at(buf, lnum)
  return tool_id ~= nil
end

local function close_preview()
  if M._preview_win and vim.api.nvim_win_is_valid(M._preview_win) then
    pcall(vim.api.nvim_win_close, M._preview_win, true)
  end
  M._preview_win = nil
  M._preview_buf = nil
end

function M.preview_at_cursor(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local tool_id, entry = find_tool_at(buf, lnum)
  if not tool_id or not entry then return false end

  if entry.diff_files and #entry.diff_files > 0 then
    local ok, dv = pcall(require, "neowork.diffview")
    if ok and dv.open(tool_id, entry) then return true end
  end

  close_preview()

  local lines = {}
  local ft = "text"
  if entry.diff and #entry.diff > 0 then
    ft = "diff"
    for _, l in ipairs(entry.diff) do lines[#lines + 1] = l end
  end
  if entry.output and #entry.output > 0 then
    if #lines > 0 then lines[#lines + 1] = "" end
    for _, l in ipairs(entry.output) do lines[#lines + 1] = l end
  end
  if #lines == 0 then
    lines = { "(no output)" }
  end

  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[pbuf].buftype = "nofile"
  vim.bo[pbuf].bufhidden = "wipe"
  vim.bo[pbuf].swapfile = false
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
  vim.bo[pbuf].modifiable = false
  vim.bo[pbuf].filetype = ft

  local width = math.min(math.floor(vim.o.columns * 0.8), 120)
  local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.6))
  local title = string.format(" %s  %s  %s ",
    entry.verb or "tool",
    entry.subject or "",
    entry.status or "")

  local win = vim.api.nvim_open_win(pbuf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "left",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  M._preview_win = win
  M._preview_buf = pbuf

  local function cls()
    close_preview()
  end
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, cls, { buffer = pbuf, silent = true, nowait = true })
  end
  vim.api.nvim_create_autocmd("BufLeave", { buffer = pbuf, once = true, callback = cls })

  return true
end

return M
