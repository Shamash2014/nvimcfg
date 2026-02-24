local M = {}
local ssh = require("tramp.ssh")
local path = require("tramp.path")

function M.browse_remote(conn, user, host, dir)
  dir = path.normalize(dir or "/")

  local files = ssh.list_directory(conn, dir)
  if not files then
    vim.notify("Failed to list directory: " .. dir, vim.log.levels.ERROR)
    return
  end

  if dir ~= "/" then
    table.insert(files, 1, {
      name = "..",
      path = path.dirname(dir),
      type = "directory",
    })
  end

  local items = vim.tbl_map(function(file)
    return {
      text = file.name,
      filename = path.build(user, host, file.path),
      path = file.path,
      is_dir = file.type == "directory",
      host = host,
      user = user,
    }
  end, files)

  if vim.fn.exists(":Snacks") == 2 then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.pick({
        items = items,
        format = function(item)
          local icon = item.is_dir and "📁" or "📄"
          return string.format("%s %s", icon, item.text)
        end,
        confirm = function(item)
          if item.is_dir then
            M.browse_remote(conn, user, host, item.path)
          else
            vim.cmd("edit " .. item.filename)
          end
        end,
        preview = function(item)
          if not item.is_dir then
            return {
              cmd = string.format(
                "ssh %s@%s 'cat %s'",
                user,
                host,
                vim.fn.shellescape(item.path)
              ),
            }
          end
        end,
      })
    else
      M.fallback_select(items, conn, user, host)
    end
  else
    M.fallback_select(items, conn, user, host)
  end
end

function M.fallback_select(items, conn, user, host)
  vim.ui.select(items, {
    prompt = "Select file or directory:",
    format_item = function(item)
      local icon = item.is_dir and "📁" or "📄"
      return string.format("%s %s", icon, item.text)
    end,
  }, function(selected)
    if not selected then
      return
    end

    if selected.is_dir then
      M.browse_remote(conn, user, host, selected.path)
    else
      vim.cmd("edit " .. selected.filename)
    end
  end)
end

function M.grep_remote(conn, user, host, dir, pattern)
  dir = path.normalize(dir or "/")

  local escaped_dir = vim.fn.shellescape(dir)
  local escaped_pattern = vim.fn.shellescape(pattern or "")

  local cmd = conn.ssh_command
    .. string.format(" 'grep -r -n -H %s %s 2>/dev/null || true'", escaped_pattern, escaped_dir)

  local results = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 and #results == 0 then
    vim.notify("Grep failed or no results found", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, line in ipairs(results) do
    local filepath, lnum, text = line:match("^([^:]+):(%d+):(.*)$")
    if filepath and lnum then
      table.insert(items, {
        text = text,
        filename = path.build(user, host, filepath),
        lnum = tonumber(lnum),
        col = 1,
        path = filepath,
      })
    end
  end

  if #items == 0 then
    vim.notify("No matches found", vim.log.levels.INFO)
    return
  end

  if vim.fn.exists(":Snacks") == 2 then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.pick({
        items = items,
        format = function(item)
          return string.format("%s:%d: %s", item.path, item.lnum, vim.trim(item.text))
        end,
        confirm = function(item)
          vim.cmd("edit " .. item.filename)
          vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
        end,
      })
    else
      vim.notify("Snacks picker not available", vim.log.levels.WARN)
    end
  end
end

return M
