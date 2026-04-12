local M = {}

local commands = {
  {
    title = "Churn Hotspots (most-changed files, 1 year)",
    cmd = { "sh", "-c", 'git log --format=format: --name-only --since="1 year ago" | sort | uniq -c | sort -nr | head -20' },
  },
  {
    title = "Bus Factor (contributors by commits)",
    cmd = { "sh", "-c", "git shortlog -sn --no-merges" },
  },
  {
    title = "Bug Clusters (files with bug-related commits)",
    cmd = { "sh", "-c", [[git log -i -E --grep="fix|bug|broken" --name-only --format='' | sort | uniq -c | sort -nr | head -20]] },
  },
  {
    title = "Project Velocity (commits by month)",
    cmd = { "sh", "-c", "git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c" },
  },
  {
    title = "Firefighting (reverts/hotfixes, 1 year)",
    cmd = { "sh", "-c", [[git log --oneline --since="1 year ago" | grep -iE 'revert|hotfix|emergency|rollback']] },
  },
}

local function open_float(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "git-analysis"

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Git Analysis ",
    title_pos = "center",
  })

  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

function M.open()
  local check = vim.system({ "git", "rev-parse", "--is-inside-work-tree" }, { text = true }):wait()
  if check.code ~= 0 then
    vim.notify("Not a git repository", vim.log.levels.WARN)
    return
  end

  local results = {}
  local remaining = #commands

  for i, entry in ipairs(commands) do
    vim.system(entry.cmd, { text = true }, function(obj)
      results[i] = { title = entry.title, output = vim.trim(obj.stdout or "") }
      remaining = remaining - 1
      if remaining == 0 then
        vim.schedule(function()
          local lines = {}
          for _, r in ipairs(results) do
            table.insert(lines, "── " .. r.title .. " ──")
            table.insert(lines, "")
            if r.output == "" then
              table.insert(lines, "  (none)")
            else
              for line in r.output:gmatch("[^\n]+") do
                table.insert(lines, "  " .. line)
              end
            end
            table.insert(lines, "")
          end
          open_float(lines)
        end)
      end
    end)
  end
end

return M
