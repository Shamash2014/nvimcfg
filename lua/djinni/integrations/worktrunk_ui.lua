local M = {}
local wt = require("djinni.integrations.worktrunk")

local function format_worktree(e)
  local mark = e.is_current and "@ " or "  "
  local name = e.branch or "(detached)"
  local parts = {}
  if e.symbols and e.symbols ~= "" then table.insert(parts, e.symbols) end
  if e.operation_state then table.insert(parts, e.operation_state) end
  if e.main_state and e.main_state ~= "is_main" then table.insert(parts, e.main_state) end
  if e.working_tree then
    local wt_flags = {}
    if e.working_tree.staged then table.insert(wt_flags, "+staged") end
    if e.working_tree.modified then table.insert(wt_flags, "!modified") end
    if e.working_tree.untracked then table.insert(wt_flags, "?untracked") end
    if #wt_flags > 0 then table.insert(parts, table.concat(wt_flags, " ")) end
    if e.working_tree.diff then
      local d = e.working_tree.diff
      if d.added > 0 or d.deleted > 0 then
        table.insert(parts, "+" .. d.added .. " -" .. d.deleted)
      end
    end
  end
  if e.main and (e.main.ahead > 0 or e.main.behind > 0) then
    table.insert(parts, "main↑" .. e.main.ahead .. "↓" .. e.main.behind)
  end
  if e.remote and (e.remote.ahead > 0 or e.remote.behind > 0) then
    table.insert(parts, "remote⇡" .. e.remote.ahead .. "⇣" .. e.remote.behind)
  end
  if e.ci and e.ci.status then table.insert(parts, "CI:" .. e.ci.status) end
  if e.commit then
    local age = ""
    if e.commit.timestamp then
      local delta = os.time() - e.commit.timestamp
      if delta < 3600 then age = string.format(" %dm", math.floor(delta / 60))
      elseif delta < 86400 then age = string.format(" %dh", math.floor(delta / 3600))
      else age = string.format(" %dd", math.floor(delta / 86400))
      end
    end
    table.insert(parts, e.commit.short_sha .. age .. " " .. (e.commit.message or ""))
  end
  local suffix = #parts > 0 and ("  " .. table.concat(parts, "  ")) or ""
  return mark .. name .. suffix
end

local function pick_branch(prompt, cb)
  wt.list({ full = true }, function(entries)
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
        format_item = format_worktree,
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
        vim.ui.select({ "Default branch", "Stacked (from current HEAD)" }, { prompt = "Base:" }, function(choice)
          if not choice then return end
          local opts = choice:match("Stacked") and { base = "@" } or {}
          wt.create_for_task(branch, opts, function(path)
            if path then
              vim.notify("[wt] Created: " .. branch, vim.log.levels.INFO)
            end
          end)
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
        wt.get_path(branch, function(path)
          wt.commit({ cwd = path }, notify_and_refresh("commit"))
        end)
      end)
    end)
    :action("S", "Squash", function()
      pick_branch("Squash on:", function(branch)
        wt.get_path(branch, function(path)
          wt.squash({ cwd = path }, notify_and_refresh("squash"))
        end)
      end)
    end)
    :action("D", "Diff", function()
      pick_branch("Diff for:", function(branch)
        wt.get_path(branch, function(path)
          wt.diff({ cwd = path }, function(ok2, lines, stderr)
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
    end)
    :action("m", "Merge", function()
      pick_branch("Merge branch:", function(branch)
        vim.ui.input({ prompt = "Merge '" .. branch .. "' into (empty=default): " }, function(target)
          if target == nil then return end
          wt.get_path(branch, function(path)
            wt.merge({ target = target ~= "" and target or nil, cwd = path }, notify_and_refresh("merge"))
          end)
        end)
      end)
    end)
    :action("r", "Rebase", function()
      pick_branch("Rebase branch:", function(branch)
        vim.ui.input({ prompt = "Rebase '" .. branch .. "' onto (empty=default): " }, function(target)
          if target == nil then return end
          wt.get_path(branch, function(path)
            wt.rebase({ target = target ~= "" and target or nil, cwd = path }, notify_and_refresh("rebase"))
          end)
        end)
      end)
    end)
    :action("u", "Update current (fetch & rebase onto default)", function()
      wt.update({}, notify_and_refresh("update"))
    end)
    :action("U", "Update from branch", function()
      pick_branch("Update from:", function(branch)
        wt.get_path(branch, function(path)
          wt.update({ cwd = path }, notify_and_refresh("update"))
        end)
      end)
    end)
    :action("i", "Copy ignored files", function()
      pick_branch("Copy ignored to:", function(branch)
        wt.copy_ignored({ to = branch }, notify_and_refresh("copy-ignored"))
      end)
    end)
    :action("p", "Push", function()
      pick_branch("Push branch:", function(branch)
        vim.ui.input({ prompt = "Push '" .. branch .. "' to (empty=default): " }, function(target)
          if target == nil then return end
          wt.get_path(branch, function(path)
            wt.push({ target = target ~= "" and target or nil, cwd = path }, notify_and_refresh("push"))
          end)
        end)
      end)
    end)
    :new_action_group("Advanced")
    :action("P", "Promote", function()
      pick_branch("Promote:", function(branch)
        wt.promote({ branch = branch }, notify_and_refresh("promote"))
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
    vim.ui.select({ "Default branch", "Stacked (from current HEAD)" }, { prompt = "Base:" }, function(choice)
      if not choice then return end
      local opts = choice:match("Stacked") and { base = "@" } or {}
      wt.create_for_task(branch, opts, function(path)
        if path then
          vim.notify("[wt] Created and switched to: " .. branch, vim.log.levels.INFO)
        end
      end)
    end)
  end)
end

function M.quick_diff()
  wt.diff(function(ok, lines, stderr)
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
