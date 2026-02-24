local M = {}
local sshfs = require("tramp.sshfs")

function M.connect(host, user, config)
  local ssh_user = user or config.default_user or vim.fn.getenv("USER")
  local mount_info = sshfs.ensure_mount_sync(host, ssh_user, config.cache_dir)

  if not mount_info then
    return nil
  end

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
    sshfs.unmount_sync(conn.mount_info)
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
