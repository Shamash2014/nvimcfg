local M = {}
local Job = require("plenary.job")
local sshfs = require("tramp.sshfs")

function M.connect(host, user, config, callback)
  local ssh_user = user or config.default_user or vim.fn.getenv("USER")

  sshfs.ensure_mount(host, ssh_user, config.cache_dir, function(mount_info, err)
    if err or not mount_info then
      callback(nil, err or "Failed to mount sshfs")
      return
    end

    callback({
      host = host,
      user = ssh_user,
      mount_info = mount_info,
      connected = true,
      last_used = os.time(),
    })
  end)
end

function M.is_alive(conn, callback)
  if not conn or not conn.connected or not conn.mount_info then
    callback(false)
    return
  end

  vim.schedule(function()
    local is_mounted = sshfs.is_mounted(conn.mount_info.mount_point)
    if not is_mounted then
      conn.connected = false
    end
    callback(is_mounted)
  end)
end

function M.read_file(conn, remote_path, callback)
  if not conn.mount_info then
    callback(nil, "No mount info available")
    return
  end

  sshfs.verify_connection(conn.mount_info, function(is_alive)
    if not is_alive then
      callback(nil, "Connection lost - mount point not responding")
      return
    end

    local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

    vim.schedule(function()
      local ok, content = pcall(vim.fn.readfile, local_path)
      conn.last_used = os.time()

      if ok then
        callback(content, nil)
      else
        callback(nil, "Failed to read file: " .. tostring(content))
      end
    end)
  end)
end

function M.write_file(conn, remote_path, content, callback)
  if not conn.mount_info then
    callback(false, "No mount info available")
    return
  end

  sshfs.verify_connection(conn.mount_info, function(is_alive)
    if not is_alive then
      callback(false, "Connection lost - mount point not responding")
      return
    end

    local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

    vim.schedule(function()
      local dir = vim.fn.fnamemodify(local_path, ":h")
      vim.fn.mkdir(dir, "p")

      local ok, err = pcall(vim.fn.writefile, content, local_path)
      conn.last_used = os.time()

      if ok then
        callback(true, nil)
      else
        callback(false, "Failed to write file: " .. tostring(err))
      end
    end)
  end)
end

function M.list_directory(conn, remote_path, callback)
  if not conn.mount_info then
    callback(nil, "No mount info available")
    return
  end

  sshfs.verify_connection(conn.mount_info, function(is_alive)
    if not is_alive then
      callback(nil, "Connection lost - mount point not responding")
      return
    end

    local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

    vim.schedule(function()
      conn.last_used = os.time()

      local ok, entries = pcall(vim.fn.readdir, local_path)
      if not ok then
        callback(nil, "Failed to list directory: " .. tostring(entries))
        return
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

      callback(files, nil)
    end)
  end)
end

function M.file_exists(conn, remote_path, callback)
  if not conn.mount_info then
    callback(false)
    return
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  vim.schedule(function()
    conn.last_used = os.time()
    local exists = vim.fn.filereadable(local_path) == 1 or vim.fn.isdirectory(local_path) == 1
    callback(exists)
  end)
end

function M.delete_file(conn, remote_path, callback)
  if not conn.mount_info then
    callback(false, "No mount info available")
    return
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  vim.schedule(function()
    conn.last_used = os.time()
    local ok, err = pcall(vim.fn.delete, local_path)
    if ok and err == 0 then
      callback(true, nil)
    else
      callback(false, "Failed to delete file")
    end
  end)
end

function M.mkdir(conn, remote_path, callback)
  if not conn.mount_info then
    callback(false, "No mount info available")
    return
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  vim.schedule(function()
    conn.last_used = os.time()
    local ok, err = pcall(vim.fn.mkdir, local_path, "p")
    if ok and err == 1 then
      callback(true, nil)
    else
      callback(false, "Failed to create directory")
    end
  end)
end

function M.rename(conn, old_path, new_path, callback)
  if not conn.mount_info then
    callback(false, "No mount info available")
    return
  end

  local old_local = sshfs.get_local_path(conn.mount_info, old_path)
  local new_local = sshfs.get_local_path(conn.mount_info, new_path)

  vim.schedule(function()
    conn.last_used = os.time()
    local ok, err = pcall(vim.fn.rename, old_local, new_local)
    if ok and err == 0 then
      callback(true, nil)
    else
      callback(false, "Failed to rename file")
    end
  end)
end

function M.grep(conn, remote_path, pattern, callback)
  if not conn.mount_info then
    callback(nil, "No mount info available")
    return
  end

  local local_path = sshfs.get_local_path(conn.mount_info, remote_path)

  Job:new({
    command = "grep",
    args = { "-r", "-n", "-H", pattern, local_path },
    on_exit = vim.schedule_wrap(function(j, _)
      conn.last_used = os.time()

      local results = {}
      for _, line in ipairs(j:result()) do
        local filepath, lnum, text = line:match("^([^:]+):(%d+):(.*)$")
        if filepath and lnum then
          local remote_filepath = sshfs.get_remote_path(conn.mount_info, filepath)
          if remote_filepath then
            table.insert(results, {
              path = remote_filepath,
              lnum = tonumber(lnum),
              text = text,
            })
          end
        end
      end

      callback(results, nil)
    end),
  }):start()
end

return M
