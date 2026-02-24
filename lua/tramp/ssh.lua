local M = {}
local rsync_ssh = require("tramp.rsync_ssh")

function M.connect(host, user, config)
  local ssh_user = user or config.default_user or vim.fn.getenv("USER")
  local cache_dir, cache_key = rsync_ssh.get_cache_dir(host, ssh_user, config.cache_dir)

  vim.fn.mkdir(cache_dir, "p")

  local ssh_cmd = string.format(
    "ssh -o BatchMode=yes -o ConnectTimeout=5 %s@%s echo ok",
    ssh_user,
    host
  )

  vim.fn.system(ssh_cmd)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  local conn = {
    host = host,
    user = ssh_user,
    cache_dir = cache_dir,
    cache_key = cache_key,
    connected = true,
    last_used = os.time(),
  }

  rsync_ssh.cache[cache_key] = conn
  return conn
end

function M.disconnect(conn)
  if conn then
    rsync_ssh.cleanup_cache(conn)
    conn.connected = false
  end
end

function M.is_alive(conn)
  if not conn or not conn.connected then
    return false
  end

  local ssh_cmd = string.format(
    "ssh -o BatchMode=yes -o ConnectTimeout=2 %s@%s echo ok",
    conn.user,
    conn.host
  )

  vim.fn.system(ssh_cmd)

  if vim.v.shell_error ~= 0 then
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
