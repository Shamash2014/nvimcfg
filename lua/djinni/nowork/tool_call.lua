local M = {}

local function content_text(tc)
  local out = {}
  for _, c in ipairs((tc or {}).content or {}) do
    if c and c.type == "content" and c.content and c.content.text then
      out[#out + 1] = c.content.text
    elseif c and c.text then
      out[#out + 1] = c.text
    end
  end
  return table.concat(out, "\n")
end

local function locations_summary(tc)
  local locs = tc and tc.locations
  if not locs or #locs == 0 then return nil end
  local parts = {}
  for i, l in ipairs(locs) do
    if i > 3 then
      parts[#parts + 1] = "…"
      break
    end
    local p = l.path or l.file or ""
    if l.line then p = p .. ":" .. tostring(l.line) end
    if p ~= "" then parts[#parts + 1] = p end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ")
end

function M.render_command(raw_input, tc)
  if type(raw_input) == "string" and raw_input ~= "" then return raw_input end
  if type(raw_input) == "table" then
    local command = raw_input.command or raw_input.cmd
    if command and command ~= "" then
      local desc = raw_input.description
      if desc and desc ~= "" then
        return "$ " .. tostring(command) .. "  — " .. tostring(desc)
      end
      return "$ " .. tostring(command)
    end
    if raw_input.file_path and raw_input.content then
      return "📝 " .. tostring(raw_input.file_path)
    end
    if raw_input.path and raw_input.content then
      return "📝 " .. tostring(raw_input.path)
    end
    local path = raw_input.file_path or raw_input.path or raw_input.filePath
    if path and path ~= "" then
      if raw_input.old_string or raw_input.new_string or raw_input.patch then
        return "✎ " .. tostring(path)
      end
      return tostring(path)
    end
    if raw_input.url then return "↗ " .. tostring(raw_input.url) end
    if raw_input.pattern then return "🔎 " .. tostring(raw_input.pattern) end
    if raw_input.query then return "? " .. tostring(raw_input.query) end
    if raw_input.description then return tostring(raw_input.description) end
  end
  local loc = locations_summary(tc)
  if loc then return loc end
  local txt = content_text(tc)
  if txt and txt ~= "" then
    local first = txt:match("([^\n]+)") or txt
    return first
  end
  if type(raw_input) == "table" and next(raw_input) then
    local ok, encoded = pcall(vim.json.encode, raw_input)
    if ok and encoded then return encoded end
  end
  return nil
end

function M.append_log(log_buf, tc, tc_state)
  tc_state = tc_state or {}
  local id = tc.toolCallId or tc.id or tc.title or tostring(tc)
  local kind = tc.kind or (tc_state[id] and tc_state[id].kind) or "tool"
  local title = tc.title or tc.name or (tc_state[id] and tc_state[id].title) or kind
  local status = (tc.status or "pending"):lower()
  local prev = tc_state[id]
  if prev and prev.status == status then return end
  tc_state[id] = { kind = kind, title = title, status = status }

  local marker
  if status == "completed" then
    marker = "  ✓"
  elseif status == "failed" or status == "error" then
    marker = "  ✗"
  elseif status == "running" or status == "in_progress" then
    marker = "  …"
  else
    marker = "  ·"
  end

  log_buf:append(string.format("%s [%s] %s · %s", marker, status, kind, title))

  if not prev then
    local detail = M.render_command(tc.rawInput or tc.raw_input or tc.input, tc)
    if detail then
      for _, line in ipairs(vim.split(detail, "\n", { plain = true })) do
        log_buf:append("     " .. line)
      end
    end
  end

  if status == "completed" or status == "failed" or status == "error" then
    local body = content_text(tc)
    if body ~= "" then
      local lines = vim.split(body, "\n", { plain = true })
      local max = 6
      for i = 1, math.min(#lines, max) do
        log_buf:append("     " .. lines[i])
      end
      if #lines > max then
        log_buf:append(string.format("     … (%d more lines)", #lines - max))
      end
    end
  end
end

M.content_text = content_text
M.locations_summary = locations_summary

return M
