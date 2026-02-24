local M = {}
local Job = require("plenary.job")

M.cache = {}

function M.get_cache_dir(host, user, base_cache_dir)
  local ssh_user = user or vim.fn.getenv("USER")
  local cache_key = string.format("%s@%s", ssh_user, host)
  local cache_dir = string.format("%s/%s", base_cache_dir, cache_key:gsub("[@:]", "_"))
  return cache_dir, cache_key
end

function M.connect(host, user, config, callback)
  local ssh_user = user or config.default_user or vim.fn.getenv("USER")
  local cache_dir, cache_key = M.get_cache_dir(host, ssh_user, config.cache_dir)

  vim.fn.mkdir(cache_dir, "p")

  Job:new({
    command = "ssh",
    args = { "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", ssh_user .. "@" .. host, "echo ok" },
    on_exit = vim.schedule_wrap(function(_, return_val)
      if return_val == 0 then
        local conn = {
          host = host,
          user = ssh_user,
          cache_dir = cache_dir,
          cache_key = cache_key,
          connected = true,
          last_used = os.time(),
        }
        M.cache[cache_key] = conn
        callback(conn, nil)
      else
        callback(nil, "Failed to connect to " .. host)
      end
    end),
  }):start()
end

function M.is_alive(conn, callback)
  if not conn or not conn.connected then
    callback(false)
    return
  end

  Job:new({
    command = "ssh",
    args = { "-o", "BatchMode=yes", "-o", "ConnectTimeout=2", conn.user .. "@" .. conn.host, "echo ok" },
    on_exit = vim.schedule_wrap(function(_, return_val)
      local alive = return_val == 0
      if alive then
        conn.last_used = os.time()
      else
        conn.connected = false
      end
      callback(alive)
    end),
  }):start()
end

function M.get_local_cache_path(conn, remote_path)
  local normalized = remote_path:gsub("^/+", "")
  return conn.cache_dir .. "/" .. normalized
end

function M.sync_from_remote(conn, remote_path, callback)
  local local_path = M.get_local_cache_path(conn, remote_path)
  local local_dir = vim.fn.fnamemodify(local_path, ":h")

  vim.fn.mkdir(local_dir, "p")

  local remote_target = conn.user .. "@" .. conn.host .. ":" .. remote_path

  Job:new({
    command = "rsync",
    args = {
      "-az",
      "--timeout=10",
      remote_target,
      local_path,
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      if return_val == 0 then
        callback(local_path, nil)
      else
        local stderr = table.concat(j:stderr_result(), "\n")
        callback(nil, "Failed to sync from remote: " .. stderr)
      end
    end),
  }):start()
end

function M.sync_to_remote(conn, local_path, remote_path, callback)
  local remote_target = conn.user .. "@" .. conn.host .. ":" .. remote_path

  Job:new({
    command = "rsync",
    args = {
      "-az",
      "--timeout=10",
      local_path,
      remote_target,
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      if return_val == 0 then
        callback(true, nil)
      else
        local stderr = table.concat(j:stderr_result(), "\n")
        callback(false, "Failed to sync to remote: " .. stderr)
      end
    end),
  }):start()
end

function M.read_file(conn, remote_path, callback)
  M.sync_from_remote(conn, remote_path, function(local_path, err)
    if err then
      callback(nil, err)
      return
    end

    vim.schedule(function()
      local ok, content = pcall(vim.fn.readfile, local_path)
      if ok then
        callback(content, nil)
      else
        callback(nil, "Failed to read cached file: " .. tostring(content))
      end
    end)
  end)
end

function M.write_file(conn, remote_path, content, callback)
  local local_path = M.get_local_cache_path(conn, remote_path)
  local local_dir = vim.fn.fnamemodify(local_path, ":h")

  vim.fn.mkdir(local_dir, "p")

  vim.schedule(function()
    local ok, err = pcall(vim.fn.writefile, content, local_path)
    if not ok then
      callback(false, "Failed to write to cache: " .. tostring(err))
      return
    end

    M.sync_to_remote(conn, local_path, remote_path, callback)
  end)
end

function M.list_directory(conn, remote_path, callback)
  local normalized_path = remote_path
  if not normalized_path:match("/$") then
    normalized_path = normalized_path .. "/"
  end

  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      string.format("ls -1 -p %s", vim.fn.shellescape(normalized_path)),
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()

      if return_val ~= 0 then
        local stderr = table.concat(j:stderr_result(), "\n")
        callback(nil, "Failed to list directory: " .. stderr)
        return
      end

      local files = {}
      for _, name in ipairs(j:result()) do
        if name ~= "" and name ~= "./" and name ~= "../" then
          local is_dir = name:match("/$")
          local clean_name = is_dir and name:sub(1, -2) or name

          local full_path = normalized_path .. clean_name

          table.insert(files, {
            name = clean_name,
            path = full_path,
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
    end),
  }):start()
end

function M.file_exists(conn, remote_path, callback)
  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      string.format("test -e %s && echo 1 || echo 0", vim.fn.shellescape(remote_path)),
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      local result = j:result()[1]
      callback(return_val == 0 and result == "1")
    end),
  }):start()
end

function M.delete_file(conn, remote_path, callback)
  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      string.format("rm -rf %s", vim.fn.shellescape(remote_path)),
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      if return_val == 0 then
        local local_path = M.get_local_cache_path(conn, remote_path)
        vim.fn.delete(local_path, "rf")
        callback(true, nil)
      else
        local stderr = table.concat(j:stderr_result(), "\n")
        callback(false, "Failed to delete file: " .. stderr)
      end
    end),
  }):start()
end

function M.mkdir(conn, remote_path, callback)
  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      string.format("mkdir -p %s", vim.fn.shellescape(remote_path)),
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      if return_val == 0 then
        callback(true, nil)
      else
        local stderr = table.concat(j:stderr_result(), "\n")
        callback(false, "Failed to create directory: " .. stderr)
      end
    end),
  }):start()
end

function M.rename(conn, old_path, new_path, callback)
  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      string.format("mv %s %s", vim.fn.shellescape(old_path), vim.fn.shellescape(new_path)),
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      if return_val == 0 then
        local old_local = M.get_local_cache_path(conn, old_path)
        local new_local = M.get_local_cache_path(conn, new_path)
        pcall(vim.fn.rename, old_local, new_local)
        callback(true, nil)
      else
        local stderr = table.concat(j:stderr_result(), "\n")
        callback(false, "Failed to rename: " .. stderr)
      end
    end),
  }):start()
end

function M.grep(conn, remote_path, pattern, callback)
  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      string.format("grep -r -n -H %s %s", vim.fn.shellescape(pattern), vim.fn.shellescape(remote_path)),
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()

      if return_val ~= 0 and return_val ~= 1 then
        local stderr = table.concat(j:stderr_result(), "\n")
        callback(nil, "Failed to grep: " .. stderr)
        return
      end

      local results = {}
      for _, line in ipairs(j:result()) do
        local filepath, lnum, text = line:match("^([^:]+):(%d+):(.*)$")
        if filepath and lnum then
          table.insert(results, {
            path = filepath,
            lnum = tonumber(lnum),
            text = text,
          })
        end
      end

      callback(results, nil)
    end),
  }):start()
end

function M.cleanup_cache(conn)
  if conn and conn.cache_dir then
    vim.fn.delete(conn.cache_dir, "rf")
    M.cache[conn.cache_key] = nil
  end
end

function M.execute(conn, command, opts, callback)
  opts = opts or {}
  local cwd = opts.cwd or "~"

  local full_command = string.format("cd %s && %s", vim.fn.shellescape(cwd), command)

  local stdout = {}
  local stderr = {}

  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      full_command,
    },
    on_stdout = opts.on_stdout or function(_, data)
      table.insert(stdout, data)
    end,
    on_stderr = opts.on_stderr or function(_, data)
      table.insert(stderr, data)
    end,
    on_exit = vim.schedule_wrap(function(_, return_val)
      conn.last_used = os.time()
      callback({
        stdout = stdout,
        stderr = stderr,
        exit_code = return_val,
        success = return_val == 0,
      })
    end),
  }):start()
end

function M.cleanup_all()
  for _, conn in pairs(M.cache) do
    if conn.cache_dir then
      vim.fn.delete(conn.cache_dir, "rf")
    end
  end
  M.cache = {}
end

return M
