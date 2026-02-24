local M = {}
local sshfs = require("tramp.sshfs")

function M.connect(host, user, config)
  local ssh_user = user or config.default_user or vim.fn.getenv("USER")
  local mount_point, mount_key = sshfs.get_mount_point(host, ssh_user, config.cache_dir)

  if sshfs.mounts[mount_key] and sshfs.is_mounted(mount_point) then
    return {
      host = host,
      user = ssh_user,
      mount_info = sshfs.mounts[mount_key],
      connected = true,
      last_used = os.time(),
    }
  end

  vim.fn.mkdir(mount_point, "p")

  local sshfs_cmd = string.format(
    "sshfs -o reconnect -o ServerAliveInterval=15 -o ServerAliveCountMax=3 %s@%s:/ %s",
    ssh_user,
    host,
    vim.fn.shellescape(mount_point)
  )

  vim.fn.system(sshfs_cmd)

  if vim.v.shell_error ~= 0 then
    vim.fn.delete(mount_point, "d")
    return nil
  end

  local mount_info = {
    host = host,
    user = ssh_user,
    mount_point = mount_point,
    mount_key = mount_key,
    mounted_at = os.time(),
  }

  sshfs.mounts[mount_key] = mount_info

  return {
    host = host,
    user = ssh_user,
    mount_info = mount_info,
    connected = true,
    last_used = os.time(),
  }
end

function M.disconnect(conn)
  if conn and conn.mount_info then
    local mount_point = conn.mount_info.mount_point
    vim.fn.system("umount " .. vim.fn.shellescape(mount_point))
    if vim.v.shell_error == 0 then
      sshfs.mounts[conn.mount_info.mount_key] = nil
      vim.fn.delete(mount_point, "d")
    end
    conn.connected = false
  end
end

function M.is_alive(conn)
  if not conn or not conn.connected or not conn.mount_info then
    return false
  end

  if not sshfs.is_mounted(conn.mount_info.mount_point) then
    conn.connected = false
    return false
  end

  conn.last_used = os.time()
  return true
end

function M.read_file(conn, remote_path)
  if not M.is_alive(conn) or not conn.mount_info then
    return nil
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  local ok, result = pcall(vim.fn.readfile, local_path)
  if not ok then
    return nil
  end

  conn.last_used = os.time()
  return result
end

function M.write_file(conn, remote_path, content)
  if not M.is_alive(conn) or not conn.mount_info then
    return false
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  local dir = vim.fn.fnamemodify(local_path, ":h")
  vim.fn.mkdir(dir, "p")

  local ok, err = pcall(vim.fn.writefile, content, local_path)

  conn.last_used = os.time()
  return ok and err == 0
end

function M.list_directory(conn, remote_path)
  if not M.is_alive(conn) or not conn.mount_info then
    return nil
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  local ok, entries = pcall(vim.fn.readdir, local_path)
  if not ok then
    return nil
  end

  local files = {}
  for _, name in ipairs(entries) do
    if name ~= "." and name ~= ".." then
      local full_local = local_path .. "/" .. name
      local full_remote = remote_path
      if not remote_path:match("/$") then
        full_remote = remote_path .. "/"
      end
      full_remote = full_remote .. name

      local is_dir = vim.fn.isdirectory(full_local) == 1

      table.insert(files, {
        name = name,
        path = full_remote,
        type = is_dir and "directory" or "file",
      })
    end
  end

  table.sort(files, function(a, b)
    if a.type ~= b.type then
      return a.type == "directory"
    end
    return a.name < b.name
  end)

  conn.last_used = os.time()
  return files
end

function M.file_exists(conn, remote_path)
  if not M.is_alive(conn) or not conn.mount_info then
    return false
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  conn.last_used = os.time()
  return vim.fn.filereadable(local_path) == 1 or vim.fn.isdirectory(local_path) == 1
end

function M.delete_file(conn, remote_path)
  if not M.is_alive(conn) or not conn.mount_info then
    return false
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  local ok, err = pcall(vim.fn.delete, local_path)

  conn.last_used = os.time()
  return ok and err == 0
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
