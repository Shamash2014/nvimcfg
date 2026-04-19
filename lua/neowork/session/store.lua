local const = require("neowork.const")

local M = {}

M._by_buf = {}

local function new_state(buf)
  return {
    buf = buf,
    turns = {},
    tools_by_id = {},
    turn_order = {},
    current_turn_id = nil,
    seq = 0,
    observers = {},
  }
end

local function get(buf)
  local s = M._by_buf[buf]
  if not s then
    s = new_state(buf)
    M._by_buf[buf] = s
  end
  return s
end

M.get = get

function M.reset(buf)
  local prev = M._by_buf[buf]
  local observers = prev and prev.observers or {}
  local fresh = new_state(buf)
  fresh.observers = observers
  M._by_buf[buf] = fresh
end

function M.detach(buf)
  M._by_buf[buf] = nil
end

function M.subscribe(buf, fn)
  local s = get(buf)
  s.observers[#s.observers + 1] = fn
  return function()
    for i, f in ipairs(s.observers) do
      if f == fn then
        table.remove(s.observers, i)
        return
      end
    end
  end
end

local function notify(s, change)
  for _, fn in ipairs(s.observers) do
    pcall(fn, s, change)
  end
end

local function next_seq(s)
  s.seq = s.seq + 1
  return s.seq
end

local function new_turn(s, role)
  local id = string.format("turn:%d", next_seq(s))
  local turn = {
    id = id,
    role = role,
    body = {},
    tool_ids = {},
    created_seq = s.seq,
  }
  s.turns[id] = turn
  s.turn_order[#s.turn_order + 1] = id
  s.current_turn_id = id
  return turn
end

function M.begin_user_turn(buf)
  local s = get(buf)
  local turn = new_turn(s, "user")
  notify(s, { kind = "turn_added", turn = turn })
  return turn
end

function M.add_user_message(buf, text)
  if not text or text == "" then return end
  local s = get(buf)
  local turn = new_turn(s, "user")
  turn.body[#turn.body + 1] = { kind = "text", text = text }
  notify(s, { kind = "turn_added", turn = turn })
  notify(s, { kind = "text_appended", turn = turn, text = text })
  return turn
end

function M.begin_assistant_turn(buf)
  local s = get(buf)
  if s.current_turn_id and s.turns[s.current_turn_id] and s.turns[s.current_turn_id].role == "assistant" then
    return s.turns[s.current_turn_id]
  end
  local turn = new_turn(s, "assistant")
  notify(s, { kind = "turn_added", turn = turn })
  return turn
end

local function current_assistant_turn(s)
  local id = s.current_turn_id
  local turn = id and s.turns[id]
  if turn and turn.role == "assistant" then return turn end
  return nil
end

function M.append_text(buf, text, opts)
  if not text or text == "" then return end
  local s = get(buf)
  opts = opts or {}
  local turn = current_assistant_turn(s)
  if not turn then
    turn = new_turn(s, "assistant")
    notify(s, { kind = "turn_added", turn = turn })
  end
  local body = turn.body
  local last = body[#body]
  local kind = opts.thought and "thought" or "text"
  if last and last.kind == kind then
    last.text = last.text .. text
  else
    body[#body + 1] = { kind = kind, text = text }
  end
  notify(s, { kind = "text_appended", turn = turn, text = text, thought = opts.thought })
end

function M.upsert_tool(buf, tool_id, patch)
  if not tool_id then return nil end
  local s = get(buf)
  local tool = s.tools_by_id[tool_id]
  local created = false
  if not tool then
    tool = {
      id = tool_id,
      kind = nil,
      title = nil,
      verb = nil,
      subject = nil,
      status = "pending",
      rawInput = nil,
      locations = nil,
      output = {},
      output_count = 0,
      diff = {},
      diff_added = 0,
      diff_deleted = 0,
      diff_files = {},
      expanded = false,
      created_seq = next_seq(s),
    }
    s.tools_by_id[tool_id] = tool
    local turn = current_assistant_turn(s) or new_turn(s, "assistant")
    turn.tool_ids[#turn.tool_ids + 1] = tool_id
    tool.turn_id = turn.id
    turn.body[#turn.body + 1] = { kind = "tool", id = tool_id }
    created = true
  end
  if patch then
    for k, v in pairs(patch) do
      tool[k] = v
    end
  end
  notify(s, { kind = created and "tool_added" or "tool_updated", tool = tool })
  return tool
end

function M.set_tool_expanded(buf, tool_id, expanded)
  local s = get(buf)
  local tool = s.tools_by_id[tool_id]
  if not tool then return end
  if tool.expanded == expanded then return end
  tool.expanded = expanded
  notify(s, { kind = "tool_toggled", tool = tool })
end

function M.get_tool(buf, tool_id)
  local s = get(buf)
  return s.tools_by_id[tool_id]
end

function M.list_tools(buf)
  local s = get(buf)
  local out = {}
  for _, id in ipairs(s.turn_order) do
    local turn = s.turns[id]
    if turn then
      for _, tid in ipairs(turn.tool_ids) do
        local tool = s.tools_by_id[tid]
        if tool then out[#out + 1] = tool end
      end
    end
  end
  return out
end

function M.list_turns(buf)
  local s = get(buf)
  local out = {}
  for _, id in ipairs(s.turn_order) do
    out[#out + 1] = s.turns[id]
  end
  return out
end

local function collect_text(content, acc, max)
  if type(content) ~= "table" then return end
  if content.type or content.text then content = { content } end
  for _, entry in ipairs(content) do
    if type(entry) == "table" then
      if entry.type == "content" and type(entry.content) == "table" then
        collect_text(entry.content, acc, max)
      elseif entry.type ~= "image" and entry.type ~= "diff" and not entry.oldText and not entry.newText then
        local text = (entry.content and entry.content.text) or entry.text
        if text then
          for line in tostring(text):gmatch("([^\n]*)\n?") do
            acc.total = acc.total + 1
            if acc.total <= max then acc.lines[#acc.lines + 1] = line end
          end
        end
      end
    end
  end
end

local function collect_diff(content)
  local files, added, deleted = {}, 0, 0
  local lines = {}
  local function walk(c)
    if type(c) ~= "table" then return end
    if c.type or c.oldText or c.newText then c = { c } end
    for _, entry in ipairs(c) do
      if type(entry) == "table" then
        if entry.type == "diff" or entry.oldText or entry.newText then
          local old_str = tostring(entry.oldText or "")
          local new_str = tostring(entry.newText or "")
          files[#files + 1] = { path = entry.path, old_text = old_str, new_text = new_str }
          if entry.path then lines[#lines + 1] = "--- " .. entry.path end
          for line in old_str:gmatch("([^\n]*)\n") do
            lines[#lines + 1] = "-" .. line
            deleted = deleted + 1
          end
          for line in new_str:gmatch("([^\n]*)\n") do
            lines[#lines + 1] = "+" .. line
            added = added + 1
          end
        elseif entry.type == "content" and type(entry.content) == "table" then
          walk(entry.content)
        end
      end
    end
  end
  walk(content)
  return lines, added, deleted, files
end

local function verb_for(kind, title)
  if kind and kind ~= "" and kind ~= "other" then return kind end
  if title and title ~= "" then
    return tostring(title):match("^(%w+)") or "tool"
  end
  return "tool"
end

function M.apply_event(buf, su, opts)
  if not su or not su.sessionUpdate then return end
  opts = opts or {}
  local max_output = opts.max_output or 50
  local t = su.sessionUpdate

  if t == const.event.agent_message_chunk then
    local text = su.content and su.content.text or ""
    if text ~= "" then M.append_text(buf, text) end

  elseif t == const.event.agent_thought_chunk then
    local text = su.content and su.content.text or ""
    if text ~= "" then M.append_text(buf, text, { thought = true }) end

  elseif t == const.event.user_message_chunk or t == const.event.user_message then
    local text = su.content and su.content.text
    if text and text ~= "" then
      local s = get(buf)
      local turn = s.current_turn_id and s.turns[s.current_turn_id]
      if not (turn and turn.role == "user") then
        turn = new_turn(s, "user")
        notify(s, { kind = "turn_added", turn = turn })
      end
      local last = turn.body[#turn.body]
      if last and last.kind == "text" then
        last.text = last.text .. text
      else
        turn.body[#turn.body + 1] = { kind = "text", text = text }
      end
      notify(s, { kind = "text_appended", turn = turn, text = text })
    end

  elseif t == const.event.tool_call or t == const.event.tool_call_update then
    local tcid = su.toolCallId or su.id
    if not tcid then return end
    local patch = {
      kind = su.kind,
      title = su.title,
      rawInput = su.rawInput,
      locations = su.locations,
    }
    patch.verb = verb_for(su.kind, su.title)
    if su.status and su.status ~= "" then patch.status = su.status end

    if su.locations and su.locations[1] then
      patch.subject = su.locations[1].path
    elseif su.rawInput then
      patch.subject = su.rawInput.file_path or su.rawInput.path or su.rawInput.command or su.rawInput.pattern or su.rawInput.query
    end

    if su.content then
      local acc = { lines = {}, total = 0 }
      collect_text(su.content, acc, max_output)
      if acc.total > 0 then
        patch.output = acc.lines
        patch.output_count = acc.total
      end
      local diff_lines, added, deleted, files = collect_diff(su.content)
      if #diff_lines > 0 then
        patch.diff = diff_lines
        patch.diff_added = added
        patch.diff_deleted = deleted
        patch.diff_files = files
      end
    end

    M.upsert_tool(buf, tcid, patch)
  end
end

return M
