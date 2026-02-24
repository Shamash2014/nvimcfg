local M = {}
local Job = require("plenary.job")

function M.connect(host, user, config, callback)
  local ssh_user = user or config.default_user or vim.fn.getenv("USER")
  local ssh_command = string.format("ssh -o ConnectTimeout=%d %s@%s", config.connection_timeout, ssh_user, host)

  Job:new({
    command = "ssh",
    args = {
      "-o",
      "ConnectTimeout=" .. config.connection_timeout,
      ssh_user .. "@" .. host,
      "echo TRAMP_OK",
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      if return_val == 0 then
        local result = j:result()
        if vim.tbl_contains(result, "TRAMP_OK") then
          callback({
            host = host,
            user = ssh_user,
            ssh_command = ssh_command,
            connected = true,
            last_used = os.time(),
          })
        else
          callback(nil, "Connection test failed")
        end
      else
        callback(nil, "SSH connection failed: " .. return_val)
      end
    end),
  }):start()
end

function M.is_alive(conn, callback)
  if not conn or not conn.connected then
    callback(false)
    return
  end

  if os.time() - conn.last_used <= 300 then
    callback(true)
    return
  end

  Job:new({
    command = "ssh",
    args = { conn.user .. "@" .. conn.host, "echo ALIVE" },
    on_exit = vim.schedule_wrap(function(j, return_val)
      if return_val == 0 then
        local result = j:result()
        conn.last_used = os.time()
        callback(vim.tbl_contains(result, "ALIVE"))
      else
        conn.connected = false
        callback(false)
      end
    end),
  }):start()
end

function M.read_file(conn, remote_path, callback)
  local escaped_path = vim.fn.shellescape(remote_path)

  Job:new({
    command = "ssh",
    args = { conn.user .. "@" .. conn.host, "cat " .. escaped_path },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      if return_val == 0 then
        callback(j:result(), nil)
      else
        callback(nil, "Failed to read file: " .. return_val)
      end
    end),
  }):start()
end

function M.write_file(conn, remote_path, content, callback)
  local temp_file = vim.fn.tempname()
  vim.fn.writefile(content, temp_file)

  local escaped_path = vim.fn.shellescape(remote_path)

  Job:new({
    command = "scp",
    args = { temp_file, conn.user .. "@" .. conn.host .. ":" .. escaped_path },
    on_exit = vim.schedule_wrap(function(_, return_val)
      vim.fn.delete(temp_file)
      conn.last_used = os.time()
      if return_val == 0 then
        callback(true, nil)
      else
        callback(false, "Failed to write file: " .. return_val)
      end
    end),
  }):start()
end

function M.list_directory(conn, remote_path, callback)
  local escaped_path = vim.fn.shellescape(remote_path)

  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      "ls -1ApL --group-directories-first " .. escaped_path .. " 2>/dev/null || ls -1Ap " .. escaped_path,
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      if return_val ~= 0 then
        callback(nil, "Failed to list directory: " .. return_val)
        return
      end

      local result = j:result()
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

      callback(files, nil)
    end),
  }):start()
end

function M.file_exists(conn, remote_path, callback)
  local escaped_path = vim.fn.shellescape(remote_path)

  Job:new({
    command = "ssh",
    args = { conn.user .. "@" .. conn.host, "test -e " .. escaped_path .. " && echo EXISTS" },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      local result = j:result()
      callback(return_val == 0 and vim.tbl_contains(result, "EXISTS"))
    end),
  }):start()
end

function M.delete_file(conn, remote_path, callback)
  local escaped_path = vim.fn.shellescape(remote_path)

  Job:new({
    command = "ssh",
    args = { conn.user .. "@" .. conn.host, "rm -f " .. escaped_path },
    on_exit = vim.schedule_wrap(function(_, return_val)
      conn.last_used = os.time()
      callback(return_val == 0, return_val == 0 and nil or "Failed to delete file")
    end),
  }):start()
end

function M.mkdir(conn, remote_path, callback)
  local escaped_path = vim.fn.shellescape(remote_path)

  Job:new({
    command = "ssh",
    args = { conn.user .. "@" .. conn.host, "mkdir -p " .. escaped_path },
    on_exit = vim.schedule_wrap(function(_, return_val)
      conn.last_used = os.time()
      callback(return_val == 0, return_val == 0 and nil or "Failed to create directory")
    end),
  }):start()
end

function M.rename(conn, old_path, new_path, callback)
  local escaped_old = vim.fn.shellescape(old_path)
  local escaped_new = vim.fn.shellescape(new_path)

  Job:new({
    command = "ssh",
    args = { conn.user .. "@" .. conn.host, "mv " .. escaped_old .. " " .. escaped_new },
    on_exit = vim.schedule_wrap(function(_, return_val)
      conn.last_used = os.time()
      callback(return_val == 0, return_val == 0 and nil or "Failed to rename file")
    end),
  }):start()
end

function M.grep(conn, remote_path, pattern, callback)
  local escaped_path = vim.fn.shellescape(remote_path)
  local escaped_pattern = vim.fn.shellescape(pattern)

  Job:new({
    command = "ssh",
    args = {
      conn.user .. "@" .. conn.host,
      "grep -r -n -H " .. escaped_pattern .. " " .. escaped_path .. " 2>/dev/null || true",
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      conn.last_used = os.time()
      if return_val ~= 0 and #j:result() == 0 then
        callback(nil, "Grep failed")
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

return M
