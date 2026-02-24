local M = {}
local path = require("tramp.path")
local ssh = require("tramp.ssh")
local async_ssh = require("tramp.async_ssh")
local buffer = require("tramp.buffer")
local async_picker = require("tramp.async_picker")
local rsync_ssh = require("tramp.rsync_ssh")

M.config = {
  ssh_config = vim.fn.expand("~/.ssh/config"),
  cache_dir = vim.fn.stdpath("cache") .. "/tramp",
  connection_timeout = 10,
  default_user = nil,
}

M.connections = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.fn.mkdir(M.config.cache_dir, "p")

  M.setup_autocmds()
  M.setup_commands()

  local oil_adapter = require("tramp.oil_adapter")
  oil_adapter.setup()
end

function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup("Tramp", { clear = true })

  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "/ssh:*",
    callback = function(args)
      M.read_remote_file(args.file)
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    pattern = "/ssh:*",
    callback = function(args)
      M.write_remote_file(args.file)
    end,
  })

  vim.api.nvim_create_autocmd("FileReadCmd", {
    group = group,
    pattern = "/ssh:*",
    callback = function(args)
      M.read_remote_file(args.file)
    end,
  })

  vim.api.nvim_create_autocmd("FileWriteCmd", {
    group = group,
    pattern = "/ssh:*",
    callback = function(args)
      M.write_remote_file(args.file)
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      rsync_ssh.cleanup_all()
    end,
  })
end

function M.setup_commands()
  vim.api.nvim_create_user_command("TrampEdit", function(opts)
    local remote_path = opts.args
    if remote_path == "" then
      M.edit_remote()
    else
      vim.cmd("edit " .. remote_path)
    end
  end, { nargs = "?", complete = "file" })

  vim.api.nvim_create_user_command("TrampFind", function()
    M.find_remote()
  end, {})

  vim.api.nvim_create_user_command("TrampConnect", function()
    M.connect()
  end, {})

  vim.api.nvim_create_user_command("TrampDisconnect", function()
    M.disconnect()
  end, {})

  vim.api.nvim_create_user_command("TrampInfo", function()
    M.info()
  end, {})

  vim.api.nvim_create_user_command("TrampGrep", function(opts)
    M.grep_remote(opts.args)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("TrampExplore", function(opts)
    M.explore_remote(opts.args)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("TrampExec", function(opts)
    M.exec_remote(opts.args)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("TrampTerm", function()
    M.open_remote_terminal()
  end, {})
end

function M.read_remote_file(filepath)
  local parsed = path.parse(filepath)
  if not parsed then
    vim.notify("Invalid TRAMP path: " .. filepath, vim.log.levels.ERROR)
    return
  end

  buffer.set_content({ "Loading remote file..." })
  vim.bo.modifiable = false

  local function do_read(conn)
    async_ssh.read_file(conn, parsed.path, function(content, err)
      if err or not content then
        vim.notify("Failed to read remote file: " .. (err or "unknown error"), vim.log.levels.ERROR)
        vim.bo.modifiable = true
        buffer.set_content({})
        return
      end

      buffer.set_content(content)
      vim.bo.modified = false
      vim.bo.modifiable = true
      vim.b.tramp_path = filepath
    end)
  end

  local conn = M.get_connection(parsed.host, parsed.user)
  if not conn then
    async_ssh.connect(parsed.host, parsed.user, M.config, function(new_conn, err)
      if err or not new_conn then
        vim.notify("Failed to connect to " .. parsed.host .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
        vim.bo.modifiable = true
        buffer.set_content({})
        return
      end

      local key = string.format("%s@%s", parsed.user or M.config.default_user or vim.fn.getenv("USER"), parsed.host)
      M.connections[key] = new_conn
      do_read(new_conn)
    end)
  else
    do_read(conn)
  end
end

function M.write_remote_file(filepath)
  local parsed = path.parse(filepath)
  if not parsed then
    vim.notify("Invalid TRAMP path: " .. filepath, vim.log.levels.ERROR)
    return
  end

  parsed.path = path.normalize(parsed.path)

  local content = buffer.get_content()

  vim.notify("Saving remote file...", vim.log.levels.INFO)

  local function do_write(conn)
    async_ssh.write_file(conn, parsed.path, content, function(success, err)
      if not success then
        vim.notify("Failed to write remote file: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end

      vim.bo.modified = false
      vim.notify("Remote file saved: " .. parsed.path, vim.log.levels.INFO)
    end)
  end

  local conn = M.get_connection(parsed.host, parsed.user)
  if not conn then
    async_ssh.connect(parsed.host, parsed.user, M.config, function(new_conn, err)
      if err or not new_conn then
        vim.notify("Failed to connect to " .. parsed.host .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end

      local key = string.format("%s@%s", parsed.user or M.config.default_user or vim.fn.getenv("USER"), parsed.host)
      M.connections[key] = new_conn
      do_write(new_conn)
    end)
  else
    do_write(conn)
  end
end

function M.get_connection(host, user)
  local key = string.format("%s@%s", user or M.config.default_user or vim.fn.getenv("USER"), host)

  if M.connections[key] and ssh.is_alive(M.connections[key]) then
    return M.connections[key]
  end

  local conn = ssh.connect(host, user, M.config)
  if conn then
    M.connections[key] = conn
  end

  return conn
end

function M.edit_remote()
  vim.ui.input({
    prompt = "Remote path (user@host:/path or /ssh:user@host:/path): ",
  }, function(input)
    if not input or input == "" then
      return
    end

    local tramp_path
    if input:match("^/ssh:") then
      tramp_path = input
    elseif input:match("^[%w_%-]+@[%w%.%-]+:") then
      local user_host, remote_path = input:match("^([%w_%-]+@[%w%.%-]+):(.*)$")
      tramp_path = "/ssh:" .. user_host .. ":/" .. remote_path
    else
      vim.notify("Invalid format. Use: user@host:/path or /ssh:user@host:/path", vim.log.levels.ERROR)
      return
    end

    vim.cmd("edit " .. tramp_path)
  end)
end

function M.find_remote()
  local hosts = ssh.get_ssh_hosts(M.config.ssh_config)

  if #hosts == 0 then
    vim.notify("No SSH hosts found in " .. M.config.ssh_config, vim.log.levels.WARN)
    return
  end

  vim.ui.select(hosts, {
    prompt = "Select remote host:",
    format_item = function(host)
      return host.name .. (host.hostname and " (" .. host.hostname .. ")" or "")
    end,
  }, function(selected)
    if not selected then
      return
    end

    local host = selected.hostname or selected.name
    local user = selected.user or M.config.default_user or vim.fn.getenv("USER")

    vim.ui.input({
      prompt = "Remote directory [/]: ",
      default = "/",
    }, function(dir)
      if not dir then
        return
      end

      local conn = M.get_connection(host, user)
      if not conn then
        async_ssh.connect(host, user, M.config, function(new_conn, err)
          if err or not new_conn then
            vim.notify("Failed to connect to " .. host .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
            return
          end

          local key = string.format("%s@%s", user or M.config.default_user or vim.fn.getenv("USER"), host)
          M.connections[key] = new_conn
          async_picker.browse_remote(new_conn, user, host, dir)
        end)
      else
        async_picker.browse_remote(conn, user, host, dir)
      end
    end)
  end)
end

function M.connect()
  local hosts = ssh.get_ssh_hosts(M.config.ssh_config)

  vim.ui.select(hosts, {
    prompt = "Connect to host:",
    format_item = function(host)
      return host.name .. (host.hostname and " (" .. host.hostname .. ")" or "")
    end,
  }, function(selected)
    if not selected then
      return
    end

    local host = selected.hostname or selected.name
    local user = selected.user or M.config.default_user or vim.fn.getenv("USER")

    local conn = M.get_connection(host, user)
    if conn then
      vim.notify("Connected to " .. user .. "@" .. host, vim.log.levels.INFO)
    else
      vim.notify("Failed to connect to " .. host, vim.log.levels.ERROR)
    end
  end)
end

function M.disconnect()
  local active = {}
  for key, _ in pairs(M.connections) do
    table.insert(active, key)
  end

  if #active == 0 then
    vim.notify("No active connections", vim.log.levels.INFO)
    return
  end

  vim.ui.select(active, {
    prompt = "Disconnect from:",
  }, function(selected)
    if not selected then
      return
    end

    if M.connections[selected] then
      local conn = M.connections[selected]
      ssh.disconnect(conn)
      M.connections[selected] = nil
      vim.notify("Disconnected from " .. selected, vim.log.levels.INFO)
    end
  end)
end

function M.info()
  local active = {}
  for key, conn in pairs(M.connections) do
    if ssh.is_alive(conn) then
      table.insert(active, key)
    end
  end

  if #active == 0 then
    vim.notify("No active connections", vim.log.levels.INFO)
    return
  end

  local info = "Active TRAMP connections:\n"
  for _, key in ipairs(active) do
    info = info .. "  • " .. key .. "\n"
  end

  vim.notify(info, vim.log.levels.INFO)
end

function M.grep_remote(pattern)
  if not buffer.is_remote() then
    vim.notify("Not a remote buffer", vim.log.levels.ERROR)
    return
  end

  local remote_path = buffer.get_remote_path()
  local parsed = path.parse(remote_path)
  if not parsed then
    return
  end

  local conn = M.get_connection(parsed.host, parsed.user)
  local dir = path.dirname(parsed.path)

  if not conn then
    async_ssh.connect(parsed.host, parsed.user, M.config, function(new_conn, err)
      if err or not new_conn then
        vim.notify("Failed to connect to " .. parsed.host .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end

      local key = string.format("%s@%s", parsed.user or M.config.default_user or vim.fn.getenv("USER"), parsed.host)
      M.connections[key] = new_conn
      async_picker.grep_remote(new_conn, parsed.user, parsed.host, dir, pattern)
    end)
  else
    async_picker.grep_remote(conn, parsed.user, parsed.host, dir, pattern)
  end
end

function M.explore_remote(tramp_path)
  if tramp_path and tramp_path ~= "" then
    local parsed = path.parse(tramp_path)
    if not parsed then
      vim.notify("Invalid TRAMP path: " .. tramp_path, vim.log.levels.ERROR)
      return
    end

    local has_oil = pcall(require, "oil")
    if has_oil then
      vim.cmd("edit " .. tramp_path)
    else
      local conn = M.get_connection(parsed.host, parsed.user)
      if not conn then
        async_ssh.connect(parsed.host, parsed.user, M.config, function(new_conn, err)
          if err or not new_conn then
            vim.notify("Failed to connect: " .. (err or "unknown error"), vim.log.levels.ERROR)
            return
          end

          local key = string.format("%s@%s", parsed.user or M.config.default_user or vim.fn.getenv("USER"), parsed.host)
          M.connections[key] = new_conn
          async_picker.browse_remote(new_conn, parsed.user, parsed.host, parsed.path)
        end)
      else
        async_picker.browse_remote(conn, parsed.user, parsed.host, parsed.path)
      end
    end
  else
    M.find_remote()
  end
end

function M.exec_remote(command)
  local hosts = ssh.get_ssh_hosts(M.config.ssh_config)

  if #hosts == 0 then
    vim.notify("No SSH hosts found in " .. M.config.ssh_config, vim.log.levels.WARN)
    return
  end

  vim.ui.select(hosts, {
    prompt = "Select remote host:",
    format_item = function(host)
      return host.name .. (host.hostname and " (" .. host.hostname .. ")" or "")
    end,
  }, function(selected)
    if not selected then
      return
    end

    local host = selected.hostname or selected.name
    local user = selected.user or M.config.default_user or vim.fn.getenv("USER")

    local cmd_to_run = command
    if not cmd_to_run or cmd_to_run == "" then
      vim.ui.input({
        prompt = "Command to execute: ",
      }, function(input)
        if not input then
          return
        end
        cmd_to_run = input
        M._do_exec(host, user, cmd_to_run)
      end)
    else
      M._do_exec(host, user, cmd_to_run)
    end
  end)
end

function M._do_exec(host, user, command, opts)
  opts = opts or {}

  local conn = M.get_connection(host, user)
  local function do_execute(connection)
    vim.notify("Executing: " .. command, vim.log.levels.INFO)

    async_ssh.execute(connection, command, opts, function(result)
      if result.success then
        local output = table.concat(result.stdout, "\n")
        if output ~= "" then
          vim.notify("Command completed:\n" .. output, vim.log.levels.INFO)
        else
          vim.notify("Command completed successfully", vim.log.levels.INFO)
        end
      else
        local error_output = table.concat(result.stderr, "\n")
        vim.notify("Command failed (exit code " .. result.exit_code .. "):\n" .. error_output, vim.log.levels.ERROR)
      end
    end)
  end

  if not conn then
    async_ssh.connect(host, user, M.config, function(new_conn, err)
      if err or not new_conn then
        vim.notify("Failed to connect to " .. host .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end

      local key = string.format("%s@%s", user or M.config.default_user or vim.fn.getenv("USER"), host)
      M.connections[key] = new_conn
      do_execute(new_conn)
    end)
  else
    do_execute(conn)
  end
end

function M.open_remote_terminal()
  local hosts = ssh.get_ssh_hosts(M.config.ssh_config)

  if #hosts == 0 then
    vim.notify("No SSH hosts found in " .. M.config.ssh_config, vim.log.levels.WARN)
    return
  end

  vim.ui.select(hosts, {
    prompt = "Select remote host:",
    format_item = function(host)
      return host.name .. (host.hostname and " (" .. host.hostname .. ")" or "")
    end,
  }, function(selected)
    if not selected then
      return
    end

    local host = selected.hostname or selected.name
    local user = selected.user or M.config.default_user or vim.fn.getenv("USER")

    vim.cmd("botright split")
    vim.cmd("resize 15")
    vim.cmd("terminal ssh " .. user .. "@" .. host)
    vim.cmd("startinsert")
  end)
end

return M
