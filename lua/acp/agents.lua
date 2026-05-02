local M = {}

local _providers = {
  {
    name    = "claude_code",
    display = "claude",
    cmd     = "claude",
    args    = { "acp" },
  },
  {
    name    = "opencode",
    display = "opencode",
    cmd     = "opencode",
    args    = { "acp" },
  },
  {
    name    = "codex",
    display = "codex",
    cmd     = "codex",
    args    = { "acp" },
  },
}

local _available = nil
local _cwd_prefs = {}  -- [cwd] -> provider name

function M.available()
  if _available then return _available end
  _available = {}
  for _, p in ipairs(_providers) do
    if vim.fn.exepath(p.cmd) ~= "" then table.insert(_available, p) end
  end
  return _available
end

function M.probe()
  _available = nil
  return M.available()
end

function M.register(cfg)
  assert(cfg.name and cfg.cmd, "provider needs name and cmd")
  cfg.display = cfg.display or cfg.name
  for i, p in ipairs(_providers) do
    if p.name == cfg.name then _providers[i] = cfg; _available = nil; return end
  end
  table.insert(_providers, cfg)
  _available = nil
end

function M.set_for_cwd(cwd, name) _cwd_prefs[cwd] = name end

function M.get(name)
  for _, p in ipairs(_providers) do
    if p.name == name then return p end
  end
  return nil
end

function M.cmd(provider_spec)
  local t = { provider_spec.cmd }
  for _, a in ipairs(provider_spec.args or {}) do table.insert(t, a) end
  return t
end

-- Display label for the current cwd's provider ("claude", "opencode", etc.)
function M.provider_label(cwd)
  local p = _cwd_prefs[cwd] and M.get(_cwd_prefs[cwd])
  if not p then
    local avail = M.available()
    return #avail > 0 and avail[1].display or "acp"
  end
  return p.display
end

function M.pick(cwd, callback)
  local avail = M.available()
  if #avail == 0 then
    callback("No ACP providers found on PATH (install claude or opencode)", nil); return
  end
  local labels = vim.tbl_map(function(p) return p.display end, avail)
  vim.ui.select(labels, { prompt = "ACP provider for " .. vim.fn.fnamemodify(cwd, ":~") .. ":  " },
    function(_, idx)
      if not idx then callback("cancelled", nil); return end
      _cwd_prefs[cwd] = avail[idx].name
      callback(nil, avail[idx])
    end)
end

function M.resolve(cwd, callback)
  local avail = M.available()
  if #avail == 0 then
    callback("No ACP providers found on PATH (install claude or opencode)", nil); return
  end
  local pref_name = _cwd_prefs[cwd]
  if pref_name then
    local p = M.get(pref_name)
    if p and vim.fn.exepath(p.cmd) ~= "" then callback(nil, p); return end
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
