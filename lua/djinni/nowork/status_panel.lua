local lifecycle = require("djinni.nowork.state")

local M = {}

M._autocmd_registered = false
M._float_buf = nil
M._float_win = nil

local function format_elapsed(seconds)
  if not seconds or seconds < 0 then return nil end
  if seconds < 60 then
    return seconds .. "s"
  end
  local m = math.floor(seconds / 60)
  local s = seconds % 60
  return m .. "m" .. s .. "s"
end

local function attention_line(d, now)
  local s = d.state or {}
  local id = "[" .. (d.id or "?") .. "]"

  if d.status == "running" then
    local elapsed = d.started_at and format_elapsed(now - d.started_at)
    return elapsed and (id .. " running " .. elapsed) or (id .. " running")
  end

  local perms = s.pending_permissions or {}
  if #perms > 0 then
    return id .. " perm!" .. #perms
  end

  local disc = s.discussion or {}
  if disc.pending_prompt and disc.staged_input then
    return id .. " req+"
  elseif disc.pending_prompt or disc.staged_input then
    return id .. " req"
  end

  return nil
end

local function build_lines()
  local droid_mod = require("djinni.nowork.droid")
  local entries = {}
  for _, d in pairs(droid_mod.active) do
    if not lifecycle.is_finished(d) then
      entries[#entries + 1] = d
    end
  end
  if #entries == 0 then return nil end
  table.sort(entries, function(a, b) return a.id < b.id end)

  local now = os.time()
  local lines = {}
  for _, d in ipairs(entries) do
    local line = attention_line(d, now)
    if line then lines[#lines + 1] = line end
  end
  if #lines == 0 then return nil end
  return lines
end

local function ensure_buf()
  if M._float_buf and vim.api.nvim_buf_is_valid(M._float_buf) then return end
  M._float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._float_buf].buftype = "nofile"
  vim.bo[M._float_buf].bufhidden = "hide"
  vim.bo[M._float_buf].swapfile = false
end

local function show_float(lines)
  ensure_buf()
  vim.api.nvim_buf_set_lines(M._float_buf, 0, -1, false, lines)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local height = #lines
  local col = math.max(0, vim.o.columns - width - 1)
  local cfg = {
    relative = "editor",
    row = 0,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    focusable = false,
    zindex = 50,
    noautocmd = true,
  }
  if M._float_win and vim.api.nvim_win_is_valid(M._float_win) then
    cfg.noautocmd = nil
    vim.api.nvim_win_set_config(M._float_win, cfg)
  else
    M._float_win = vim.api.nvim_open_win(M._float_buf, false, cfg)
    vim.wo[M._float_win].winhighlight = "Normal:Comment,NormalFloat:Comment"
    vim.wo[M._float_win].winblend = 0
  end
end

local function hide_float()
  if M._float_win and vim.api.nvim_win_is_valid(M._float_win) then
    pcall(vim.api.nvim_win_close, M._float_win, true)
  end
  M._float_win = nil
end

local function ensure_autocmds()
  if M._autocmd_registered then return end
  M._autocmd_registered = true
  local group = vim.api.nvim_create_augroup("NoworkStatusPanel", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "TabEnter", "BufWritePost" }, {
    group = group,
    callback = function() M.update() end,
  })
end

function M.hide()
  hide_float()
end

function M.update()
  ensure_autocmds()
  local lines = build_lines()
  if not lines then
    hide_float()
  else
    show_float(lines)
  end
  pcall(vim.cmd, "redrawstatus")
end

return M
