local M = {}
local async_ssh = require("tramp.async_ssh")
local path = require("tramp.path")

M.SCHEME = "ssh"

local function get_tramp_module()
  return require("tramp")
end

function M.setup()
  local has_oil = pcall(require, "oil")
  if not has_oil then
    return false
  end

  local oil_config = require("oil.config")
  if not oil_config.adapters then
    oil_config.adapters = {}
  end

  oil_config.adapters.ssh = M

  return true
end

function M.normalize_url(url)
  if url:match("^/ssh:") then
    return url
  end
  return url
end

function M.parse_url(url)
  local parsed = path.parse(url)
  if not parsed then
    return nil
  end

  return {
    scheme = "ssh",
    host = parsed.host,
    user = parsed.user,
    path = parsed.path,
  }
end

function M.list(url, _, cb)
  local parsed = M.parse_url(url)
  if not parsed then
    cb("Invalid TRAMP URL", nil)
    return
  end

  local tramp = get_tramp_module()
  local conn = tramp.get_connection(parsed.host, parsed.user)

  if not conn then
    async_ssh.connect(parsed.host, parsed.user, tramp.config, function(new_conn, err)
      if err or not new_conn then
        cb(err or "Connection failed", nil)
        return
      end

      tramp.connections[parsed.user .. "@" .. parsed.host] = new_conn
      M._do_list(new_conn, parsed.path, cb)
    end)
  else
    M._do_list(conn, parsed.path, cb)
  end
end

function M._do_list(conn, remote_path, cb)
  async_ssh.list_directory(conn, remote_path, function(files, err)
    if err or not files then
      cb(err or "Failed to list directory", nil)
      return
    end

    local entries = {}
    for _, file in ipairs(files) do
      local entry_type = file.type == "directory" and "directory" or "file"
      table.insert(entries, {
        name = file.name,
        type = entry_type,
        id = file.path,
      })
    end

    cb(nil, entries)
  end)
end

function M.is_modifiable()
  return true
end

function M.perform_action(url, action, cb)
  local parsed = M.parse_url(url)
  if not parsed then
    cb("Invalid TRAMP URL")
    return
  end

  local tramp = get_tramp_module()
  local conn = tramp.get_connection(parsed.host, parsed.user)

  local function do_action(connection)
    if action.type == "create" then
      if action.entry_type == "directory" then
        local new_path = action.url:match("^/") and action.url or path.join(parsed.path, action.url)
        async_ssh.mkdir(connection, new_path, function(_, err)
          cb(err)
        end)
      else
        local new_path = action.url:match("^/") and action.url or path.join(parsed.path, action.url)
        async_ssh.write_file(connection, new_path, {}, function(_, err)
          cb(err)
        end)
      end
    elseif action.type == "delete" then
      local delete_path = action.url:match("^/") and action.url or path.join(parsed.path, action.url)
      async_ssh.delete_file(connection, delete_path, function(_, err)
        cb(err)
      end)
    elseif action.type == "move" then
      local src_parsed = M.parse_url(action.src_url)
      local dest_parsed = M.parse_url(action.dest_url)

      if src_parsed and dest_parsed then
        async_ssh.rename(connection, src_parsed.path, dest_parsed.path, function(_, err)
          cb(err)
        end)
      else
        cb("Invalid move operation")
      end
    elseif action.type == "copy" then
      cb("Copy not supported for remote files")
    else
      cb("Unknown action: " .. action.type)
    end
  end

  if not conn then
    async_ssh.connect(parsed.host, parsed.user, tramp.config, function(new_conn, err)
      if err or not new_conn then
        cb("Failed to connect to " .. parsed.host .. ": " .. (err or "unknown error"))
        return
      end

      local key = string.format("%s@%s", parsed.user or tramp.config.default_user or vim.fn.getenv("USER"), parsed.host)
      tramp.connections[key] = new_conn
      do_action(new_conn)
    end)
  else
    do_action(conn)
  end
end

function M.read_file(url, cb)
  local parsed = M.parse_url(url)
  if not parsed then
    cb("Invalid TRAMP URL", nil)
    return
  end

  local tramp = get_tramp_module()
  local conn = tramp.get_connection(parsed.host, parsed.user)

  local function do_read(connection)
    async_ssh.read_file(connection, parsed.path, function(content, err)
      if err then
        cb(err, nil)
        return
      end
      cb(nil, table.concat(content, "\n"))
    end)
  end

  if not conn then
    async_ssh.connect(parsed.host, parsed.user, tramp.config, function(new_conn, err)
      if err or not new_conn then
        cb("Failed to connect to " .. parsed.host .. ": " .. (err or "unknown error"), nil)
        return
      end

      local key = string.format("%s@%s", parsed.user or tramp.config.default_user or vim.fn.getenv("USER"), parsed.host)
      tramp.connections[key] = new_conn
      do_read(new_conn)
    end)
  else
    do_read(conn)
  end
end

function M.write_file(url, content, cb)
  local parsed = M.parse_url(url)
  if not parsed then
    cb("Invalid TRAMP URL")
    return
  end

  local tramp = get_tramp_module()
  local conn = tramp.get_connection(parsed.host, parsed.user)

  local function do_write(connection)
    local lines = vim.split(content, "\n")
    async_ssh.write_file(connection, parsed.path, lines, function(_, err)
      cb(err)
    end)
  end

  if not conn then
    async_ssh.connect(parsed.host, parsed.user, tramp.config, function(new_conn, err)
      if err or not new_conn then
        cb("Failed to connect to " .. parsed.host .. ": " .. (err or "unknown error"))
        return
      end

      local key = string.format("%s@%s", parsed.user or tramp.config.default_user or vim.fn.getenv("USER"), parsed.host)
      tramp.connections[key] = new_conn
      do_write(new_conn)
    end)
  else
    do_write(conn)
  end
end

return M
