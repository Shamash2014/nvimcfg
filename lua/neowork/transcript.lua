local M = {}

local function session_id(buf)
  local ok, document = pcall(require, "neowork.document")
  if not ok then return "" end
  return document.read_frontmatter_field(buf, "session") or ""
end

local function first_line(text)
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then return trimmed end
  end
  return ""
end

local function summarize(ev)
  local ts = ev.ts or ""
  if ev.type == "user" then
    return "# You", first_line(ev.content), "N"
  elseif ev.type == "assistant" or ev.type == "agent_message" then
    return "# Djinni", first_line(ev.content), "N"
  elseif ev.type == "tool_call" then
    local label = ev.title or ev.kind or "tool"
    local path = (ev.locations and ev.locations[1] and ev.locations[1].path)
      or (ev.rawInput and (ev.rawInput.file_path or ev.rawInput.path))
    if path then label = label .. "  " .. vim.fn.fnamemodify(path, ":t") end
    local status = ev.status or "?"
    local sym = status == "completed" and "I" or (status == "failed" or status == "error") and "E" or "W"
    return "[*] " .. label, status, sym
  elseif ev.type == "plan" then
    local total = ev.entries and #ev.entries or 0
    local done = 0
    for _, e in ipairs(ev.entries or {}) do
      if e.status == "completed" then done = done + 1 end
    end
    return "### Plan", string.format("%d/%d done", done, total), "W"
  elseif ev.type == "result" then
    local tok = ev.tokens or {}
    local total = (tok.inputTokens or 0) + (tok.outputTokens or 0)
    return "# System result", string.format("tokens=%d cost=%s", total, tostring(ev.cost or 0)), "I"
  else
    return "# System " .. (ev.type or "?"), ts, "N"
  end
end

local function build_items(buf, events)
  local items = {}
  for _, ev in ipairs(events) do
    local head, tail, sym = summarize(ev)
    local text = tail ~= "" and (head .. "  " .. tail) or head
    if ev.ts then text = text .. "  (" .. ev.ts .. ")" end
    items[#items + 1] = {
      bufnr = buf,
      lnum = 1,
      col = 1,
      text = text,
      type = sym,
      valid = 0,
    }
  end
  if #items == 0 then
    items[#items + 1] = { bufnr = buf, lnum = 1, col = 1, text = "(transcript empty)", valid = 0 }
  end
  return items
end

local function ll_title(buf, sid, count)
  local name = vim.api.nvim_buf_get_name(buf)
  local short = name ~= "" and vim.fn.fnamemodify(name, ":t") or ("buf " .. buf)
  local sidshort = sid ~= "" and (" — " .. sid:sub(1, 12)) or ""
  return string.format("Neowork Transcript — %s%s (%d)", short, sidshort, count)
end

function M.open(buf, opts)
  if type(buf) == "table" then
    opts = buf
    buf = nil
  end
  buf = buf or vim.api.nvim_get_current_buf()
  opts = opts or {}

  local document = require("neowork.document")
  local store = require("neowork.store")
  local sid = session_id(buf)
  local root = document.read_frontmatter_field(buf, "root") or vim.fn.getcwd()

  if sid == "" then
    vim.notify("neowork: no session id", vim.log.levels.WARN)
    return
  end

  if vim.bo[buf].modified then pcall(vim.cmd, "silent! write") end

  local events = store.read_transcript(sid, root) or {}
  local items = build_items(buf, events)

  local win = vim.api.nvim_get_current_win()
  vim.fn.setloclist(win, {}, " ", { title = ll_title(buf, sid, #events), items = items })
  vim.cmd("lopen")
end

function M.close(buf)
  local win = vim.api.nvim_get_current_win()
  pcall(vim.fn.setloclist, win, {}, "f")
  pcall(vim.cmd, "lclose")
  _ = buf
end

local function render_tool_content(content, cap)
  local out, n = {}, 0
  local function push(text)
    if n >= cap then return end
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
      if n >= cap then out[#out + 1] = "… (more)"; return end
      out[#out + 1] = line
      n = n + 1
    end
  end
  local function walk(c)
    if type(c) ~= "table" then return end
    if c.type == "diff" then
      out[#out + 1] = "```diff"
      if c.path then out[#out + 1] = "--- " .. c.path end
      if c.oldText then for line in tostring(c.oldText):gmatch("[^\r\n]+") do out[#out + 1] = "-" .. line end end
      if c.newText then for line in tostring(c.newText):gmatch("[^\r\n]+") do out[#out + 1] = "+" .. line end end
      out[#out + 1] = "```"
      return
    end
    if c.text and not c.type then push(c.text); return end
    if c.content then walk(c.content); return end
    if #c > 0 then
      for _, entry in ipairs(c) do walk(entry) end
      return
    end
    local text = (c.content and c.content.text) or c.text
    if text then push(text) end
  end
  walk(content)
  return out
end

local function render_events(events)
  local ok_cfg, config = pcall(require, "neowork.config")
  local cap = ok_cfg and (config.get and config.get("max_tool_output_lines") or 20) or 20
  local seen_tool = {}
  local tool_final = {}
  for _, ev in ipairs(events) do
    if ev.type == "tool_call" and ev.toolCallId then
      local prev = tool_final[ev.toolCallId]
      if not prev then
        tool_final[ev.toolCallId] = ev
      else
        tool_final[ev.toolCallId] = vim.tbl_extend("keep", ev, prev)
      end
    end
  end
  local out = {}
  local djinni_open = false
  local djinni_ts = ""
  local function close_djinni()
    if not djinni_open then return end
    out[#out + 1] = ""
    out[#out + 1] = "---"
    out[#out + 1] = ""
    djinni_open = false
  end
  local function ensure_djinni(ts)
    if djinni_open then return end
    out[#out + 1] = "# Djinni  " .. (ts or djinni_ts or "")
    djinni_open = true
    djinni_ts = ts or djinni_ts
  end
  for _, ev in ipairs(events) do
    local ts = ev.ts or ""
    if ev.type == "user" then
      close_djinni()
      out[#out + 1] = "# You  " .. ts
      for line in (ev.content or ""):gmatch("[^\n]+") do
        out[#out + 1] = line
      end
      out[#out + 1] = ""
      out[#out + 1] = "---"
      out[#out + 1] = ""
    elseif ev.type == "assistant" or ev.type == "agent_message" then
      ensure_djinni(ts)
      for line in (ev.content or ""):gmatch("[^\n]+") do
        out[#out + 1] = line
      end
    elseif ev.type == "tool_call" then
      local tcid = ev.toolCallId
      if tcid and seen_tool[tcid] then
        -- already emitted the final version
      else
        if tcid then seen_tool[tcid] = true end
        ensure_djinni(ts)
        local final = (tcid and tool_final[tcid]) or ev
        local path = nil
        if final.locations and final.locations[1] then path = final.locations[1].path end
        if not path and final.rawInput then
          path = final.rawInput.file_path or final.rawInput.path
        end
        local args = final.rawInput and (final.rawInput.command or final.rawInput.pattern or final.rawInput.query)
        local head = string.format("[*] %s", final.title or final.kind or "tool")
        if final.kind and final.kind ~= (final.title or "") then
          head = head .. "  (" .. final.kind .. ")"
        end
        if path then head = head .. "  " .. path end
        if args then
          head = head .. "  — " .. tostring(args):gsub("\r?\n.*$", ""):sub(1, 160)
        end
        out[#out + 1] = head .. "  [" .. (final.status or "?") .. "]  " .. ts
        if final.content then
          local body = render_tool_content(final.content, cap)
          for _, l in ipairs(body) do out[#out + 1] = l end
        end
        out[#out + 1] = ""
      end
    elseif ev.type == "plan" then
      ensure_djinni(ts)
      out[#out + 1] = "### Plan  " .. ts
      for _, e in ipairs(ev.entries or {}) do
        local mark = e.status == "completed" and "[x]" or (e.status == "in_progress" and "[>]" or "[ ]")
        out[#out + 1] = "- " .. mark .. " " .. (e.text or "")
      end
      out[#out + 1] = ""
    elseif ev.type == "result" then
      close_djinni()
      local tok = ev.tokens or {}
      local total = (tok.inputTokens or 0) + (tok.outputTokens or 0)
      out[#out + 1] = string.format("# System  result — tokens=%d cost=%s  %s", total, tostring(ev.cost or 0), ts)
      out[#out + 1] = ""
      out[#out + 1] = "---"
      out[#out + 1] = ""
    else
      out[#out + 1] = string.format("# System  %s  %s", ev.type or "?", ts)
    end
  end
  close_djinni()
  if #out == 0 then out[#out + 1] = "(transcript empty)" end
  return out
end

function M.open_full(buf, opts)
  buf = buf or vim.api.nvim_get_current_buf()
  opts = opts or {}
  local document = require("neowork.document")
  local store = require("neowork.store")
  local sid = document.read_frontmatter_field(buf, "session") or ""
  local root = document.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
  if sid == "" then
    vim.notify("neowork: no session id", vim.log.levels.WARN)
    return
  end

  local events = store.read_transcript(sid, root)
  local lines = render_events(events)

  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].swapfile = false
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  vim.bo[scratch].modifiable = false
  vim.bo[scratch].filetype = "markdown"
  vim.bo[scratch].syntax = "markdown"
  vim.b[scratch].neowork_chat = true
  vim.b[scratch].neowork_transcript = true

  local win
  if opts.float then
    local title = " Full Transcript — " .. sid:sub(1, 12) .. " (" .. #events .. " events) "
    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * 0.9)
    win = vim.api.nvim_open_win(scratch, true, {
      relative = "editor", width = width, height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal", border = "rounded", title = title, title_pos = "center",
    })
  else
    local mods = opts.mods
    if not mods or mods == "" then mods = "botright" end
    local split = opts.split == "vsplit" and "vsplit" or "split"
    vim.cmd(mods .. " " .. split)
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, scratch)
  end

  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  pcall(require("neowork.highlight").apply, scratch)
  pcall(vim.api.nvim_win_set_cursor, win, { #lines, 0 })

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local function reload()
    local fresh = store.read_transcript(sid, root)
    local fresh_lines = render_events(fresh)
    vim.bo[scratch].modifiable = true
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, fresh_lines)
    vim.bo[scratch].modifiable = false
    pcall(require("neowork.highlight").apply, scratch)
    pcall(vim.api.nvim_win_set_cursor, win, { #fresh_lines, 0 })
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, close, { buffer = scratch, silent = true, nowait = true })
  end
  vim.keymap.set("n", "R", reload, { buffer = scratch, silent = true, nowait = true, desc = "neowork: reload full transcript" })
  if opts.float then
    vim.api.nvim_create_autocmd("BufLeave", { buffer = scratch, once = true, callback = close })
  end
end

return M
