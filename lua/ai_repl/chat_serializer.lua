local M = {}

local function escape_markdown(text)
  if not text then return "" end
  return text:gsub("\\", "\\\\")
end

local function format_timestamp(ts)
  if not ts then return "" end
  return os.date("%Y-%m-%d %H:%M:%S", ts)
end

local function message_to_chat(msg, idx)
  local role = msg.role or "user"
  local content = msg.content or ""
  local timestamp = msg.timestamp and os.date("%Y-%m-%d %H:%M:%S", msg.timestamp) or ""
  local tool_calls = msg.tool_calls

  local lines = {}

  -- Role header with timestamp
  if role == "user" then
    table.insert(lines, "@You:")
  elseif role == "djinni" or role == "system" then
    local role_name = role == "djinni" and "Djinni" or "System"
    table.insert(lines, "@" .. role_name .. ":")
  else
    table.insert(lines, "@" .. role .. ":")
  end

  -- Content
  if content ~= "" then
    -- Split into lines and handle code blocks
    for line in content:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
  end

  -- Tool calls (if any)
  if tool_calls and #tool_calls > 0 then
    for _, tool in ipairs(tool_calls) do
      local tool_id = tool.id or tool.toolCallId or "unknown"
      local tool_name = tool.title or tool.kind or tool.name or "unknown"
      local tool_input = tool.input or tool.rawInput or {}

      table.insert(lines, "")
      table.insert(lines, "**Tool Use:** `" .. tool_id .. "` (`" .. tool_name .. "`)")
      table.insert(lines, "")
      table.insert(lines, "```json")

      local json_str
      if type(tool_input) == "string" then
        json_str = tool_input
      else
        local ok, encoded = pcall(vim.json.encode, tool_input)
        json_str = ok and encoded or "{}"
      end

      for json_line in json_str:gmatch("[^\n]+") do
        table.insert(lines, json_line)
      end
      table.insert(lines, "```")
    end
  end

  table.insert(lines, "")

  return table.concat(lines, "\n")
end

local function annotation_to_chat(annotation)
  local lines = {}

  table.insert(lines, "@Annotation:")

  -- Location
  if annotation.start_line == annotation.end_line then
    table.insert(lines, "**Location:** `" .. annotation.file .. ":" .. annotation.start_line .. "`")
  else
    table.insert(lines, "**Location:** `" .. annotation.file .. ":" .. annotation.start_line .. "-" .. annotation.end_line .. "`")
  end

  -- Note
  if annotation.note then
    table.insert(lines, "**Note:** " .. annotation.note)
  end

  -- Code snippet (if available)
  if annotation.text and annotation.text ~= "" then
    table.insert(lines, "")
    table.insert(lines, "**Context:**")
    local lang = annotation.filetype or ""
    table.insert(lines, "```" .. lang)
    for line in annotation.text:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
  end

  table.insert(lines, "")
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

function M.serialize_to_chat(session_id, proc)
  proc = proc or require("ai_repl.registry").get(session_id)
  if not proc then
    return nil, "Process not found"
  end

  local messages = proc.data.messages or {}
  local session_name = proc.data.name or session_id:sub(1, 8)
  local provider = proc.data.provider or "unknown"
  local cwd = proc.data.cwd or vim.fn.getcwd()

  -- Load annotations if active annotation session exists
  local annotations = {}
  local annotation_session = require("ai_repl.annotations.session")
  if annotation_session.is_active() then
    local annotation_buf = annotation_session.get_bufnr()
    if annotation_buf and vim.api.nvim_buf_is_valid(annotation_buf) then
      local ann_lines = vim.api.nvim_buf_get_lines(annotation_buf, 0, -1, false)
      -- Parse annotation format: - **`file:line`** — note
      for _, line in ipairs(ann_lines) do
        local file_ref, note = line:match("^%-%s*%*%*`([^`]+)`%*%*%s*—%s*(.*)")
        if file_ref then
          local file, line_range = file_ref:match("^(.+):(%d+%-?%d*)")
          local start_line, end_line = line_range:match("^(%d+)%-(%d+)")
          if not end_line then
            start_line = tonumber(line_range)
            end_line = start_line
          else
            start_line = tonumber(start_line)
            end_line = tonumber(end_line)
          end

          table.insert(annotations, {
            file = file,
            start_line = start_line,
            end_line = end_line,
            note = note,
          })
        end
      end
    end
  end

  local lines = {}

  -- Annotations (if any)
  if #annotations > 0 then
    table.insert(lines, "<!--")
    table.insert(lines, "-- Annotations from this session")
    table.insert(lines, "-- Use /import-chat to restore annotation session")
    table.insert(lines, "-->")
    table.insert(lines, "")
    for _, ann in ipairs(annotations) do
      table.insert(lines, annotation_to_chat(ann))
    end
  end

  -- System prompt (if exists)
  local has_system = false
  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      table.insert(lines, message_to_chat(msg, 0))
      has_system = true
    end
  end

  -- User and djinni messages
  for i, msg in ipairs(messages) do
    if msg.role ~= "system" then
      table.insert(lines, message_to_chat(msg, i))
    end
  end

  return table.concat(lines, "\n"), nil
end

function M.save_chat_file(session_id, output_path)
  local proc = require("ai_repl.registry").get(session_id)
  if not proc then
    return nil, "Session not found"
  end

  local content, err = M.serialize_to_chat(session_id, proc)
  if err then
    return nil, err
  end

  local timestamp = os.time()
  local random = math.floor(math.random() * 10000)
  local chat_id = string.format("%s-%d-%04d.chat",
    proc.data.name or "chat",
    timestamp,
    random
  )
  local file_path = output_path or proc.data.cwd .. "/" .. chat_id

  local f = io.open(file_path, "w")
  if not f then
    return nil, "Failed to create file: " .. file_path
  end

  f:write(content)
  f:close()

  return file_path, nil
end

local function parse_role(content)
  local role = content:match("^@(%w+):")
  return role
end

local function extract_message_content(lines, start_idx)
  local content_lines = {}
  local tool_calls = {}
  local i = start_idx

  while i <= #lines do
    local line = lines[i]

    -- Check if we hit next role
    if line:match("^@%w+:") then
      break
    end

    -- Check for tool use blocks
    if line:match("^%*%*Tool Use:%*%*") then
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

        table.insert(tool_calls, {
          id = tool_id,
          kind = tool_name,
          title = tool_name,
          input = ok and input or {},
        })

        if i <= #lines and lines[i]:match("^```") then
          i = i + 1
        end
      end
    else
      table.insert(content_lines, line)
      i = i + 1
    end
  end

  local content = table.concat(content_lines, "\n")
  -- Remove trailing newlines
  content = content:gsub("%s*$", "")

  return content, tool_calls, i - 1
end

local function extract_annotation_content(lines, start_idx)
  local annotation = {
    note = "",
    text = "",
    filetype = "",
  }
  local i = start_idx

  -- Parse annotation fields
  while i <= #lines do
    local line = lines[i]

    -- Check if we hit next role or blank line after annotation
    if line:match("^@%w+:") or (line == "" and i > start_idx) then
      break
    end

    -- Extract location
    local location = line:match("^%*%*Location:%*%*%s*`([^`]+)`")
    if location then
      local file, line_range = location:match("^(.+):(%d+%-?%d*)")
      if file then
        annotation.file = file
        local start_line, end_line = line_range:match("^(%d+)%-(%d+)")
        if not end_line then
          annotation.start_line = tonumber(line_range)
          annotation.end_line = annotation.start_line
        else
          annotation.start_line = tonumber(start_line)
          annotation.end_line = tonumber(end_line)
        end
      end
      i = i + 1
      -- Extract note from same line if present
    elseif line:match("^%*%*Note:%*%*") then
      annotation.note = line:gsub("^%*%*Note:%*%*%s*", "")
      i = i + 1
    elseif line:match("^%*%*Context:%*%*") then
      -- Parse code block
      i = i + 1
      local code_lines = {}
      while i <= #lines do
        if lines[i]:match("^```") then
          local ft = lines[i]:match("^```%w*")
          annotation.filetype = ft or ""
          i = i + 1
          -- Collect code content
          while i <= #lines and not lines[i]:match("^```") do
            table.insert(code_lines, lines[i])
            i = i + 1
          end
          annotation.text = table.concat(code_lines, "\n")
          if i <= #lines and lines[i]:match("^```") then
            i = i + 1
          end
          break
        else
          i = i + 1
        end
      end
    else
      i = i + 1
    end
  end

  return annotation, i - 1
end

function M.load_chat_file(file_path)
  local f = io.open(file_path, "r")
  if not f then
    return nil, "Failed to open file: " .. file_path
  end

  local content = f:read("*a")
  f:close()

  local lines = vim.split(content, "\n", { trimempty = false })
  local messages = {}
  local metadata = {}
  local annotations = {}

  local i = 1

  -- Parse messages
  while i <= #lines do
    local line = lines[i]
    local role = parse_role(line)

    if role == "Annotation" or role:lower() == "annotation" then
      -- Parse @Annotation: message
      local annotation, next_idx = extract_annotation_content(lines, i + 1)
      if annotation and annotation.file then
        table.insert(annotations, annotation)
      end
      i = next_idx
    elseif role then
      local msg_content, tool_calls, last_idx = extract_message_content(lines, i + 1)

      local msg = {
        role = role:lower(),
        content = msg_content,
        timestamp = os.time(),
      }

      if tool_calls and #tool_calls > 0 then
        msg.tool_calls = tool_calls
      end

      table.insert(messages, msg)
      i = last_idx + 1
    else
      i = i + 1
    end
  end

  return {
    messages = messages,
    metadata = metadata,
    annotations = annotations,
  }, nil
end

return M
