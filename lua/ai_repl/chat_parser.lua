-- Chat parser module for .chat file format
-- Parses @Role: markers, frontmatter, and tool calls

local M = {}

local chat_state = require("ai_repl.chat_state")

-- Role markers
local ROLES = {
  ["@You:"] = "user",
  ["@User:"] = "user",
  ["@Djinni:"] = "djinni",
  ["@Assistant:"] = "djinni",  -- Legacy: use @Djinni: instead
  ["@System:"] = "system",
  ["@Annotation:"] = "annotation",
}

-- Annotation patterns
local ANNOTATION_PATTERNS = {
  location = "^%-%s*%*%*`([^`]+)`%*%*%s*—%s*(.*)",
  location_single = "^%-%s*%*%*`([^:]+):(%d+)`%*%*%s*—%s*(.*)",
  location_range = "^%-%s*%*%*`([^:]+):(%d+)%-(%d+)`%*%*%s*—%s*(.*)",
  code_block = "^%s*```(%w*)",
}

-- Invalidate parser cache for a buffer
function M.invalidate_cache(buf)
  local state = chat_state.get_buffer_state(buf)
  state.ast_cache = nil
  state.ast_changedtick = -1
end

-- Parse entire .chat buffer with caching using changedtick
function M.parse_buffer_cached(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return M.parse_buffer({}, nil)
  end

  local state = chat_state.get_buffer_state(buf)
  local current_tick = vim.api.nvim_buf_get_changedtick(buf)

  if state.ast_cache and state.ast_changedtick == current_tick then
    return state.ast_cache
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = M.parse_buffer(lines, buf)

  state.ast_cache = parsed
  state.ast_changedtick = current_tick

  return parsed
end

-- Parse entire .chat buffer (non-cached, used by parse_buffer_cached)
function M.parse_buffer(lines, buf)

  local result = {
    frontmatter = {},
    messages = {},
    tools = {},
    pending_tools = {},
    attachments = {},
    annotations = {},
    last_role = nil,
    session_id = nil,
  }

  local i = 1
  local in_frontmatter = false
  local in_tool = false
  local current_message = nil
  local tool_lines = {}

  -- Check for frontmatter (must be at start)
  if #lines > 0 and lines[1]:match("^```") then
    in_frontmatter = true
    local fm_lines = {}
    i = 2
    while i <= #lines and not lines[i]:match("^```") do
      table.insert(fm_lines, lines[i])
      i = i + 1
    end
    result.frontmatter = M.parse_frontmatter(fm_lines)
    if i <= #lines and lines[i]:match("^```") then
      i = i + 1
    end
  end

  -- Parse messages
  while i <= #lines do
    local line = lines[i]

    -- Check for annotation (special case - doesn't start a message)
    local annotation = M.parse_annotation_line(line)
    if annotation then
      table.insert(result.annotations, annotation)
      i = i + 1
    -- Check for role marker
    elseif M.parse_role_marker(line) then
      local role = M.parse_role_marker(line)
      -- Save previous message
      if current_message then
        table.insert(result.messages, current_message)
      end

      current_message = {
        role = role,
        content = "",
        tool_calls = {},
        start_line = i,
      }

      result.last_role = role
      i = i + 1

    -- Check for tool use block
    elseif line:match("^%*%*Tool Use:%*%*") and current_message then
      local tool_id, tool_name = line:match("^%*%*Tool Use:%*%*%s*`([^`]+)`%s*%(?`([^`]+)`%)?")
      if not tool_id then
        tool_id, tool_name = line:match("^%*%*Tool Use:%*%*%s*`([^`]+)`%s*`([^`]+)`")
      end
      i = i + 1

      -- Skip blank lines
      while i <= #lines and lines[i]:match("^%s*$") do
        i = i + 1
      end

      -- Parse JSON block
      if i <= #lines and lines[i]:match("^```json") then
        i = i + 1
        local json_lines = {}
        while i <= #lines and not lines[i]:match("^```") do
          table.insert(json_lines, lines[i])
          i = i + 1
        end

        local json_str = table.concat(json_lines, "\n")
        local ok, input = pcall(vim.json.decode, json_str)

        local tool = {
          id = tool_id,
          title = tool_name,
          kind = tool_name,
          input = ok and input or {},
          status = "completed", -- Default to completed for past tools
        }

        table.insert(current_message.tool_calls, tool)
        table.insert(result.tools, tool)

        -- Check if pending (placeholder)
        if not ok or vim.tbl_isempty(input) then
          tool.status = "pending"
          table.insert(result.pending_tools, tool)
        end

        if i <= #lines and lines[i]:match("^```") then
          i = i + 1
        end
      end

    -- Check for tool result
    elseif line:match("^%*%*Tool Result:%*%*") and current_message then
      i = i + 1
      -- Skip result content for now
      while i <= #lines and not lines[i]:match("^%*%*") do
        i = i + 1
      end

    -- Check for thinking block
    elseif line:match("^<thinking>") and current_message then
      local thinking_lines = {}
      i = i + 1
      while i <= #lines and not lines[i]:match("^</thinking>") do
        table.insert(thinking_lines, lines[i])
        i = i + 1
      end
      current_message.thinking = table.concat(thinking_lines, "\n")
      if i <= #lines and lines[i]:match("^</thinking>") then
        i = i + 1
      end

    -- Regular content line
    elseif current_message then
      if current_message.content == "" then
        current_message.content = line
      else
        current_message.content = current_message.content .. "\n" .. line
      end
      i = i + 1

    else
      -- Content before first role marker
      i = i + 1
    end
  end

  -- Save last message
  if current_message then
    table.insert(result.messages, current_message)
  end

  -- Extract session_id from frontmatter
  if result.frontmatter.session_id then
    result.session_id = result.frontmatter.session_id
  end

  return result
end

-- Parse frontmatter (Lua or JSON)
function M.parse_frontmatter(lines)
  local content = table.concat(lines, "\n")

  -- Try Lua first
  if content:match("^local") or content:match("^return") then
    local ok, result = loadstring(content)
    if ok then
      return result
    end
  end

  -- Try JSON
  local ok, result = pcall(vim.json.decode, content)
  if ok then
    return result
  end

  return {}
end

-- Parse role marker from line
function M.parse_role_marker(line)
  for marker, role in pairs(ROLES) do
    if line:match("^" .. vim.pesc(marker)) then
      return role
    end
  end
  return nil
end

-- Build prompt from content with @file references
function M.build_prompt(content, attachments)
  local prompt = { { type = "text", text = content } }

  -- Add file attachments
  for _, att in ipairs(attachments or {}) do
    local file_path = att.path
    if not vim.tbl_isempty(att) and vim.fn.filereadable(file_path) == 1 then
      table.insert(prompt, {
        type = "resource",
        resource = {
          uri = "file://" .. file_path,
          name = vim.fn.fnamemodify(file_path, ":t"),
          mimeType = att.mime_type or "text/plain",
        },
      })
    end
  end

  return prompt
end

-- Jump to next/previous message
function M.jump_to_message(buf, direction)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local current_line = cursor[1]

  local function find_message(start, step)
    for i = start, step > 0 and #lines or 1, step do
      if M.parse_role_marker(lines[i]) then
        return i
      end
    end
    return nil
  end

  local target_line
  if direction > 0 then
    target_line = find_message(current_line + 1, 1)
  else
    target_line = find_message(current_line - 1, -1)
  end

  if target_line then
    vim.api.nvim_win_set_cursor(win, { target_line, 0 })
  end
end

-- Select message as text object
function M.select_message(buf, whole)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local current_line = cursor[1]

  -- Find message start
  local start_line = current_line
  while start_line > 1 and not M.parse_role_marker(lines[start_line]) do
    start_line = start_line - 1
  end

  -- Find message end
  local end_line = start_line + 1
  while end_line <= #lines and not M.parse_role_marker(lines[end_line]) do
    end_line = end_line + 1
  end
  end_line = end_line - 1

  -- Set selection
  if whole then
    -- Visual select entire message linewise
    vim.api.nvim_win_set_cursor(win, { start_line, 0 })
    vim.cmd("normal! V")
    vim.api.nvim_win_set_cursor(win, { end_line, 0 })
  else
    -- Visual select inside message (without marker)
    vim.api.nvim_win_set_cursor(win, { start_line + 1, 0 })
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(win, { end_line, 0 })
  end
end

-- Generate frontmatter for new .chat buffer
function M.generate_frontmatter(opts)
  opts = opts or {}

  local lines = {
    "```lua",
  }

  -- Session metadata
  if opts.session_id then
    table.insert(lines, 'session_id = "' .. opts.session_id .. '"')
  end

  if opts.provider then
    table.insert(lines, 'provider = "' .. opts.provider .. '"')
  end

  if opts.mode then
    table.insert(lines, 'mode = "' .. opts.mode .. '"')
  end

  table.insert(lines, "```")
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

-- Generate empty .chat buffer template
function M.generate_template(opts)
  opts = opts or {}

  local lines = {}

  -- Frontmatter
  table.insert(lines, M.generate_frontmatter(opts))

  -- System prompt (optional)
  if opts.system then
    table.insert(lines, "@System:")
    table.insert(lines, opts.system)
    table.insert(lines, "")
  end

  -- User message placeholder
  table.insert(lines, "@You:")
  table.insert(lines, "")
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

-- Parse annotation line from buffer
function M.parse_annotation_line(line)
  -- Match: - **`file:line`** — note
  local file_single, line_single, note = line:match("^%s*%-%s*%*`([^`]+):(%d+)`%*%*%s*—%s*(.-)%s*$")
  if file_single and line_single and note then
    return {
      file = file_single,
      start_line = tonumber(line_single),
      end_line = tonumber(line_single),
      note = note,
      type = "location"
    }
  end

  -- Match: - **`file:line-line`** — note
  local file_range, line_start, line_end, note_range = line:match("^%s*%-%s*%*`([^`]+):(%d+)%-(%d+)`%*%*%s*—%s*(.-)%s*$")
  if file_range and line_start and line_end and note_range then
    return {
      file = file_range,
      start_line = tonumber(line_start),
      end_line = tonumber(line_end),
      note = note_range,
      type = "location"
    }
  end

  -- Match: - **`file:line`**
  local file_simple, line_simple = line:match("^%s*%-%s*%*`([^`]+):(%d+)`%*%*%s*$")
  if file_simple and line_simple then
    return {
      file = file_simple,
      start_line = tonumber(line_simple),
      end_line = tonumber(line_simple),
      note = "",
      type = "location"
    }
  end

  return nil
end

-- Generate annotation line in .chat format
function M.generate_annotation_line(annotation)
  if annotation.start_line == annotation.end_line then
    return string.format("- **`%s:%d`** — %s",
      annotation.file,
      annotation.start_line,
      annotation.note or ""
    )
  else
    return string.format("- **`%s:%d-%d`** — %s",
      annotation.file,
      annotation.start_line,
      annotation.end_line,
      annotation.note or ""
    )
  end
end

-- Parse code block from annotation (snippet mode)
function M.parse_code_block(lines, start_idx, filetype)
  local code_lines = {}
  local i = start_idx

  -- Skip blank lines before code block
  while i <= #lines and lines[i]:match("^%s*$") do
    i = i + 1
  end

  -- Check for code block marker
  if i <= #lines and lines[i]:match("^```" .. (filetype or "")) then
    i = i + 1
    while i <= #lines and not lines[i]:match("^```") do
      table.insert(code_lines, lines[i])
      i = i + 1
    end
  end

  return table.concat(code_lines, "\n")
end

return M
