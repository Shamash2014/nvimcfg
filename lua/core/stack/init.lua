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
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local parent = git.get_parent(current)
  if not parent then
    notify_error("No parent branch (at stack root or not in a stack)")
    return false
  end

  local ok = git.checkout(parent)
  if ok then
    notify("Moved up to: " .. parent)
  else
    notify_error("Failed to checkout: " .. parent)
  end
  return ok
end

function M.down()
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local children = git.get_children(current)
  if #children == 0 then
    notify_error("No child branches")
    return false
  end

  local target = children[1]
  if #children > 1 then
    vim.ui.select(children, {
      prompt = "Select child branch:",
    }, function(choice)
      if choice then
        local ok = git.checkout(choice)
        if ok then
          notify("Moved down to: " .. choice)
        else
          notify_error("Failed to checkout: " .. choice)
        end
      end
    end)
    return true
  end

  local ok = git.checkout(target)
  if ok then
    notify("Moved down to: " .. target)
  else
    notify_error("Failed to checkout: " .. target)
  end
  return ok
end

function M.top()
  local trunk = config.get_trunk()
  if not trunk then
    notify_error("Could not determine trunk branch")
    return false
  end

  local ok = git.checkout(trunk)
  if ok then
    notify("Moved to trunk: " .. trunk)
  else
    notify_error("Failed to checkout: " .. trunk)
  end
  return ok
end

function M.bottom()
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local function find_leaf(branch)
    local children = git.get_children(branch)
    if #children == 0 then
      return branch
    end
    return find_leaf(children[1])
  end

  local leaf = find_leaf(current)
  if leaf == current then
    notify("Already at bottom of stack")
    return true
  end

  local ok = git.checkout(leaf)
  if ok then
    notify("Moved to bottom: " .. leaf)
  else
    notify_error("Failed to checkout: " .. leaf)
  end
  return ok
end

function M.create(name)
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local function do_create(branch_name)
    if not branch_name or branch_name == "" then
      return
    end

    local ok = git.create_branch(branch_name)
    if not ok then
      notify_error("Failed to create branch: " .. branch_name)
      return false
    end

    ok = git.set_parent(branch_name, current)
    if not ok then
      notify_error("Failed to set parent for: " .. branch_name)
      return false
    end

    notify("Created stack branch: " .. branch_name .. " (parent: " .. current .. ")")
    return true
  end

  if name then
    return do_create(name)
  end

  vim.ui.input({ prompt = "New branch name: " }, function(input)
    do_create(input)
  end)
end

function M.list()
  local current = git.current_branch()
  local chain = config.get_stack_chain(current)
  local trunk = config.get_trunk()

  if #chain == 0 then
    notify("Not in a stack")
    return {}
  end

  local lines = { "Stack (" .. #chain .. " branches):", "" }
  if trunk then
    table.insert(lines, "  " .. trunk .. " (trunk)")
  end

  for i, branch in ipairs(chain) do
    local prefix = i == #chain and "  └── " or "  ├── "
    local marker = branch == current and " <- HEAD" or ""
    local commits = git.commits_between(git.get_parent(branch) or trunk or "HEAD~10", branch)
    local commit_info = #commits > 0 and " [" .. #commits .. " commit" .. (#commits > 1 and "s" or "") .. "]" or ""
    table.insert(lines, prefix .. branch .. commit_info .. marker)
  end

  notify(table.concat(lines, "\n"))
  return chain
end

function M.adopt(branch)
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local function do_adopt(target)
    if not target or target == "" then
      return
    end

    if not git.branch_exists(target) then
      notify_error("Branch does not exist: " .. target)
      return false
    end

    local ok = git.set_parent(target, current)
    if ok then
      notify("Adopted " .. target .. " as child of " .. current)
    else
      notify_error("Failed to adopt: " .. target)
    end
    return ok
  end

  if branch then
    return do_adopt(branch)
  end

  vim.ui.input({ prompt = "Branch to adopt: " }, function(input)
    do_adopt(input)
  end)
end

function M.orphan()
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local parent = git.get_parent(current)
  if not parent then
    notify_error("Branch is not in a stack")
    return false
  end

  local children = git.get_children(current)
  for _, child in ipairs(children) do
    git.set_parent(child, parent)
  end

  local ok = git.unset_parent(current)
  if ok then
    notify("Removed " .. current .. " from stack (re-parented " .. #children .. " children to " .. parent .. ")")
  else
    notify_error("Failed to orphan branch")
  end
  return ok
end

function M.delete(branch)
  branch = branch or git.current_branch()
  if not branch then
    notify_error("No branch specified")
    return false
  end

  local parent = git.get_parent(branch)
  local children = git.get_children(branch)

  for _, child in ipairs(children) do
    if parent then
      git.set_parent(child, parent)
    else
      git.unset_parent(child)
    end
  end

  git.unset_parent(branch)

  if branch == git.current_branch() and parent then
    git.checkout(parent)
  end

  local ok = git.delete_branch(branch, true)
  if ok then
    notify("Deleted " .. branch .. " from stack")
  else
    notify_error("Failed to delete: " .. branch)
  end
  return ok
end

function M.sync()
  local trunk = config.get_trunk()
  if not trunk then
    notify_error("Could not determine trunk branch")
    return false
  end

  local ok, err = config.validate_git_version()
  if not ok then
    notify_error(err)
    return false
  end

  local root = config.get_stack_root()
  if not root then
    notify_error("Not in a stack")
    return false
  end

  notify("Fetching " .. trunk .. "...")
  git.fetch("origin", trunk)

  local current = git.current_branch()
  git.checkout(root)

  notify("Rebasing stack onto " .. trunk .. "...")
  ok = git.rebase_update_refs(trunk)

  if not ok then
    if git.is_rebasing() then
      notify_error("Rebase conflict. Resolve and run :StackContinue, or :StackAbort")
      return false
    end
    notify_error("Rebase failed")
    return false
  end

  if current and git.branch_exists(current) then
    git.checkout(current)
  end

  notify("Stack synced to latest " .. trunk)
  return true
end

function M.restack()
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local children = git.get_children(current)
  if #children == 0 then
    notify("No children to restack")
    return true
  end

  local ok, err = config.validate_git_version()
  if not ok then
    notify_error(err)
    return false
  end

  notify("Restacking " .. #children .. " child branch(es)...")

  ok = git.rebase_update_refs(current)
  if not ok then
    if git.is_rebasing() then
      notify_error("Rebase conflict. Resolve and run :StackContinue, or :StackAbort")
      return false
    end
    notify_error("Restack failed")
    return false
  end

  git.checkout(current)
  notify("Restacked children of " .. current)
  return true
end

function M.rebase_continue()
  if not git.is_rebasing() then
    notify("No rebase in progress")
    return true
  end
  local ok = git.rebase_continue()
  if ok then
    notify("Rebase continued")
  else
    notify_error("Continue failed - resolve remaining conflicts")
  end
  return ok
end

function M.rebase_abort()
  if not git.is_rebasing() then
    notify("No rebase in progress")
    return true
  end
  local ok = git.rebase_abort()
  if ok then
    notify("Rebase aborted")
  else
    notify_error("Abort failed")
  end
  return ok
end

function M.modify()
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  if not git.has_staged_changes() and not git.has_unstaged_changes() then
    notify("No changes to amend")
    return false
  end

  local ok = git.amend()
  if not ok then
    notify_error("Amend failed")
    return false
  end

  notify("Amended commit")

  local children = git.get_children(current)
  if #children > 0 then
    M.restack()
  end

  return true
end

function M.edit()
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local ok = git.amend_edit()
  if not ok then
    notify_error("Amend failed")
    return false
  end

  notify("Amended commit")

  local children = git.get_children(current)
  if #children > 0 then
    M.restack()
  end

  return true
end

function M.squash()
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local parent = git.get_parent(current)
  if not parent then
    notify_error("Not in a stack")
    return false
  end

  vim.ui.input({ prompt = "Squash commit message: " }, function(message)
    if not message or message == "" then
      return
    end

    local ok, err = git.squash(message)
    if not ok then
      notify_error(err or "Squash failed")
      return
    end

    notify("Squashed to single commit")

    local children = git.get_children(current)
    if #children > 0 then
      M.restack()
    end
  end)
end

function M.commit()
  local current = git.current_branch()
  if not current then
    notify_error("Not on a branch")
    return false
  end

  local parent = git.get_parent(current)
  if not parent then
    notify_error("Not in a stack")
    return false
  end

  local commits = git.commits_between(parent, current)
  local is_first = #commits == 0

  local ok
  if is_first then
    ok = git.commit()
    if ok then
      notify("Created commit")
    end
  else
    ok = git.amend()
    if ok then
      notify("Amended commit")
      local children = git.get_children(current)
      if #children > 0 then
        M.restack()
      end
    end
  end

  if not ok then
    notify_error("Commit failed")
  end
  return ok
end

function M.push()
  local chain = config.get_stack_chain()
  if #chain == 0 then
    notify_error("Not in a stack")
    return false
  end

  notify("Pushing " .. #chain .. " branch(es)...")
  for _, branch in ipairs(chain) do
    local ok = git.push(branch, true)
    if ok then
      notify("Pushed " .. branch)
    else
      notify_error("Failed to push " .. branch)
    end
  end
  return true
end

function M.submit()
  local chain = config.get_stack_chain()
  if #chain == 0 then
    notify_error("Not in a stack")
    return false
  end

  local trunk = config.get_trunk()
  local mr_term = git.get_mr_term()
  local forge = git.get_forge()
  notify("Submitting " .. #chain .. " branch(es) as " .. mr_term .. "s to " .. forge .. "...")

  for i, branch in ipairs(chain) do
    local base = i == 1 and trunk or chain[i - 1]
    local pr_num = git.pr_exists(branch)

    if pr_num then
      git.push(branch, true)
      local ok = git.update_pr_base(pr_num, base)
      if ok then
        notify("Updated " .. mr_term .. " #" .. pr_num .. " for " .. branch)
      else
        notify_error("Failed to update " .. mr_term .. " for " .. branch)
      end
    else
      local commits = git.commits_between(base, branch)
      local title = #commits > 0 and commits[#commits].message or branch
      local body = "Part of stack:\n"
      for j, b in ipairs(chain) do
        body = body .. (j == i and "- **" .. b .. "** (this " .. mr_term .. ")\n" or "- " .. b .. "\n")
      end

      local ok = git.create_pr(branch, base, title, body)
      if ok then
        local url = git.get_pr_url(branch)
        notify("Created " .. mr_term .. " for " .. branch .. (url and ": " .. url or ""))
      else
        notify_error("Failed to create " .. mr_term .. " for " .. branch)
      end
    end
  end

  return true
end

function M.log()
  local graph = require("core.stack.graph")
  graph.show()
end

function M.popup()
  local current = git.current_branch() or "(detached)"
  local parent = git.get_parent(current)
  local children = git.get_children(current)
  local trunk = config.get_trunk()

  local has_changes = git.has_staged_changes() or git.has_unstaged_changes()

  local items = {
    { key = "u", label = "up (parent)", action = M.up, enabled = parent ~= nil },
    { key = "d", label = "down (child)", action = M.down, enabled = #children > 0 },
    { key = "t", label = "top (trunk)", action = M.top, enabled = trunk ~= nil },
    { key = "b", label = "bottom (leaf)", action = M.bottom, enabled = #children > 0 },
    { key = "", label = "", action = nil },
    { key = "C", label = "commit (auto-amend)", action = M.commit, enabled = parent ~= nil },
    { key = "m", label = "modify (amend + restack)", action = M.modify, enabled = has_changes },
    { key = "e", label = "edit (amend with editor)", action = M.edit, enabled = true },
    { key = "q", label = "squash to 1 commit", action = M.squash, enabled = parent ~= nil },
    { key = "", label = "", action = nil },
    { key = "c", label = "create child", action = M.create, enabled = true },
    { key = "l", label = "list stack", action = M.list, enabled = true },
    { key = "L", label = "log (graph)", action = M.log, enabled = true },
    { key = "", label = "", action = nil },
    { key = "s", label = "sync (rebase onto trunk)", action = M.sync, enabled = parent ~= nil },
    { key = "r", label = "restack (after amend)", action = M.restack, enabled = #children > 0 },
    { key = "p", label = "push stack", action = M.push, enabled = parent ~= nil },
    { key = "S", label = "submit PRs", action = M.submit, enabled = parent ~= nil },
    { key = "", label = "", action = nil },
    { key = "a", label = "adopt branch", action = M.adopt, enabled = true },
    { key = "o", label = "orphan (leave stack)", action = M.orphan, enabled = parent ~= nil },
    { key = "D", label = "delete from stack", action = M.delete, enabled = parent ~= nil },
  }

  local lines = { "Stack: " .. current, string.rep("─", 30) }
  local key_map = {}

  for _, item in ipairs(items) do
    if item.key == "" then
      table.insert(lines, "")
    else
      local prefix = item.enabled and " " or " "
      local style = item.enabled and "" or " (disabled)"
      table.insert(lines, prefix .. item.key .. "  " .. item.label .. style)
      if item.enabled then
        key_map[item.key] = item.action
      end
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local width = 35
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " Stack ",
    title_pos = "center",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf })

  for key, action in pairs(key_map) do
    vim.keymap.set("n", key, function()
      close()
      vim.schedule(action)
    end, { buffer = buf })
  end
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
