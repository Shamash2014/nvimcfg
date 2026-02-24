local M = {}
local rsync_ssh = require("tramp.rsync_ssh")

function M.connect(host, user, config, callback)
  rsync_ssh.connect(host, user, config, callback)
end

function M.is_alive(conn, callback)
  rsync_ssh.is_alive(conn, callback)
end

function M.read_file(conn, remote_path, callback)
  rsync_ssh.read_file(conn, remote_path, callback)
end

function M.write_file(conn, remote_path, content, callback)
  rsync_ssh.write_file(conn, remote_path, content, callback)
end

function M.list_directory(conn, remote_path, callback)
  rsync_ssh.list_directory(conn, remote_path, callback)
end

function M.file_exists(conn, remote_path, callback)
  rsync_ssh.file_exists(conn, remote_path, callback)
end

function M.delete_file(conn, remote_path, callback)
  rsync_ssh.delete_file(conn, remote_path, callback)
end

function M.mkdir(conn, remote_path, callback)
  rsync_ssh.mkdir(conn, remote_path, callback)
end

function M.rename(conn, old_path, new_path, callback)
  rsync_ssh.rename(conn, old_path, new_path, callback)
end

function M.grep(conn, remote_path, pattern, callback)
  rsync_ssh.grep(conn, remote_path, pattern, callback)
end

function M.execute(conn, command, opts, callback)
  rsync_ssh.execute(conn, command, opts, callback)
end

return M
