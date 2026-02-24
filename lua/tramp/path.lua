local M = {}

function M.parse(tramp_path)
  if not tramp_path or not tramp_path:match("^/ssh:") then
    return nil
  end

  local user, host, path = tramp_path:match("^/ssh:([^@]+)@([^:]+):(.*)$")

  if not user or not host then
    user = nil
    host, path = tramp_path:match("^/ssh:([^:]+):(.*)$")
  end

  if not host or not path then
    return nil
  end

  return {
    user = user,
    host = host,
    path = path,
    original = tramp_path,
  }
end

function M.build(user, host, remote_path)
  if user then
    return string.format("/ssh:%s@%s:%s", user, host, remote_path)
  else
    return string.format("/ssh:%s:%s", host, remote_path)
  end
end

function M.normalize(remote_path)
  if not remote_path then
    return "/"
  end

  if not remote_path:match("^/") then
    remote_path = "/" .. remote_path
  end

  remote_path = remote_path:gsub("//+", "/")

  return remote_path
end

function M.join(...)
  local parts = { ... }
  local result = table.concat(parts, "/")
  return M.normalize(result)
end

function M.dirname(remote_path)
  if not remote_path or remote_path == "/" then
    return "/"
  end

  local dir = remote_path:match("^(.+)/[^/]*$")
  return dir or "/"
end

function M.basename(remote_path)
  if not remote_path or remote_path == "/" then
    return ""
  end

  local name = remote_path:match("^.+/([^/]*)$")
  return name or remote_path
end

return M
