local M = {}

local function git_root()
  local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then return nil end
  return out[1]
end

local function list_worktrees()
  local out = vim.fn.systemlist({ "git", "worktree", "list", "--porcelain" })
  if vim.v.shell_error ~= 0 then return {} end
  local cur = vim.fn.getcwd()
  local entries, e = {}, nil
  local function flush()
    if e and e.path then table.insert(entries, e) end
    e = nil
  end
  for _, line in ipairs(out) do
    if line == "" then
      flush()
    else
      e = e or {}
      local k, v = line:match("^(%S+)%s*(.*)$")
      if k == "worktree" then
        e.path = v
        e.is_current = (v == cur)
      elseif k == "HEAD" then
        e.head = v
      elseif k == "branch" then
        e.branch = (v:gsub("^refs/heads/", ""))
      elseif line == "bare" then
        e.bare = true
      elseif line == "detached" then
        e.detached = true
      end
    end
  end
  flush()
  return entries
end

local function close_neogit()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].filetype == "NeogitStatus" then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

local function reopen_neogit()
  vim.schedule(function()
    pcall(function() require("neogit").open({ kind = "replace" }) end)
  end)
end

local function do_switch(branch, path, opts)
  opts = opts or {}
  local wt = require("config.wt")
  close_neogit()
  if branch and branch ~= "" then
    wt.switch_to(branch, {}, function(ok)
      if ok and opts.reopen then reopen_neogit() end
    end)
  elseif path and path ~= "" then
    vim.cmd("tcd " .. vim.fn.fnameescape(path))
    if opts.reopen then reopen_neogit() end
  end
end

function M.open(opts)
  opts = opts or {}
  local entries = list_worktrees()
  if #entries == 0 then
    vim.notify("No worktrees", vim.log.levels.WARN, { title = "worktrunk" })
    return
  end

  local items = {}
  for _, e in ipairs(entries) do
    local branch = e.branch or (e.detached and "(detached)" or "(bare)")
    local marker = e.is_current and "● " or "  "
    items[#items + 1] = {
      text     = marker .. branch .. "  " .. vim.fn.fnamemodify(e.path, ":~"),
      branch   = e.branch,
      path     = e.path,
      is_current = e.is_current,
    }
  end

  local sn = require("snacks")
  sn.picker.pick({
    source = "worktrees",
    title  = "worktrees",
    items  = items,
    format = function(item) return { { item.text } } end,
    confirm = function(picker, item)
      picker:close()
      if not item or item.is_current then return end
      do_switch(item.branch, item.path, { reopen = opts.reopen ~= false })
    end,
    actions = {
      create = function(picker)
        picker:close()
        vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
          if not branch or branch == "" then return end
          local wt = require("config.wt")
          close_neogit()
          wt.create(branch, { base = "@" }, function(ok)
            if ok and opts.reopen ~= false then reopen_neogit() end
          end)
        end)
      end,
      remove = function(picker, item)
        if not item or not item.branch or item.is_current then return end
        picker:close()
        require("config.wt").remove(item.branch, { yes = true }, function(ok, msg)
          vim.notify(ok and ("Removed " .. item.branch) or (msg or "remove failed"),
            ok and vim.log.levels.INFO or vim.log.levels.ERROR,
            { title = "worktrunk" })
        end)
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-n>"] = { "create", mode = { "i", "n" } },
          ["<C-x>"] = { "remove", mode = { "i", "n" } },
        },
      },
    },
  })
end

return M
