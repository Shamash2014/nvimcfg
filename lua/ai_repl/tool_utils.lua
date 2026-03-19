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
    return "Done"
  end

  return "Done"
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

return M
