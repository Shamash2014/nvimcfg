local M = {}

local ns = vim.api.nvim_create_namespace("nowork_log")

local statusline_providers = {}

function M._sl(buf)
  local fn = statusline_providers[buf]
  if not fn then return "" end
  local ok, text = pcall(fn)
  if not ok or type(text) ~= "string" then return "" end
  return vim.fn.escape(text, "%")
end

local HL = {
  turn     = "Title",
  user     = "Statement",
  agent    = "Comment",
  tool     = "DiagnosticHint",
  bracket  = "DiagnosticInfo",
  error    = "DiagnosticError",
  warn     = "DiagnosticWarn",
  done     = "DiagnosticOk",
}

local function highlight_line(buf, lnum, line)
  if line:match("^─── turn") then
    vim.api.nvim_buf_add_highlight(buf, ns, HL.turn, lnum, 0, -1)
  elseif line:match("^user:") then
    vim.api.nvim_buf_add_highlight(buf, ns, HL.user, lnum, 0, 5)
  elseif line:match("^agent:") then
    vim.api.nvim_buf_add_highlight(buf, ns, HL.agent, lnum, 0, 6)
  elseif line:match("^  ! ") then
    vim.api.nvim_buf_add_highlight(buf, ns, HL.tool, lnum, 0, -1)
  elseif line:match("^%[error%]") or line:match("^%[error ") then
    vim.api.nvim_buf_add_highlight(buf, ns, HL.error, lnum, 0, -1)
  elseif line:match("^%[warn%]") or line:match("^%[cancelled%]") then
    vim.api.nvim_buf_add_highlight(buf, ns, HL.warn, lnum, 0, -1)
  elseif line:match("^%[done%]") then
    vim.api.nvim_buf_add_highlight(buf, ns, HL.done, lnum, 0, -1)
  elseif line:match("^%[") then
    vim.api.nvim_buf_add_highlight(buf, ns, HL.bracket, lnum, 0, -1)
  end
end

function M.new(opts)
  opts = opts or {}
  local split = opts.split or "below"
  local height = opts.height or 15

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "nowork"
  vim.bo[buf].modifiable = false

  local win_id = nil

  local function find_win()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == buf then
        return w
      end
    end
    return nil
  end

  local on_append = opts.on_append

  local function append(self, lines)
    if type(lines) == "string" then
      lines = vim.split(lines, "\n", { plain = true })
    end
    vim.bo[buf].modifiable = true
    local count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, count, count, false, lines)
    vim.bo[buf].modified = false
    vim.bo[buf].modifiable = false
    for i, line in ipairs(lines) do
      highlight_line(buf, count + i - 1, line)
    end
    if on_append then
      for _, line in ipairs(lines) do
        pcall(on_append, line)
      end
    end
    local w = find_win()
    if w then
      local last = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_win_set_cursor(w, { last, 0 })
    end
  end

  local function show(self)
    if find_win() then
      return
    end
    local cmd_map = {
      below = "below " .. height .. "split",
      above = "above " .. height .. "split",
      right = "vertical rightbelow " .. height .. "split",
      left = "vertical leftabove " .. height .. "split",
    }
    vim.cmd(cmd_map[split] or ("below " .. height .. "split"))
    win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win_id, buf)
  end

  local function hide(self)
    local w = find_win()
    if w then
      vim.api.nvim_win_close(w, true)
    end
  end

  local function clear(self)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.bo[buf].modified = false
    vim.bo[buf].modifiable = false
  end

  local function apply_statusline_to_window(w)
    if w and vim.api.nvim_win_is_valid(w) then
      vim.wo[w].statusline = "%{%v:lua.require'djinni.nowork.log_buffer'._sl(" .. buf .. ")%}"
    end
  end

  local function set_statusline_provider(_, fn)
    statusline_providers[buf] = fn
    local w = find_win()
    if w then apply_statusline_to_window(w) end
    local group = vim.api.nvim_create_augroup("NoworkLogStatusline_" .. buf, { clear = true })
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinNew" }, {
      group = group,
      buffer = buf,
      callback = function()
        apply_statusline_to_window(find_win())
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = group,
      buffer = buf,
      once = true,
      callback = function()
        statusline_providers[buf] = nil
      end,
    })
  end

  local lb = { buf = buf }
  lb.append = append
  lb.show = show
  lb.hide = hide
  lb.clear = clear
  lb.set_statusline_provider = set_statusline_provider

  return lb
end

return M
