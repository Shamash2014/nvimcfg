local M = {}
local Job = require("plenary.job")

M.mounts = {}

function M.get_mount_point(host, user, cache_dir)
  local ssh_user = user or vim.fn.getenv("USER")
  local mount_key = string.format("%s@%s", ssh_user, host)
  local mount_point = string.format("%s/%s", cache_dir, mount_key:gsub("[@:]", "_"))
  return mount_point, mount_key
end

function M.is_mounted(mount_point)
  local result = vim.fn.systemlist("mount | grep " .. vim.fn.shellescape(mount_point))
  return vim.v.shell_error == 0 and #result > 0
end

function M.mount(host, user, cache_dir, callback)
  local mount_point, mount_key = M.get_mount_point(host, user, cache_dir)

  if M.mounts[mount_key] and M.is_mounted(mount_point) then
    callback(M.mounts[mount_key], nil)
    return
  end

  vim.fn.mkdir(mount_point, "p")

  local ssh_user = user or vim.fn.getenv("USER")

  Job:new({
    command = "sshfs",
    args = {
      "-o", "reconnect",
      "-o", "ServerAliveInterval=15",
      "-o", "ServerAliveCountMax=3",
      ssh_user .. "@" .. host .. ":/",
      mount_point,
    },
    on_exit = vim.schedule_wrap(function(_, return_val)
      if return_val == 0 then
        local mount_info = {
          host = host,
          user = ssh_user,
          mount_point = mount_point,
          mount_key = mount_key,
          mounted_at = os.time(),
        }
        M.mounts[mount_key] = mount_info
        callback(mount_info, nil)
      else
        vim.fn.delete(mount_point, "d")
        callback(nil, "Failed to mount sshfs: " .. return_val)
      end
    end),
  }):start()
end

function M.unmount(mount_info, callback)
  if not mount_info or not mount_info.mount_point then
    callback(false, "Invalid mount info")
    return
  end

  Job:new({
    command = "umount",
    args = { mount_info.mount_point },
    on_exit = vim.schedule_wrap(function(_, return_val)
      if return_val == 0 then
        M.mounts[mount_info.mount_key] = nil
        vim.fn.delete(mount_info.mount_point, "d")
        callback(true, nil)
      else
        callback(false, "Failed to unmount: " .. return_val)
      end
    end),
  }):start()
end

function M.unmount_all(callback)
  local count = 0
  local total = vim.tbl_count(M.mounts)

  if total == 0 then
    callback(true, nil)
    return
  end

  for _, mount_info in pairs(M.mounts) do
    M.unmount(mount_info, function(success, err)
      count = count + 1
      if count == total then
        callback(true, nil)
      end
    end)
  end
end

function M.get_local_path(mount_info, remote_path)
  local normalized = remote_path:gsub("^/+", "/")
  return mount_info.mount_point .. normalized
end

function M.get_remote_path(mount_info, local_path)
  if not local_path:find(mount_info.mount_point, 1, true) then
    return nil
  end
  return local_path:sub(#mount_info.mount_point + 1)
end

return M
