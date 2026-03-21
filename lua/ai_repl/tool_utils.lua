local M = {}

M.STATUS_ICONS = {
  pending = "○",
  in_progress = "◐",
  completed = "●",
  failed = "✗",
}

function M.get_tool_description(title, input, locations, opts)
  opts = opts or {}
  local path_format = opts.path_format or ":~:."

  if title == "Read" or title == "Edit" or title == "Write" then
    local path = input.file_path or input.path or ""
    return vim.fn.fnamemodify(path, path_format)
  elseif title == "Bash" then
    local desc = input.description or ""
    if desc ~= "" then return desc end
    local cmd = input.command or ""
    local max_len = opts.max_cmd_len or 60
    if #cmd > max_len then cmd = cmd:sub(1, max_len - 3) .. "..." end
    return cmd
  elseif title == "Glob" then
    return input.pattern or ""
  elseif title == "Grep" then
    local pattern = input.pattern or ""
    if opts.include_path and input.path then
      return pattern .. " in " .. vim.fn.fnamemodify(input.path, path_format)
    end
    return pattern
  elseif title == "Task" then
    local desc = input.description or ""
    if desc == "" and input.prompt then
      desc = input.prompt:sub(1, 40)
    end
    return desc
  elseif title == "WebFetch" then
    local url = input.url or ""
    return url:match("://([^/]+)") or url:sub(1, 40)
  elseif title == "WebSearch" then
    return input.query or ""
  elseif title == "LSP" then
    return input.operation or ""
  elseif title == "KillShell" then
    return input.shell_id or ""
  elseif title == "Skill" then
    return input.skill or input.name or ""
  elseif title and title:match("^mcp__") then
    local tool_name = title:match("^mcp__[^_]+__(.+)$") or title
    return tool_name
  end

  if locations and #locations > 0 then
    local l = locations[1]
    local path = l.path or l.uri or ""
    local loc = vim.fn.fnamemodify(path, path_format)
    if opts.include_line and l.line then
      loc = loc .. ":" .. l.line
    end
    return loc
  end

  return ""
end

function M.get_tool_result_summary(tool)
  if not tool then return "Done" end
  local title = tool.title or tool.kind or ""
  local status = tool.status
  local raw_output = tool.rawOutput
  local raw_input = tool.rawInput or {}
  if type(raw_input) == "string" then
    local ok, parsed = pcall(vim.json.decode, raw_input)
    raw_input = ok and parsed or {}
  end

  if status == "failed" then
    local err_text = raw_output
    if type(err_text) ~= "string" or err_text == "" then
      err_text = nil
    end
    if err_text then
      local first_line = err_text:match("^([^\n]*)")
      if first_line and #first_line > 60 then
        first_line = first_line:sub(1, 57) .. "..."
      end
      return "Error: " .. (first_line or "unknown")
    end
    return "Failed"
  end

  if title == "Read" then
    if type(raw_output) == "string" then
      local _, count = raw_output:gsub("\n", "")
      return "(" .. (count + 1) .. " lines)"
    end
    return "Done"
  elseif title == "Bash" then
    local output = raw_output
    if type(output) == "table" then
      output = output.stdout or output.stderr or output.output or ""
    end
    if type(output) == "string" and output ~= "" then
      local first_line = output:match("^([^\n]*)")
      if first_line and first_line ~= "" then
        if #first_line > 60 then
          first_line = first_line:sub(1, 57) .. "..."
        end
        return first_line
      end
    end
    return "Done"
  elseif title == "Edit" then
    local path = (type(raw_input) == "table" and raw_input.file_path) or ""
    return "Updated " .. vim.fn.fnamemodify(path, ":t")
  elseif title == "Write" then
    local path = (type(raw_input) == "table" and raw_input.file_path) or ""
    return "Wrote " .. vim.fn.fnamemodify(path, ":t")
  elseif title == "Grep" or title == "Glob" then
    if type(raw_output) == "string" and raw_output ~= "" then
      local _, count = raw_output:gsub("\n", "")
      return count .. " files"
    end
    return "0 files"
  elseif title == "Task" or title == "Agent" then
    local output = raw_output
    if type(output) == "table" then
      output = output.stdout or output.output or ""
    end
    if type(output) == "string" and output ~= "" then
      local first_line = output:match("^%s*\n?([^\n]*)")
      if first_line and first_line ~= "" then
        if #first_line > 60 then
          first_line = first_line:sub(1, 57) .. "..."
        end
        return first_line
      end
    end
    return "Done"
  end

  return "Done"
end

function M.format_tool_output_lines(tool, opts)
  if not tool then return {} end
  opts = opts or {}
  local prefix = opts.prefix or "  \xe2\x8e\xbf  "

  local title = tool.title or tool.kind or ""
  local status = tool.status
  local raw_output = tool.rawOutput

  local wants_output = (title == "Bash" or title == "Task" or title == "Agent" or status == "failed")
  if not wants_output then return {} end

  local output = raw_output
  if type(output) == "table" then
    output = output.stdout or output.stderr or output.output or ""
  end
  if type(output) ~= "string" or output == "" then return {} end

  local all_lines = vim.split(output, "\n", { trimempty = false })
  while #all_lines > 0 and all_lines[#all_lines]:match("^%s*$") do
    table.remove(all_lines)
  end
  if #all_lines == 0 then return {} end

  local max_lines, mode
  if status == "failed" then
    max_lines = opts.max_lines or 5
    mode = "tail"
  elseif title == "Bash" then
    max_lines = opts.max_lines or 8
    mode = "tail"
  else
    max_lines = opts.max_lines or 5
    mode = "head"
  end

  local selected
  local truncated = #all_lines > max_lines
  if not truncated then
    selected = all_lines
  elseif mode == "tail" then
    selected = vim.list_slice(all_lines, #all_lines - max_lines + 1, #all_lines)
  else
    selected = vim.list_slice(all_lines, 1, max_lines)
  end

  local result = {}
  for _, line in ipairs(selected) do
    table.insert(result, prefix .. line)
  end
  if truncated then
    local remaining = #all_lines - max_lines
    table.insert(result, prefix .. "... (" .. remaining .. " more lines)")
  end

  return result
end

function M.parse_permission_options(agent_options)
  local entries = {}
  local seen_roles = {}

  for _, opt in ipairs(agent_options) do
    local oid = opt.optionId or opt.id
    if not oid then goto continue end

    local okind = opt.kind or ""
    local label = opt.label or opt.text or opt.name or oid
    local role

    if oid:match("allow_always") or oid:match("allowAlways") or okind:match("allow_always") then
      role = "always"
    elseif okind:match("deny") or oid:match("deny") or oid:match("no") or oid:match("reject") then
      role = "deny"
    elseif okind:match("allow") or oid:match("allow") or oid:match("yes") or oid:match("approve") then
      role = "allow"
    end

    if role and not seen_roles[role] then
      seen_roles[role] = true
      table.insert(entries, { id = oid, label = label, role = role })
    else
      table.insert(entries, { id = oid, label = label, role = role or "other" })
    end

    ::continue::
  end

  if #entries == 0 and #agent_options >= 1 then
    local first = agent_options[1]
    table.insert(entries, { id = first.optionId or first.id, label = first.label or first.text or first.name or "Allow", role = "allow" })
    if #agent_options >= 2 then
      local last = agent_options[#agent_options]
      table.insert(entries, { id = last.optionId or last.id, label = last.label or last.text or last.name or "Deny", role = "deny" })
    end
  end

  local allow = entries[1] and entries[1].role == "allow" and entries[1] or nil
  local deny, always
  for _, e in ipairs(entries) do
    if e.role == "allow" and not allow then allow = e end
    if e.role == "deny" and not deny then deny = e end
    if e.role == "always" and not always then always = e end
  end

  return {
    allow = allow and allow.id,
    deny = deny and deny.id,
    always = always and always.id,
    entries = entries,
  }
end

function M.build_permission_prompt(entries)
  local keys = {}
  local bindings = {}
  local key_order = { "y", "a", "n", "e", "d", "f", "g", "h" }
  local role_keys = { allow = "y", always = "a", deny = "n" }
  local used_keys = {}
  local cancel_key = "c"

  for _, entry in ipairs(entries) do
    local key = role_keys[entry.role]
    if key and not used_keys[key] then
      used_keys[key] = true
      table.insert(keys, "[" .. key .. "] " .. entry.label)
      table.insert(bindings, { key = key, id = entry.id, label = entry.label, role = entry.role })
    end
  end

  for _, entry in ipairs(entries) do
    if not vim.tbl_contains(vim.tbl_map(function(b) return b.id end, bindings), entry.id) then
      for _, k in ipairs(key_order) do
        if not used_keys[k] and k ~= cancel_key then
          used_keys[k] = true
          table.insert(keys, "[" .. k .. "] " .. entry.label)
          table.insert(bindings, { key = k, id = entry.id, label = entry.label, role = entry.role })
          break
        end
      end
    end
  end

  table.insert(keys, "[" .. cancel_key .. "] Cancel")
  table.insert(bindings, { key = cancel_key, id = nil, label = "Cancel", role = "cancel" })

  return "  " .. table.concat(keys, "  "), bindings
end

function M.format_tool_preview(title, input)
  if not input or type(input) ~= "table" then return {} end
  local lines = {}
  local max = 80

  local function trunc(s)
    if #s > max then return s:sub(1, max - 3) .. "..." end
    return s
  end

  if title == "Read" then
    local path = input.file_path or input.path or ""
    local extra = ""
    if input.offset then extra = extra .. " +" .. input.offset end
    if input.limit then extra = extra .. "," .. input.limit end
    table.insert(lines, trunc("  \xe2\x96\xb8 " .. path .. extra))

  elseif title == "Edit" then
    local path = input.file_path or input.path or ""
    table.insert(lines, trunc("  \xe2\x96\xb8 " .. path))
    if input.old_string then
      local first = input.old_string:match("^([^\n]*)")
      table.insert(lines, trunc("  \xe2\x96\xb8 old: " .. (first or "")))
    end
    if input.new_string then
      local first = input.new_string:match("^([^\n]*)")
      table.insert(lines, trunc("  \xe2\x96\xb8 new: " .. (first or "")))
    end

  elseif title == "Write" then
    local path = input.file_path or input.path or ""
    local size = input.content and #input.content or 0
    table.insert(lines, trunc("  \xe2\x96\xb8 " .. path .. " (" .. size .. " bytes)"))

  elseif title == "Bash" then
    local cmd = input.command or ""
    table.insert(lines, trunc("  \xe2\x96\xb8 $ " .. cmd))

  elseif title == "Glob" then
    local pattern = input.pattern or ""
    local path = input.path or ""
    local text = pattern
    if path ~= "" then text = text .. " in " .. path end
    table.insert(lines, trunc("  \xe2\x96\xb8 " .. text))

  elseif title == "Grep" then
    local pattern = input.pattern or ""
    local path = input.path or ""
    local text = "/" .. pattern .. "/"
    if path ~= "" then text = text .. " in " .. path end
    table.insert(lines, trunc("  \xe2\x96\xb8 " .. text))

  elseif title == "WebFetch" then
    local url = input.url or ""
    local domain = url:match("://([^/]+)") or url:sub(1, 40)
    table.insert(lines, trunc("  \xe2\x96\xb8 " .. domain))

  elseif title == "Task" or title == "Agent" then
    local desc = input.description or input.prompt or ""
    if desc ~= "" then
      table.insert(lines, trunc("  \xe2\x96\xb8 " .. desc))
    end

  else
    local parts = {}
    local count = 0
    for k, v in pairs(input) do
      if count >= 3 then break end
      local val = type(v) == "string" and v:sub(1, 20) or tostring(v)
      table.insert(parts, k .. "=" .. val)
      count = count + 1
    end
    if #parts > 0 then
      table.insert(lines, trunc("  \xe2\x96\xb8 " .. table.concat(parts, ", ")))
    end
  end

  return lines
end

return M
