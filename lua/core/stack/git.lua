local Job = require("plenary.job")

local M = {}

local function run_async(cmd, opts, callback)
  opts = opts or {}
  Job:new({
    command = "sh",
    args = { "-c", cmd },
    on_exit = function(j, code)
      vim.schedule(function()
        local success = code == 0
        local result = j:result()
        if opts.trim and #result == 1 then
          callback(success, result[1])
        else
          callback(success, result)
        end
      end)
    end,
  }):start()
end
function M.current_branch(callback)
  run_async("git branch --show-current", { trim = true }, function(ok, branch)
    if ok and branch ~= "" then
      callback(branch)
    else
      callback(nil)
    end
  end)
end

function M.branch_exists(name, callback)
  run_async("git show-ref --verify --quiet refs/heads/" .. vim.fn.shellescape(name), {}, function(ok)
    callback(ok)
  end)
end

function M.checkout(branch, callback)
  run_async("git checkout " .. vim.fn.shellescape(branch), {}, function(ok)
    callback(ok)
  end)
end

function M.create_branch(name, base, callback)
  base = base or "HEAD"
  run_async("git checkout -b " .. vim.fn.shellescape(name) .. " " .. vim.fn.shellescape(base), {}, function(ok)
    callback(ok)
  end)
end

function M.delete_branch(name, force, callback)
  local flag = force and "-D" or "-d"
  run_async("git branch " .. flag .. " " .. vim.fn.shellescape(name), {}, function(ok)
    callback(ok)
  end)
end

function M.get_parent(branch, callback)
  if not branch then
    M.current_branch(function(current)
      if not current then
        callback(nil)
        return
      end
      M.get_parent(current, callback)
    end)
    return
  end
  run_async("git config --get branch." .. vim.fn.shellescape(branch) .. ".stackParent", { trim = true }, function(ok, parent)
    if ok and parent ~= "" then
      callback(parent)
    else
      callback(nil)
    end
  end)
end

function M.set_parent(branch, parent, callback)
  run_async("git config branch." .. vim.fn.shellescape(branch) .. ".stackParent " .. vim.fn.shellescape(parent), {}, function(ok)
    callback(ok)
  end)
end

function M.unset_parent(branch, callback)
  run_async("git config --unset branch." .. vim.fn.shellescape(branch) .. ".stackParent", {}, function(ok)
    callback(ok)
  end)
end

function M.get_children(branch, callback)
  if not branch then
    M.current_branch(function(current)
      if not current then
        callback({})
        return
      end
      M.get_children(current, callback)
    end)
    return
  end

  run_async("git config --get-regexp 'branch\\..*\\.stackParent'", {}, function(ok, lines)
    if not ok then
      callback({})
      return
    end

    local children = {}
    for _, line in ipairs(lines) do
      local child_branch, parent = line:match("^branch%.(.-)%.stackParent%s+(.+)$")
      if child_branch and parent == branch then
        table.insert(children, child_branch)
      end
    end
    callback(children)
  end)
end

function M.commits_between(base, head, callback)
  run_async("git log --oneline " .. vim.fn.shellescape(base) .. ".." .. vim.fn.shellescape(head), {}, function(ok, commits)
    if not ok then
      callback({})
      return
    end

    local result = {}
    for _, line in ipairs(commits) do
      local hash, msg = line:match("^(%S+)%s+(.+)$")
      if hash then
        table.insert(result, { hash = hash, message = msg })
      end
    end
    callback(result)
  end)
end

function M.rebase_update_refs(onto, callback)
  run_async("git rebase --update-refs " .. vim.fn.shellescape(onto), {}, function(ok)
    callback(ok)
  end)
end

function M.is_rebasing(callback)
  run_async("git rev-parse --git-dir", { trim = true }, function(ok, git_dir)
    if not ok then
      callback(false)
      return
    end
    local rebasing = vim.fn.isdirectory(git_dir .. "/rebase-merge") == 1
        or vim.fn.isdirectory(git_dir .. "/rebase-apply") == 1
    callback(rebasing)
  end)
end

function M.rebase_continue(callback)
  run_async("git rebase --continue", {}, function(ok)
    callback(ok)
  end)
end

function M.rebase_abort(callback)
  run_async("git rebase --abort", {}, function(ok)
    callback(ok)
  end)
end

function M.fetch(remote, branch, callback)
  remote = remote or "origin"
  local cmd
  if branch then
    cmd = "git fetch " .. vim.fn.shellescape(remote) .. " " .. vim.fn.shellescape(branch) .. ":" .. vim.fn.shellescape(branch)
  else
    cmd = "git fetch " .. vim.fn.shellescape(remote)
  end
  run_async(cmd, {}, function(ok)
    callback(ok)
  end)
end

function M.get_forge(callback)
  run_async("git remote get-url origin", { trim = true }, function(ok, url)
    if not ok or not url then
      callback("github")
      return
    end

    if url:match("gitlab") then
      callback("gitlab")
    elseif url:match("codeberg") or url:match("gitea") or url:match("forgejo") then
      callback("gitea")
    else
      callback("github")
    end
  end)
end

function M.get_mr_term(callback)
  M.get_forge(function(forge)
    callback(forge == "gitlab" and "MR" or "PR")
  end)
end

function M.push(branch, force, callback)
  if not branch then
    M.current_branch(function(current)
      if not current then
        callback(false)
        return
      end
      M.push(current, force, callback)
    end)
    return
  end
  local flag = force and "--force-with-lease" or ""
  run_async(string.format("git push -u origin %s %s", vim.fn.shellescape(branch), flag), {}, function(ok)
    callback(ok)
  end)
end

function M.pr_exists(branch, callback)
  local cmd = string.format("gcli pulls --from %s 2>/dev/null | head -1 | awk '{print $1}'", vim.fn.shellescape(branch))
  run_async(cmd, { trim = true }, function(ok, result)
    if ok and type(result) == "string" and result ~= "" and result:match("^%d+$") then
      callback(tonumber(result))
    else
      callback(nil)
    end
  end)
end

function M.create_pr(branch, base, title, body, callback)
  M.push(branch, false, function()
    local cmd = string.format(
      "gcli pulls create -y --from %s --to %s --body %s %s",
      vim.fn.shellescape(branch),
      vim.fn.shellescape(base),
      vim.fn.shellescape(body or ""),
      vim.fn.shellescape(title)
    )
    run_async(cmd, {}, function(ok)
      callback(ok)
    end)
  end)
end

function M.update_pr_base(pr_number, base, callback)
  local cmd = string.format("gcli pulls edit %s --base %s", pr_number, vim.fn.shellescape(base))
  run_async(cmd, {}, function(ok)
    callback(ok)
  end)
end

function M.get_pr_url(branch, callback)
  local cmd = string.format("gcli pulls --from %s 2>/dev/null | head -1 | awk '{print $NF}'", vim.fn.shellescape(branch))
  run_async(cmd, { trim = true }, function(ok, url)
    if ok and url and url:match("^http") then
      callback(url)
    else
      callback(nil)
    end
  end)
end

function M.commit(callback)
  vim.cmd("!git add -A && git commit")
  callback(vim.v.shell_error == 0)
end

function M.amend(callback)
  run_async("git add -A && git commit --amend --no-edit", {}, function(ok)
    callback(ok)
  end)
end

function M.amend_edit(callback)
  vim.cmd("!git commit --amend")
  callback(vim.v.shell_error == 0)
end

function M.squash(message, callback)
  M.current_branch(function(current)
    M.get_parent(current, function(parent)
      if not parent then
        callback(false, "No parent branch")
        return
      end

      run_async("git reset --soft " .. vim.fn.shellescape(parent), {}, function(ok)
        if not ok then
          callback(false, "Reset failed")
          return
        end

        if message then
          run_async("git commit -m " .. vim.fn.shellescape(message), {}, function(commit_ok)
            callback(commit_ok)
          end)
        else
          vim.cmd("!git commit")
          callback(vim.v.shell_error == 0)
        end
      end)
    end)
  end)
end

function M.has_staged_changes(callback)
  run_async("git diff --cached --quiet", {}, function(ok)
    callback(not ok)
  end)
end

function M.has_unstaged_changes(callback)
  run_async("git diff --quiet", {}, function(ok)
    callback(not ok)
  end)
end

return M
