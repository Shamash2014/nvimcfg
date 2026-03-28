local M = {}

function M.pick_task(opts)
  opts = opts or {}
  local projects = require("djinni.integrations.projects")
  local index = require("djinni.store.index")

  local all = index.get_all()
  local items = {}
  for file_path, entry in pairs(all) do
    table.insert(items, {
      text = entry.title or vim.fn.fnamemodify(file_path, ":t:r"),
      project = entry.project or "",
      status = entry.status or "unknown",
      file_path = file_path,
    })
  end

  if opts.context then
    vim.ui.input({ prompt = "Task: " }, function(prompt)
      if not prompt or prompt == "" then return end
      local root = vim.fn.getcwd()
      require("djinni.nowork.chat").create(root, {
        prompt = prompt,
        context_file = opts.context,
      })
    end)
    return
  end

  local status_icons = {
    running = "~",
    done = "+",
    error = "x",
    pending = "o",
    unknown = "?",
  }

  Snacks.picker({
    title = "Nowork Tasks",
    items = items,
    format = function(item, picker)
      local icon = status_icons[item.status] or "?"
      return {
        { "[" .. icon .. "] ", "Comment" },
        { item.text .. "  ", "Normal" },
        { "(" .. item.project .. ")", "Comment" },
      }
    end,
    confirm = function(_, item)
      if item and item.file_path then
        require("djinni.nowork.chat").open(item.file_path)
      end
    end,
  })
end

function M.pick_sessions()
  local chat = require("djinni.nowork.chat")
  local items = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "nowork-chat" and vim.api.nvim_buf_is_valid(buf) then
      local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
      local streaming = chat._streaming[buf] == true
      table.insert(items, {
        text = name,
        buf = buf,
        kind = "chat",
        streaming = streaming,
      })
    end
  end

  local ok, terms = pcall(function() return require("snacks.terminal")._terms end)
  if ok and terms then
    for _, term in pairs(terms) do
      if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
        local cmd = type(term.cmd) == "table" and table.concat(term.cmd, " ") or tostring(term.cmd or "terminal")
        table.insert(items, {
          text = cmd,
          buf = term.buf,
          kind = "terminal",
          streaming = false,
        })
      end
    end
  end

  if #items == 0 then
    M.notify("No background sessions", vim.log.levels.INFO)
    return
  end

  Snacks.picker({
    title = "Background Sessions",
    items = items,
    format = function(item)
      local icon = item.kind == "terminal" and ">" or (item.streaming and "~" or "+")
      local hl = item.streaming and "DiagnosticWarn" or "Comment"
      return {
        { "[" .. icon .. "] ", hl },
        { item.text, "Normal" },
        { "  " .. item.kind, "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.buf then
        vim.schedule(function()
          local win = vim.fn.bufwinid(item.buf)
          if win ~= -1 then
            vim.api.nvim_set_current_win(win)
          else
            vim.cmd("buffer " .. item.buf)
          end
        end)
      end
    end,
  })
end

function M.pick_project(callback)
  Snacks.picker.projects({
    title = "Add Project",
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        vim.schedule(function()
          callback(tostring(item.file))
        end)
      end
    end,
  })
end

function M.notify(msg, level)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.notifier then
    snacks.notifier.notify(msg, level)
  else
    vim.notify(msg, level)
  end
end

function M.notify_task_complete(task)
  M.notify(task.title .. " completed", vim.log.levels.INFO)
end

function M.notify_permission_needed(task)
  M.notify(task.title .. " needs approval", vim.log.levels.WARN)
end

function M.pick_worktree(prompt, callback)
  local wt = require("djinni.integrations.worktrunk")
  wt.list(function(entries, err)
    if not entries or #entries == 0 then
      M.notify(err or "No worktrees found", vim.log.levels.WARN)
      return
    end

    local items = {}
    for _, e in ipairs(entries) do
      table.insert(items, {
        text = e.raw,
        branch = e.branch,
        current = e.current,
        trunk = e.trunk,
      })
    end

    Snacks.picker({
      title = prompt or "Worktrees",
      items = items,
      format = function(item)
        return { { item.text } }
      end,
      layout = { preset = "vscode" },
      confirm = function(picker, item)
        picker:close()
        if item then
          callback(item)
        end
      end,
    })
  end)
end

function M.action_worktree_create()
  vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
    if not branch or branch == "" then return end
    local wt = require("djinni.integrations.worktrunk")
    wt.create(branch, function(ok, result)
      if ok then
        M.notify("Created worktree: " .. branch, vim.log.levels.INFO)
        wt.get_path(branch, function(path)
          if path then
            vim.cmd("cd " .. vim.fn.fnameescape(path))
          end
        end)
      else
        M.notify("Failed: " .. (result or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.action_worktree_list()
  M.pick_worktree("Worktrees", function(item)
    local wt = require("djinni.integrations.worktrunk")
    wt.get_path(item.branch, function(path)
      if path then
        vim.cmd("cd " .. vim.fn.fnameescape(path))
        M.notify("Switched to " .. item.branch, vim.log.levels.INFO)
      else
        M.notify("Could not find path for " .. item.branch, vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.action_worktree_remove()
  M.pick_worktree("Remove worktree", function(item)
    vim.ui.input({ prompt = "Remove worktree '" .. item.branch .. "'? (y/n): " }, function(answer)
      if answer ~= "y" then return end
      local wt = require("djinni.integrations.worktrunk")
      wt.remove(item.branch, function(ok, msg)
        if ok then
          M.notify("Removed worktree: " .. item.branch, vim.log.levels.INFO)
        else
          M.notify("Failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

function M.action_worktree_merge()
  M.pick_worktree("Merge worktree", function(item)
    vim.ui.input({ prompt = "Merge target branch: " }, function(target)
      if not target or target == "" then return end
      local wt = require("djinni.integrations.worktrunk")
      wt.merge(target, item.branch, function(ok, msg)
        if ok then
          M.notify("Merged " .. item.branch .. " into " .. target, vim.log.levels.INFO)
        else
          M.notify("Merge failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

return M
