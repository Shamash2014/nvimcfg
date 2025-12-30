local M = {}

local function run(cmd, opts)
  opts = opts or {}
  local result = vim.fn.systemlist(cmd)
  local success = vim.v.shell_error == 0
  if opts.trim and #result == 1 then
    return success, result[1]
  end
  return success, result
end

function M.current_branch()
  local ok, branch = run("git branch --show-current", { trim = true })
  if ok and branch ~= "" then
    return branch
  end
  return nil
end

function M.branch_exists(name)
  local ok = run("git show-ref --verify --quiet refs/heads/" .. vim.fn.shellescape(name))
  return ok
end

function M.checkout(branch)
  return run("git checkout " .. vim.fn.shellescape(branch))
end

function M.create_branch(name, base)
  base = base or "HEAD"
  return run("git checkout -b " .. vim.fn.shellescape(name) .. " " .. vim.fn.shellescape(base))
end

function M.delete_branch(name, force)
  local flag = force and "-D" or "-d"
  return run("git branch " .. flag .. " " .. vim.fn.shellescape(name))
end

function M.get_parent(branch)
  branch = branch or M.current_branch()
  if not branch then return nil end
  local ok, parent = run("git config --get branch." .. vim.fn.shellescape(branch) .. ".stackParent", { trim = true })
  if ok and parent ~= "" then
    return parent
  end
  return nil
end

function M.set_parent(branch, parent)
  return run("git config branch." .. vim.fn.shellescape(branch) .. ".stackParent " .. vim.fn.shellescape(parent))
end

function M.unset_parent(branch)
  return run("git config --unset branch." .. vim.fn.shellescape(branch) .. ".stackParent")
end

function M.get_children(branch)
  branch = branch or M.current_branch()
  if not branch then return {} end

  local ok, lines = run("git config --get-regexp 'branch\\..*\\.stackParent'")
  if not ok then return {} end

  local children = {}
  for _, line in ipairs(lines) do
    local child_branch, parent = line:match("^branch%.(.-)%.stackParent%s+(.+)$")
    if child_branch and parent == branch then
      table.insert(children, child_branch)
    end
  end
  return children
end

function M.commits_between(base, head)
  local ok, commits = run("git log --oneline " .. vim.fn.shellescape(base) .. ".." .. vim.fn.shellescape(head))
  if not ok then return {} end

  local result = {}
  for _, line in ipairs(commits) do
    local hash, msg = line:match("^(%S+)%s+(.+)$")
    if hash then
      table.insert(result, { hash = hash, message = msg })
    end
  end
  return result
end

function M.rebase_update_refs(onto)
  return run("git rebase --update-refs " .. vim.fn.shellescape(onto))
end

function M.is_rebasing()
  local git_dir = vim.fn.systemlist("git rev-parse --git-dir")[1]
  if vim.v.shell_error ~= 0 then return false end
  return vim.fn.isdirectory(git_dir .. "/rebase-merge") == 1
      or vim.fn.isdirectory(git_dir .. "/rebase-apply") == 1
end

function M.rebase_continue()
  return run("git rebase --continue")
end

function M.rebase_abort()
  return run("git rebase --abort")
end

function M.fetch(remote, branch)
  remote = remote or "origin"
  if branch then
    return run("git fetch " .. vim.fn.shellescape(remote) .. " " .. vim.fn.shellescape(branch) .. ":" .. vim.fn.shellescape(branch))
  end
  return run("git fetch " .. vim.fn.shellescape(remote))
end

local function get_forge()
  local ok, url = run("git remote get-url origin", { trim = true })
  if not ok or not url then return "github" end

  if url:match("gitlab") then
    return "gitlab"
  elseif url:match("codeberg") or url:match("gitea") or url:match("forgejo") then
    return "gitea"
  else
    return "github"
  end
end

function M.get_forge()
  return get_forge()
end

function M.get_mr_term()
  local forge = get_forge()
  return forge == "gitlab" and "MR" or "PR"
end

function M.push(branch, force)
  branch = branch or M.current_branch()
  if not branch then return false end
  local flag = force and "--force-with-lease" or ""
  return run(string.format("git push -u origin %s %s", branch, flag))
end

function M.pr_exists(branch)
  local cmd = string.format("gcli pulls --from %s 2>/dev/null | head -1 | awk '{print $1}'", vim.fn.shellescape(branch))
  local ok, result = run(cmd, { trim = true })
  if ok and result and result ~= "" and result:match("^%d+$") then
    return tonumber(result)
  end
  return nil
end

function M.create_pr(branch, base, title, body)
  M.push(branch)
  local cmd = string.format(
    "gcli pulls create -y --from %s --to %s --body %s %s",
    vim.fn.shellescape(branch),
    vim.fn.shellescape(base),
    vim.fn.shellescape(body or ""),
    vim.fn.shellescape(title)
  )
  return run(cmd)
end

function M.update_pr_base(pr_number, base)
  local cmd = string.format("gcli pulls edit %s --base %s", pr_number, vim.fn.shellescape(base))
  return run(cmd)
end

function M.get_pr_url(branch)
  local cmd = string.format("gcli pulls --from %s 2>/dev/null | head -1 | awk '{print $NF}'", vim.fn.shellescape(branch))
  local ok, url = run(cmd, { trim = true })
  if ok and url and url:match("^http") then
    return url
  end
  return nil
end

function M.commit()
  vim.cmd("!git add -A && git commit")
  return vim.v.shell_error == 0
end

function M.amend()
  return run("git add -A && git commit --amend --no-edit")
end

function M.amend_edit()
  vim.cmd("!git commit --amend")
  return vim.v.shell_error == 0
end

function M.squash(message)
  local parent = M.get_parent(M.current_branch())
  if not parent then
    return false, "No parent branch"
  end

  local ok = run("git reset --soft " .. vim.fn.shellescape(parent))
  if not ok then
    return false, "Reset failed"
  end

  if message then
    return run("git commit -m " .. vim.fn.shellescape(message))
  else
    vim.cmd("!git commit")
    return vim.v.shell_error == 0
  end
end

function M.has_staged_changes()
  local ok = run("git diff --cached --quiet")
  return not ok
end

function M.has_unstaged_changes()
  local ok = run("git diff --quiet")
  return not ok
end

return M
