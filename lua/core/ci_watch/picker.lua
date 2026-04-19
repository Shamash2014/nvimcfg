local M = {}

local TITLE = "CI Watch"

local GLYPH = {
  success = { "✓", "DiagnosticOk" },
  failure = { "✗", "DiagnosticError" },
  running = { "●", "DiagnosticWarn" },
  pending = { "●", "DiagnosticWarn" },
  cancelled = { "○", "Comment" },
  skipped = { "○", "Comment" },
  unknown = { "○", "Comment" },
}

local function glyph(status)
  return GLYPH[status] or GLYPH.unknown
end

local function relative_time(iso)
  if not iso or iso == "" then return "" end
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
  local offset = os.time() - os.time(os.date("!*t"))
  local ago = os.time() - (t + offset)
  if ago < 60 then return string.format("%ds ago", ago) end
  if ago < 3600 then return string.format("%dm ago", math.floor(ago / 60)) end
  if ago < 86400 then return string.format("%dh ago", math.floor(ago / 3600)) end
  return string.format("%dd ago", math.floor(ago / 86400))
end

local function build_items(prs, runs, default_branch)
  local items = {}
  for _, p in ipairs(prs or {}) do
    items[#items + 1] = {
      kind = "pr",
      status = p.status,
      branch = p.branch,
      number = p.number,
      title = p.title,
      url = p.url,
      text = string.format("PR #%d %s %s %s", p.number or 0, p.status or "?", p.branch or "", p.title or ""),
    }
  end
  for _, r in ipairs(runs or {}) do
    items[#items + 1] = {
      kind = "run",
      status = r.status,
      id = r.id,
      name = r.name,
      branch = r.branch,
      event = r.event,
      url = r.url,
      created_at = r.created_at,
      text = string.format("RUN %s %s %s %s %s", tostring(r.id or ""), r.status or "?", r.name or "", r.branch or "", r.event or ""),
    }
  end
  if default_branch and default_branch ~= "" then
    local kind_rank = { pr = 0, run = 1 }
    table.sort(items, function(a, b)
      local a_match = a.branch == default_branch
      local b_match = b.branch == default_branch
      if a_match ~= b_match then return a_match end
      if a_match and b_match then
        return (kind_rank[a.kind] or 2) < (kind_rank[b.kind] or 2)
      end
      return false
    end)
  end
  return items
end

local function format_item(item)
  local g = glyph(item.status)
  if item.kind == "pr" then
    return {
      { "[PR  #" .. tostring(item.number or "?") .. "] ", "Comment" },
      { g[1] .. " ", g[2] },
      { (item.branch or "") .. " ", "Normal" },
      { "— " .. (item.title or ""), "Comment" },
    }
  end
  return {
    { "[RUN " .. tostring(item.id or "?") .. "] ", "Comment" },
    { g[1] .. " ", g[2] },
    { (item.name or "") .. " ", "Normal" },
    { "· " .. (item.branch or "") .. " · " .. (item.event or "") .. " · " .. relative_time(item.created_at), "Comment" },
  }
end

local function open_url(item)
  if item and item.url and item.url ~= "" then
    vim.ui.open(item.url)
  else
    vim.notify("No URL for item", vim.log.levels.WARN, { title = TITLE })
  end
end

local function watch_item(item)
  if not item or not item.branch or item.branch == "" then
    vim.notify("No branch for item", vim.log.levels.WARN, { title = TITLE })
    return
  end
  require("core.ci_watch").watch({ branch = item.branch })
end

local function view_logs(item)
  if not item or item.kind ~= "run" or not item.id then
    vim.notify("Logs only available for run items", vim.log.levels.WARN, { title = TITLE })
    return
  end
  require("core.ci_watch.logs").view(item.id)
end

local function launch(items)
  if #items == 0 then
    vim.notify("No open PRs or recent runs found", vim.log.levels.INFO, { title = TITLE })
    return
  end
  if not Snacks or not Snacks.picker then
    vim.notify("Snacks.picker not available", vim.log.levels.ERROR, { title = TITLE })
    return
  end
  Snacks.picker({
    title = "CI — PRs & Runs",
    items = items,
    format = format_item,
    layout = { preset = "vscode" },
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      watch_item(item)
    end,
    actions = {
      ci_open = function(_, item)
        open_url(item)
      end,
      ci_logs = function(picker, item)
        picker:close()
        view_logs(item)
      end,
      ci_help = function()
        vim.notify(
          "CI picker:\n  <CR> watch branch in statusline\n  o    open url\n  l    view logs (runs)\n  ?    this help",
          vim.log.levels.INFO,
          { title = TITLE }
        )
      end,
    },
    win = {
      input = {
        keys = {
          ["o"] = { "ci_open", mode = { "n" } },
          ["l"] = { "ci_logs", mode = { "n" } },
          ["?"] = { "ci_help", mode = { "n" } },
        },
      },
    },
  })
end

function M.open()
  local github = require("core.ci_watch.github")
  local prs, runs
  local pr_err, run_err

  local function maybe_launch()
    if prs == nil or runs == nil then return end
    if pr_err and run_err then
      vim.notify("CI picker: " .. (pr_err or run_err), vim.log.levels.ERROR, { title = TITLE })
      return
    end
    launch(build_items(prs, runs))
  end

  github.list_my_prs(function(items, err)
    prs = items or {}
    pr_err = err
    maybe_launch()
  end)
  github.list_recent_runs(function(items, err)
    runs = items or {}
    run_err = err
    maybe_launch()
  end)
end

return M
