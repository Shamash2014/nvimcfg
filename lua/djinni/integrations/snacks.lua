local M = {}
local ui = require("djinni.integrations.snacks_ui")

local function win_id(value)
  if type(value) == "number" then return value end
  if type(value) == "table" then
    if type(value.win) == "number" then return value.win end
    if type(value.winid) == "number" then return value.winid end
  end
  return nil
end

local function normal_win(preferred)
  preferred = win_id(preferred)
  if preferred and vim.api.nvim_win_is_valid(preferred) then
    local ok, cfg = pcall(vim.api.nvim_win_get_config, preferred)
    if ok and cfg.relative == "" then return preferred end
  end
  local current = vim.api.nvim_get_current_win()
  local ok, cfg = pcall(vim.api.nvim_win_get_config, current)
  if ok and cfg.relative == "" then return current end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    if ok and cfg.relative == "" then return win end
  end
  return nil
end

local function bufwinid_in_tab(buf, tab)
  if not tab or not vim.api.nvim_tabpage_is_valid(tab) then return -1 end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
  return -1
end

local function after_picker(fn)
  vim.defer_fn(fn, 20)
end

local function close_picker(picker)
  if picker then pcall(function() picker:close() end) end
end

local function open_buf_in_vsplit(buf, source_win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local win = bufwinid_in_tab(buf, vim.api.nvim_get_current_tabpage())
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
    return
  end
  win = normal_win(source_win)
  if win then vim.api.nvim_set_current_win(win) end
  vim.cmd("rightbelow vsplit")
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
end

local function open_chat_in_vsplit(file_path, source_win)
  if not file_path or file_path == "" then return end
  local chat = require("djinni.nowork.chat")
  local existing = vim.fn.bufnr(file_path)
  if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
    open_buf_in_vsplit(existing, source_win)
    return
  end
  local win = normal_win(source_win)
  if win then vim.api.nvim_set_current_win(win) end
  vim.cmd("rightbelow vsplit")
  chat.open(file_path)
end

function M.pick_task(opts)
  opts = opts or {}
  local projects = require("djinni.integrations.projects")
  local index = require("djinni.store.index")

  local all = index.get_all()
  local items = {}
  for file_path, entry in pairs(all) do
    table.insert(items, {
      text = entry.title or vim.fn.fnamemodify(file_path, ":t:r"),
      project = entry.project or "",
      status = entry.status or "unknown",
      file_path = file_path,
    })
  end

  if opts.context then
    vim.ui.input({ prompt = "Task: " }, function(prompt)
      if not prompt or prompt == "" then return end
      local root = vim.fn.getcwd()
      require("djinni.nowork.chat").create(root, {
        prompt = prompt,
        context_file = opts.context,
      })
    end)
    return
  end

  local status_icons = {
    running = "~",
    done = "+",
    error = "x",
    pending = "o",
    unknown = "?",
  }

  local source_win = normal_win(vim.api.nvim_get_current_win())
  ui.picker({
    title = "Nowork Tasks",
    items = items,
    format = function(item)
      local icon = status_icons[item.status] or "?"
      return {
        { "[" .. icon .. "] ", "Comment" },
        { item.text .. "  ", "Normal" },
        { "(" .. item.project .. ")", "Comment" },
      }
    end,
    confirm = function(picker, item)
      close_picker(picker)
      if item and item.file_path then
        after_picker(function()
          pcall(open_chat_in_vsplit, item.file_path, source_win)
        end)
      end
    end,
  })
end

function M.pick_sessions()
  local panel = require("djinni.nowork.panel")
  local items = {}

  local sessions = panel._collect_sessions()
  for _, s in ipairs(sessions) do
    table.insert(items, {
      text = s.title .. " " .. s.project,
      buf = s.buf,
      kind = "chat",
      streaming = s.status == "running",
      session = s,
    })
  end

  local ok, terms = pcall(function() return require("snacks.terminal")._terms end)
  if ok and terms then
    for _, term in pairs(terms) do
      if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
        local cmd = type(term.cmd) == "table" and table.concat(term.cmd, " ") or tostring(term.cmd or "terminal")
        table.insert(items, {
          text = cmd,
          buf = term.buf,
          kind = "terminal",
          streaming = false,
        })
      end
    end
  end

  if #items == 0 then
    M.notify("No background sessions", vim.log.levels.INFO)
    return
  end

  local source_win = normal_win(vim.api.nvim_get_current_win())
  ui.picker({
    title = "Background Sessions",
    items = items,
    format = function(item)
      if item.session then
        local s = item.session
        local icon = s.status == "running" and "●" or s.status == "input" and "⚠" or "◆"
        local hl = s.status == "running" and "DiagnosticOk" or s.status == "input" and "DiagnosticWarn" or "Comment"
        local parts = {{ icon .. " ", hl }, { s.title }}
        if s.project ~= "" then table.insert(parts, { "  (" .. s.project .. ")", "Comment" }) end
        if s.cost ~= "" then table.insert(parts, { "  " .. s.cost, "String" }) end
        if s.context ~= "" then table.insert(parts, { "  " .. s.context, "Number" }) end
        return parts
      end
      return {{ "> ", "Comment" }, { item.text }}
    end,
    confirm = function(picker, item)
      close_picker(picker)
      if item and item.buf then
        after_picker(function()
          pcall(function()
            open_buf_in_vsplit(item.buf, source_win)
            if item.kind == "chat" then
              local root = require("djinni.nowork.chat").get_project_root(item.buf)
              if root and root ~= "" then
                vim.cmd("lcd " .. vim.fn.fnameescape(root))
              end
            end
          end)
        end)
      end
    end,
  })
end

function M.trim_bg_terminals()
  local ok, terms = pcall(function() return require("snacks.terminal")._terms end)
  if not ok or not terms then return end
  for _, term in pairs(terms) do
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      local wins = vim.fn.win_findbuf(term.buf)
      if #wins == 0 then
        pcall(vim.api.nvim_set_option_value, 'scrollback', 100, { buf = term.buf })
      end
    end
  end
end

function M.pick_project(callback)
  local picker = ui.get_picker()
  if not picker then return end
  picker.projects({
    title = "Add Project",
    confirm = function(p, item)
      p:close()
      if item and item.file then
        vim.schedule(function()
          callback(tostring(item.file))
        end)
      end
    end,
  })
end

function M.notify(msg, level)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.notifier then
    snacks.notifier.notify(msg, level)
  else
    vim.notify(msg, level)
  end
end

function M.notify_task_complete(task)
  M.notify(task.title .. " completed", vim.log.levels.INFO)
end

function M.notify_permission_needed(task)
  M.notify(task.title .. " needs approval", vim.log.levels.WARN)
end

function M.pick_worktree(prompt, callback)
  local wt = require("djinni.integrations.worktrunk")
  wt.list(function(entries, err)
    if not entries or #entries == 0 then
      M.notify(err or "No worktrees found", vim.log.levels.WARN)
      return
    end

    local items = {}
    for _, e in ipairs(entries) do
      table.insert(items, {
        text = e.raw,
        branch = e.branch,
        current = e.current,
        trunk = e.trunk,
      })
    end

    ui.picker({
      title = prompt or "Worktrees",
      items = items,
      format = function(item)
        return { { item.text } }
      end,
      layout = { preset = "vscode" },
      confirm = function(picker, item)
        picker:close()
        if item then
          callback(item)
        end
      end,
    })
  end)
end

function M.action_worktree_create()
  vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
    if not branch or branch == "" then return end
    local wt = require("djinni.integrations.worktrunk")
    wt.create(branch, function(ok, result)
      if ok then
        M.notify("Created worktree: " .. branch, vim.log.levels.INFO)
        wt.get_path(branch, function(path)
          if path then
            vim.cmd("cd " .. vim.fn.fnameescape(path))
          end
        end)
      else
        M.notify("Failed: " .. (result or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.action_worktree_list()
  M.pick_worktree("Worktrees", function(item)
    local wt = require("djinni.integrations.worktrunk")
    wt.get_path(item.branch, function(path)
      if path then
        vim.cmd("cd " .. vim.fn.fnameescape(path))
        M.notify("Switched to " .. item.branch, vim.log.levels.INFO)
      else
        M.notify("Could not find path for " .. item.branch, vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.action_worktree_remove()
  M.pick_worktree("Remove worktree", function(item)
    ui.select({ "remove", "remove --force" }, { prompt = "Remove worktree '" .. item.branch .. "':" }, function(choice)
      if not choice then return end
      local wt = require("djinni.integrations.worktrunk")
      local opts = { yes = true }
      if choice == "remove --force" then opts.force = true end
      wt.remove(item.branch, opts, function(ok, msg)
        if ok then
          M.notify("Removed worktree: " .. item.branch, vim.log.levels.INFO)
        else
          M.notify("Failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

function M.action_worktree_merge()
  M.pick_worktree("Merge worktree", function(item)
    vim.ui.input({ prompt = "Merge into (empty=default): " }, function(target)
      if target == nil then return end
      local wt = require("djinni.integrations.worktrunk")
      wt.get_path(item.branch, function(path)
        wt.merge({ target = target ~= "" and target or nil, cwd = path }, function(ok, msg)
          if ok then
            M.notify("Merged " .. item.branch .. " into " .. (target ~= "" and target or "default"), vim.log.levels.INFO)
          else
            M.notify("Merge failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end)
end

return M
