local M = {}

M._autocmd_registered = false
M._float_buf = nil
M._float_win = nil
M._git_cache = {}

local GIT_TTL = 3

local function git_info(cwd)
  if not cwd or cwd == "" then return nil end
  local now = os.time()
  local cached = M._git_cache[cwd]
  if cached and (now - cached.at) < GIT_TTL then return cached.info end

  local function run(args)
    local ok, obj = pcall(function()
      return vim.system({ "git", unpack(args) }, { cwd = cwd, text = true, timeout = 500 }):wait()
    end)
    if not ok or not obj or obj.code ~= 0 then return nil end
    return (obj.stdout or ""):gsub("%s+$", "")
  end

  local branch = run({ "rev-parse", "--abbrev-ref", "HEAD" })
  if not branch then return nil end

  local worktree = run({ "rev-parse", "--show-toplevel" })
  worktree = worktree and vim.fn.fnamemodify(worktree, ":t") or nil

  local numstat = run({ "diff", "--numstat" }) or ""
  local added, removed = 0, 0
  for line in numstat:gmatch("[^\n]+") do
    local a, r = line:match("^(%S+)%s+(%S+)")
    if a and a ~= "-" then added = added + (tonumber(a) or 0) end
    if r and r ~= "-" then removed = removed + (tonumber(r) or 0) end
  end

  local info = { branch = branch, worktree = worktree, added = added, removed = removed }
  M._git_cache[cwd] = { at = now, info = info }
  return info
end

local function format_tokens(n)
  if not n or n == 0 then return nil end
  if n < 1000 then return tostring(n) end
  if n < 1000000 then return string.format("%.1fk", n / 1000) end
  return string.format("%.1fM", n / 1000000)
end

local function format_cost(c)
  if not c or c == 0 then return nil end
  return string.format("$%.2f", c)
end

local function format_elapsed(seconds)
  if not seconds or seconds < 0 then return nil end
  if seconds < 60 then
    return seconds .. "s"
  end
  local m = math.floor(seconds / 60)
  local s = seconds % 60
  return m .. "m" .. s .. "s"
end

local function count_done(state)
  local topo = state and state.topo_order
  local tasks = state and state.tasks
  if not topo or not tasks then return 0, 0 end
  local done = 0
  for _, id in ipairs(topo) do
    local t = tasks[id]
    if t and t.status == "done" then
      done = done + 1
    end
  end
  return done, #topo
end

local function sprint_idx(state)
  if not state or not state.topo_order or not state.current_task_id then return nil end
  for i, id in ipairs(state.topo_order) do
    if id == state.current_task_id then return i end
  end
  return nil
end

local function format_tag(d)
  local mode = d.mode or "?"
  if mode == "autorun" then
    local state = d.state or {}
    local tag = "auto:" .. (state.phase or "?")
    if state.current_task_id then
      tag = tag .. "·" .. state.current_task_id
    end
    if state.phase == "generate" or state.phase == "evaluate" then
      local idx = sprint_idx(state)
      local total = state.topo_order and #state.topo_order or 0
      if idx and total > 0 then
        tag = tag .. " sprint " .. idx .. "/" .. total
      end
      local retries = state.sprint_retries and state.current_task_id and state.sprint_retries[state.current_task_id]
      if retries and retries > 0 then
        tag = tag .. " r" .. retries
      end
    end
    if state.turns_on_task and state.turns_on_task > 0 then
      tag = tag .. " T:" .. state.turns_on_task
    end
    local done, total = count_done(state)
    if total > 0 then
      tag = tag .. " " .. done .. "/" .. total
    end
    if state.pending_retry then
      tag = tag .. " R!"
    end
    return tag
  elseif mode == "explore" then
    local qfix = d.state and d.state.qfix_items
    if qfix and #qfix > 0 then
      return "explore " .. #qfix .. "loc"
    end
    return "explore"
  elseif mode == "routine" then
    local bits = { "routine" }
    local staged = d.state and d.state.staged_input
    if staged and staged ~= "" then
      bits[#bits + 1] = "+in"
    end
    local q = d.state and d.state.queue
    if q and #q > 0 then
      bits[#bits + 1] = "q:" .. #q
    end
    local perms = d.state and d.state.pending_permissions
    if perms and #perms > 0 then
      bits[#bits + 1] = "perm!" .. #perms
    end
    return table.concat(bits, " ")
  end
  local perms = d.state and d.state.pending_permissions
  if perms and #perms > 0 then
    return mode .. " perm!" .. #perms
  end
  return mode
end

local function build_lines()
  local droid_mod = require("djinni.nowork.droid")
  local entries = {}
  for _, d in pairs(droid_mod.active) do
    local finished = d.status == "done" or d.status == "cancelled" or d.status == "blocked"
    if not finished then
      entries[#entries + 1] = d
    end
  end
  if #entries == 0 then return nil end
  table.sort(entries, function(a, b) return a.id < b.id end)

  local now = os.time()
  local lines = {}
  for _, d in ipairs(entries) do
    local tag = format_tag(d)
    local status = d.status or "?"
    local elapsed = d.started_at and format_elapsed(now - d.started_at)
    local inner = elapsed and (status .. " " .. elapsed) or status
    local line = "[" .. d.id .. "] " .. tag .. " " .. inner
    local t = d.state and d.state.tokens
    if t then
      local bits = {}
      local i_str = format_tokens(t.input)
      local o_str = format_tokens(t.output)
      if i_str then bits[#bits + 1] = "↑" .. i_str end
      if o_str then bits[#bits + 1] = "↓" .. o_str end
      local cache = (t.cache_read or 0) + (t.cache_write or 0)
      local c_str = format_tokens(cache)
      if c_str then bits[#bits + 1] = "⊚" .. c_str end
      local cost = format_cost(t.cost)
      if cost then bits[#bits + 1] = cost end
      if #bits > 0 then line = line .. "  " .. table.concat(bits, " ") end
    end
    local g = git_info(d.opts and d.opts.cwd)
    if g then
      local git_bits = "  " .. g.branch
      if g.worktree and g.worktree ~= g.branch then
        git_bits = git_bits .. "@" .. g.worktree
      end
      if g.added > 0 or g.removed > 0 then
        git_bits = git_bits .. " +" .. g.added .. "/-" .. g.removed
      end
      line = line .. git_bits
    end
    lines[#lines + 1] = line
  end
  return lines
end

local function ensure_buf()
  if M._float_buf and vim.api.nvim_buf_is_valid(M._float_buf) then return end
  M._float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._float_buf].buftype = "nofile"
  vim.bo[M._float_buf].bufhidden = "hide"
  vim.bo[M._float_buf].swapfile = false
end

local function show_float(lines)
  ensure_buf()
  vim.api.nvim_buf_set_lines(M._float_buf, 0, -1, false, lines)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local height = #lines
  local col = math.max(0, vim.o.columns - width - 1)
  local cfg = {
    relative = "editor",
    row = 0,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    focusable = false,
    zindex = 50,
    noautocmd = true,
  }
  if M._float_win and vim.api.nvim_win_is_valid(M._float_win) then
    cfg.noautocmd = nil
    vim.api.nvim_win_set_config(M._float_win, cfg)
  else
    M._float_win = vim.api.nvim_open_win(M._float_buf, false, cfg)
    vim.wo[M._float_win].winhighlight = "Normal:Comment,NormalFloat:Comment"
    vim.wo[M._float_win].winblend = 0
  end
end

local function hide_float()
  if M._float_win and vim.api.nvim_win_is_valid(M._float_win) then
    pcall(vim.api.nvim_win_close, M._float_win, true)
  end
  M._float_win = nil
end

local function ensure_autocmds()
  if M._autocmd_registered then return end
  M._autocmd_registered = true
  local group = vim.api.nvim_create_augroup("NoworkStatusPanel", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "TabEnter", "BufWritePost" }, {
    group = group,
    callback = function() M.update() end,
  })
end

function M.hide()
  hide_float()
end

function M.update()
  ensure_autocmds()
  local lines = build_lines()
  if not lines then
    hide_float()
    return
  end
  show_float(lines)
end

return M
