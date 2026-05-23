local M = {}

local entries = {}

local function storage_path()
  local dir = vim.fn.stdpath("state") .. "/nvim3"
  vim.fn.mkdir(dir, "p")
  return dir .. "/findings.jsonl"
end

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function read_all()
  local path = storage_path()
  local f = io.open(path, "r")
  if not f then return {} end
  local out = {}
  for line in f:lines() do
    if line ~= "" then
      local ok, obj = pcall(vim.json.decode, line)
      if ok and type(obj) == "table" then table.insert(out, obj) end
    end
  end
  f:close()
  return out
end

local function write_all(list)
  local path = storage_path()
  local f = assert(io.open(path, "w"))
  for _, e in ipairs(list) do
    f:write(vim.json.encode(e) .. "\n")
  end
  f:close()
end

local function next_id(list)
  local max_id = 0
  for _, e in ipairs(list) do
    local n = tonumber(e.id)
    if n and n > max_id then max_id = n end
  end
  return tostring(max_id + 1)
end

local function current_agent_meta()
  local ok, agent = pcall(require, "core.agent_term")
  if not ok or type(agent.meta_for_buf) ~= "function" then return nil end
  return agent.meta_for_buf(vim.api.nvim_get_current_buf())
end

local function format_entry(e)
  local status = e.status == "done" and "✓" or "•"
  return string.format(
    "%s [%-4s] [%-5s] %s  (%s/%s)",
    status,
    e.severity or "med",
    e.kind or "todo",
    e.summary or "",
    e.agent_name or "agent",
    vim.fs.basename(e.project or ".")
  )
end

local function pick_entry(list, prompt, cb)
  if #list == 0 then
    vim.notify("findings: none", vim.log.levels.INFO)
    return
  end
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.picker and snacks.picker.pick then
    local items = {}
    for _, e in ipairs(list) do
      table.insert(items, { text = format_entry(e), data = e })
    end
    snacks.picker.pick({
      source = "findings",
      title = prompt,
      items = items,
      format = function(item)
        local e = item.data
        return {
          { (e.status == "done" and "✓ " or "• "), "Comment" },
          { string.format("%-5s ", e.kind or "todo"), "Identifier" },
          { string.format("%-4s ", e.severity or "med"), "DiagnosticWarn" },
          { e.summary or "", "Normal" },
        }
      end,
      preview = function(ctx)
        local e = ctx.item and ctx.item.data
        if not e then return end
        ctx.preview:set_lines({
          "ID:        " .. (e.id or ""),
          "Status:    " .. (e.status or "open"),
          "Kind:      " .. (e.kind or "todo"),
          "Severity:  " .. (e.severity or "med"),
          "Agent:     " .. (e.agent_name or ""),
          "Project:   " .. (e.project or ""),
          "Branch:    " .. (e.branch or ""),
          "Created:   " .. (e.created_at or ""),
          "",
          "Summary:",
          e.summary or "",
          "",
          "Suggested patch:",
          e.suggested_patch or "",
        })
      end,
      confirm = function(picker, item)
        picker:close()
        if item and item.data then cb(item.data) end
      end,
    })
    return
  end

  vim.ui.select(list, {
    prompt = prompt,
    format_item = format_entry,
  }, function(choice)
    if choice then cb(choice) end
  end)
end

local function finding_qf_item(e)
  return {
    filename = e.project or vim.uv.cwd(),
    lnum = 1,
    col = 1,
    text = string.format("#%s [%s/%s] %s", e.id, e.kind or "todo", e.severity or "med", e.summary or ""),
  }
end

local function append_to_qf(e)
  vim.fn.setqflist({}, "a", {
    title = "Findings (stream)",
    items = { finding_qf_item(e) },
  })
end

local function find_by_id(list, id)
  for _, e in ipairs(list) do
    if tostring(e.id) == tostring(id) then return e end
  end
  return nil
end

function M.add(entry)
  entries = read_all()
  entry.id = next_id(entries)
  entry.created_at = now_iso()
  entry.status = entry.status or "open"
  table.insert(entries, entry)
  write_all(entries)
  append_to_qf(entry)
  vim.notify("finding added #" .. entry.id, vim.log.levels.INFO)
end

function M.add_prompt()
  local kinds = { "risk", "debt", "todo", "patch" }
  local severities = { "low", "med", "high" }
  vim.ui.select(kinds, { prompt = "Finding kind" }, function(kind)
    if not kind then return end
    vim.ui.select(severities, { prompt = "Severity" }, function(sev)
      if not sev then return end
      vim.ui.input({ prompt = "Summary: " }, function(summary)
        if not summary or summary == "" then return end
        vim.ui.input({ prompt = "Suggested patch (optional): " }, function(suggested)
          local meta = current_agent_meta() or {}
          M.add({
            kind = kind,
            severity = sev,
            summary = summary,
            suggested_patch = suggested or "",
            agent_name = meta.name,
            project = meta.project,
            branch = meta.branch,
            cwd = meta.cwd,
          })
        end)
      end)
    end)
  end)
end

function M.list(open_only)
  entries = read_all()
  local list = {}
  for _, e in ipairs(entries) do
    if not open_only or e.status ~= "done" then
      table.insert(list, e)
    end
  end
  table.sort(list, function(a, b)
    return (a.id or "") > (b.id or "")
  end)
  return list
end

function M.show()
  pick_entry(M.list(false), "Findings", function() end)
end

function M.mark_done()
  local open = M.list(true)
  pick_entry(open, "Mark finding done", function(chosen)
    entries = read_all()
    for _, e in ipairs(entries) do
      if e.id == chosen.id then
        e.status = "done"
        e.closed_at = now_iso()
      end
    end
    write_all(entries)
    append_to_qf(chosen)
    vim.notify("finding done #" .. chosen.id, vim.log.levels.INFO)
  end)
end

function M.update_prompt(id)
  entries = read_all()
  local function do_update(target)
    if not target then return end
    vim.ui.input({ prompt = "Summary: ", default = target.summary or "" }, function(summary)
      if not summary or summary == "" then return end
      vim.ui.input({ prompt = "Suggested patch: ", default = target.suggested_patch or "" }, function(suggested)
        local statuses = { "open", "done" }
        vim.ui.select(statuses, { prompt = "Status", format_item = function(s) return s end }, function(status)
          if not status then return end
          local meta = current_agent_meta() or {}
          for _, e in ipairs(entries) do
            if tostring(e.id) == tostring(target.id) then
              e.summary = summary
              e.suggested_patch = suggested or ""
              e.status = status
              e.updated_at = now_iso()
              e.agent_name = meta.name or e.agent_name
              e.project = meta.project or e.project
              e.branch = meta.branch or e.branch
              e.cwd = meta.cwd or e.cwd
              if status == "done" and not e.closed_at then e.closed_at = now_iso() end
              if status ~= "done" then e.closed_at = nil end
              append_to_qf(e)
              break
            end
          end
          write_all(entries)
          vim.notify("finding updated #" .. tostring(target.id), vim.log.levels.INFO)
        end)
      end)
    end)
  end

  if id and tostring(id) ~= "" then
    do_update(find_by_id(entries, id))
    return
  end
  pick_entry(entries, "Update finding", do_update)
end

function M.qf(open_only)
  local list = M.list(open_only)
  if #list == 0 then
    vim.notify("findings: none", vim.log.levels.INFO)
    return
  end
  local items = {}
  for _, e in ipairs(list) do
    table.insert(items, finding_qf_item(e))
  end
  vim.fn.setqflist({}, " ", {
    title = open_only and "Findings (open)" or "Findings (all)",
    items = items,
  })
  vim.cmd("botright copen")
end

function M.setup()
  vim.api.nvim_create_user_command("FindingAdd", function() M.add_prompt() end,
    { desc = "Findings: add finding" })
  vim.api.nvim_create_user_command("Findings", function() M.show() end,
    { desc = "Findings: browse all" })
  vim.api.nvim_create_user_command("FindingDone", function() M.mark_done() end,
    { desc = "Findings: mark done" })
  vim.api.nvim_create_user_command("FindingUpdate", function(opts)
    M.update_prompt(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Findings: update finding (optional id)" })
  vim.api.nvim_create_user_command("FindingsOpen", function() M.qf(true) end,
    { desc = "Findings: open only in quickfix" })
  vim.api.nvim_create_user_command("FindingsAll", function() M.qf(false) end,
    { desc = "Findings: all in quickfix" })

  -- short aliases
  vim.api.nvim_create_user_command("FAdd", function() M.add_prompt() end, { desc = "Findings: add" })
  vim.api.nvim_create_user_command("FUpd", function(opts)
    M.update_prompt(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Findings: update" })
  vim.api.nvim_create_user_command("FOpen", function() M.qf(true) end, { desc = "Findings: open" })
end

return M
