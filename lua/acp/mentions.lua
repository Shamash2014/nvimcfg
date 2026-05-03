local M = {}

local function resolve_at_token(path, cwd)
  if not path or path == "" then return nil end

  if path:sub(1, 1) == "/" or path:sub(1, 2) == "./" or path:sub(1, 3) == "../" or path:sub(1, 1) == "~" then
    local expanded = vim.fn.fnamemodify(path, ":p")
    local stat = vim.loop.fs_stat(expanded)
    if stat and stat.type == "file" then
      local ok, content = pcall(vim.fn.readfile, expanded)
      if ok then return table.concat(content, "\n") end
    end
    return nil
  end

  local rel_path = cwd .. "/" .. path
  local stat = vim.loop.fs_stat(rel_path)
  if stat and stat.type == "file" then
    local ok, content = pcall(vim.fn.readfile, rel_path)
    if ok then
      local size = #table.concat(content, "\n")
      if size > 200000 then
        vim.notify("@" .. path .. " too large, skipping (>200KB)", vim.log.levels.WARN, { title = "acp" })
        return nil
      end
      return table.concat(content, "\n")
    end
  end

  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n")
  end

  return nil
end

local function format_qf_items(items)
  if not items or #items == 0 then return nil end
  local lines = {}
  for _, item in ipairs(items) do
    local fname = (item.bufnr and item.bufnr ~= 0)
      and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.bufnr), ":.")
      or (item.filename or "?")
    table.insert(lines, ("%s:%d:%d %s"):format(
      fname, item.lnum or 0, item.col or 0, (item.text or ""):gsub("\n", " ")))
  end
  return table.concat(lines, "\n")
end

local function format_diagnostics()
  local diags = vim.diagnostic.get()
  if #diags == 0 then return nil end
  local lines = {}
  for _, d in ipairs(diags) do
    local fname = d.bufnr and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(d.bufnr), ":.") or "?"
    local sev   = vim.diagnostic.severity[d.severity] or "?"
    table.insert(lines, ("%s:%d:%d [%s] %s"):format(
      fname, (d.lnum or 0) + 1, (d.col or 0) + 1, sev, (d.message or ""):gsub("\n", " ")))
  end
  return table.concat(lines, "\n")
end

local function resolve_hash_token(tag)
  if tag == "diag" then
    local out = format_diagnostics()
    if not out then vim.notify("No diagnostics for #{diag}", vim.log.levels.INFO, { title = "acp" }) end
    return out
  elseif tag == "qflist" then
    local out = format_qf_items(vim.fn.getqflist())
    if not out then vim.notify("Quickfix empty for #{qflist}", vim.log.levels.INFO, { title = "acp" }) end
    return out
  elseif tag == "loclist" then
    local win = vim.api.nvim_get_current_win()
    local out = format_qf_items(vim.fn.getloclist(win))
    if not out then vim.notify("Loclist empty for #{loclist}", vim.log.levels.INFO, { title = "acp" }) end
    return out
  end
  return nil
end

function M.parse(text, cwd)
  local cleaned = text
  local blocks = {}
  for path in text:gmatch("@(%S+)") do
    local content = resolve_at_token(path, cwd)
    if content then
      table.insert(blocks, { type = "text", text = "--- @" .. path .. " ---\n" .. content })
      cleaned = cleaned:gsub("@" .. vim.pesc(path) .. "%s*", "")
    end
  end
  for tag in text:gmatch("#{(%w+)}") do
    local content = resolve_hash_token(tag)
    if content then
      table.insert(blocks, { type = "text", text = "--- #{" .. tag .. "} ---\n" .. content })
      cleaned = cleaned:gsub("#{" .. vim.pesc(tag) .. "}%s*", "")
    end
  end
  return vim.trim(cleaned), blocks
end

function M.parse_and_inject(text, cwd, add_context)
  local cleaned, blocks = M.parse(text, cwd)
  for _, block in ipairs(blocks) do add_context(block) end
  return cleaned
end

return M
