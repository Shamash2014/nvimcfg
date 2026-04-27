local M = {}

local function acp_label(droid)
  if not (droid.acp_modes and droid.acp_modes.current_id) then return nil end
  local id = droid.acp_modes.current_id
  for _, mode in ipairs(droid.acp_modes.available or {}) do
    if mode.id == id then return mode.name or mode.id end
  end
  return id
end

function M.token_compact(n)
  n = tonumber(n) or 0
  if n < 1000 then return tostring(math.floor(n)) end
  if n < 1e6  then return string.format("%.1fk", n / 1e3) end
  if n < 1e9  then return string.format("%.1fM", n / 1e6) end
  return string.format("%.1fB", n / 1e9)
end

function M.cost_compact(n)
  n = tonumber(n)
  if not n or n <= 0 then return nil end
  return string.format("$%.2f", n)
end

function M.components(droid)
  if not droid then return {} end
  local s     = droid.state or {}
  local tok   = s.tokens or {}
  local disc  = s.discussion or {}
  local q     = disc.queue or {}
  local sum   = require("djinni.nowork.events").summary(droid)

  local parts = {}
  local function push(sym, val)
    if val == nil or val == "" then return end
    parts[#parts + 1] = { sym = sym, val = tostring(val) }
  end

  if droid.id then parts[#parts + 1] = { sym = nil, val = "[" .. tostring(droid.id) .. "]" } end
  if droid.status and droid.status ~= "" then
    parts[#parts + 1] = { sym = nil, val = droid.status }
  end

  local total = (tok.input or 0) + (tok.output or 0)
  if total > 0 then push("T", M.token_compact(total)) end
  if (tok.input or 0)  > 0 then push("I", M.token_compact(tok.input))  end
  if (tok.output or 0) > 0 then push("O", M.token_compact(tok.output)) end
  local cache = (tok.cache_read or 0) + (tok.cache_write or 0)
  if cache > 0 then push("C", M.token_compact(cache)) end
  push("$", M.cost_compact(tok.cost))
  if #q > 0              then push("Q", tostring(#q)) end
  if sum.staged > 0      then push("+", tostring(sum.staged)) end
  if sum.permissions > 0 then push("P", tostring(sum.permissions)) end
  if sum.questions > 0   then push("?", tostring(sum.questions)) end
  if sum.blockers > 0    then push("!", tostring(sum.blockers)) end
  push("M", droid.model_name)
  push("A", acp_label(droid))
  push("policy", droid.mode)

  return parts
end

function M.render(parts, sep)
  sep = sep or " · "
  local out = {}
  for _, p in ipairs(parts) do
    if p.sym then out[#out + 1] = p.sym .. " " .. p.val
    else          out[#out + 1] = p.val end
  end
  return table.concat(out, sep)
end

function M.compact_render(droid)
  return M.render(M.components(droid))
end

function M.statusline_parts(droids)
  local R, B, I = 0, 0, 0
  local Tt, Qt = 0, 0
  local cost = 0
  for _, d in ipairs(droids) do
    local st = d.status
    if st == "running" then R = R + 1
    elseif st == "booting" then B = B + 1
    elseif st == "idle" then I = I + 1 end
    local s = d.state or {}
    local tok = s.tokens or {}
    Tt = Tt + (tok.input or 0) + (tok.output or 0)
    cost = cost + (tok.cost or 0)
    local disc = s.discussion or {}
    Qt = Qt + #(disc.queue or {})
  end
  local agg = require("djinni.nowork.events").aggregate(droids)
  local parts = {}
  local function push(sym, n)
    if n and n > 0 then parts[#parts + 1] = { sym = sym, val = tostring(n) } end
  end
  push("R", R); push("B", B); push("I", I)
  if Tt > 0 then parts[#parts + 1] = { sym = "T", val = M.token_compact(Tt) } end
  push("Q", Qt)
  push("+", agg.staged)
  push("P", agg.permissions)
  push("?", agg.questions)
  push("!", agg.blockers)
  local cost_str = M.cost_compact(cost)
  if cost_str then parts[#parts + 1] = { sym = nil, val = cost_str } end
  return parts
end

function M.statusline_render(droids)
  return M.render(M.statusline_parts(droids), " ")
end

if vim and vim.env and vim.env.DJINNI_TEST == "1" then
  local cases = {
    {
      name   = "zero-state",
      droid  = { id = "a1" },
      expect = "[a1]",
    },
    {
      name = "busy-with-tokens",
      droid = {
        id = "b2", status = "running",
        state = { tokens = { input = 1500, output = 200, cost = 0.07 } },
      },
      expect = "[b2] · running · T 1.7k · I 1.5k · O 200 · $ $0.07",
    },
    {
      name = "decision-pending",
      droid = {
        id = "c3", status = "waiting",
        state = {
          pending_events = { { kind = "permission" }, { kind = "permission" } },
          discussion = { queue = {}, pending_prompt = true },
        },
      },
      expect = "[c3] · waiting · P 2 · ? 1",
    },
  }
  for _, c in ipairs(cases) do
    local got = M.compact_render(c.droid)
    if got ~= c.expect then
      error(("DJINNI_TEST golden mismatch [%s]\n  expect %q\n  got    %q"):format(c.name, c.expect, got))
    end
  end
end

return M
