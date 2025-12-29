local git = require("core.stack.git")

local M = {}

function M.get_trunk()
  local ok, trunk = pcall(function()
    local result = vim.fn.systemlist("git config --get stack.trunk")
    if vim.v.shell_error == 0 and result[1] and result[1] ~= "" then
      return result[1]
    end
    return nil
  end)

  if ok and trunk then
    return trunk
  end

  if git.branch_exists("main") then
    return "main"
  end

  if git.branch_exists("master") then
    return "master"
  end

  return nil
end

function M.is_stack_branch(branch)
  return git.get_parent(branch) ~= nil
end

function M.get_stack_root(branch)
  branch = branch or git.current_branch()
  if not branch then return nil end

  local trunk = M.get_trunk()
  local visited = {}
  local current = branch

  while current and not visited[current] do
    visited[current] = true

    if current == trunk then
      return nil
    end

    local parent = git.get_parent(current)
    if not parent or parent == trunk then
      return current
    end

    current = parent
  end

  return nil
end

function M.get_stack_chain(branch)
  branch = branch or git.current_branch()
  if not branch then return {} end

  local trunk = M.get_trunk()
  local chain = {}
  local visited = {}
  local current = branch

  while current and not visited[current] and current ~= trunk do
    visited[current] = true
    table.insert(chain, 1, current)
    current = git.get_parent(current)
  end

  return chain
end

function M.get_full_stack_tree(branch)
  branch = branch or git.current_branch()
  if not branch then return {} end

  local root = M.get_stack_root(branch)
  if not root then
    if M.is_stack_branch(branch) then
      root = branch
    else
      return {}
    end
  end

  local function build_tree(node)
    local children = git.get_children(node)
    local tree = {
      branch = node,
      children = {},
    }
    for _, child in ipairs(children) do
      table.insert(tree.children, build_tree(child))
    end
    return tree
  end

  return build_tree(root)
end

function M.validate_git_version()
  local result = vim.fn.systemlist("git --version")
  if vim.v.shell_error ~= 0 then
    return false, "git not found"
  end

  local version_str = result[1]:match("git version (%d+%.%d+)")
  if not version_str then
    return false, "Could not parse git version"
  end

  local major, minor = version_str:match("(%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)

  if major < 2 or (major == 2 and minor < 38) then
    return false, "Git 2.38+ required for --update-refs"
  end

  return true
end

return M
