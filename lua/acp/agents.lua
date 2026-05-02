local M = {}

-- Provider spec: { name, display, cmd: string[], args: string[]?, env: table? }
local _providers = {
  {
    name    = "claude_code",
    display = "Claude Code  (claude acp)",
    cmd     = "claude",
    args    = { "acp" },
  },
  {
    name    = "opencode",
    display = "OpenCode  (opencode acp)",
    cmd     = "opencode",
    args    = { "acp" },
  },
}

local _available  = nil          -- cached after first probe
local _cwd_prefs  = {}           -- [cwd] -> provider name

-- Returns list of providers whose executable exists on $PATH.
-- Result is cached — call M.probe() to force a refresh.
function M.available()
  if _available then return _available end
  _available = {}
  for _, p in ipairs(_providers) do
    if vim.fn.exepath(p.cmd) ~= "" then
      table.insert(_available, p)
    end
  end
  return _available
end

function M.probe()
  _available = nil
  return M.available()
end

-- Register a custom provider at runtime or from setup().
-- cfg: { name, display?, cmd, args?, env? }
function M.register(cfg)
  assert(cfg.name and cfg.cmd, "provider needs name and cmd")
  cfg.display = cfg.display or (cfg.name .. "  (" .. cfg.cmd .. ")")
  -- Replace if name already exists
  for i, p in ipairs(_providers) do
    if p.name == cfg.name then _providers[i] = cfg; _available = nil; return end
  end
  table.insert(_providers, cfg)
  _available = nil
end

-- Set the preferred provider for a cwd.
function M.set_for_cwd(cwd, name)
  _cwd_prefs[cwd] = name
end

-- Returns the full provider spec for `name`, or nil.
function M.get(name)
  for _, p in ipairs(_providers) do
    if p.name == name then return p end
  end
  return nil
end

-- Build the cmd table passed to transport.spawn().
function M.cmd(provider_spec)
  local t = { provider_spec.cmd }
  for _, a in ipairs(provider_spec.args or {}) do table.insert(t, a) end
  return t
end

-- Show vim.ui.select picker over available providers.
-- On selection: sets cwd preference, calls callback(err, provider_spec).
function M.pick(cwd, callback)
  local avail = M.available()
  if #avail == 0 then
    callback("No ACP providers found on PATH (install claude or opencode)", nil)
    return
  end
  local labels = vim.tbl_map(function(p) return p.display end, avail)
  vim.ui.select(labels, { prompt = "ACP provider for " .. vim.fn.fnamemodify(cwd, ":~") .. ":  " },
    function(_, idx)
      if not idx then callback("cancelled", nil); return end
      local chosen = avail[idx]
      _cwd_prefs[cwd] = chosen.name
      callback(nil, chosen)
    end)
end

-- Resolve the provider for `cwd`:
--   1. If cwd has a stored preference and that provider is available → use it.
--   2. If exactly one provider available → use it silently.
--   3. If multiple available → show picker.
--   4. If none → error.
-- callback: fn(err: string|nil, provider_spec: table|nil)
function M.resolve(cwd, callback)
  local avail = M.available()
  if #avail == 0 then
    callback("No ACP providers found on PATH (install claude or opencode)", nil)
    return
  end

  local pref_name = _cwd_prefs[cwd]
  if pref_name then
    local p = M.get(pref_name)
    -- Verify it's still available (PATH may change)
    if p and vim.fn.exepath(p.cmd) ~= "" then
      callback(nil, p)
      return
    end
    -- Stale preference — clear and fall through
    _cwd_prefs[cwd] = nil
  end

  if #avail == 1 then
    _cwd_prefs[cwd] = avail[1].name
    callback(nil, avail[1])
  else
    M.pick(cwd, callback)
  end
end

return M
