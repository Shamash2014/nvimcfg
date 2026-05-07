local M = {}

local _providers = {
  {
    name    = "claude",
    display = "claude",
    cmd     = "claude-agent-acp",
    args    = {},
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
    cmd     = "codex-acp",
    args    = {},
  },
  {
    name    = "hermes",
    display = "hermes",
    cmd     = "hermes",
    args    = { "acp" },
  },
  {
    name    = "cursor",
    display = "cursor",
    cmd     = "agent",
    args    = { "acp" },
  },
  {
    name    = "pi",
    display = "pi",
    cmd     = "pi-acp",
    args    = {},
  },
}

local _available = nil

local _prefs_path      = vim.fn.stdpath("data") .. "/acp/cwd_prefs.json"
local _models_path     = vim.fn.stdpath("data") .. "/acp/cwd_models.json"
local _key_models_path = vim.fn.stdpath("data") .. "/acp/key_models.json"
local _key_prefs_path  = vim.fn.stdpath("data") .. "/acp/key_prefs.json"

local function load_json(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local raw = f:read("*a"); f:close()
  local ok, decoded = pcall(vim.json.decode, raw)
  return (ok and type(decoded) == "table") and decoded or {}
end

local _cwd_prefs  = load_json(_prefs_path)
local _cwd_models = load_json(_models_path)
local _key_models = load_json(_key_models_path)
local _key_prefs  = load_json(_key_prefs_path)

local function save_json(path, tbl)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w"); if not f then return end
  f:write(vim.json.encode(tbl)); f:close()
end

local function save_prefs()      save_json(_prefs_path,      _cwd_prefs)  end
local function save_models()     save_json(_models_path,     _cwd_models) end
local function save_key_models() save_json(_key_models_path, _key_models) end
local function save_key_prefs()  save_json(_key_prefs_path,  _key_prefs)  end

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

function M.set_for_cwd(cwd, name) _cwd_prefs[cwd] = name; save_prefs() end
function M.set_for_key(key, name) _key_prefs[key] = name; save_key_prefs() end
function M.get_for_key(key) return _key_prefs[key] end
function M.set_model_for_cwd(cwd, model) _cwd_models[cwd] = model; save_models() end
function M.get_model_for_cwd(cwd) return _cwd_models[cwd] end
function M.set_model_for_key(key, model) _key_models[key] = model; save_key_models() end
function M.get_model_for_key(key) return _key_models[key] end
function M.set_mode_for_key(key, mode) _key_prefs["mode:" .. key] = mode; save_key_prefs() end
function M.get_mode_for_key(key) return _key_prefs["mode:" .. key] end
function M.set_mode_for_cwd(cwd, mode) _cwd_prefs["mode:" .. cwd] = mode; save_prefs() end
function M.get_mode_for_cwd(cwd) return _cwd_prefs["mode:" .. cwd] end

-- Look up a value (pref or model), falling back from key-scoped to cwd-scoped.
local function _lookup(key_fn, cwd_fn, k, v) return key_fn(k) or cwd_fn(v) end
M.lookup_mode   = function(key, cwd) return _lookup(M.get_mode_for_key,   M.get_mode_for_cwd,   key, cwd) end
M.lookup_model  = function(key, cwd) return _lookup(M.get_model_for_key,  M.get_model_for_cwd,  key, cwd) end

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
  local ok, session_mod = pcall(require, "acp.session")
  if ok then
    local s = session_mod.find_ready_for_cwd(cwd)
    if s and s.provider then
      local p = M.get(s.provider)
      if p then return p.display end
    end
  end
  local p = _cwd_prefs[cwd] and M.get(_cwd_prefs[cwd])
  if not p then
    local avail = M.available()
    return #avail > 0 and avail[1].display or "acp"
  end
  return p.display
end

function M.current_model_label(cwd)
  local provider = M.provider_label(cwd)
  local ok, session = pcall(require, "acp.session")
  if ok then
    local opts = session.get_config_options_for_cwd(cwd)
    for _, opt in ipairs(opts) do
      if opt.category == "model" and opt.currentValue then
        for _, o in ipairs(opt.options or {}) do
          if o.value == opt.currentValue then
            return provider .. "/" .. (o.name or opt.currentValue)
          end
        end
        return provider .. "/" .. opt.currentValue
      end
    end
  end
  local stored = _cwd_models[cwd]
  if stored and stored ~= "" then
    return provider .. "/" .. stored
  end
  return provider
end

-- Resolve a session's current_mode to its human-readable name from available_modes.
-- Returns nil if no mode is set; returns the raw current_mode as fallback.
function M.mode_name_from_session(sess)
  if not sess or (sess.current_mode or "") == "" then return nil end
  for _, m in ipairs(sess.available_modes or {}) do
    if (m.id or m.modeId) == sess.current_mode then
      return m.name or m.id or sess.current_mode
    end
  end
  return sess.current_mode
end

function M.chip(cwd) return M.current_model_label(cwd or vim.fn.getcwd()) end

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
      save_prefs()
      callback(nil, avail[idx])
    end)
end

-- opts = { key = session_key } to set provider per-session instead of per-cwd
function M.choose_provider(cwd, callback, opts)
  cwd = cwd or vim.fn.getcwd()
  local key = opts and opts.key
  M.probe()
  local avail = M.available()
  if #avail == 0 then
    vim.notify("No ACP providers on PATH", vim.log.levels.WARN, { title = "acp" })
    if callback then callback("none") end
    return
  end
  local cur = (key and _key_prefs[key]) or _cwd_prefs[cwd]
  local labels = {}
  for _, p in ipairs(avail) do
    local mark = (cur == p.name) and "  ✓" or ""
    table.insert(labels, p.display .. mark)
  end
  local scope = key and ("session:" .. key) or vim.fn.fnamemodify(cwd, ":~")
  vim.ui.select(labels, { prompt = "ACP provider for " .. scope .. ": " },
    function(_, idx)
      if not idx then if callback then callback("cancelled") end; return end
      local picked = avail[idx]
      local prev = cur
      if key then
        _key_prefs[key] = picked.name; save_key_prefs()
        if prev ~= picked.name then
          require("acp.session").close(key)
        end
      else
        _cwd_prefs[cwd] = picked.name; save_prefs()
        if prev ~= picked.name then
          local session = require("acp.session")
          for _, s in ipairs(session.active()) do
            if s.cwd == cwd then session.close(s.key) end
          end
        end
      end
      vim.notify("ACP provider: " .. picked.display, vim.log.levels.INFO, { title = "acp" })
      if callback then callback(nil, picked) end
    end)
end

-- cwd_or_opts: string cwd, or { cwd, key } for per-session provider resolution
function M.resolve(cwd_or_opts, callback)
  local cwd = type(cwd_or_opts) == "string" and cwd_or_opts or cwd_or_opts.cwd
  local key = type(cwd_or_opts) == "table" and cwd_or_opts.key or nil
  local avail = M.available()
  if #avail == 0 then
    callback("No ACP providers found on PATH (install claude or opencode)", nil); return
  end
  local pref_name = (key and _key_prefs[key]) or _cwd_prefs[cwd]
  if pref_name then
    local p = M.get(pref_name)
    if p and vim.fn.exepath(p.cmd) ~= "" then callback(nil, p); return end
    vim.notify("ACP provider '" .. pref_name .. "' not on PATH — picking again",
               vim.log.levels.WARN, { title = "acp" })
    if key and _key_prefs[key] == pref_name then
      _key_prefs[key] = nil; save_key_prefs()
    else
      _cwd_prefs[cwd] = nil; save_prefs()
    end
  end
  if #avail == 1 then
    _cwd_prefs[cwd] = avail[1].name
    save_prefs()
    callback(nil, avail[1])
  else
    M.pick(cwd, callback)
  end
end

return M
