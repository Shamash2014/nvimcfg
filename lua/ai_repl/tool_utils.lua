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

return M
