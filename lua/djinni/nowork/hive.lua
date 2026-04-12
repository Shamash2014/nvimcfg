local chat = require("djinni.nowork.chat")
local session = require("djinni.acp.session")

local M = {}

-- Letter <-> buf mapping (the only new state)
M._buf_for = {} -- letter -> buf
M._letter = {} -- buf -> letter
M._active = nil -- active letter
M._annotations = {} -- bufnr -> { { start_line, end_line, text } }

local function get_root()
  local ok, utils = pcall(require, "core.utils")
  if ok and utils.get_project_root then return utils.get_project_root() end
  return vim.fn.getcwd()
end

local function get_buf_status(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return "done" end
  if chat._streaming[buf] then return "running" end
  if chat._pending_permission[buf] then return "permission" end
  if chat._waiting_input and chat._waiting_input[buf] then return "idle" end
  if chat._sessions[buf] or chat.get_session_id(buf) then return "idle" end
  return "done"
end

function M.assign(letter, buf)
  local old = M._buf_for[letter]
  if old then M._letter[old] = nil end
  M._buf_for[letter] = buf
  M._letter[buf] = letter
  if not M._active then M._active = letter end
end

function M.start(letter, opts)
  opts = opts or {}
  local buf = chat.create(opts.root or get_root(), {
    title = opts.label or ("hive-" .. letter),
    no_send = true,
    no_open = opts.no_open,
  })
  if not buf then return end
  M.assign(letter, buf)
  require("djinni.nowork.panel").schedule_render()
end

function M.stop(letter)
  if letter == "*" then
    for l in pairs(M._buf_for) do M.stop(l) end
    return
  end
  local buf = M._buf_for[letter]
  if not buf then return end
  local sid = chat._sessions[buf] or chat.get_session_id(buf)
  if sid then session.interrupt(nil, sid, nil) end
  M._letter[buf] = nil
  M._buf_for[letter] = nil
  if M._active == letter then M._active = next(M._buf_for) end
  require("djinni.nowork.panel").schedule_render()
end

function M.switch(letter)
  if not M._buf_for[letter] then
    vim.notify("[hive] no agent " .. letter, vim.log.levels.WARN)
    return
  end
  M._active = letter
  require("djinni.nowork.panel").schedule_render()
end

function M.active_buf()
  if not M._active then return nil end
  local buf = M._buf_for[M._active]
  if buf and vim.api.nvim_buf_is_valid(buf) then return buf end
  return nil
end

function M.list()
  local result = {}
  for letter, buf in pairs(M._buf_for) do
    if vim.api.nvim_buf_is_valid(buf) then
      table.insert(result, {
        letter = letter,
        buf = buf,
        active = letter == M._active,
        status = get_buf_status(buf),
      })
    end
  end
  table.sort(result, function(a, b) return a.letter < b.letter end)
  return result
end

function M.tell(msg)
  local buf = M.active_buf()
  if not buf then
    vim.notify("[hive] no active agent", vim.log.levels.WARN)
    return
  end
  chat.send(buf, msg)
end

function M.approve()
  local buf = M.active_buf()
  if buf and chat._pending_permission[buf] then
    chat._permission_action(buf, "allow")
  end
end

function M.paste()
  local buf = M.active_buf()
  if not buf then
    vim.notify("[hive] no active agent", vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local code_lines = {}
  local in_fence = false
  for _, line in ipairs(lines) do
    if line:match("^```") then
      if in_fence then
        in_fence = false
      else
        in_fence = true
        code_lines = {}
      end
    elseif in_fence then
      table.insert(code_lines, line)
    end
  end
  if #code_lines == 0 then
    vim.notify("[hive] no code block found", vim.log.levels.WARN)
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, code_lines)
end

function M.replay()
  local buf = M.active_buf()
  if not buf then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local last_start, last_end, in_you
  for i, line in ipairs(lines) do
    if line:match("^@You") then
      in_you = true
      last_start = i
      last_end = i
    elseif in_you then
      if line:match("^@") or line:match("^---$") then
        in_you = false
      else
        last_end = i
      end
    end
  end
  if not last_start then return end
  local msg = {}
  for i = last_start + 1, last_end do table.insert(msg, lines[i]) end
  local text = table.concat(msg, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
  if text ~= "" then chat.send(buf, text) end
end

function M.perm_to_qf()
  local items = {}
  for letter, buf in pairs(M._buf_for) do
    local perm = chat._pending_permission[buf]
    if perm then
      table.insert(items, {
        bufnr = buf, lnum = 1,
        text = ("[%s] %s: %s"):format(letter, perm.tool_kind or "tool", perm.tool_desc or "permission needed"),
      })
    end
  end
  if #items == 0 then
    vim.notify("[hive] no pending permissions", vim.log.levels.INFO)
    return
  end
  vim.fn.setqflist({}, "a", { title = "Hive Permissions", items = items })
  vim.cmd("copen")
end

function M.resp_to_loclist()
  local buf = M.active_buf()
  if not buf then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local items = {}
  for i, line in ipairs(lines) do
    if line:match("^@Djinni") or line:match("^@Agent") then
      table.insert(items, { bufnr = buf, lnum = i, text = lines[i + 1] or line })
    end
  end
  if #items == 0 then
    vim.notify("[hive] no responses found", vim.log.levels.INFO)
    return
  end
  vim.fn.setloclist(0, {}, "a", { title = "Hive Responses", items = items })
  vim.cmd("lopen")
end

-- ga{motion}: give code to active agent
function M._give_operatorfunc(_)
  local start_line = vim.fn.line("'[")
  local end_line = vim.fn.line("']")
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":~:.")

  local anns = M._consume_annotations(bufnr, start_line, end_line)
  local parts = {}
  for _, ann in ipairs(anns) do
    table.insert(parts, ann.text)
  end
  if #anns > 0 then table.insert(parts, "") end
  table.insert(parts, ("```%s %s:%d-%d"):format(vim.bo[bufnr].filetype or "", rel, start_line, end_line))
  vim.list_extend(parts, lines)
  table.insert(parts, "```")
  M.tell(table.concat(parts, "\n"))
end

function M.give()
  vim.o.operatorfunc = "v:lua.require'djinni.nowork.hive'._give_operatorfunc"
  return "g@"
end

-- gn{motion}: annotate code
function M._annotate_operatorfunc(_)
  local start_line = vim.fn.line("'[")
  local end_line = vim.fn.line("']")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.ui.input({ prompt = "Annotation: " }, function(text)
    if not text or text == "" then return end
    if not M._annotations[bufnr] then M._annotations[bufnr] = {} end
    table.insert(M._annotations[bufnr], { start_line = start_line, end_line = end_line, text = text })
  end)
end

function M.annotate()
  vim.o.operatorfunc = "v:lua.require'djinni.nowork.hive'._annotate_operatorfunc"
  return "g@"
end

function M._consume_annotations(bufnr, start_line, end_line)
  local anns = M._annotations[bufnr]
  if not anns then return {} end
  local hit, keep = {}, {}
  for _, a in ipairs(anns) do
    if a.start_line <= end_line and a.end_line >= start_line then
      table.insert(hit, a)
    else
      table.insert(keep, a)
    end
  end
  M._annotations[bufnr] = #keep > 0 and keep or nil
  return hit
end

function M.statusline()
  local agents = M.list()
  if #agents == 0 then return "" end
  local icons = { running = "●", permission = "⚡", idle = "◆", done = "✓" }
  local parts = {}
  for _, a in ipairs(agents) do
    table.insert(parts, (a.active and "*" or " ") .. a.letter .. (icons[a.status] or "○"))
  end
  return "[" .. table.concat(parts, "") .. "]"
end

function M.command(args, bang)
  if bang then return M.approve() end
  local cmd = args:match("^(%S+)")
  local rest = args:match("^%S+%s+(.+)$")
  if not cmd or cmd == "" then return end

  if cmd == "open" then require("djinni.nowork.panel").toggle()
  elseif cmd == "paste" then M.paste()
  elseif cmd == "replay" then M.replay()
  elseif cmd == "perm" then M.perm_to_qf()
  elseif cmd == "resp" then M.resp_to_loclist()
  elseif cmd == "+" then
    if not rest then return vim.notify("[hive] usage: :H + {letter} [label]", vim.log.levels.WARN) end
    local letter = rest:match("^(%a)")
    local label = rest:match("^%a%s+(.+)$")
    if letter then M.start(letter, { label = label }) end
  elseif cmd == "-" then
    M.stop(rest or M._active or "")
  else
    M.tell(args)
  end
end

return M
