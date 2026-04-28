local M = {}

local function normalize_path(path)
  if not path or path == "" then return nil end
  return vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
end

local function known_roots(base_cwd)
  local archive = require("djinni.nowork.archive")
  local droid_mod = require("djinni.nowork.droid")
  local roots = {}

  local function add(path)
    path = normalize_path(path)
    if path then roots[path] = true end
  end

  add(base_cwd or vim.fn.getcwd())

  local ok_projects, projects = pcall(require, "djinni.integrations.projects")
  if ok_projects and projects and projects.get then
    for _, root in ipairs(projects.get() or {}) do
      add(root)
    end
  end

  for _, d in pairs(droid_mod.active or {}) do
    add(d.opts and d.opts.cwd)
  end

  for _, h in ipairs(droid_mod.history or {}) do
    add(h.cwd)
    if h.archive_path then
      add(h.archive_path:match("^(.*)/%.nowork/logs/"))
    end
  end

  for _, a in ipairs(archive.list(30) or {}) do
    add(a.cwd)
  end

  local list = vim.tbl_keys(roots)
  table.sort(list)
  return list
end

local function read_excerpt(path, max_lines, max_chars)
  local fh = io.open(path, "r")
  if not fh then return "(unreadable worklog)" end
  local out = {}
  local chars = 0
  for _ = 1, max_lines do
    local line = fh:read("*l")
    if not line then break end
    local clipped = line
    if chars + #clipped > max_chars then
      clipped = clipped:sub(1, math.max(0, max_chars - chars))
    end
    out[#out + 1] = clipped
    chars = chars + #clipped
    if chars >= max_chars then
      out[#out + 1] = "… [truncated]"
      break
    end
  end
  fh:close()
  if #out == 0 then return "(empty worklog)" end
  return table.concat(out, "\n")
end

local function prompt_text(value)
  return tostring(value or "")
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
end

local function active_excerpt(droid, max_lines, max_chars)
  local buf = droid and droid.log_buf and droid.log_buf.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return "(active log buffer unavailable)"
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, math.min(max_lines, vim.api.nvim_buf_line_count(buf)), false)
  local out = {}
  local chars = 0
  for _, line in ipairs(lines) do
    local clipped = line
    if chars + #clipped > max_chars then
      clipped = clipped:sub(1, math.max(0, max_chars - chars))
    end
    out[#out + 1] = clipped
    chars = chars + #clipped
    if chars >= max_chars then
      out[#out + 1] = "… [truncated]"
      break
    end
  end
  if #out == 0 then return "(empty active log)" end
  return table.concat(out, "\n")
end

local function collect_worklogs(base_cwd)
  local droid_mod = require("djinni.nowork.droid")
  local archive = require("djinni.nowork.archive")
  local roots = known_roots(base_cwd)
  local items = {}
  local seen = {}

  for _, d in pairs(droid_mod.active or {}) do
    local cwd = normalize_path(d.opts and d.opts.cwd)
    local key = table.concat({ "active", d.id or "?", cwd or "?" }, "::")
    if not seen[key] then
      seen[key] = true
      items[#items + 1] = {
        kind = "active",
        id = d.id,
        mode = d.mode,
        status = d.status,
        cwd = cwd,
        started_at = d.started_at or 0,
        provider = d.provider_name,
        title = d.state and d.state.title or nil,
        prompt = d.initial_prompt,
        excerpt = active_excerpt(d, 120, 5000),
      }
    end
  end

  for _, a in ipairs(archive.list(30, roots) or {}) do
    local key = "archive::" .. tostring(a.path)
    if not seen[key] then
      seen[key] = true
      local state = archive.read_state(a.path)
      items[#items + 1] = {
        kind = "archive",
        id = a.id,
        mode = a.mode,
        status = a.has_state and "resumable" or "archived",
        cwd = normalize_path(a.cwd),
        date = a.date,
        stamp = a.stamp,
        path = a.path,
        title = state and state.title or nil,
        prompt = archive.prompt_hint and archive.prompt_hint(a.path) or nil,
        excerpt = read_excerpt(a.path, 120, 5000),
      }
    end
  end

  table.sort(items, function(a, b)
    local at = a.started_at or 0
    local bt = b.started_at or 0
    if a.kind == "archive" then
      at = tonumber((a.date or "") .. (a.stamp or "")) or 0
    end
    if b.kind == "archive" then
      bt = tonumber((b.date or "") .. (b.stamp or "")) or 0
    end
    if at ~= bt then return at > bt end
    return (a.id or a.path or "") < (b.id or b.path or "")
  end)

  return items
end

local function build_prompt(items)
  local out = {
    "Summarize these nowork worklogs.",
    "Produce a concise cross-worklog recap with recurring themes, notable outcomes, risks, and recommended follow-ups.",
    "Prefer grouping similar work together instead of listing every log separately.",
    "",
    "Use this structure:",
    "<Summary>one-paragraph overview</Summary>",
    "<Themes>- theme bullets</Themes>",
    "<Risks>- risk bullets</Risks>",
    "<FollowUps>- follow-up bullets</FollowUps>",
    "",
  }

  for idx, item in ipairs(items) do
    out[#out + 1] = string.format("<Worklog index=\"%d\" kind=\"%s\">", idx, item.kind)
    out[#out + 1] = "id: " .. prompt_text(item.id or "?")
    out[#out + 1] = "mode: " .. prompt_text(item.mode or "?")
    out[#out + 1] = "status: " .. prompt_text(item.status or "?")
    if item.cwd then out[#out + 1] = "cwd: " .. prompt_text(item.cwd) end
    if item.provider then out[#out + 1] = "provider: " .. prompt_text(item.provider) end
    if item.title and item.title ~= "" then out[#out + 1] = "title: " .. prompt_text(item.title) end
    if item.prompt and item.prompt ~= "" then out[#out + 1] = "prompt: " .. prompt_text(item.prompt) end
    if item.path then out[#out + 1] = "path: " .. prompt_text(item.path) end
    if item.date or item.stamp then out[#out + 1] = "timestamp: " .. prompt_text(tostring(item.date or "?") .. " " .. tostring(item.stamp or "")) end
    out[#out + 1] = ""
    out[#out + 1] = prompt_text(item.excerpt)
    out[#out + 1] = "</Worklog>"
    out[#out + 1] = ""
  end

  return table.concat(out, "\n")
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
  Snacks.picker.select(providers, { prompt = "worklog summary provider" }, function(chosen)
    if chosen then cb(chosen) end
  end)
end

local function pick_model(provider_name, cb)
  local Provider = require("djinni.acp.provider")
  local items = Provider.list_models(nil, provider_name) or {}
  if #items == 0 then
    vim.ui.input({ prompt = "worklog summary model: " }, function(input)
      input = input and vim.trim(input) or ""
      if input ~= "" then cb(input) end
    end)
    return
  end
  Snacks.picker.select(items, {
    prompt = "worklog summary model",
    format_item = function(item) return item.label or item.id end,
  }, function(choice)
    if not choice then return end
    cb(choice.id or choice)
  end)
end

function M.summarize_all(opts)
  opts = opts or {}
  local nowork = require("djinni.nowork")
  local base_cwd = normalize_path(opts.cwd or vim.fn.getcwd()) or vim.fn.getcwd()

  if not opts.provider and not opts._picked_provider then
    pick_provider((nowork.config and nowork.config.provider) or nil, function(provider_name)
      M.summarize_all(vim.tbl_extend("force", opts, { provider = provider_name, _picked_provider = true }))
    end)
    return
  end

  if not opts.model and not opts._picked_model then
    pick_model(opts.provider, function(model_name)
      M.summarize_all(vim.tbl_extend("force", opts, { model = model_name, _picked_model = true }))
    end)
    return
  end

  local items = collect_worklogs(base_cwd)
  if #items == 0 then
    vim.notify("nowork: no worklogs found to summarize", vim.log.levels.WARN)
    return
  end

  vim.notify(
    string.format("nowork: summarizing %d worklogs with %s/%s", #items, tostring(opts.provider), tostring(opts.model)),
    vim.log.levels.INFO
  )
  return nowork.explore(build_prompt(items), {
    cwd = base_cwd,
    provider = opts.provider,
    model = opts.model,
    no_template = true,
  })
end

return M
