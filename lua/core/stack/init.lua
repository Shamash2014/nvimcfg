local git = require("core.stack.git")
local config = require("core.stack.config")

local M = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Stack" })
end

local function notify_error(msg)
  notify(msg, vim.log.levels.ERROR)
end

function M.up()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    git.get_parent(current, function(parent)
      if not parent then
        notify_error("No parent branch (at stack root or not in a stack)")
        return
      end

      git.checkout(parent, function(ok)
        if ok then
          notify("Moved up to: " .. parent)
        else
          notify_error("Failed to checkout: " .. parent)
        end
      end)
    end)
  end)
end

function M.down()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    git.get_children(current, function(children)
      if #children == 0 then
        notify_error("No child branches")
        return
      end

      if #children > 1 then
        vim.ui.select(children, {
          prompt = "Select child branch:",
        }, function(choice)
          if choice then
            git.checkout(choice, function(ok)
              if ok then
                notify("Moved down to: " .. choice)
              else
                notify_error("Failed to checkout: " .. choice)
              end
            end)
          end
        end)
        return
      end

      local target = children[1]
      git.checkout(target, function(ok)
        if ok then
          notify("Moved down to: " .. target)
        else
          notify_error("Failed to checkout: " .. target)
        end
      end)
    end)
  end)
end

function M.top()
  config.get_trunk(function(trunk)
    if not trunk then
      notify_error("Could not determine trunk branch")
      return
    end

    git.checkout(trunk, function(ok)
      if ok then
        notify("Moved to trunk: " .. trunk)
      else
        notify_error("Failed to checkout: " .. trunk)
      end
    end)
  end)
end

function M.bottom()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    local function find_leaf(branch, cb)
      git.get_children(branch, function(children)
        if #children == 0 then
          cb(branch)
        else
          find_leaf(children[1], cb)
        end
      end)
    end

    find_leaf(current, function(leaf)
      if leaf == current then
        notify("Already at bottom of stack")
        return
      end

      git.checkout(leaf, function(ok)
        if ok then
          notify("Moved to bottom: " .. leaf)
        else
          notify_error("Failed to checkout: " .. leaf)
        end
      end)
    end)
  end)
end

function M.create(name)
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    local function do_create(branch_name)
      if not branch_name or branch_name == "" then
        return
      end

      git.create_branch(branch_name, nil, function(ok)
        if not ok then
          notify_error("Failed to create branch: " .. branch_name)
          return
        end

        git.set_parent(branch_name, current, function(parent_ok)
          if not parent_ok then
            notify_error("Failed to set parent for: " .. branch_name)
            return
          end

          notify("Created stack branch: " .. branch_name .. " (parent: " .. current .. ")")
        end)
      end)
    end

    if name then
      do_create(name)
      return
    end

    vim.ui.input({ prompt = "New branch name: " }, function(input)
      do_create(input)
    end)
  end)
end

function M.list()
  git.current_branch(function(current)
    config.get_stack_chain(current, function(chain)
      config.get_trunk(function(trunk)
        if #chain == 0 then
          notify("Not in a stack")
          return
        end

        local lines = { "Stack (" .. #chain .. " branches):", "" }
        if trunk then
          table.insert(lines, "  " .. trunk .. " (trunk)")
        end

        local pending = #chain
        local branch_info = {}

        for i, branch in ipairs(chain) do
          branch_info[i] = { branch = branch, commits = {} }
          git.get_parent(branch, function(parent)
            local base = parent or trunk or "HEAD~10"
            git.commits_between(base, branch, function(commits)
              branch_info[i].commits = commits
              pending = pending - 1

              if pending == 0 then
                for j, info in ipairs(branch_info) do
                  local prefix = j == #chain and "  └── " or "  ├── "
                  local marker = info.branch == current and " <- HEAD" or ""
                  local commit_info = #info.commits > 0
                      and " [" .. #info.commits .. " commit" .. (#info.commits > 1 and "s" or "") .. "]"
                      or ""
                  table.insert(lines, prefix .. info.branch .. commit_info .. marker)
                end
                notify(table.concat(lines, "\n"))
              end
            end)
          end)
        end
      end)
    end)
  end)
end

function M.adopt(branch)
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    local function do_adopt(target)
      if not target or target == "" then
        return
      end

      git.branch_exists(target, function(exists)
        if not exists then
          notify_error("Branch does not exist: " .. target)
          return
        end

        git.set_parent(target, current, function(ok)
          if ok then
            notify("Adopted " .. target .. " as child of " .. current)
          else
            notify_error("Failed to adopt: " .. target)
          end
        end)
      end)
    end

    if branch then
      do_adopt(branch)
      return
    end

    vim.ui.input({ prompt = "Branch to adopt: " }, function(input)
      do_adopt(input)
    end)
  end)
end

function M.orphan()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    git.get_parent(current, function(parent)
      if not parent then
        notify_error("Branch is not in a stack")
        return
      end

      git.get_children(current, function(children)
        local pending = #children
        local done = function()
          git.unset_parent(current, function(ok)
            if ok then
              notify("Removed " .. current .. " from stack (re-parented " .. #children .. " children to " .. parent .. ")")
            else
              notify_error("Failed to orphan branch")
            end
          end)
        end

        if pending == 0 then
          done()
          return
        end

        for _, child in ipairs(children) do
          git.set_parent(child, parent, function()
            pending = pending - 1
            if pending == 0 then
              done()
            end
          end)
        end
      end)
    end)
  end)
end

function M.delete(branch)
  git.current_branch(function(current)
    local target = branch or current
    if not target then
      notify_error("No branch specified")
      return
    end

    git.get_parent(target, function(parent)
      git.get_children(target, function(children)
        local pending = #children
        local do_delete = function()
          git.unset_parent(target, function()
            local finish = function()
              git.delete_branch(target, true, function(ok)
                if ok then
                  notify("Deleted " .. target .. " from stack")
                else
                  notify_error("Failed to delete: " .. target)
                end
              end)
            end

            if target == current and parent then
              git.checkout(parent, function()
                finish()
              end)
            else
              finish()
            end
          end)
        end

        if pending == 0 then
          do_delete()
          return
        end

        for _, child in ipairs(children) do
          local set_or_unset = function(cb)
            if parent then
              git.set_parent(child, parent, cb)
            else
              git.unset_parent(child, cb)
            end
          end

          set_or_unset(function()
            pending = pending - 1
            if pending == 0 then
              do_delete()
            end
          end)
        end
      end)
    end)
  end)
end

function M.sync()
  config.get_trunk(function(trunk)
    if not trunk then
      notify_error("Could not determine trunk branch")
      return
    end

    config.validate_git_version(function(ok, err)
      if not ok then
        notify_error(err)
        return
      end

      config.get_stack_root(nil, function(root)
        if not root then
          notify_error("Not in a stack")
          return
        end

        notify("Fetching " .. trunk .. "...")
        git.fetch("origin", trunk, function()
          git.current_branch(function(current)
            git.checkout(root, function()
              notify("Rebasing stack onto " .. trunk .. "...")
              git.rebase_update_refs(trunk, function(rebase_ok)
                if not rebase_ok then
                  git.is_rebasing(function(rebasing)
                    if rebasing then
                      notify_error("Rebase conflict. Resolve and run :StackContinue, or :StackAbort")
                    else
                      notify_error("Rebase failed")
                    end
                  end)
                  return
                end

                if current then
                  git.branch_exists(current, function(exists)
                    if exists then
                      git.checkout(current, function()
                        notify("Stack synced to latest " .. trunk)
                      end)
                    else
                      notify("Stack synced to latest " .. trunk)
                    end
                  end)
                else
                  notify("Stack synced to latest " .. trunk)
                end
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

function M.restack()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    git.get_children(current, function(children)
      if #children == 0 then
        notify("No children to restack")
        return
      end

      config.validate_git_version(function(ok, err)
        if not ok then
          notify_error(err)
          return
        end

        notify("Restacking " .. #children .. " child branch(es)...")

        git.rebase_update_refs(current, function(rebase_ok)
          if not rebase_ok then
            git.is_rebasing(function(rebasing)
              if rebasing then
                notify_error("Rebase conflict. Resolve and run :StackContinue, or :StackAbort")
              else
                notify_error("Restack failed")
              end
            end)
            return
          end

          git.checkout(current, function()
            notify("Restacked children of " .. current)
          end)
        end)
      end)
    end)
  end)
end

function M.rebase_continue()
  git.is_rebasing(function(rebasing)
    if not rebasing then
      notify("No rebase in progress")
      return
    end
    git.rebase_continue(function(ok)
      if ok then
        notify("Rebase continued")
      else
        notify_error("Continue failed - resolve remaining conflicts")
      end
    end)
  end)
end

function M.rebase_abort()
  git.is_rebasing(function(rebasing)
    if not rebasing then
      notify("No rebase in progress")
      return
    end
    git.rebase_abort(function(ok)
      if ok then
        notify("Rebase aborted")
      else
        notify_error("Abort failed")
      end
    end)
  end)
end

function M.modify()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    git.has_staged_changes(function(staged)
      git.has_unstaged_changes(function(unstaged)
        if not staged and not unstaged then
          notify("No changes to amend")
          return
        end

        git.amend(function(ok)
          if not ok then
            notify_error("Amend failed")
            return
          end

          notify("Amended commit")

          git.get_children(current, function(children)
            if #children > 0 then
              M.restack()
            end
          end)
        end)
      end)
    end)
  end)
end

function M.edit()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    git.amend_edit(function(ok)
      if not ok then
        notify_error("Amend failed")
        return
      end

      notify("Amended commit")

      git.get_children(current, function(children)
        if #children > 0 then
          M.restack()
        end
      end)
    end)
  end)
end

function M.squash()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    git.get_parent(current, function(parent)
      if not parent then
        notify_error("Not in a stack")
        return
      end

      vim.ui.input({ prompt = "Squash commit message: " }, function(message)
        if not message or message == "" then
          return
        end

        git.squash(message, function(ok, err)
          if not ok then
            notify_error(err or "Squash failed")
            return
          end

          notify("Squashed to single commit")

          git.get_children(current, function(children)
            if #children > 0 then
              M.restack()
            end
          end)
        end)
      end)
    end)
  end)
end

function M.commit()
  git.current_branch(function(current)
    if not current then
      notify_error("Not on a branch")
      return
    end

    git.get_parent(current, function(parent)
      if not parent then
        notify_error("Not in a stack")
        return
      end

      git.commits_between(parent, current, function(commits)
        local is_first = #commits == 0

        if is_first then
          git.commit(function(ok)
            if ok then
              notify("Created commit")
            else
              notify_error("Commit failed")
            end
          end)
        else
          git.amend(function(ok)
            if ok then
              notify("Amended commit")
              git.get_children(current, function(children)
                if #children > 0 then
                  M.restack()
                end
              end)
            else
              notify_error("Commit failed")
            end
          end)
        end
      end)
    end)
  end)
end

function M.push()
  config.get_stack_chain(nil, function(chain)
    if #chain == 0 then
      notify_error("Not in a stack")
      return
    end

    notify("Pushing " .. #chain .. " branch(es)...")

    local i = 1
    local function push_next()
      if i > #chain then
        return
      end
      local branch = chain[i]
      git.push(branch, true, function(ok)
        if ok then
          notify("Pushed " .. branch)
        else
          notify_error("Failed to push " .. branch)
        end
        i = i + 1
        push_next()
      end)
    end
    push_next()
  end)
end

function M.submit()
  config.get_stack_chain(nil, function(chain)
    if #chain == 0 then
      notify_error("Not in a stack")
      return
    end

    config.get_trunk(function(trunk)
      git.get_mr_term(function(mr_term)
        git.get_forge(function(forge)
          notify("Submitting " .. #chain .. " branch(es) as " .. mr_term .. "s to " .. forge .. "...")

          local i = 1
          local function submit_next()
            if i > #chain then
              return
            end
            local branch = chain[i]
            local base = i == 1 and trunk or chain[i - 1]

            git.pr_exists(branch, function(pr_num)
              if pr_num then
                git.push(branch, true, function()
                  git.update_pr_base(pr_num, base, function(ok)
                    if ok then
                      notify("Updated " .. mr_term .. " #" .. pr_num .. " for " .. branch)
                    else
                      notify_error("Failed to update " .. mr_term .. " for " .. branch)
                    end
                    i = i + 1
                    submit_next()
                  end)
                end)
              else
                git.commits_between(base, branch, function(commits)
                  local title = #commits > 0 and commits[#commits].message or branch
                  local body = "Part of stack:\n"
                  for j, b in ipairs(chain) do
                    body = body .. (j == i and "- **" .. b .. "** (this " .. mr_term .. ")\n" or "- " .. b .. "\n")
                  end

                  git.create_pr(branch, base, title, body, function(ok)
                    if ok then
                      git.get_pr_url(branch, function(url)
                        notify("Created " .. mr_term .. " for " .. branch .. (url and ": " .. url or ""))
                        i = i + 1
                        submit_next()
                      end)
                    else
                      notify_error("Failed to create " .. mr_term .. " for " .. branch)
                      i = i + 1
                      submit_next()
                    end
                  end)
                end)
              end
            end)
          end
          submit_next()
        end)
      end)
    end)
  end)
end

function M.log()
  local graph = require("core.stack.graph")
  graph.show()
end

function M.popup()
  git.current_branch(function(current)
    current = current or "(detached)"
    git.get_parent(current, function(parent)
      git.get_children(current, function(children)
        config.get_trunk(function(trunk)
          git.has_staged_changes(function(staged)
            git.has_unstaged_changes(function(unstaged)
              local has_changes = staged or unstaged

              local popup = require("core.stack.popup")

              popup.builder()
                :name("Stack: " .. current)
                :group_heading("Navigate")
                :action("u", "up (parent)", M.up, { enabled = parent ~= nil })
                :action("d", "down (child)", M.down, { enabled = #children > 0 })
                :action("t", "top (trunk)", M.top, { enabled = trunk ~= nil })
                :action("b", "bottom (leaf)", M.bottom, { enabled = #children > 0 })
                :group_heading("Commit")
                :action("C", "commit (auto-amend)", M.commit, { enabled = parent ~= nil })
                :action("m", "modify (amend + restack)", M.modify, { enabled = has_changes })
                :action("e", "edit (amend with editor)", M.edit)
                :action("Q", "squash to 1 commit", M.squash, { enabled = parent ~= nil })
                :group_heading("Branch")
                :action("c", "create child", M.create)
                :action("l", "list stack", M.list)
                :action("L", "log (graph)", M.log)
                :group_heading("Sync")
                :action("s", "sync (rebase onto trunk)", M.sync, { enabled = parent ~= nil })
                :action("r", "restack (after amend)", M.restack, { enabled = #children > 0 })
                :action("p", "push stack", M.push, { enabled = parent ~= nil })
                :action("S", "submit PRs", M.submit, { enabled = parent ~= nil })
                :group_heading("Manage")
                :action("a", "adopt branch", M.adopt)
                :action("o", "orphan (leave stack)", M.orphan, { enabled = parent ~= nil })
                :action("D", "delete from stack", M.delete, { enabled = parent ~= nil })
                :build()
                :show()
            end)
          end)
        end)
      end)
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("Stack", function(opts)
    local cmd = opts.args
    if cmd == "" or cmd == "popup" then
      M.popup()
    elseif M[cmd] then
      M[cmd]()
    else
      notify_error("Unknown command: " .. cmd)
    end
  end, {
    nargs = "?",
    complete = function()
      return { "up", "down", "top", "bottom", "commit", "modify", "edit", "squash", "create", "list", "log", "sync", "restack", "push", "submit", "adopt", "orphan", "delete", "popup" }
    end,
  })

  vim.api.nvim_create_user_command("StackContinue", M.rebase_continue, {})
  vim.api.nvim_create_user_command("StackAbort", M.rebase_abort, {})
end

return M
