local git = require("core.stack.git")
local config = require("core.stack.config")

local M = {}

local function get_pr_info(branch, callback)
  git.pr_exists(branch, function(pr_num)
    if pr_num then
      callback("[PR #" .. pr_num .. "]")
    else
      callback(nil)
    end
  end)
end

local function build_tree(branch, depth, is_last, prefix_parts, callback)
  git.current_branch(function(current)
    git.get_children(branch, function(children)
      git.get_parent(branch, function(parent)
        local function with_commits(commits)
          local lines = {}
          local branch_refs = {}

          local prefix = table.concat(prefix_parts, "")
          local connector = depth == 0 and "" or (is_last and "└── " or "├── ")
          local marker = branch == current and " <- HEAD" or ""

          get_pr_info(branch, function(pr_info)
            pr_info = pr_info or ""
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

            if #children == 0 then
              callback(lines, branch_refs)
              return
            end

            local pending = #children
            local child_results = {}

            for i, child in ipairs(children) do
              local child_is_last = i == #children
              local new_prefix = vim.deepcopy(prefix_parts)
              if depth > 0 then
                table.insert(new_prefix, is_last and "    " or "│   ")
              end

              build_tree(child, depth + 1, child_is_last, new_prefix, function(child_lines, child_refs)
                child_results[i] = { lines = child_lines, refs = child_refs }
                pending = pending - 1

                if pending == 0 then
                  for j = 1, #children do
                    local offset = #lines
                    for _, line in ipairs(child_results[j].lines) do
                      table.insert(lines, line)
                    end
                    for _, ref in ipairs(child_results[j].refs) do
                      ref.line = ref.line + offset
                      table.insert(branch_refs, ref)
                    end
                  end
                  callback(lines, branch_refs)
                end
              end)
            end
          end)
        end

        if parent then
          git.commits_between(parent, branch, with_commits)
        else
          with_commits({})
        end
      end)
    end)
  end)
end

function M.render(callback)
  git.current_branch(function(current)
    config.get_trunk(function(trunk)
      config.get_full_stack_tree(current, function(tree)
        local lines = {}
        local branch_refs = {}

        if trunk then
          table.insert(lines, trunk .. " (trunk)")
          table.insert(lines, "│")
        end

        if tree.branch then
          build_tree(tree.branch, 0, true, {}, function(tree_lines, tree_refs)
            for _, line in ipairs(tree_lines) do
              table.insert(lines, line)
            end
            for _, ref in ipairs(tree_refs) do
              ref.line = ref.line + (trunk and 2 or 0)
              table.insert(branch_refs, ref)
            end

            table.insert(lines, "")
            table.insert(lines, string.rep("─", 50))
            table.insert(lines, "[u] up  [d] down  [Enter] checkout  [S] submit  [q] close")

            callback(lines, branch_refs)
          end)
        else
          config.get_stack_chain(current, function(chain)
            if #chain == 0 then
              table.insert(lines, "")
              table.insert(lines, "(not in a stack)")
            else
              local pending = #chain
              local chain_results = {}

              for i, branch in ipairs(chain) do
                get_pr_info(branch, function(pr_info)
                  chain_results[i] = { branch = branch, pr_info = pr_info }
                  pending = pending - 1

                  if pending == 0 then
                    for j, result in ipairs(chain_results) do
                      local is_last = j == #chain
                      local connector = is_last and "└── " or "├── "
                      local marker = result.branch == current and " <- HEAD" or ""
                      local info = result.pr_info or ""
                      if info ~= "" then info = " " .. info end

                      table.insert(lines, connector .. result.branch .. info .. marker)
                      table.insert(branch_refs, { line = #lines + (trunk and 2 or 0), branch = result.branch })
                    end

                    table.insert(lines, "")
                    table.insert(lines, string.rep("─", 50))
                    table.insert(lines, "[u] up  [d] down  [Enter] checkout  [S] submit  [q] close")

                    callback(lines, branch_refs)
                  end
                end)
              end
            end

            if #chain == 0 then
              table.insert(lines, "")
              table.insert(lines, string.rep("─", 50))
              table.insert(lines, "[u] up  [d] down  [Enter] checkout  [S] submit  [q] close")
              callback(lines, branch_refs)
            end
          end)
        end
      end)
    end)
  end)
end

function M.show()
  M.render(function(lines, branch_refs)
    git.current_branch(function(current)
      current = current or "(detached)"
      config.get_trunk(function(trunk)
        trunk = trunk or "main"

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
            git.checkout(branch, function(ok)
              if ok then
                vim.notify("Checked out: " .. branch, vim.log.levels.INFO, { title = "Stack" })
              end
            end)
          end
        end, { buffer = buf })

        vim.keymap.set("n", "r", function()
          M.render(function(new_lines, new_branch_refs)
            git.current_branch(function(new_current)
              config.get_trunk(function(new_trunk)
                new_current = new_current or "(detached)"
                new_trunk = new_trunk or "main"

                local new_header = { "Stack: " .. new_current .. " (on " .. new_trunk .. ")", string.rep("═", 50), "" }
                for i = #new_header, 1, -1 do
                  table.insert(new_lines, 1, new_header[i])
                end

                for _, ref in ipairs(new_branch_refs) do
                  ref.line = ref.line + #new_header
                end

                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
                vim.bo[buf].modifiable = false

                branch_refs = new_branch_refs
              end)
            end)
          end)
        end, { buffer = buf })
      end)
    end)
  end)
end

return M
