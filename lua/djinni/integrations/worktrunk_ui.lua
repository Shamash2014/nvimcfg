local M = {}
local wt = require("djinni.integrations.worktrunk")

local function pick_branch(prompt, cb)
  wt.list(function(entries)
    vim.schedule(function()
      if not entries or #entries == 0 then
        vim.notify("[wt] No worktrees", vim.log.levels.WARN)
        return
      end
      local items = {}
      for _, e in ipairs(entries) do
        if e.kind == "worktree" then table.insert(items, e) end
      end
      if #items == 0 then
        vim.notify("[wt] No worktrees", vim.log.levels.WARN)
        return
      end
      vim.ui.select(items, {
        prompt = prompt,
        format_item = function(e)
          local mark = e.is_current and "@ " or "  "
          local name = e.branch or "(detached)"
          local stats = {}
          if e.symbols and e.symbols ~= "" then table.insert(stats, e.symbols) end
          if e.working_tree and e.working_tree.diff then
            local d = e.working_tree.diff
            if d.added > 0 or d.deleted > 0 then
              table.insert(stats, "+" .. d.added .. " -" .. d.deleted)
            end
          end
          if e.commit then table.insert(stats, e.commit.short_sha .. " " .. (e.commit.message or "")) end
          local suffix = #stats > 0 and ("  " .. table.concat(stats, "  ")) or ""
          return mark .. name .. suffix
        end,
      }, function(choice)
        if choice then cb(choice.branch) end
      end)
    end)
  end)
end

local function notify_and_refresh(op)
  return function(ok, lines, stderr)
    vim.schedule(function()
      wt.notify_result(op, ok, lines, stderr)
    end)
  end
end

function M.create()
  local ok, popup = pcall(require, "neogit.lib.popup")
  if not ok then
    vim.notify("[wt] Neogit not available", vim.log.levels.ERROR)
    return
  end

  local p = popup
    .builder()
    :name("NeogitWorktrunkPopup")
    :group_heading("Switch")
    :action("w", "Switch worktree", function()
      pick_branch("Switch to:", function(branch)
        wt.switch_to(branch)
      end)
    end)
    :action("c", "Create worktree", function()
      vim.ui.input({ prompt = "New branch: " }, function(branch)
        if not branch or branch == "" then return end
        wt.create_for_task(branch, function(path)
          if path then
            vim.notify("[wt] Created: " .. branch, vim.log.levels.INFO)
          end
        end)
      end)
    end)
    :action("d", "Delete worktree", function()
      pick_branch("Delete:", function(branch)
        vim.ui.input({ prompt = "Remove '" .. branch .. "'? (y/n): " }, function(answer)
          if answer ~= "y" then return end
          wt.remove(branch, function(ok2, msg)
            vim.schedule(function()
              if ok2 then
                vim.notify("[wt] Removed: " .. branch, vim.log.levels.INFO)
              else
                vim.notify("[wt] Remove failed: " .. (msg or ""), vim.log.levels.ERROR)
              end
            end)
          end)
        end)
      end)
    end)
    :new_action_group("Operations")
    :action("C", "Commit", function()
      pick_branch("Commit on:", function(branch)
        wt.commit(branch, notify_and_refresh("commit"))
      end)
    end)
    :action("S", "Squash", function()
      pick_branch("Squash on:", function(branch)
        wt.squash(branch, notify_and_refresh("squash"))
      end)
    end)
    :action("D", "Diff", function()
      pick_branch("Diff for:", function(branch)
        wt.diff(branch, function(ok2, lines, stderr)
          vim.schedule(function()
            if ok2 and #lines > 0 then
              wt.open_diff_buf(lines)
            elseif ok2 then
              vim.notify("[wt] No changes", vim.log.levels.INFO)
            else
              vim.notify("[wt] Diff failed: " .. table.concat(stderr or {}, "\n"), vim.log.levels.ERROR)
            end
          end)
        end)
      end)
    end)
    :action("m", "Merge", function()
      pick_branch("Merge branch:", function(branch)
        vim.ui.input({ prompt = "Merge '" .. branch .. "' into: " }, function(target)
          if not target or target == "" then return end
          wt.merge(target, branch, notify_and_refresh("merge"))
        end)
      end)
    end)
    :action("r", "Rebase", function()
      pick_branch("Rebase branch:", function(branch)
        vim.ui.input({ prompt = "Rebase '" .. branch .. "' onto: " }, function(target)
          if not target then return end
          wt.rebase(target, branch, notify_and_refresh("rebase"))
        end)
      end)
    end)
    :action("p", "Push", function()
      pick_branch("Push branch:", function(branch)
        vim.ui.input({ prompt = "Push '" .. branch .. "' to (empty=trunk): " }, function(target)
          if not target then return end
          wt.push(target, branch, notify_and_refresh("push"))
        end)
      end)
    end)
    :new_action_group("Advanced")
    :action("P", "Promote", function()
      pick_branch("Promote:", function(branch)
        wt.promote(branch, notify_and_refresh("promote"))
      end)
    end)
    :action("x", "Prune", function()
      wt.prune(notify_and_refresh("prune"))
    end)
    :action("R", "Relocate", function()
      wt.relocate(notify_and_refresh("relocate"))
    end)
    :action("e", "Eval", function()
      vim.ui.input({ prompt = "Expression: " }, function(expr)
        if not expr then return end
        wt.eval(expr, notify_and_refresh("eval"))
      end)
    end)
    :action("!", "For-each", function()
      vim.ui.input({ prompt = "Command: " }, function(cmd)
        if not cmd then return end
        wt.for_each(cmd, notify_and_refresh("for-each"))
      end)
    end)
    :build()

  p:show()
  return p
end

function M.quick_switch()
  pick_branch("Switch to:", function(branch)
    wt.switch_to(branch)
  end)
end

function M.quick_create()
  vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
    if not branch or branch == "" then return end
    wt.create_for_task(branch, function(path)
      if path then
        vim.notify("[wt] Created and switched to: " .. branch, vim.log.levels.INFO)
      end
    end)
  end)
end

function M.quick_diff()
  wt.diff(nil, function(ok, lines, stderr)
    vim.schedule(function()
      if ok and #lines > 0 then
        wt.open_diff_buf(lines)
      elseif ok then
        vim.notify("[wt] No changes", vim.log.levels.INFO)
      else
        vim.notify("[wt] Diff failed: " .. table.concat(stderr or {}, "\n"), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("Worktrunk", function()
    M.create()
  end, {})

  vim.keymap.set("n", "<leader>oww", function() M.create() end, { desc = "Worktrunk" })
  vim.keymap.set("n", "<leader>ows", function() M.quick_switch() end, { desc = "Switch worktree" })
  vim.keymap.set("n", "<leader>owc", function() M.quick_create() end, { desc = "Create worktree" })
  vim.keymap.set("n", "<leader>owd", function() M.quick_diff() end, { desc = "Diff worktree" })
end

return M
