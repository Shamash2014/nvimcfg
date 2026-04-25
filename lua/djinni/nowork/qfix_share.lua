local droid_mod = require("djinni.nowork.droid")
local parser = require("djinni.nowork.parser")
local qfix = require("djinni.nowork.qfix")

local M = {}

local MAX_ENTRIES = 200

local function format_entry(item)
  local filename = item.filename or (item.bufnr and vim.fn.bufname(item.bufnr)) or ""
  if filename == "" then return nil end
  local lnum = item.lnum or 0
  local col = item.col or 0
  local text = (item.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local loc
  if col and col > 0 then
    loc = string.format("%s:%d:%d", filename, lnum, col)
  else
    loc = string.format("%s:%d", filename, lnum)
  end
  if text ~= "" then
    return loc .. ": " .. text
  end
  return loc
end

local function format_block(title, items)
  local lines = {}
  local total = #items
  local shown = math.min(total, MAX_ENTRIES)
  for i = 1, shown do
    local entry = format_entry(items[i])
    if entry then lines[#lines + 1] = entry end
  end
  if total > shown then
    lines[#lines + 1] = string.format("... (%d truncated)", total - shown)
  end
  local safe_title = (title and title ~= "") and title or "quickfix"
  return string.format("<Quickfix title=%q>\n%s\n</Quickfix>", safe_title, table.concat(lines, "\n"))
end

local function stage(droid, block)
  droid_mod.stage_append(droid, block)
end

local function current_items()
  local info = vim.fn.getqflist({ title = 0, items = 0 })
  return info, info.items or {}
end

local function pick_range(items, l1, l2)
  local picked = {}
  for i = l1, l2 do
    if items[i] then picked[#picked + 1] = items[i] end
  end
  return picked
end

local function route(block)
  require("djinni.nowork.capture").route(block)
end

function M.share_full(droid)
  local info, items = current_items()
  if #items == 0 then
    vim.notify("nowork: quickfix list is empty", vim.log.levels.WARN)
    return
  end
  local block = format_block(info.title, items)
  stage(droid, block)
end

function M.compose_full()
  local info, items = current_items()
  if #items == 0 then
    vim.notify("nowork: quickfix list is empty", vim.log.levels.WARN)
    return
  end
  route(format_block(info.title, items))
end

function M.share_range(droid, l1, l2)
  local info, items = current_items()
  local picked = pick_range(items, l1, l2)
  if #picked == 0 then
    vim.notify("nowork: no quickfix entries in range", vim.log.levels.WARN)
    return
  end
  local block = format_block(info.title, picked)
  stage(droid, block)
end

function M.compose_range(l1, l2)
  local info, items = current_items()
  local picked = pick_range(items, l1, l2)
  if #picked == 0 then
    vim.notify("nowork: no quickfix entries in range", vim.log.levels.WARN)
    return
  end
  route(format_block(info.title, picked))
end

function M.share_marked(droid)
  local marks = require("djinni.nowork.qf_marks")
  local items = marks.marked_items()
  if #items == 0 then
    vim.notify("nowork: no marked quickfix entries", vim.log.levels.WARN)
    return
  end
  local info = vim.fn.getqflist({ title = 0 })
  local title = (info.title or "quickfix") .. " (marked)"
  stage(droid, format_block(title, items))
end

function M.compose_marked()
  local marks = require("djinni.nowork.qf_marks")
  local items = marks.marked_items()
  if #items == 0 then
    vim.notify("nowork: no marked quickfix entries", vim.log.levels.WARN)
    return
  end
  local info = vim.fn.getqflist({ title = 0 })
  local title = (info.title or "quickfix") .. " (marked)"
  route(format_block(title, items))
end

local function extract_review(text, ref)
  local items = {}
  local title = nil
  local parse_ref = ref and { cwd = ref.cwd }
  for _, block in ipairs(parser.extract_review_blocks(text)) do
    if not title and block.title and block.title ~= "" then
      title = block.title
    end
    for _, item in ipairs(parser.parse(block.body, parse_ref)) do
      items[#items + 1] = item
    end
  end
  return items, title
end

function M.flush_touched(droid)
  local bag = droid.state and droid.state.touched
  if not bag or not bag.items or #bag.items == 0 then
    vim.notify("nowork: no touched locations on " .. droid.id, vim.log.levels.WARN)
    return
  end
  local title = bag.title or ("nowork " .. droid.mode .. " results: " .. (droid.initial_prompt or droid.id))
  qfix.set(bag.items, {
    mode = "replace",
    open = true,
    title = title,
  })
  vim.notify(("nowork %s: %d location(s) → qflist"):format(droid.mode, #bag.items), vim.log.levels.INFO)
end

function M.pull_from_droid(droid)
  local lines = vim.api.nvim_buf_get_lines(droid.log_buf.buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  local log_ref = droid._log_path or ""
  local items = parser.parse_with_sections(text, { filename = log_ref, cwd = droid.opts and droid.opts.cwd })
  local review_items, review_title = extract_review(text, { cwd = droid.opts and droid.opts.cwd })
  local seen = {}
  local merged = {}
  local function push(it)
    if not it or not it.filename then return end
    local key = it.filename .. ":" .. (it.lnum or 0) .. ":" .. (it.col or 0) .. "|" .. (it.text or "")
    if not seen[key] then
      seen[key] = true
      merged[#merged + 1] = it
    end
  end
  for _, it in ipairs(items) do push(it) end
  for _, it in ipairs(review_items) do push(it) end
  if #merged >= 1 then
    qfix.set(merged, {
      mode = "replace",
      open = true,
      title = review_title or ("nowork " .. droid.mode .. " log: " .. (droid.initial_prompt or droid.id)),
    })
    vim.notify(("nowork %s log: %d entr%s → qflist"):format(droid.mode, #merged, #merged == 1 and "y" or "ies"), vim.log.levels.INFO)
  else
    vim.notify("nowork: no sections or locations in droid log for " .. droid.id, vim.log.levels.WARN)
  end
end

local function dedup_key(it)
  return (it.filename or "") .. ":" .. tostring(it.lnum or 0) .. ":" .. tostring(it.col or 0) .. "|" .. (it.text or "")
end

function M.populate(droid)
  if not droid then
    vim.notify("nowork: no droid", vim.log.levels.WARN)
    return
  end
  local seen = {}
  local merged = {}
  local function push(list)
    for _, it in ipairs(list or {}) do
      if it and it.filename and it.filename ~= "" then
        local k = dedup_key(it)
        if not seen[k] then
          seen[k] = true
          merged[#merged + 1] = it
        end
      end
    end
  end
  local bag = droid.state and droid.state.touched
  push(bag and bag.items)
  push(droid.state and droid.state.qfix_items)
  local title = (bag and bag.title)
    or (droid.state and droid.state.qfix_title)
    or ("nowork " .. droid.mode .. " results: " .. (droid.initial_prompt or droid.id))
  if #merged > 0 then
    qfix.set(merged, { mode = "replace", open = true, title = title })
  end
  local tasks = {}
  if droid.mode == "autorun" then
    local order = droid.state and droid.state.topo_order or {}
    for _, id in ipairs(order) do
      local t = (droid.state.tasks or {})[id]
      if t then
        tasks[#tasks + 1] = {
          text = ("[%s] %-10s %s"):format(id, t.status or "open", t.desc or ""),
          valid = 0,
        }
      end
    end
    if #tasks > 0 then
      qfix.set(tasks, {
        mode = #merged > 0 and "append" or "replace",
        open = true,
        title = "nowork autorun tasks: " .. (droid.initial_prompt or droid.id),
      })
    end
  end
  local total = #merged + #tasks
  if total == 0 then
    vim.notify("nowork: nothing to populate from " .. droid.id, vim.log.levels.WARN)
  else
    vim.notify(("nowork: populated %d entr%s from %s"):format(total, total == 1 and "y" or "ies", droid.id), vim.log.levels.INFO)
  end
end

M.format_block = format_block
M.format_entry = format_entry
M.extract_review = extract_review

return M
