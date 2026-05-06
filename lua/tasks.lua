local M = {}

-- ── helpers ────────────────────────────────────────────────────

local function find_up(start, names)
  local dir = start or vim.fn.getcwd()
  while dir and dir ~= "/" do
    for _, n in ipairs(names) do
      local p = dir .. "/" .. n
      if vim.fn.filereadable(p) == 1 then return p end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end
    dir = parent
  end
end

local function read_file(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

-- Build terminal environment with mise-managed tool versions.
-- Ensures task terminals inherit the same runtimes as the editor.
local function build_terminal_env()
  local env = vim.tbl_extend("keep", {
    ["PATH"]       = (vim.env.PATH or ""),
    ["SHELL"]      = vim.env.SHELL,
    ["EDITOR"]     = "nvim",
    ["VISUAL"]     = "nvim",
    ["LANG"]       = vim.env.LANG,
  }, {})

  -- mise-managed runtimes and SDKs
  local vars = {
    "NVM_DIR", "PYENV_ROOT", "CARGO_HOME", "RUSTUP_HOME",
    "GEM_HOME", "GOFLAGS", "GOPATH", "GOROOT", "NODE_MODULES_GLOBAL",
    "JAVA_HOME", "MIX_ENV",
  }
  for _, key in ipairs(vars) do
    if vim.env[key] then env[key] = vim.env[key] end
  end

  -- Custom dev vars (e.g. MISE_OVERRIDE_*)
  local dev_vars = os.getenv("DEV_VARS")
  if dev_vars and dev_vars ~= "" then
    for var in string.gmatch(dev_vars, "[^:]+") do
      env[var:gsub("^%s*", "")] = vim.env[var:gsub("^%s*", "")] or ""
    end
  end

  return env
end

local function attach_overlay(buf, win, task, extra, opts)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  opts = opts or {}
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn,
      { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("q", function()
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    elseif vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end, "Close task panel")
  map("r", function()
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    M.run(task, extra)
  end, "Rerun task")
  map("<C-c>", function()
    if opts.job_id then
      pcall(vim.fn.jobstop, opts.job_id)
    else
      local chan = vim.bo[buf].channel
      if chan and chan > 0 then
        pcall(vim.fn.chansend, chan,
          vim.api.nvim_replace_termcodes("<C-c>", true, false, true))
      end
    end
  end, "Send SIGINT")
end

local function open_term(task, extra)
  local cmd     = task.cmd(extra)
  local cmdline = table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.terminal then
    local term = snacks.terminal(cmdline, {
      cwd         = task.cwd,
      start_insert = false,
      win         = { position = "right" },
    })
    if term and term.buf then
      attach_overlay(term.buf, term.win, task, extra)
    end
    return
  end
  vim.cmd("botright 15new")
  vim.bo.bufhidden = "wipe"
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local job = vim.fn.jobstart(cmd, { cwd = task.cwd, term = true, env = build_terminal_env() })
  attach_overlay(buf, win, task, extra, { job_id = job })
end

-- ── providers ────────────────────────────────────────────────

local function provider_just(cb)
  local path = find_up(nil, { "justfile", "Justfile", ".justfile" })
  if not path then cb({}); return end
  local cwd = vim.fn.fnamemodify(path, ":h")
  local text = read_file(path) or ""
  local out, pending_doc = {}, nil
  for line in text:gmatch("([^\n]*)\n?") do
    if line:match("^%s*#") then
      pending_doc = line:gsub("^%s*#%s*", "")
    elseif line:match("^%s*$") then
      pending_doc = nil
    elseif not line:match("^%s") then
      if line:match("^%s*[%w_%-]+%s*:=") then
        pending_doc = nil
      else
        local name, params = line:match("^([%w_][%w_%-]*)([^:]*):")
        if name then
          local args = vim.trim(params or "")
          table.insert(out, {
            source = "just",
            name   = name,
            args   = args ~= "" and args or nil,
            doc    = pending_doc,
            cwd    = cwd,
            cmd    = function(extra)
              local c = { "just", name }
              for tok in (extra or ""):gmatch("%S+") do table.insert(c, tok) end
              return c
            end,
          })
          pending_doc = nil
        end
      end
    end
  end
  cb(out)
end

local function provider_npm(cb)
  local path = find_up(nil, { "package.json" })
  if not path then cb({}); return end
  local cwd  = vim.fn.fnamemodify(path, ":h")
  local text = read_file(path) or "{}"
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" or type(data.scripts) ~= "table" then cb({}); return end
  local runner = "npm"
  if vim.fn.filereadable(cwd .. "/bun.lockb") == 1 or vim.fn.filereadable(cwd .. "/bun.lock") == 1 then
    runner = "bun"
  elseif vim.fn.filereadable(cwd .. "/pnpm-lock.yaml") == 1 then
    runner = "pnpm"
  elseif vim.fn.filereadable(cwd .. "/yarn.lock") == 1 then
    runner = "yarn"
  end
  local out = {}
  for name, body in pairs(data.scripts) do
    table.insert(out, {
      source = runner,
      name   = name,
      doc    = type(body) == "string" and body or nil,
      cwd    = cwd,
      cmd    = function(extra)
        local c = { runner, "run", name }
        if extra and extra ~= "" then table.insert(c, "--"); for tok in extra:gmatch("%S+") do table.insert(c, tok) end end
        return c
      end,
    })
  end
  cb(out)
end

local function provider_make(cb)
  local path = find_up(nil, { "Makefile", "makefile", "GNUmakefile" })
  if not path then cb({}); return end
  local cwd = vim.fn.fnamemodify(path, ":h")
  local text = read_file(path) or ""
  local out, seen = {}, {}
  for line in text:gmatch("([^\n]*)\n?") do
    local target = line:match("^([%w_%-./]+)%s*:")
    if target and not target:match("^%.") and not seen[target] and not line:match("=") then
      seen[target] = true
      table.insert(out, {
        source = "make",
        name   = target,
        cwd    = cwd,
        cmd    = function(extra)
          local c = { "make", target }
          for tok in (extra or ""):gmatch("%S+") do table.insert(c, tok) end
          return c
        end,
      })
    end
  end
  cb(out)
end

local function provider_mix(cb)
  local path = find_up(nil, { "mix.exs" })
  if not path or vim.fn.executable("mix") == 0 then cb({}); return end
  local cwd = vim.fn.fnamemodify(path, ":h")
  local out = {}
  vim.fn.jobstart({ "mix", "help", "--names" }, {
    cwd = cwd,
    stdout_buffered = true,
    on_stdout = function(_, data) if data then vim.list_extend(out, data) end end,
    on_exit = function(_, code)
      if code ~= 0 then cb({}); return end
      local tasks = {}
      for _, line in ipairs(out) do
        local name = vim.trim(line)
        if name ~= "" and not name:match("^#") and name:match("^[%w_%-%.]+$") then
          table.insert(tasks, {
            source = "mix",
            name   = name,
            cwd    = cwd,
            cmd    = function(extra)
              local c = { "mix", name }
              for tok in (extra or ""):gmatch("%S+") do table.insert(c, tok) end
              return c
            end,
          })
        end
      end
      vim.schedule(function() cb(tasks) end)
    end,
  })
end

M.providers = { provider_just, provider_npm, provider_make, provider_mix }

function M.collect(on_done)
  local all = {}
  local pending = #M.providers
  if pending == 0 then on_done(all); return end
  for _, p in ipairs(M.providers) do
    p(function(tasks)
      for _, t in ipairs(tasks or {}) do table.insert(all, t) end
      pending = pending - 1
      if pending == 0 then
        table.sort(all, function(a, b)
          if a.source ~= b.source then return a.source < b.source end
          return a.name < b.name
        end)
        on_done(all)
      end
    end)
  end
end

function M.run(task, extra)
  open_term(task, extra)
end

function M.pick()
  M.collect(function(tasks)
    if #tasks == 0 then
      vim.notify("No tasks found (justfile / package.json / Makefile / mix.exs)",
        vim.log.levels.WARN, { title = "tasks" })
      return
    end

    local labels = {}
    for i, t in ipairs(tasks) do
      local args = t.args and ("  " .. t.args) or ""
      local doc  = t.doc and ("  — " .. t.doc) or ""
      labels[i] = string.format("[%-4s] %-24s%s%s", t.source, t.name, args, doc)
    end

    local function on_pick(idx)
      local t = tasks[idx]; if not t then return end
      if t.args then
        vim.ui.input({ prompt = t.source .. " " .. t.name .. " " .. t.args .. " → " }, function(extra)
          if extra == nil then return end
          M.run(t, extra)
        end)
      else
        M.run(t)
      end
    end

    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.select(labels, { prompt = "tasks" },
        function(_, idx) if idx then on_pick(idx) end end)
    else
      vim.ui.select(labels, { prompt = "tasks" },
        function(_, idx) if idx then on_pick(idx) end end)
    end
  end)
end

return M
