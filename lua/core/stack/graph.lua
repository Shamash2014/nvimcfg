local git = require("core.stack.git")
local config = require("core.stack.config")

local M = {}

local function get_pr_info(branch)
  local pr_num = git.pr_exists(branch)
  if pr_num then
    return "[PR #" .. pr_num .. "]"
  end
  return nil
end

local function build_tree(branch, depth, is_last, prefix_parts)
  local current = git.current_branch()
  local children = git.get_children(branch)
  local parent = git.get_parent(branch)
  local commits = {}

  if parent then
    commits = git.commits_between(parent, branch)
  end

  local lines = {}
  local branch_refs = {}

  local prefix = table.concat(prefix_parts, "")
  local connector = depth == 0 and "" or (is_last and "└── " or "├── ")
  local marker = branch == current and " <- HEAD" or ""
  local pr_info = get_pr_info(branch) or ""
  if pr_info ~= "" then pr_info = " " .. pr_info end

  local branch_line = prefix .. connector .. branch .. pr_info .. marker
  table.insert(lines, branch_line)
  table.insert(branch_refs, { line = #lines, branch = branch })

  local commit_prefix = prefix .. (depth == 0 and "" or (is_last and "    " or "│   "))
  for _, commit in ipairs(commits) do
    local commit_line = commit_prefix .. "│ " .. commit.hash .. " " .. commit.message
    table.insert(lines, commit_line)
  end

  if #commits > 0 then
    table.insert(lines, commit_prefix .. "│")
  end

  for i, child in ipairs(children) do
    local child_is_last = i == #children
    local new_prefix = vim.deepcopy(prefix_parts)
    if depth > 0 then
      table.insert(new_prefix, is_last and "    " or "│   ")
    end

    local offset = #lines
    local child_lines, child_refs = build_tree(child, depth + 1, child_is_last, new_prefix)
    for _, line in ipairs(child_lines) do
      table.insert(lines, line)
    end
    for _, ref in ipairs(child_refs) do
      ref.line = ref.line + offset
      table.insert(branch_refs, ref)
    end
  end

  return lines, branch_refs
end

function M.render()
  local current = git.current_branch()
  local trunk = config.get_trunk()
  local tree = config.get_full_stack_tree(current)

  local lines = {}
  local branch_refs = {}

  if trunk then
    table.insert(lines, trunk .. " (trunk)")
    table.insert(lines, "│")
  end

  if tree.branch then
    local tree_lines, tree_refs = build_tree(tree.branch, 0, true, {})
    for _, line in ipairs(tree_lines) do
      table.insert(lines, line)
    end
    for _, ref in ipairs(tree_refs) do
      ref.line = ref.line + (trunk and 2 or 0)
      table.insert(branch_refs, ref)
    end
  else
    local chain = config.get_stack_chain(current)
    if #chain == 0 then
      table.insert(lines, "")
      table.insert(lines, "(not in a stack)")
    else
      for i, branch in ipairs(chain) do
        local is_last = i == #chain
        local connector = is_last and "└── " or "├── "
        local marker = branch == current and " <- HEAD" or ""
        local pr_info = get_pr_info(branch) or ""
        if pr_info ~= "" then pr_info = " " .. pr_info end

        table.insert(lines, connector .. branch .. pr_info .. marker)
        table.insert(branch_refs, { line = #lines + (trunk and 2 or 0), branch = branch })
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "[u] up  [d] down  [Enter] checkout  [S] submit  [q] close")

  return lines, branch_refs
end

function M.show()
  local lines, branch_refs = M.render()
  local current = git.current_branch() or "(detached)"
  local trunk = config.get_trunk() or "main"

  local header = { "Stack: " .. current .. " (on " .. trunk .. ")", string.rep("═", 50), "" }
  for i = #header, 1, -1 do
    table.insert(lines, 1, header[i])
  end

  for _, ref in ipairs(branch_refs) do
    ref.line = ref.line + #header
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "stack-graph"

  local height = math.min(#lines + 1, math.floor(vim.o.lines / 3))
  vim.cmd("botright " .. height .. "split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winfixheight = true

  local stack = require("core.stack")

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function get_branch_at_cursor()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    for _, ref in ipairs(branch_refs) do
      if ref.line == cursor_line then
        return ref.branch
      end
    end
    return nil
  end

  vim.keymap.set("n", "q", close, { buffer = buf })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf })

  vim.keymap.set("n", "u", function()
    close()
    vim.schedule(stack.up)
  end, { buffer = buf })

  vim.keymap.set("n", "d", function()
    close()
    vim.schedule(stack.down)
  end, { buffer = buf })

  vim.keymap.set("n", "S", function()
    close()
    vim.schedule(stack.submit)
  end, { buffer = buf })

  vim.keymap.set("n", "<CR>", function()
    local branch = get_branch_at_cursor()
    if branch then
      close()
      vim.schedule(function()
        git.checkout(branch)
        vim.notify("Checked out: " .. branch, vim.log.levels.INFO, { title = "Stack" })
      end)
    end
  end, { buffer = buf })

  vim.keymap.set("n", "r", function()
    vim.bo[buf].modifiable = true
    local new_lines = M.render()
    local new_header = { "Stack: " .. (git.current_branch() or "(detached)") .. " (on " .. (config.get_trunk() or "main") .. ")", string.rep("═", 50), "" }
    for i = #new_header, 1, -1 do
      table.insert(new_lines, 1, new_header[i])
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
    vim.bo[buf].modifiable = false
  end, { buffer = buf })
end

return M
