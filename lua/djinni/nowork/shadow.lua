local M = {}

local function run_git(cwd, args)
  local ok, obj = pcall(function()
    return vim.system({ "git", unpack(args) }, { cwd = cwd, text = true, timeout = 2000 }):wait()
  end)
  if not ok or not obj or obj.code ~= 0 then return nil end
  return obj.stdout or ""
end

local function collect_touched(droid)
  local out = {}
  local bag = droid.state and droid.state.touched
  if bag and bag.items then
    for _, it in ipairs(bag.items) do
      local loc = it.filename .. ":" .. (it.lnum or 1)
      if it.col and it.col > 1 then loc = loc .. ":" .. it.col end
      if it.text and it.text ~= "" then loc = loc .. ": " .. it.text end
      out[#out + 1] = loc
    end
  end
  return out
end

local function pick_provider(default, cb)
  local providers = require("djinni.acp.provider").list() or {}
  if #providers <= 1 then
    cb(providers[1] or default)
    return
  end
  table.sort(providers, function(a, b)
    if a == default then return true end
    if b == default then return false end
    return a < b
  end)
  Snacks.picker.select(providers, { prompt = "shadow review provider" }, function(chosen)
    if chosen then cb(chosen) end
  end)
end

function M.review(droid_or_id, opts)
  opts = opts or {}
  local droid_mod = require("djinni.nowork.droid")
  local droid = droid_mod.resolve(droid_or_id)
  if not droid then
    vim.notify("nowork.shadow: droid not found", vim.log.levels.WARN)
    return
  end
  if not opts.provider and not opts._picked_provider then
    local default = droid.provider_name
    pick_provider(default, function(chosen)
      M.review(droid, { provider = chosen, _picked_provider = true })
    end)
    return
  end
  local cwd = droid.opts and droid.opts.cwd or vim.fn.getcwd()
  local diff = run_git(cwd, { "diff" }) or ""
  local staged = run_git(cwd, { "diff", "--cached" }) or ""
  local touched = collect_touched(droid)

  local sections = {}
  sections[#sections + 1] = "Shadow review of nowork session " .. droid.id
    .. " (" .. droid.mode .. ")"
  if droid.initial_prompt and droid.initial_prompt ~= "" then
    sections[#sections + 1] = "Task was: " .. droid.initial_prompt
  end
  sections[#sections + 1] = ""
  sections[#sections + 1] = "Audit these changes. Report locations worth reviewing as explore output."
  sections[#sections + 1] = "Focus on: regressions, missed callers, missing tests, incomplete edits, style/consistency drift."
  sections[#sections + 1] = ""

  if #touched > 0 then
    sections[#sections + 1] = "<TouchedLocations>"
    for _, l in ipairs(touched) do sections[#sections + 1] = l end
    sections[#sections + 1] = "</TouchedLocations>"
    sections[#sections + 1] = ""
  end

  if diff ~= "" then
    sections[#sections + 1] = "<Diff>"
    sections[#sections + 1] = diff
    sections[#sections + 1] = "</Diff>"
  end
  if staged ~= "" then
    sections[#sections + 1] = "<StagedDiff>"
    sections[#sections + 1] = staged
    sections[#sections + 1] = "</StagedDiff>"
  end
  if diff == "" and staged == "" and #touched == 0 then
    vim.notify("nowork.shadow: no diff or touched files on " .. droid.id, vim.log.levels.WARN)
    return
  end

  pcall(require("djinni.nowork.qfix_share").populate, droid)

  local prompt = table.concat(sections, "\n")
  local explore_opts = { cwd = cwd }
  if opts.provider then explore_opts.provider = opts.provider end
  if opts.provider and opts.provider ~= droid.provider_name then
    vim.notify(
      string.format("nowork.shadow: reviewing %s with %s", droid.id, opts.provider),
      vim.log.levels.INFO
    )
  end
  return require("djinni.nowork").explore(prompt, explore_opts)
end

return M
