local M = {}

local ns = vim.api.nvim_create_namespace("nowork_qf_virt")
local focus_ns = vim.api.nvim_create_namespace("nowork_qf_focus")
local enabled = true

pcall(vim.api.nvim_set_hl, 0, "NoworkQfVirt", { link = "DiagnosticHint", default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfSummary",     { link = "DiagnosticInfo",  default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfReview",      { link = "DiagnosticOk",    default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfObservation", { link = "DiagnosticHint",  default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfNext",        { link = "DiagnosticWarn",  default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfTasks",       { link = "Todo",            default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfWorklog",    { link = "Comment",         default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfEdit",       { link = "DiagnosticWarn",    default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfWrite",      { link = "DiagnosticOk",      default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfCreate",     { link = "DiagnosticHint",    default = true })
pcall(vim.api.nvim_set_hl, 0, "NoworkQfDelete",     { link = "DiagnosticError",   default = true })

local TAG_HL = {
  Summary      = "NoworkQfSummary",
  Review       = "NoworkQfReview",
  Observation  = "NoworkQfObservation",
  Observations = "NoworkQfObservation",
  Next         = "NoworkQfNext",
  Tasks        = "NoworkQfTasks",
  worklog      = "NoworkQfWorklog",
  edit         = "NoworkQfEdit",
  write        = "NoworkQfWrite",
  create       = "NoworkQfCreate",
  delete       = "NoworkQfDelete",
}

local TAG_ICON = {
  Summary      = "📜",
  Review       = "✍",
  Observation  = "👁",
  Observations = "👁",
  Next         = "▶",
  Tasks        = "✅",
  worklog      = "📄",
  edit         = "⚡",
  write        = "💾",
  create       = "✨",
  delete       = "🗑",
}

local function buf_path(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil end
  return vim.fn.fnamemodify(name, ":p")
end

local function item_path(it)
  if it.bufnr and it.bufnr > 0 then
    local n = vim.fn.bufname(it.bufnr)
    if n ~= "" then return vim.fn.fnamemodify(n, ":p") end
  end
  if it.filename and it.filename ~= "" then
    return vim.fn.fnamemodify(it.filename, ":p")
  end
  return nil
end

function M.clear(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

function M.clear_focus(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, focus_ns, 0, -1)
  end
end

function M.apply_focus(buf)
  M.clear_focus(buf)
  local target = buf_path(buf)
  if not target then return end
  
  local qf = vim.fn.getqflist({ idx = 0, items = 0 })
  if qf.idx == 0 or not qf.items or #qf.items == 0 then return end
  
  local it = qf.items[qf.idx]
  if not it then return end
  
  local p = item_path(it)
  if p == target and it.lnum and it.lnum > 0 then
    local text = (it.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    
    local tag = text:match("^%[(%w+)[:%]]")
    local hl = (tag and TAG_HL[tag]) or "NoworkQfVirt"
    local icon = (tag and TAG_ICON[tag]) or "▶"
    
    local line_count = vim.api.nvim_buf_line_count(buf)
    local lnum = math.min(it.lnum, line_count)
    
    pcall(vim.api.nvim_buf_set_extmark, buf, focus_ns, lnum - 1, 0, {
      virt_lines = { { { "  " .. icon .. " " .. text, hl } } },
      virt_lines_above = true,
    })
  end
end

function M.apply(buf)
  if not enabled then return end
  local target = buf_path(buf)
  if not target then return end
  local items = vim.fn.getqflist({ items = 0 }).items or {}
  if #items == 0 then
    M.clear(buf)
    return
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  local by_line = {}
  for _, it in ipairs(items) do
    local p = item_path(it)
    if p == target and it.lnum and it.lnum > 0 and it.lnum <= line_count then
      local text = it.text or ""
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then
        local slot = by_line[it.lnum] or {}
        slot[#slot + 1] = text
        by_line[it.lnum] = slot
      end
    end
  end
  M.clear(buf)
  for lnum, texts in pairs(by_line) do
    local chunks = { { " ▸ ", "NoworkQfVirt" } }
    for i, t in ipairs(texts) do
      if i > 1 then chunks[#chunks + 1] = { " | ", "NoworkQfVirt" } end
      local tag = t:match("^%[(%w+)[:%]]")
      local hl = (tag and TAG_HL[tag]) or "NoworkQfVirt"
      local icon = tag and TAG_ICON[tag]
      if icon then
        chunks[#chunks + 1] = { icon .. " ", hl }
      end
      chunks[#chunks + 1] = { t, hl }
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum - 1, 0, {
      virt_text = chunks,
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end
end

function M.apply_all()
  if not enabled then return end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.apply(buf)
    end
  end
end

function M.toggle()
  enabled = not enabled
  if not enabled then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      M.clear(buf)
    end
    vim.notify("nowork qf virt: off", vim.log.levels.INFO)
  else
    M.apply_all()
    vim.notify("nowork qf virt: on", vim.log.levels.INFO)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("NoworkQfVirt", { clear = true })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost", "BufEnter" }, {
    group = group,
    callback = function(args)
      vim.schedule(function() 
        M.apply(args.buf) 
        M.apply_focus(args.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "NoworkQfChanged",
    callback = function() M.apply_all() end,
  })

  vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    group = group,
    callback = function() vim.schedule(M.apply_all) end,
  })
end

return M
