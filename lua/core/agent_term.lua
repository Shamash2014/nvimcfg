local M = {}

local registry = {}

local function default_agent()
  return vim.g.nvim3_agent_default or "claude"
end

local function resolve_cmd(name)
  local presets = vim.g.nvim3_agent_terms or { claude = "claude", opencode = "opencode", codex = "codex" }
  return presets[name] or name
end

local function git_root(path)
  path = path or vim.uv.cwd()
  local res =
    vim.system({ "git", "-C", path, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if res.code == 0 then return (res.stdout or ""):gsub("\n$", "") end
  return path
end

local function wt_info(cwd)
  local ok, wt = pcall(require, "core.wt")
  if not ok then return nil end
  return wt.info_for(cwd)
end

local function current_project()
  local info = wt_info()
  if info then return info.main_repo end
  return git_root()
end

local function gc()
  for buf in pairs(registry) do
    if not vim.api.nvim_buf_is_valid(buf) then
      registry[buf] = nil
    end
  end
end

function M.list()
  gc()
  local out = {}
  for buf, meta in pairs(registry) do
    table.insert(out, vim.tbl_extend("force", { bufnr = buf }, meta))
  end
  return out
end

function M.count_current_project()
  gc()
  local here = current_project()
  local n, wt = 0, 0
  for _, meta in pairs(registry) do
    if meta.project == here then
      n = n + 1
      if meta.is_worktree then wt = wt + 1 end
    end
  end
  return n, wt
end

local function focus(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
      vim.cmd("startinsert")
      return
    end
  end
  vim.cmd("botright vsplit")
  vim.api.nvim_win_set_buf(0, buf)
  vim.cmd("startinsert")
end

function M.spawn(name)
  name = name or default_agent()
  local cmd = resolve_cmd(name)
  local cwd = vim.uv.cwd()
  local info = wt_info(cwd)
  local project = info and info.main_repo or git_root(cwd)
  local branch = info and info.branch or nil
  local is_worktree = info and info.is_secondary or false

  vim.cmd("botright vsplit")
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()

  local job = vim.fn.jobstart(cmd, {
    term = true,
    cwd = cwd,
    on_exit = function()
      vim.schedule(function() registry[buf] = nil end)
    end,
  })

  if job <= 0 then
    vim.notify("agent: failed to start " .. cmd, vim.log.levels.ERROR)
    return
  end

  registry[buf] = {
    name = name,
    cmd = cmd,
    cwd = cwd,
    project = project,
    branch = branch,
    is_worktree = is_worktree,
    started_at = os.time(),
    job = job,
  }
  local tag = is_worktree and ("wt-" .. (branch or "?")) or (branch or vim.fs.basename(project))
  pcall(vim.api.nvim_buf_set_name, buf, string.format("agent://%s/%s/%s", name, vim.fs.basename(project), tag))
  vim.bo[buf].buflisted = true
  vim.b[buf].agent_term = name

  vim.keymap.set("t", "<C-q>", [[<C-\><C-n>]], { buffer = buf, silent = true })
  vim.keymap.set("n", "q", "<cmd>hide<cr>", { buffer = buf, silent = true })

  vim.cmd("startinsert")
  return buf
end

function M.spawn_pick()
  local presets = vim.g.nvim3_agent_terms or { claude = "claude", opencode = "opencode", codex = "codex" }
  local names = {}
  for name in pairs(presets) do table.insert(names, name) end
  table.sort(names)
  if #names == 0 then
    vim.notify("agent: no presets in vim.g.nvim3_agent_terms", vim.log.levels.WARN)
    return
  end
  if #names == 1 then
    M.spawn(names[1])
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if not (ok and snacks and snacks.picker and snacks.picker.pick) then
    vim.ui.select(names, {
      prompt = "Agent",
      format_item = function(n) return string.format("%-10s  %s", n, presets[n]) end,
    }, function(choice) if choice then M.spawn(choice) end end)
    return
  end

  local items = {}
  for _, n in ipairs(names) do
    table.insert(items, {
      text = n .. " " .. presets[n],
      data = n,
    })
  end
  snacks.picker.pick({
    source = "agents_spawn",
    title = "Spawn agent",
    items = items,
    format = function(item)
      return {
        { string.format("%-10s ", item.data), "Function" },
        { presets[item.data] or "", "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.data then vim.schedule(function() M.spawn(item.data) end) end
    end,
  })
end

function M.smart_open()
  local here = current_project()
  for buf, meta in pairs(registry) do
    if meta.project == here and vim.api.nvim_buf_is_valid(buf) then
      focus(buf)
      return
    end
  end
  M.spawn()
end

function M.pick()
  local list = M.list()
  if #list == 0 then
    vim.notify("no agents running", vim.log.levels.WARN)
    return
  end
  local here = current_project()
  table.sort(list, function(a, b)
    if (a.project == here) ~= (b.project == here) then
      return a.project == here
    end
    return a.started_at > b.started_at
  end)

  local ok, snacks = pcall(require, "snacks")
  if not (ok and snacks and snacks.picker and snacks.picker.pick) then
    vim.ui.select(list, {
      prompt = "Agents",
      format_item = function(e)
        local mark = e.project == here and "*" or " "
        local wt = e.is_worktree and "wt" or "  "
        return string.format(
          "%s %s %-8s  %-15s  %-20s  %s",
          mark, wt, e.name, e.branch or "?",
          vim.fs.basename(e.project), os.date("%H:%M", e.started_at)
        )
      end,
    }, function(choice)
      if choice then focus(choice.bufnr) end
    end)
    return
  end

  local items = {}
  for _, e in ipairs(list) do
    local mark = e.project == here and "*" or " "
    local wt = e.is_worktree and "wt" or "  "
    table.insert(items, {
      text = string.format(
        "%s %s %s %s %s %s",
        mark, wt, e.name, e.branch or "?",
        vim.fs.basename(e.project), os.date("%H:%M", e.started_at)
      ),
      data = e,
      bufnr = e.bufnr,
    })
  end

  snacks.picker.pick({
    source = "agents",
    title = "Agents",
    items = items,
    format = function(item)
      local e = item.data
      local mark = e.project == here and "*" or " "
      local wt = e.is_worktree and "wt" or "  "
      return {
        { mark .. " ", "Comment" },
        { wt .. " ", "DiagnosticHint" },
        { string.format("%-8s ", e.name), "Function" },
        { string.format("%-18s ", e.branch or "?"), "Identifier" },
        { string.format("%-18s ", vim.fs.basename(e.project)), "Directory" },
        { os.date("%H:%M", e.started_at), "Comment" },
      }
    end,
    preview = function(ctx)
      local buf = ctx.item and ctx.item.bufnr
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        ctx.preview:set_lines({ "(buffer gone)" })
        return
      end
      local lines = vim.api.nvim_buf_get_lines(buf, math.max(-200, -vim.api.nvim_buf_line_count(buf)), -1, false)
      ctx.preview:set_lines(lines)
      ctx.preview:highlight({ ft = "log" })
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.bufnr then focus(item.bufnr) end
    end,
  })
end

function M.list_qf()
  local list = M.list()
  if #list == 0 then
    vim.notify("no agents running", vim.log.levels.WARN)
    return
  end
  table.sort(list, function(a, b)
    if a.project ~= b.project then return a.project < b.project end
    if a.is_worktree ~= b.is_worktree then return not a.is_worktree end
    if (a.branch or "") ~= (b.branch or "") then return (a.branch or "") < (b.branch or "") end
    return a.started_at > b.started_at
  end)
  local items, last_project = {}, nil
  local wt_count = 0
  for _, e in ipairs(list) do
    if e.project ~= last_project then
      table.insert(items, {
        text = "── " .. vim.fs.basename(e.project) .. " ──",
        valid = 0,
      })
      last_project = e.project
    end
    local marker = e.is_worktree and "wt " or "   "
    if e.is_worktree then wt_count = wt_count + 1 end
    table.insert(items, {
      bufnr = e.bufnr,
      lnum = 1,
      col = 1,
      text = string.format(
        "  %s%-8s  %-20s  %s",
        marker,
        e.name,
        e.branch or "?",
        os.date("%H:%M", e.started_at)
      ),
    })
  end
  vim.fn.setqflist({}, " ", {
    title = string.format("Agents (%d, wt:%d)", #list, wt_count),
    items = items,
  })
  vim.cmd("botright copen")
end

local function pick_target(cb)
  local list = M.list()
  if #list == 0 then
    vim.notify("no agents; <leader>aa to spawn", vim.log.levels.WARN)
    return
  end
  local here = current_project()
  local in_project = {}
  for _, e in ipairs(list) do
    if e.project == here then table.insert(in_project, e) end
  end
  if #in_project >= 1 then
    table.sort(in_project, function(a, b) return a.started_at > b.started_at end)
    return cb(in_project[1])
  end
  vim.ui.select(list, {
    prompt = "Send to agent",
    format_item = function(e)
      return string.format("%-8s  %s", e.name, vim.fs.basename(e.project))
    end,
  }, function(choice)
    if choice then cb(choice) end
  end)
end

local function send_paste(target, text)
  local meta = registry[target.bufnr]
  if not meta then return end
  vim.fn.chansend(meta.job, "\27[200~" .. text .. "\27[201~")
  focus(target.bufnr)
end

local function send_raw(target, text)
  local meta = registry[target.bufnr]
  if not meta then return end
  vim.fn.chansend(meta.job, text)
  focus(target.bufnr)
end

local function visual_text()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    vim.cmd('normal! "vy')
  end
  local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  if s[2] == 0 or e[2] == 0 then return nil end
  local lines = vim.api.nvim_buf_get_lines(0, s[2] - 1, e[2], false)
  return table.concat(lines, "\n")
end

function M.send_selection()
  local text = visual_text()
  if not text or text == "" then
    vim.notify("no selection", vim.log.levels.WARN)
    return
  end
  pick_target(function(t) send_paste(t, text) end)
end

function M.send_file()
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("no file in current buffer", vim.log.levels.WARN)
    return
  end
  pick_target(function(t)
    local rel = vim.fs.relpath(t.project, path) or path
    send_raw(t, "@" .. rel .. " ")
  end)
end

function M.send_diff(scope)
  pick_target(function(t)
    local args = { "git", "-C", t.project, "diff" }
    if scope == "staged" then table.insert(args, "--cached") end
    local res = vim.system(args, { text = true }):wait()
    if res.code ~= 0 or (res.stdout or "") == "" then
      vim.notify("no diff to send", vim.log.levels.WARN)
      return
    end
    send_paste(t, res.stdout)
  end)
end

function M.send_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if #lines == 0 then return end
  pick_target(function(t) send_paste(t, table.concat(lines, "\n")) end)
end

function M.send_to_target(text)
  if not text or text == "" then return end
  pick_target(function(t) send_paste(t, text) end)
end

function M.send_neogit_selection()
  local ctx, err = require("core.neogit_ctx").collect()
  if not ctx then
    vim.notify(err or "no Neogit context", vim.log.levels.WARN)
    return
  end
  local prompt = require("core.neogit_ctx").review_prompt(ctx)
  pick_target(function(t) send_paste(t, prompt) end)
end

function M.shutdown_all()
  for buf, meta in pairs(registry) do
    pcall(vim.fn.jobstop, meta.job)
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  registry = {}
end

function M.setup()
  vim.api.nvim_create_user_command("Agent", function(opts)
    M.spawn(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Spawn agent in current project" })

  vim.api.nvim_create_user_command("Agents", function() M.pick() end, {})
  vim.api.nvim_create_user_command("AgentList", function() M.list_qf() end, {})

  vim.keymap.set("n", "<leader>aa", function() M.spawn_pick() end,
    { desc = "Agent: pick agent and spawn" })
  vim.keymap.set("n", "<leader>aA", function() M.spawn() end,
    { desc = "Agent: spawn default at cwd" })

  vim.keymap.set("n", "<leader>oc", function()
    require("core.task_picker").pick()
  end, { desc = "Tasks: pick npm/just task" })
  vim.keymap.set("n", "<leader>ap", function() M.pick() end,
    { desc = "Agent: pick across projects" })
  vim.keymap.set("n", "<leader>al", function() M.list_qf() end,
    { desc = "Agent: qflist grouped by project" })

  vim.keymap.set("x", "<leader>av", function() M.send_selection() end,
    { desc = "Agent: send visual selection" })
  vim.keymap.set("n", "<leader>af", function() M.send_file() end,
    { desc = "Agent: send @file reference" })
  vim.keymap.set("n", "<leader>ad", function() M.send_diff() end,
    { desc = "Agent: send git diff (unstaged)" })
  vim.keymap.set("n", "<leader>aD", function() M.send_diff("staged") end,
    { desc = "Agent: send git diff (staged)" })
  vim.keymap.set("n", "<leader>ab", function() M.send_buffer() end,
    { desc = "Agent: send whole buffer" })

  vim.api.nvim_create_user_command("AgentSend", function(opts)
    if opts.range > 0 then M.send_selection() else M.send_buffer() end
  end, { range = true, desc = "Send selection or buffer to agent" })

  local grp = vim.api.nvim_create_augroup("nvim3_agent_term_neogit", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = grp,
    pattern = { "NeogitStatus", "NeogitPopup", "NeogitCommitView", "NeogitCommitMessage" },
    callback = function(args)
      vim.keymap.set({ "n", "x" }, "a", function()
        require("core.agent_term").send_neogit_selection()
      end, { buffer = args.buf, silent = true, desc = "Send Neogit diff to agent" })
    end,
  })
end

return M
