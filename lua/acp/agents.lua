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
}

local _available = nil

local _prefs_path  = vim.fn.stdpath("data") .. "/acp/cwd_prefs.json"
local _models_path = vim.fn.stdpath("data") .. "/acp/cwd_models.json"

local function load_json(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local raw = f:read("*a"); f:close()
  local ok, decoded = pcall(vim.json.decode, raw)
  return (ok and type(decoded) == "table") and decoded or {}
end

local _cwd_prefs  = load_json(_prefs_path)
local _cwd_models = load_json(_models_path)

local function save_json(path, tbl)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w"); if not f then return end
  f:write(vim.json.encode(tbl)); f:close()
end

local function save_prefs()  save_json(_prefs_path,  _cwd_prefs)  end
local function save_models() save_json(_models_path, _cwd_models) end

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
function M.set_model_for_cwd(cwd, model) _cwd_models[cwd] = model; save_models() end
function M.get_model_for_cwd(cwd) return _cwd_models[cwd] end

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

function M.choose_provider(cwd, callback)
  cwd = cwd or vim.fn.getcwd()
  M.probe()
  local avail = M.available()
  if #avail == 0 then
    vim.notify("No ACP providers on PATH", vim.log.levels.WARN, { title = "acp" })
    if callback then callback("none") end
    return
  end
  local labels = {}
  for _, p in ipairs(avail) do
    local mark = (_cwd_prefs[cwd] == p.name) and "  ✓" or ""
    table.insert(labels, p.display .. mark)
  end
  vim.ui.select(labels, { prompt = "ACP provider for " .. vim.fn.fnamemodify(cwd, ":~") .. ": " },
    function(_, idx)
      if not idx then if callback then callback("cancelled") end; return end
      local picked = avail[idx]
      local prev = _cwd_prefs[cwd]
      _cwd_prefs[cwd] = picked.name
      save_prefs()
      if prev ~= picked.name then
        local session = require("acp.session")
        for _, s in ipairs(session.active()) do
          if s.cwd == cwd then session.close(s.key) end
        end
      end
      vim.notify("ACP provider: " .. picked.display, vim.log.levels.INFO, { title = "acp" })
      if callback then callback(nil, picked) end
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
    vim.notify("ACP provider '" .. pref_name .. "' not on PATH — picking again",
               vim.log.levels.WARN, { title = "acp" })
    _cwd_prefs[cwd] = nil
    save_prefs()
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
