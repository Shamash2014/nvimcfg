local Job = require("plenary.job")
local git = require("core.stack.git")

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

function M.get_trunk(callback)
  run_async("git config --get stack.trunk", { trim = true }, function(ok, trunk)
    if ok and trunk and trunk ~= "" then
      callback(trunk)
      return
    end

    git.branch_exists("main", function(main_exists)
      if main_exists then
        callback("main")
        return
      end

      git.branch_exists("master", function(master_exists)
        if master_exists then
          callback("master")
        else
          callback(nil)
        end
      end)
    end)
  end)
end

function M.is_stack_branch(branch, callback)
  git.get_parent(branch, function(parent)
    callback(parent ~= nil)
  end)
end

function M.get_stack_root(branch, callback)
  local function resolve_branch(cb)
    if branch then
      cb(branch)
    else
      git.current_branch(cb)
    end
  end

  resolve_branch(function(current)
    if not current then
      callback(nil)
      return
    end

    M.get_trunk(function(trunk)
      local visited = {}

      local function find_root(node)
        if not node or visited[node] then
          callback(nil)
          return
        end

        visited[node] = true

        if node == trunk then
          callback(nil)
          return
        end

        git.get_parent(node, function(parent)
          if not parent or parent == trunk then
            callback(node)
          else
            find_root(parent)
          end
        end)
      end

      find_root(current)
    end)
  end)
end

function M.get_stack_chain(branch, callback)
  local function resolve_branch(cb)
    if branch then
      cb(branch)
    else
      git.current_branch(cb)
    end
  end

  resolve_branch(function(current)
    if not current then
      callback({})
      return
    end

    M.get_trunk(function(trunk)
      local chain = {}
      local visited = {}

      local function build_chain(node)
        if not node or visited[node] or node == trunk then
          callback(chain)
          return
        end

        visited[node] = true
        table.insert(chain, 1, node)

        git.get_parent(node, function(parent)
          build_chain(parent)
        end)
      end

      build_chain(current)
    end)
  end)
end

function M.get_full_stack_tree(branch, callback)
  local function resolve_branch(cb)
    if branch then
      cb(branch)
    else
      git.current_branch(cb)
    end
  end

  resolve_branch(function(current)
    if not current then
      callback({})
      return
    end

    M.get_stack_root(current, function(root)
      if not root then
        M.is_stack_branch(current, function(is_stack)
          if is_stack then
            root = current
          else
            callback({})
            return
          end
        end)
      end

      local function build_tree(node, cb)
        git.get_children(node, function(children)
          local tree = {
            branch = node,
            children = {},
          }

          if #children == 0 then
            cb(tree)
            return
          end

          local pending = #children
          for i, child in ipairs(children) do
            build_tree(child, function(child_tree)
              tree.children[i] = child_tree
              pending = pending - 1
              if pending == 0 then
                cb(tree)
              end
            end)
          end
        end)
      end

      build_tree(root, callback)
    end)
  end)
end

function M.validate_git_version(callback)
  run_async("git --version", { trim = true }, function(ok, version_line)
    if not ok then
      callback(false, "git not found")
      return
    end

    local version_str = version_line:match("git version (%d+%.%d+)")
    if not version_str then
      callback(false, "Could not parse git version")
      return
    end

    local major, minor = version_str:match("(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)

    if major < 2 or (major == 2 and minor < 38) then
      callback(false, "Git 2.38+ required for --update-refs")
      return
    end

    callback(true)
  end)
end

return M
