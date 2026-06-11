local M = {}

local registry = {}

local function default_agent()
  return vim.g.nvim3_agent_default or "claude"
end

local function default_presets()
  return {
    claude = "claude",
    opencode = "opencode",
    codex = "codex",
    pi = "pi",
    hermes = "hermes",
    ["omlx-opencode"] = {
      "/Applications/oMLX.app/Contents/MacOS/omlx-cli",
      "launch",
      "opencode",
    },
    ["omlx-pi"] = {
      "/Applications/oMLX.app/Contents/MacOS/omlx-cli",
      "launch",
      "pi",
    },
  }
end

local function presets()
  return vim.g.nvim3_agent_terms or default_presets()
end

local function normalize_spec(spec)
  if type(spec) == "table" and type(spec.cmd) == "table" then
    return {
      cmd = spec.cmd,
      display = spec.display or table.concat(spec.cmd, " "),
      resume = spec.resume,
    }
  end
  if type(spec) == "table" and type(spec.cmd) == "string" then
    return {
      cmd = spec.cmd,
      display = spec.display or spec.cmd,
      resume = spec.resume,
    }
  end
  if type(spec) == "table" then
    return {
      cmd = spec,
      display = table.concat(spec, " "),
    }
  end
  return {
    cmd = spec,
    display = tostring(spec),
  }
end

local function resolve_spec(name)
  local spec = presets()[name] or name
  return normalize_spec(spec)
end

-- resume args per agent; override per-preset with spec.resume (table or false)
local RESUME_ARGS = {
  claude = { "--resume" },
  codex = { "resume" },
  opencode = { "--continue" },
}

local function resume_args(name, kind, spec)
  if spec and spec.resume ~= nil then
    if spec.resume == false then return nil end
    if type(spec.resume) == "string" then return { spec.resume } end
    return spec.resume
  end
  return RESUME_ARGS[name] or (kind and RESUME_ARGS[kind]) or nil
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

local function expand_path(p, base)
  if not p or p == "" then return nil end
  local out = vim.fn.expand(vim.trim(p))
  if out == "" then return nil end
  if out:sub(1, 1) ~= "/" then
    out = vim.fs.normalize((base or vim.uv.cwd()) .. "/" .. out)
  end
  return out
end

local function read_marker(path)
  local st = vim.uv.fs_stat(path)
  if not (st and st.type == "file") then return nil, nil end
  local lines = vim.fn.readfile(path)
  if not lines or not lines[1] then return nil, nil end
  return lines[1], vim.fs.dirname(path)
end

local AGENT_ENV = {
  claude = {
    var = "CLAUDE_CONFIG_DIR", marker = ".claude-config-dir",
    home = "~/.claude",
    share = { "skills", "agents", "commands", "plugins", "hooks", "output-styles", "statusline-cache" },
  },
  codex = {
    var = "CODEX_HOME", marker = ".codex-home",
    home = "~/.codex",
    share = { "agents", "prompts" },
  },
  hermes = {
    var = "HERMES_HOME", marker = ".hermes-home",
    home = "~/.hermes",
    share = { "skills", "plugins", "bundles", "toolsets" },
  },
}

local function bootstrap_share(kind, dir)
  local spec = AGENT_ENV[kind]
  if not (spec and spec.share and dir) then return end
  local src_home = expand_path(spec.home)
  if not src_home then return end
  vim.fn.mkdir(dir, "p")
  for _, sub in ipairs(spec.share) do
    local link = dir .. "/" .. sub
    if not vim.uv.fs_lstat(link) then
      local src = src_home .. "/" .. sub
      if vim.uv.fs_stat(src) then
        pcall(vim.uv.fs_symlink, src, link, { dir = true })
      end
    end
  end
end

local function agent_kind(name, cmd)
  if AGENT_ENV[name] then return name end
  local exe = type(cmd) == "table" and cmd[1] or cmd
  local base = vim.fs.basename(tostring(exe or ""))
  if AGENT_ENV[base] then return base end
  return nil
end

local function agents_conf_root()
  return expand_path(vim.g.nvim3_agents_conf_root or "~/.agents-conf")
end

function M.resolve_agent_dir(kind, cwd, project)
  local spec = AGENT_ENV[kind]
  if not spec then return nil end
  cwd = cwd or vim.uv.cwd()
  project = project or git_root(cwd)
  local info = wt_info(cwd)
  local repo_home = (info and info.main_repo) or project
  local is_wt = info and info.is_secondary or false
  local search = is_wt and { repo_home .. "/" .. spec.marker }
                  or { cwd .. "/" .. spec.marker, repo_home .. "/" .. spec.marker }
  for _, p in ipairs(search) do
    local content, base = read_marker(p)
    local v = expand_path(content, base)
    if v then return v end
  end
  local all = vim.g.nvim3_agent_dirs or {}
  local m = all[kind] or {}
  local key = is_wt and repo_home or (m[cwd] and cwd or repo_home)
  local v = expand_path(m[key])
  if v then return v end
  if kind == "claude" then
    local legacy = vim.g.nvim3_claude_config_dirs or {}
    v = expand_path(legacy[is_wt and repo_home or (legacy[cwd] and cwd or repo_home)])
    if v then return v end
  end
  if vim.g.nvim3_agents_conf_root == false then return nil end
  local root = agents_conf_root()
  if root then
    local candidate = root .. "/" .. vim.fs.basename(repo_home) .. "/" .. kind
    bootstrap_share(kind, candidate)
    return candidate
  end
  return nil
end

function M.resolve_claude_config_dir(cwd, project)
  return M.resolve_agent_dir("claude", cwd, project)
end

function M.project_env(cwd, project)
  local env = {}
  for kind, spec in pairs(AGENT_ENV) do
    local dir = M.resolve_agent_dir(kind, cwd, project)
    if dir then env[spec.var] = dir end
  end
  if next(env) == nil then return nil end
  return env
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

function M.meta_for_buf(buf)
  gc()
  local meta = registry[buf]
  if not meta then return nil end
  return vim.tbl_extend("force", { bufnr = buf }, meta)
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

local function with_resume(cmd, args)
  if not (args and #args > 0) then return cmd end
  if type(cmd) == "table" then
    local out = vim.deepcopy(cmd)
    for _, a in ipairs(args) do table.insert(out, a) end
    return out
  end
  return cmd .. " " .. table.concat(args, " ")
end

function M.spawn(name, opts)
  opts = opts or {}
  name = name or default_agent()
  local spec = resolve_spec(name)
  local cmd = spec.cmd
  local cwd = opts.cwd or vim.uv.cwd()
  local info = wt_info(cwd)
  local project = info and info.main_repo or git_root(cwd)
  local branch = info and info.branch or nil
  local is_worktree = info and info.is_secondary or false

  vim.cmd("botright vsplit")
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()

  local kind = agent_kind(name, cmd)
  if opts.resume then cmd = with_resume(cmd, resume_args(name, kind, spec)) end
  local env_var, env_dir, env = nil, nil, nil
  if kind then
    env_var = AGENT_ENV[kind].var
    local override = opts.config_dir or opts.claude_config_dir
    env_dir = (override and expand_path(override)) or M.resolve_agent_dir(kind, cwd, project)
    if env_dir then env = { [env_var] = env_dir } end
  end

  local job = vim.fn.jobstart(cmd, {
    term = true,
    cwd = cwd,
    env = env,
    on_exit = function()
      vim.schedule(function() registry[buf] = nil end)
    end,
  })

  if job <= 0 then
    vim.notify("agent: failed to start " .. spec.display, vim.log.levels.ERROR)
    return
  end

  registry[buf] = {
    name = name,
    cmd = spec.display,
    cwd = cwd,
    project = project,
    branch = branch,
    is_worktree = is_worktree,
    started_at = os.time(),
    job = job,
    env_var = env_var,
    env_dir = env_dir,
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

function M.choose_location_and_spawn(name, opts)
  opts = opts or {}
  local ok, wt = pcall(require, "core.wt")
  if not ok then
    M.spawn(name, opts)
    return
  end
  local cwd = vim.uv.cwd()
  local cur = wt.info_for(cwd)
  local cur_path = cur and cur.path or cwd
  local choices = { { label = "here   " .. vim.fs.basename(cwd), kind = "cwd" } }
  for _, e in ipairs(wt.list()) do
    if e.path ~= cur_path and not e.bare then
      local b = e.branch or (e.detached and "detached" or "?")
      table.insert(choices, {
        label = "wt     " .. b .. "  (" .. vim.fs.basename(e.path) .. ")",
        kind = "path",
        path = e.path,
      })
    end
  end
  table.insert(choices, { label = "+ new worktree…", kind = "new" })
  if #choices == 1 then
    M.spawn(name, opts)
    return
  end
  vim.ui.select(choices, {
    prompt = "Run " .. name .. (opts.resume and " --resume" or "") .. " in:",
    format_item = function(c) return c.label end,
  }, function(c)
    if not c then return end
    if c.kind == "cwd" then
      M.spawn(name, opts)
    elseif c.kind == "path" then
      M.spawn(name, vim.tbl_extend("force", opts, { cwd = c.path }))
    elseif c.kind == "new" then
      vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
        if branch and branch ~= "" then
          wt.create_path(branch, function(p)
            M.spawn(name, vim.tbl_extend("force", opts, { cwd = p }))
          end)
        end
      end)
    end
  end)
end

function M.spawn_pick()
  local available = presets()
  local names = {}
  for name in pairs(available) do table.insert(names, name) end
  table.sort(names)
  if #names == 0 then
    vim.notify("agent: no presets in vim.g.nvim3_agent_terms", vim.log.levels.WARN)
    return
  end
  if #names == 1 then
    M.choose_location_and_spawn(names[1])
    return
  end

  local function supports_resume(n)
    local spec = resolve_spec(n)
    return resume_args(n, agent_kind(n, spec.cmd), spec) ~= nil
  end

  local ok, snacks = pcall(require, "snacks")
  if not (ok and snacks and snacks.picker and snacks.picker.pick) then
    vim.ui.select(names, {
      prompt = "Agent",
      format_item = function(n)
        return string.format("%-14s  %s", n, resolve_spec(n).display)
      end,
    }, function(choice) if choice then M.choose_location_and_spawn(choice) end end)
    return
  end

  local items = {}
  for _, n in ipairs(names) do
    table.insert(items, {
      text = n .. " " .. resolve_spec(n).display,
      data = n,
    })
  end
  local function go(picker, item, resume)
    picker:close()
    if item and item.data then
      vim.schedule(function() M.choose_location_and_spawn(item.data, { resume = resume }) end)
    end
  end
  snacks.picker.pick({
    source = "agents_spawn",
    title = "Spawn agent  (<c-r> resume)",
    items = items,
    format = function(item)
      local row = {
        { string.format("%-14s ", item.data), "Function" },
        { resolve_spec(item.data).display, "Comment" },
      }
      if supports_resume(item.data) then
        table.insert(row, { "  ⟳", "DiagnosticHint" })
      end
      return row
    end,
    confirm = function(picker, item) go(picker, item, false) end,
    actions = {
      spawn_resume = function(picker, item) go(picker, item, true) end,
    },
    win = {
      input = {
        keys = {
          ["<c-r>"] = { "spawn_resume", mode = { "n", "i" }, desc = "spawn with resume" },
        },
      },
    },
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
  end, { desc = "Tasks: pick project task" })
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

  vim.keymap.set("n", "<leader>au", function()
    require("core.findings").update_prompt()
  end, { desc = "Findings: update" })
  vim.keymap.set("n", "<leader>aq", function()
    require("core.findings").qf(true)
  end, { desc = "Findings: quickfix" })

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
