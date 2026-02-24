local M = {}

function M.connect(host, user, config)
  local ssh_user = user or config.default_user or vim.fn.getenv("USER")
  local ssh_command = string.format("ssh -o ConnectTimeout=%d %s@%s", config.connection_timeout, ssh_user, host)

  local test_cmd = ssh_command .. " 'echo TRAMP_OK'"
  local result = vim.fn.systemlist(test_cmd)

  if vim.v.shell_error ~= 0 or not vim.tbl_contains(result, "TRAMP_OK") then
    return nil
  end

  return {
    host = host,
    user = ssh_user,
    ssh_command = ssh_command,
    connected = true,
    last_used = os.time(),
  }
end

function M.disconnect(conn)
  if conn then
    conn.connected = false
  end
end

function M.is_alive(conn)
  if not conn or not conn.connected then
    return false
  end

  if os.time() - conn.last_used > 300 then
    local test_cmd = conn.ssh_command .. " 'echo ALIVE'"
    local result = vim.fn.systemlist(test_cmd)

    if vim.v.shell_error ~= 0 or not vim.tbl_contains(result, "ALIVE") then
      conn.connected = false
      return false
    end
  end

  conn.last_used = os.time()
  return true
end

function M.read_file(conn, remote_path)
  if not M.is_alive(conn) then
    return nil
  end

  local escaped_path = vim.fn.shellescape(remote_path)
  local cmd = conn.ssh_command .. " 'cat " .. escaped_path .. "'"

  local result = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  conn.last_used = os.time()
  return result
end

function M.write_file(conn, remote_path, content)
  if not M.is_alive(conn) then
    return false
  end

  local escaped_path = vim.fn.shellescape(remote_path)

  local temp_file = vim.fn.tempname()
  vim.fn.writefile(content, temp_file)

  local scp_cmd = string.format("scp %s %s@%s:%s", vim.fn.shellescape(temp_file), conn.user, conn.host, escaped_path)

  vim.fn.system(scp_cmd)
  local success = vim.v.shell_error == 0

  vim.fn.delete(temp_file)

  conn.last_used = os.time()
  return success
end

function M.list_directory(conn, remote_path)
  if not M.is_alive(conn) then
    return nil
  end

  local escaped_path = vim.fn.shellescape(remote_path)
  local cmd = conn.ssh_command
    .. " 'ls -1ApL --group-directories-first "
    .. escaped_path
    .. " 2>/dev/null || ls -1Ap "
    .. escaped_path
    .. "'"

  local result = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  local files = {}
  for _, line in ipairs(result) do
    if line ~= "" and line ~= "./" and line ~= "../" then
      local is_dir = line:match("/$")
      local name = is_dir and line:sub(1, -2) or line

      local full_path = remote_path
      if not remote_path:match("/$") then
        full_path = remote_path .. "/"
      end
      full_path = full_path .. name

      table.insert(files, {
        name = name,
        path = full_path,
        type = is_dir and "directory" or "file",
      })
    end
  end

  conn.last_used = os.time()
  return files
end

function M.file_exists(conn, remote_path)
  if not M.is_alive(conn) then
    return false
  end

  local escaped_path = vim.fn.shellescape(remote_path)
  local cmd = conn.ssh_command .. " 'test -e " .. escaped_path .. " && echo EXISTS'"

  local result = vim.fn.systemlist(cmd)

  conn.last_used = os.time()
  return vim.v.shell_error == 0 and vim.tbl_contains(result, "EXISTS")
end

function M.delete_file(conn, remote_path)
  if not M.is_alive(conn) then
    return false
  end

  local escaped_path = vim.fn.shellescape(remote_path)
  local cmd = conn.ssh_command .. " 'rm -f " .. escaped_path .. "'"

  vim.fn.system(cmd)

  conn.last_used = os.time()
  return vim.v.shell_error == 0
end

function M.get_ssh_hosts(ssh_config_path)
  local hosts = {}

  if vim.fn.filereadable(ssh_config_path) == 0 then
    return hosts
  end

  local lines = vim.fn.readfile(ssh_config_path)
  local current_host = nil

  for _, line in ipairs(lines) do
    line = vim.trim(line)

    if line:match("^Host%s+") then
      local host_pattern = line:match("^Host%s+(.+)$")

      if host_pattern and not host_pattern:match("[*?]") then
        current_host = {
          name = host_pattern,
          hostname = nil,
          user = nil,
        }
        table.insert(hosts, current_host)
      else
        current_host = nil
      end
    elseif current_host then
      local hostname = line:match("^HostName%s+(.+)$")
      if hostname then
        current_host.hostname = hostname
      end

      local user = line:match("^User%s+(.+)$")
      if user then
        current_host.user = user
      end
    end
  end

  return hosts
end

return M
