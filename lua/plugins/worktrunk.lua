local function pick_worktree(prompt, callback)
  local wt = require("core.worktrunk")
  wt.list(function(entries, err)
    if not entries or #entries == 0 then
      vim.notify(err or "No worktrees found", vim.log.levels.WARN)
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

local function action_create()
  vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
    if not branch or branch == "" then return end
    local wt = require("core.worktrunk")
    wt.create(branch, function(ok, result)
      if ok then
        vim.notify("Created worktree: " .. branch, vim.log.levels.INFO)
        wt.get_worktree_path(branch, function(path)
          if path then
            vim.cmd("cd " .. vim.fn.fnameescape(path))
          end
        end)
      else
        vim.notify("Failed: " .. (result or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function action_list()
  pick_worktree("Worktrees", function(item)
    local wt = require("core.worktrunk")
    wt.get_worktree_path(item.branch, function(path)
      if path then
        vim.cmd("cd " .. vim.fn.fnameescape(path))
        vim.notify("Switched to " .. item.branch, vim.log.levels.INFO)
      else
        vim.notify("Could not find path for " .. item.branch, vim.log.levels.ERROR)
      end
    end)
  end)
end

local function confirm_and_remove(branch)
  vim.ui.input({ prompt = "Remove worktree '" .. (branch or "current") .. "'? (y/n): " }, function(answer)
    if answer ~= "y" then return end
    local wt = require("core.worktrunk")
    wt.remove(branch, function(ok, msg)
      if ok then
        vim.notify("Removed worktree" .. (branch and (": " .. branch) or ""), vim.log.levels.INFO)
      else
        vim.notify("Failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function action_remove_current()
  confirm_and_remove(nil)
end

local function action_remove_pick()
  pick_worktree("Remove worktree", function(item)
    confirm_and_remove(item.branch)
  end)
end

local function do_merge(branch)
  vim.ui.input({ prompt = "Merge target branch: " }, function(target)
    if not target or target == "" then return end
    local wt = require("core.worktrunk")
    wt.merge(target, branch, function(ok, msg)
      if ok then
        vim.notify("Merged" .. (branch and (" " .. branch) or "") .. " into " .. target, vim.log.levels.INFO)
      else
        vim.notify("Merge failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function action_merge_current()
  do_merge(nil)
end

local function action_merge_pick()
  pick_worktree("Merge worktree", function(item)
    do_merge(item.branch)
  end)
end

local function action_step_commit()
  local wt = require("core.worktrunk")
  wt.step_commit(function(ok, msg)
    if ok then
      vim.notify("Step commit done", vim.log.levels.INFO)
    else
      vim.notify("Step commit failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

local function action_step_rollback()
  local wt = require("core.worktrunk")
  wt.step_rollback(function(ok, msg)
    if ok then
      vim.notify("Step rollback done", vim.log.levels.INFO)
    else
      vim.notify("Step rollback failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

return {
  "folke/which-key.nvim",
  optional = true,
  cond = function()
    return vim.fn.executable("wt") == 1
  end,
  init = function()
    if vim.fn.executable("wt") == 1 then
      require("core.worktrunk").start_statusline(5000)
      vim.o.statusline = "%f %m%r%h%w %= %{v:lua.require('core.worktrunk').statusline()} %l:%c %p%%"
    end
  end,
  keys = {
    { "<leader>gwc", action_create, desc = "Create Worktree" },
    { "<leader>gwl", action_list, desc = "List Worktrees" },
    { "<leader>gwr", action_remove_current, desc = "Remove Current" },
    { "<leader>gwR", action_remove_pick, desc = "Remove (pick)" },
    { "<leader>gwm", action_merge_current, desc = "Merge Current" },
    { "<leader>gwM", action_merge_pick, desc = "Merge (pick)" },
    { "<leader>gws", action_step_commit, desc = "Step Commit" },
    { "<leader>gwu", action_step_rollback, desc = "Step Rollback (undo)" },
  },
}
