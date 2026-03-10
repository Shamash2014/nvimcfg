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

function M.parse_permission_options(agent_options)
  local first_allow_id, first_deny_id, allow_always_id
  for _, opt in ipairs(agent_options) do
    local oid = opt.optionId or opt.id
    local okind = opt.kind or ""
    if oid then
      if oid:match("allow_always") or oid:match("allowAlways") then
        allow_always_id = allow_always_id or oid
      elseif okind:match("allow") or oid:match("allow") or oid:match("yes") or oid:match("approve") then
        first_allow_id = first_allow_id or oid
      end
      if okind:match("deny") or oid:match("deny") or oid:match("no") or oid:match("reject") then
        first_deny_id = first_deny_id or oid
      end
    end
  end

  -- Positional fallback: if pattern matching found nothing, use first/last options
  if #agent_options >= 2 then
    local first_oid = agent_options[1].optionId or agent_options[1].id
    local last_oid = agent_options[#agent_options].optionId or agent_options[#agent_options].id
    if not first_allow_id and not allow_always_id then
      first_allow_id = first_oid
    end
    if not first_deny_id then
      first_deny_id = last_oid
    end
  elseif #agent_options == 1 then
    local oid = agent_options[1].optionId or agent_options[1].id
    if not first_allow_id and not allow_always_id then
      first_allow_id = oid
    end
  end

  return {
    allow = first_allow_id,
    deny = first_deny_id,
    always = allow_always_id,
  }
end

return M
