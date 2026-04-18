local M = {}

local config = require("neowork.config")
local store = require("neowork.store")
local util = require("neowork.util")
local const = require("neowork.const")

local get_document = util.lazy("neowork.document")
local get_bridge = util.lazy("neowork.bridge")

M._tail_row = {}
M._tail_text = {}
M._pending = {}
M._gen = {}
M._timer = nil
M._active_bufs = {}
M._auto_scroll = {}
M._tool_diff_seen = {}
M._summary_text = {}
M._summary_last = {}
M._agent_text = {}
M._turn_start_row = {}
M._status_redraw_pending = {}

M.detach = function(buf) M.reset(buf) end

function M.reset(buf)
  M._tail_row[buf] = nil
  M._tail_text[buf] = nil
  M._pending[buf] = nil
  M._gen[buf] = nil
  M._active_bufs[buf] = nil
  M._auto_scroll[buf] = nil
  M._tool_diff_seen[buf] = nil
  M._summary_text[buf] = nil
  M._summary_last[buf] = nil
  M._agent_text[buf] = nil
  M._turn_start_row[buf] = nil
  M._status_redraw_pending[buf] = nil
end

function M._stream_chunk_lines(tail, text)
  local segments = {}
  local start = 1
  while true do
    local nl = text:find("\n", start, true)
    if not nl then break end
    segments[#segments + 1] = text:sub(start, nl - 1)
    start = nl + 1
  end

  if #segments == 0 then
    local merged = (tail or "") .. text
    return { merged }, merged
  end

  local lines = { (tail or "") .. segments[1] }
  for i = 2, #segments do
    lines[#lines + 1] = segments[i]
  end

  local remainder = text:sub(start)
  if text:sub(-1) == "\n" then
    lines[#lines + 1] = ""
  else
    lines[#lines + 1] = remainder
  end

  return lines, lines[#lines]
end

function M._sync_tail(buf)
  local count = vim.api.nvim_buf_line_count(buf)
  local last_text = ""
  if count > 0 then
    local lines = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)
    last_text = lines[1] or ""
  end
  return count, last_text
end

function M._apply_chunk(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  require("neowork.writequeue").flush(buf)

  local row = M._tail_row[buf]
  local tail = M._tail_text[buf]

  local line_count = vim.api.nvim_buf_line_count(buf)
  local resync = not row or row > line_count
  if not resync and row and tail then
    local current = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    if current ~= tail then resync = true end
  end
  if resync then
    local doc = get_document()
    local inner = doc.find_djinni_tail(buf)
    if inner then
      row = inner
      tail = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    else
      local compose = doc.find_compose_line(buf)
      if compose then
        row = compose - 1
        tail = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
      else
        row, tail = M._sync_tail(buf)
      end
    end
    M._tail_row[buf] = row
    M._tail_text[buf] = tail
  end

  local lines, new_tail = M._stream_chunk_lines(tail, text)

  local start_row = row - 1
  local end_row = row
  require("neowork.writequeue").enqueue(buf, function()
    vim.api.nvim_buf_set_lines(buf, start_row, end_row, false, lines)
  end)

  M._tail_row[buf] = row + #lines - 1
  M._tail_text[buf] = new_tail
end

function M._update_summary(buf)
  local text = M._summary_text[buf]
  if not text or text == "" then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local last
  for line in text:gmatch("[^\r\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then last = trimmed end
  end
  if not last then return end
  if #last > 80 then last = last:sub(1, 79) .. "…" end

  if M._summary_last[buf] == last then return end

  pcall(require("neowork.summary").set, buf, last)
  M._summary_last[buf] = last
end

local function normalize_summary(text)
  local value = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if value == "" then return nil end
  if #value > 80 then value = value:sub(1, 79) .. "…" end
  return value
end

local function set_summary_fallback(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if M._summary_text[buf] and M._summary_text[buf] ~= "" then return end
  local value = normalize_summary(text)
  if not value or M._summary_last[buf] == value then return end
  pcall(require("neowork.summary").set, buf, value)
  M._summary_last[buf] = value
end

local function tool_summary(su)
  return normalize_summary(su.title or su.kind or "tool")
end

local function plan_summary(entries)
  entries = entries or {}
  local pending = 0
  for _, entry in ipairs(entries) do
    if (entry.status or "") ~= const.plan_status.completed then
      pending = pending + 1
    end
  end
  return normalize_summary(string.format("plan · %d steps (%d pending)", #entries, pending))
end

function M._flush_now(buf)
  local chunks = M._pending[buf]
  if not chunks or #chunks == 0 then return end
  M._pending[buf] = {}

  if not vim.api.nvim_buf_is_valid(buf) then return end

  local text = table.concat(chunks)
  M._apply_chunk(buf, text)
end

function M._do_auto_scroll(buf)
  if not M._auto_scroll[buf] then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local last = vim.api.nvim_buf_line_count(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_set_cursor, win, { last, 0 })
    end
  end
end

local function collapse_detail_fold(buf, header_lnum)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then return end
  local parent_lnum
  for lnum = math.max(1, header_lnum - 1), 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    if line:match("^@Djinni") then
      parent_lnum = lnum
      break
    end
    if line:match("^@You") or line:match("^@System") then
      break
    end
  end
  local function close_in_windows()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function()
          pcall(vim.cmd, string.format("silent! %dfoldclose", math.max(1, header_lnum)))
          if parent_lnum then
            pcall(vim.cmd, string.format("silent! %dfoldopen", parent_lnum))
          end
        end)
      end
    end
  end

  local ok_doc, doc = pcall(require, "neowork.document")
  if ok_doc and doc then
    if doc.compute_folds then
      pcall(doc.compute_folds, buf)
    end
    if doc.schedule_refold then
      pcall(doc.schedule_refold, buf)
    end
  end

  vim.schedule(function()
    close_in_windows()
  end)
end

local function request_status_redraw(buf)
  if M._status_redraw_pending[buf] then return end
  M._status_redraw_pending[buf] = true
  vim.schedule(function()
    M._status_redraw_pending[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.cmd.redrawstatus)
    end
  end)
end

local function set_runtime_status(buf, status, meta)
  local ok, bridge = pcall(get_bridge)
  if not ok or not bridge then return end
  bridge._runtime_status[buf] = status
  bridge._runtime_meta[buf] = meta
  request_status_redraw(buf)
end

local function get_session_context(buf)
  local doc = get_document()
  return {
    doc = doc,
    sid = get_bridge().get_session_id(buf),
    root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd(),
  }
end

local function append_session_event(buf, event)
  local ctx = get_session_context(buf)
  if not ctx.sid then return end
  store.append_event(ctx.sid, ctx.root, event)
end

local function append_fenced_block(dst, lang, lines)
  if not lines or #lines == 0 then return end
  dst[#dst + 1] = "```" .. (lang or "")
  for _, line in ipairs(lines) do
    dst[#dst + 1] = tostring(line)
  end
  dst[#dst + 1] = "```"
end

local function append_detail_block(buf, title, body_lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  body_lines = body_lines or {}
  local tag = "detail"
  local meta = nil
  if type(title) == "table" then
    tag = title.tag or tag
    meta = title.meta
    title = title.title or "detail"
  end
  local header = "#### [" .. tag .. "] " .. title
  if meta and meta ~= "" then
    header = header .. " -- " .. meta
  end
  local lines = { header }
  if #body_lines > 0 then
    lines[#lines + 1] = ""
    for _, line in ipairs(body_lines) do
      lines[#lines + 1] = tostring(line)
    end
  end
  lines[#lines + 1] = ""

  M._flush_now(buf)
  local prefix = (M._tail_text[buf] and M._tail_text[buf] ~= "") and "\n" or ""
  local before = vim.api.nvim_buf_line_count(buf)
  M._apply_chunk(buf, prefix .. table.concat(lines, "\n") .. "\n")
  local header_lnum = before + ((prefix ~= "") and 1 or 0)
  collapse_detail_fold(buf, header_lnum)
  return header_lnum
end

function M._ensure_timer()
  if M._timer then return end

  M._timer = vim.uv.new_timer()
  local interval = config.get_flush_interval()

  M._timer:start(interval, interval, vim.schedule_wrap(function()
    for buf in pairs(M._active_bufs) do
      if M._pending[buf] and #M._pending[buf] > 0 then
        M._flush_now(buf)
        M._do_auto_scroll(buf)
      end
      M._update_summary(buf)
    end
  end))
end

function M._stop_timer()
  if M._timer then
    M._timer:stop()
    M._timer:close()
    M._timer = nil
  end
end

function M.start(buf, gen)
  M._gen[buf] = gen
  M._pending[buf] = {}
  M._active_bufs[buf] = true
  M._auto_scroll[buf] = true
  M._summary_text[buf] = nil
  M._summary_last[buf] = nil
  M._agent_text[buf] = {}
  M._tool_diff_seen[buf] = {}

  local doc = get_document()
  local inner_row = doc.insert_djinni_turn(buf)
  M._tail_row[buf] = inner_row
  M._tail_text[buf] = ""
  M._turn_start_row[buf] = math.max((inner_row or 1) - 2, 0)

  M._ensure_timer()
end

function M.stop(buf, gen)
  if M._gen[buf] ~= gen then return end

  M._flush_now(buf)
  M._update_summary(buf)

  local chunks = M._agent_text[buf]
  if chunks and #chunks > 0 then
    local full = table.concat(chunks)
    if full ~= "" then
      local doc = get_document()
      local sid = get_bridge().get_session_id(buf)
      local root = doc.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
      if sid then
        store.append_event(sid, root, { type = "assistant", content = full })
      end
    end
  end
  M._agent_text[buf] = nil

  require("neowork.writequeue").flush(buf)

  M._active_bufs[buf] = nil
  M._pending[buf] = nil
  M._tail_row[buf] = nil
  M._tail_text[buf] = nil
  M._auto_scroll[buf] = nil

  if not next(M._active_bufs) then
    M._stop_timer()
  end

  local turn_start = M._turn_start_row[buf]
  M._turn_start_row[buf] = nil

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    get_document().compute_folds(buf)
    local ok, hl = pcall(require, "neowork.highlight")
    if ok then
      local total = vim.api.nvim_buf_line_count(buf)
      hl.apply(buf, turn_start or 0, total)
    end
  end)
end

function M.on_event(buf, su, gen)
  if M._gen[buf] ~= gen then return end

  local t = su.sessionUpdate

  if t == const.event.agent_message_chunk then
    local text = su.content and su.content.text or ""
    if text ~= "" then
      set_runtime_status(buf, const.session_status.streaming, nil)
      M._pending[buf] = M._pending[buf] or {}
      M._pending[buf][#M._pending[buf] + 1] = text
      M._summary_text[buf] = (M._summary_text[buf] or "") .. text
      M._agent_text[buf] = M._agent_text[buf] or {}
      M._agent_text[buf][#M._agent_text[buf] + 1] = text
    end

  elseif t == const.event.agent_thought_chunk then
    local text = su.content and su.content.text or ""
    if text ~= "" then
      set_runtime_status(buf, const.session_status.streaming, nil)
      local prefixed = text:gsub("([^\n]+)", function(line) return "> " .. line end)
      M._pending[buf] = M._pending[buf] or {}
      M._pending[buf][#M._pending[buf] + 1] = prefixed
    end

  elseif t == const.event.tool_call or t == const.event.tool_call_update then
    set_runtime_status(buf, const.session_status.tool, {
      title = su.title,
      kind = su.kind,
      status = su.status,
    })
    local is_initial = t == const.event.tool_call
    local status = su.status
    local terminal = status == const.plan_status.completed or status == const.plan_status.failed or status == "error"

    M._tool_diff_seen[buf] = M._tool_diff_seen[buf] or {}
    local seen = M._tool_diff_seen[buf]
    local tcid = su.toolCallId or su.id

    local body_lines = {}
    local text_sections = {}

    local max_body = config.get("max_tool_output_lines") or 20

    local function push_capped(text)
      local count = 0
      local truncated = 0
      local body = {}
      for line in tostring(text):gmatch("([^\n]*)\n?") do
        if line ~= "" then
          if count < max_body then
            body[#body + 1] = line
            count = count + 1
          else
            truncated = truncated + 1
          end
        end
      end
      if #body == 0 and truncated == 0 then return end
      local section = {}
      for _, l in ipairs(body) do section[#section + 1] = l end
      if truncated > 0 then
        section[#section + 1] = "… (+" .. truncated .. " more)"
      end
      text_sections[#text_sections + 1] = section
    end

    local had_diff = false
    local diff_files = 0
    local diff_added = 0
    local diff_deleted = 0
    local function emit_diff(c)
      had_diff = true
      diff_files = diff_files + 1
      local diff_body = {}
      if c.path then diff_body[#diff_body + 1] = "--- " .. c.path end
      local old_str = tostring(c.oldText or "")
      local new_str = tostring(c.newText or "")
      if old_str ~= "" and not old_str:match("\n$") then old_str = old_str .. "\n" end
      if new_str ~= "" and not new_str:match("\n$") then new_str = new_str .. "\n" end

      local added_n, deleted_n = 0, 0
      local ok, hunks = pcall(vim.diff, old_str, new_str, { result_type = "indices" })
      if not ok or type(hunks) ~= "table" or #hunks == 0 then
        for line in old_str:gmatch("([^\n]*)\n?") do
          if line ~= "" then diff_body[#diff_body + 1] = "- " .. line; deleted_n = deleted_n + 1 end
        end
        for line in new_str:gmatch("([^\n]*)\n?") do
          if line ~= "" then diff_body[#diff_body + 1] = "+ " .. line; added_n = added_n + 1 end
        end
      else
        local old_lines = {}
        for l in old_str:gmatch("([^\n]*)\n") do old_lines[#old_lines + 1] = l end
        local new_lines = {}
        for l in new_str:gmatch("([^\n]*)\n") do new_lines[#new_lines + 1] = l end

        for _, h in ipairs(hunks) do
          local old_start, old_count, new_start, new_count = h[1], h[2], h[3], h[4]
          diff_body[#diff_body + 1] = string.format("@@ -%d,%d +%d,%d @@", old_start, old_count, new_start, new_count)
          for i = old_start, old_start + old_count - 1 do
            diff_body[#diff_body + 1] = "- " .. (old_lines[i] or "")
            deleted_n = deleted_n + 1
          end
          for i = new_start, new_start + new_count - 1 do
            diff_body[#diff_body + 1] = "+ " .. (new_lines[i] or "")
            added_n = added_n + 1
          end
        end
      end

      pcall(function()
        require("neowork.bridge")._record_diff(buf, added_n, deleted_n)
      end)
      diff_added = diff_added + added_n
      diff_deleted = diff_deleted + deleted_n

      if #body_lines > 0 then body_lines[#body_lines + 1] = "" end
      body_lines[#body_lines + 1] = "##### Changes"
      append_fenced_block(body_lines, "diff", diff_body)
    end

    local function walk_content(entries)
      if type(entries) ~= "table" then return end
      if entries.type or entries.text then
        entries = { entries }
      end
      for _, c in ipairs(entries) do
        if type(c) == "table" then
          if c.type == "diff" or c.oldText or c.newText then
            if not (tcid and seen[tcid]) then
              emit_diff(c)
              if tcid then seen[tcid] = true end
            end
          elseif c.type == "content" and type(c.content) == "table" then
            walk_content(c.content)
          elseif c.type ~= "image" then
            local text = (c.content and c.content.text) or c.text
            if text and is_initial then push_capped(text) end
          end
        end
      end
    end

    if type(su.content) == "table" then
      if su.content.text and not su.content.type then
        if is_initial then push_capped(su.content.text) end
      else
        walk_content(su.content)
      end
    end

    local summary_lines = {}
    if su.kind and su.kind ~= "" then
      summary_lines[#summary_lines + 1] = "- kind: `" .. tostring(su.kind) .. "`"
    end
    if status and status ~= "" then
      summary_lines[#summary_lines + 1] = "- status: `" .. tostring(status) .. "`"
    end
    if #summary_lines > 0 then
      for _, line in ipairs(summary_lines) do
        body_lines[#body_lines + 1] = line
      end
    end

    for _, section in ipairs(text_sections) do
      if #body_lines > 0 then body_lines[#body_lines + 1] = "" end
      body_lines[#body_lines + 1] = "##### Output"
      append_fenced_block(body_lines, "text", section)
    end

    if terminal then
      if #body_lines > 0 then body_lines[#body_lines + 1] = "" end
      body_lines[#body_lines + 1] = "- terminal result: `" .. tostring(status == const.plan_status.completed and "done" or status) .. "`"
      body_lines[#body_lines + 1] = "*" .. (status == const.plan_status.completed and "done" or status) .. "*"
    end

    if is_initial and (#body_lines > 0 or terminal) then
      local header_tag = had_diff and "edit" or "tool"
      local title = su.title or su.kind or "tool"
      local meta
      if had_diff then
        meta = string.format("%d files  +%d -%d", diff_files, diff_added, diff_deleted)
      elseif status and status ~= "" then
        meta = status
      elseif su.kind and su.kind ~= "" then
        meta = su.kind
      end
      local header_lnum = append_detail_block(buf, {
        tag = header_tag,
        title = title,
        meta = meta,
      }, body_lines)
      if had_diff then
        local ok, hl = pcall(require, "neowork.highlight")
        if ok then
          local total = vim.api.nvim_buf_line_count(buf)
          pcall(hl.apply, buf, math.max((header_lnum or total) - 1, 0), total)
        end
      end
    elseif terminal then
      append_detail_block(buf, {
        tag = had_diff and "edit" or "tool",
        title = su.title or su.kind or "tool",
        meta = status or su.kind,
      }, body_lines)
    end

    if is_initial then
      local ctx = get_session_context(buf)
      if ctx.sid then
        store.append_event(ctx.sid, ctx.root, {
          type = const.event.tool_call,
          kind = su.kind,
          title = su.title,
          status = su.status,
          toolCallId = su.toolCallId,
          content = su.content,
          rawOutput = su.rawOutput,
          locations = su.locations,
        })
        require("neowork.summary").bump_tool_count(ctx.sid)
      end
    elseif terminal then
      append_session_event(buf, {
        type = const.event.tool_call,
        kind = su.kind,
        title = su.title,
        status = su.status,
        toolCallId = su.toolCallId,
        content = su.content,
        rawOutput = su.rawOutput,
        locations = su.locations,
        terminal = true,
      })
    end

    if terminal or is_initial then
      set_summary_fallback(buf, tool_summary(su))
    end

  elseif t == const.event.plan then
    local ok, plan = pcall(require, "neowork.plan")
    if ok and su.entries then
      plan.on_plan_event(buf, su.entries)
    end
    set_summary_fallback(buf, plan_summary(su.entries))

  elseif t == const.event.usage_update or t == const.event.result then
    local doc = get_document()
    local fields = {}
    if su.tokenUsage then
      local total = (su.tokenUsage.inputTokens or 0) + (su.tokenUsage.outputTokens or 0)
      fields.tokens = total >= 1000 and string.format("%.1fk", total / 1000) or tostring(total)
    end
    local cost_num = tonumber(su.cost)
    if cost_num then
      fields.cost = string.format("%.4f", cost_num)
    end
    if next(fields) then doc.set_frontmatter_fields(buf, fields) end

    if t == const.event.usage_update then
      pcall(function()
        local bridge = get_bridge()
        bridge._usage[buf] = bridge._usage[buf] or {}
        if su.tokenUsage then
          bridge._usage[buf].input_tokens = su.tokenUsage.inputTokens or bridge._usage[buf].input_tokens or 0
          bridge._usage[buf].output_tokens = su.tokenUsage.outputTokens or bridge._usage[buf].output_tokens or 0
        end
        if cost_num then bridge._usage[buf].cost = cost_num end
      end)
    end

  elseif t == const.event.modes or t == const.event.current_mode_update
      or t == const.event.available_commands_update or t == const.event.config_option_update then
    if t == const.event.current_mode_update and su.modeId then
      append_detail_block(buf, {
        tag = "session",
        title = "update",
        meta = "mode",
      }, { "- mode: `" .. tostring(su.modeId) .. "`" })
    elseif t == const.event.modes then
      local available = su.availableModes or {}
      local current = su.currentModeId and ("current -> " .. tostring(su.currentModeId)) or nil
      local body = { "- modes available: `" .. tostring(#available) .. "`" }
      if current then body[#body + 1] = "- " .. current:gsub(" -> ", ": `") .. "`" end
      append_detail_block(buf, {
        tag = "session",
        title = "update",
        meta = "modes",
      }, body)
    elseif t == const.event.available_commands_update then
      local commands = su.availableCommands or su.commands or {}
      append_detail_block(buf, {
        tag = "session",
        title = "update",
        meta = "commands",
      }, { "- commands updated: `" .. tostring(#commands) .. "`" })
    elseif t == const.event.config_option_update then
      local option_id = su.optionId or su.configOptionId or "option"
      local value = su.value
      if value == nil then value = su.currentValue end
      append_detail_block(buf, {
        tag = "session",
        title = "update",
        meta = tostring(option_id),
      }, {
        "- value: `" .. tostring(vim.inspect(value)) .. "`",
      })
    end
    M._last_status_state = M._last_status_state or {}
    local sig = t .. ":" .. (su.currentModeId or su.modeId or "")
    if M._last_status_state[buf] ~= sig then
      M._last_status_state[buf] = sig
      request_status_redraw(buf)
    end
  end
end

return M
