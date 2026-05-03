local M = {}
local NS = vim.api.nvim_create_namespace("acp_pipe")

local _runs = {}
local _state = { buf=nil, win=nil, on_winbar=nil, cwd=nil }

local function km(buf, lhs, fn, desc)
  vim.keymap.set("n", lhs, fn,
    {buffer=buf, nowait=true, noremap=true, silent=true, desc=desc})
end

local function status_hl_icon(conclusion, status)
  if status == "in_progress" then return "AcpPipeRunning", "⟳ " end
  if status == "queued"       then return "AcpPipePend",    "· " end
  if conclusion == "success"  then return "AcpPipeOk",      "✓ " end
  if conclusion == "failure"  then return "AcpPipeFail",    "✗ " end
  return "Comment", "· "
end

function M._render(buf)
  local ls, hls = {}, {}
  local function add(s, hl)
    local row = #ls; table.insert(ls, s or "")
    if hl then table.insert(hls, {row, hl}) end
  end
  add("  Pipeline", "AcpSection"); add("")
  if #_runs == 0 then
    add("  No recent runs.", "Comment")
  else
    for _, run in ipairs(_runs) do
      local hl, icon = status_hl_icon(run.conclusion, run.status)
      add("  " .. icon .. (run.displayTitle or "?"):sub(1,55)
          .. "  [" .. tostring(run.databaseId or "") .. "]", hl)
    end
  end
  add(""); add("  l=log  r=retry  R=refresh  q=close", "AcpFooter")
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, ls)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, NS, h[1], 0, {line_hl_group = h[2]})
  end
  vim.b[buf].acp_pipe_runs = _runs
end

local function run_at_cursor(buf)
  local line = vim.api.nvim_buf_get_lines(buf,
    vim.api.nvim_win_get_cursor(0)[1]-1,
    vim.api.nvim_win_get_cursor(0)[1], false)[1] or ""
  local id = line:match("%[(%d+)%]")
  if not id then return nil end
  for _, r in ipairs(_runs) do
    if tostring(r.databaseId) == id then return r end
  end
end

function M._install_keymaps(buf)
  km(buf, "l", function()
    local run = run_at_cursor(buf)
    if not run then return end
    local id = tostring(run.databaseId)
    if _state.on_winbar then _state.on_winbar("log " .. id .. " ⟳") end
    vim.fn.jobstart({"gh","run","view",id,"--log"}, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        vim.schedule(function()
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false,
            {"# " .. (run.displayTitle or id), ""})
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
          vim.bo[buf].modifiable = false
          if _state.on_winbar then _state.on_winbar("log " .. id) end
        end)
      end,
    })
  end, "View log")

  km(buf, "r", function()
    local run = run_at_cursor(buf)
    if not run then return end
    local id = tostring(run.databaseId)
    vim.fn.jobstart({"gh","run","rerun",id}, {
      on_exit = function(_, code)
        vim.schedule(function()
          local lvl = code==0 and vim.log.levels.INFO or vim.log.levels.WARN
          vim.notify(code==0 and "Retried "..id or "Retry failed", lvl, {title="acp"})
          M.open(_state.cwd, _state.win, buf, _state.on_winbar)
        end)
      end,
    })
  end, "Retry")

  km(buf, "R", function()
    M.open(_state.cwd, _state.win, buf, _state.on_winbar)
  end, "Refresh")

  km(buf, "q", function()
    require("acp.workbench").render()
  end, "Close")
end

local _uv          = vim.uv or vim.loop
local _runs_cache  = {}     -- [cwd] = { runs = {}, ts = 0 }
local _refreshing  = {}     -- [cwd] = true while in-flight
local RUNS_TTL_MS  = 30000

local function async_refresh_runs(cwd, limit, on_done)
  if _refreshing[cwd] then return end
  _refreshing[cwd] = true
  local out = {}
  vim.fn.jobstart({
    "gh", "run", "list",
    "--json", "databaseId,displayTitle,status,conclusion,startedAt",
    "-L", tostring(limit),
  }, {
    cwd = cwd,
    stdout_buffered = true,
    on_stdout = function(_, data) if data then vim.list_extend(out, data) end end,
    on_exit = function(_, code)
      _refreshing[cwd] = nil
      if code ~= 0 then return end
      local raw = table.concat(out, "\n")
      local ok, parsed = pcall(vim.fn.json_decode, raw)
      if ok and type(parsed) == "table" then
        _runs_cache[cwd] = { runs = parsed, ts = _uv.now() }
        if on_done then vim.schedule(on_done) end
      end
    end,
  })
end

function M.list_runs(cwd, limit)
  if vim.fn.executable("gh") == 0 then return {} end
  limit = limit or 5
  local entry = _runs_cache[cwd]
  local fresh = entry and (_uv.now() - entry.ts) < RUNS_TTL_MS
  if not fresh then
    async_refresh_runs(cwd, math.max(limit, 20), function()
      pcall(function() require("acp.workbench").render() end)
    end)
  end
  local runs = entry and entry.runs or {}
  if limit and #runs > limit then
    local trimmed = {}
    for i = 1, limit do trimmed[i] = runs[i] end
    return trimmed
  end
  return runs
end

function M.invalidate(cwd)
  _runs_cache[cwd] = nil
end

function M.open(cwd, main_win, main_buf, on_winbar)
  _state.buf = main_buf; _state.win = main_win
  _state.on_winbar = on_winbar; _state.cwd = cwd

  if vim.fn.executable("gh") == 0 then
    vim.bo[main_buf].modifiable = true
    vim.api.nvim_buf_set_lines(main_buf, 0, -1, false,
      {"  gh CLI not found.", "", "  brew install gh  or  https://cli.github.com"})
    vim.bo[main_buf].modifiable = false
    if on_winbar then on_winbar("pipeline") end
    return
  end

  if on_winbar then on_winbar("pipeline ⟳") end
  local entry = _runs_cache[cwd]
  _runs = entry and entry.runs or {}
  M._render(main_buf)
  M._install_keymaps(main_buf)
  if on_winbar then on_winbar("pipeline") end

  -- Force a fresh fetch on explicit open and re-render when it lands.
  M.invalidate(cwd)
  async_refresh_runs(cwd, 20, function()
    if _state.buf == main_buf and vim.api.nvim_buf_is_valid(main_buf) then
      _runs = (_runs_cache[cwd] or {}).runs or {}
      M._render(main_buf)
    end
  end)
end

return M
