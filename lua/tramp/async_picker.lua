local M = {}
local async_ssh = require("tramp.async_ssh")
local path = require("tramp.path")

function M.browse_remote(conn, user, host, dir, opts)
  opts = opts or {}
  dir = path.normalize(dir or "/")

  if not conn or not conn.connected then
    vim.notify("No valid connection to " .. host, vim.log.levels.ERROR)
    return
  end

  vim.notify("Loading remote directory...", vim.log.levels.INFO)

  async_ssh.list_directory(conn, dir, function(files, err)
    if err or not files then
      vim.notify("Failed to list directory: " .. (err or "unknown error"), vim.log.levels.ERROR)
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

    M._show_picker(items, conn, user, host, opts)
  end)
end

function M._show_picker(items, conn, user, host, opts)
  if vim.fn.exists(":Snacks") == 2 then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.pick({
        items = items,
        layout = { preset = "vscode" },
        format = function(item)
          local icon = item.is_dir and "📁" or "📄"
          return string.format("%s %s", icon, item.text)
        end,
        confirm = function(item)
          if item.is_dir then
            M.browse_remote(conn, user, host, item.path, opts)
          else
            vim.cmd("edit " .. item.filename)
          end
        end,
        preview = function(item)
          if not item.is_dir then
            return {
              cmd = string.format("ssh %s@%s 'cat %s'", user, host, vim.fn.shellescape(item.path)),
            }
          end
        end,
      })
      return
    end
  end

  M._fallback_select(items, conn, user, host, opts)
end

function M._fallback_select(items, conn, user, host, opts)
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
      M.browse_remote(conn, user, host, selected.path, opts)
    else
      vim.cmd("edit " .. selected.filename)
    end
  end)
end

function M.grep_remote(conn, user, host, dir, pattern, opts)
  opts = opts or {}
  dir = path.normalize(dir or "/")

  if not conn or not conn.connected then
    vim.notify("No valid connection to " .. host, vim.log.levels.ERROR)
    return
  end

  vim.notify("Searching remote files...", vim.log.levels.INFO)

  async_ssh.grep(conn, dir, pattern, function(results, err)
    if err then
      vim.notify("Grep failed: " .. err, vim.log.levels.ERROR)
      return
    end

    if not results or #results == 0 then
      vim.notify("No matches found", vim.log.levels.INFO)
      return
    end

    local items = vim.tbl_map(function(result)
      return {
        text = result.text,
        filename = path.build(user, host, result.path),
        lnum = result.lnum,
        col = 1,
        path = result.path,
      }
    end, results)

    M._show_grep_results(items, opts)
  end)
end

function M._show_grep_results(items, opts)
  if vim.fn.exists(":Snacks") == 2 then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.pick({
        items = items,
        layout = { preset = "vscode" },
        format = function(item)
          return string.format("%s:%d: %s", vim.fn.fnamemodify(item.path, ":~:."), item.lnum, vim.trim(item.text))
        end,
        confirm = function(item)
          vim.cmd("edit " .. item.filename)
          vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
        end,
        preview = function(item)
          return {
            cmd = string.format(
              "ssh %s 'sed -n %d,%dp %s'",
              item.filename:match("ssh:([^:]+):"),
              math.max(1, item.lnum - 5),
              item.lnum + 5,
              vim.fn.shellescape(item.path)
            ),
          }
        end,
      })
      return
    end
  end

  vim.ui.select(items, {
    prompt = "Grep results:",
    format_item = function(item)
      return string.format("%s:%d: %s", vim.fn.fnamemodify(item.path, ":t"), item.lnum, vim.trim(item.text))
    end,
  }, function(selected)
    if not selected then
      return
    end

    vim.cmd("edit " .. selected.filename)
    vim.api.nvim_win_set_cursor(0, { selected.lnum, selected.col - 1 })
  end)
end

function M.find_files(conn, user, host, dir, opts)
  opts = opts or {}
  dir = path.normalize(dir or "/")

  if not conn or not conn.connected then
    vim.notify("No valid connection to " .. host, vim.log.levels.ERROR)
    return
  end

  vim.notify("Finding remote files...", vim.log.levels.INFO)

  async_ssh.list_directory(conn, dir, function(files, err)
    if err or not files then
      vim.notify("Failed to list directory: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end

    local all_files = {}

    local function collect_files(current_files, current_dir, depth)
      if depth > (opts.max_depth or 3) then
        return
      end

      for _, file in ipairs(current_files) do
        if file.type == "file" then
          table.insert(all_files, {
            text = file.name,
            filename = path.build(user, host, file.path),
            path = file.path,
            display_path = file.path:sub(#dir + 1),
          })
        elseif file.type == "directory" and not file.name:match("^%.") then
          async_ssh.list_directory(conn, file.path, function(sub_files, sub_err)
            if not sub_err and sub_files then
              collect_files(sub_files, file.path, depth + 1)
            end
          end)
        end
      end
    end

    collect_files(files, dir, 0)

    vim.defer_fn(function()
      if #all_files == 0 then
        vim.notify("No files found", vim.log.levels.INFO)
        return
      end

      M._show_file_picker(all_files, opts)
    end, 500)
  end)
end

function M._show_file_picker(items, opts)
  if vim.fn.exists(":Snacks") == 2 then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.pick({
        items = items,
        layout = { preset = "vscode" },
        format = function(item)
          return item.display_path or item.text
        end,
        confirm = function(item)
          vim.cmd("edit " .. item.filename)
        end,
      })
      return
    end
  end

  vim.ui.select(items, {
    prompt = "Select file:",
    format_item = function(item)
      return item.display_path or item.text
    end,
  }, function(selected)
    if not selected then
      return
    end
    vim.cmd("edit " .. selected.filename)
  end)
end

return M
