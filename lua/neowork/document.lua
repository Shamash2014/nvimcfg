local M = {}

local config = require("neowork.config")
local store = require("neowork.store")
local util = require("neowork.util")
local const = require("neowork.const")

M._fm_end_cache = {}
M._attached = {}
M._refold_pending = {}
M._scan_cache = {}
M._hl_timer = {}

local augroup = vim.api.nvim_create_augroup("NeoworkDocument", { clear = true })

local function scan_cache(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = M._scan_cache[buf]
  if not c or c.tick ~= tick then
    c = { tick = tick }
    M._scan_cache[buf] = c
  end
  return c
end

function M.create(root, opts)
  opts = opts or {}
  local slug = opts.slug or util.unique_slug(root, "session-" .. os.date("!%Y%m%dT%H%M%S"))
  local meta = {
    project = opts.project or vim.fn.fnamemodify(root, ":t"),
    root = root,
    session = opts.session or "",
    provider = opts.provider or config.get("provider"),
    model = opts.model or config.get("model"),
    status = "idle",
    created = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    tokens = "0",
    cost = "0.00",
    parent = opts.parent or "",
  }
  return store.write_session_file(root, slug, meta)
end

function M.open(filepath, opts)
  opts = opts or {}
  local split = opts.split or "edit"
  vim.cmd(split .. " " .. vim.fn.fnameescape(filepath))
  local buf = vim.api.nvim_get_current_buf()

  local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  if first ~= "---" and vim.fn.filereadable(filepath) == 1 then
    vim.cmd("silent! edit!")
    buf = vim.api.nvim_get_current_buf()
    first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  end
  if first ~= "---" then
    vim.notify("neowork: session file has no frontmatter: " .. filepath, vim.log.levels.WARN)
  end

  M.attach(buf)
  require("neowork.keymaps").setup_document_keymaps(buf)
  M.goto_compose(buf)
  return buf
end

function M.goto_compose(buf)
  local compose = M.find_compose_line(buf)
  if not compose then return end
  local target = compose + 1
  local lc = vim.api.nvim_buf_line_count(buf)
  if target > lc then
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, { "" })
    target = lc + 1
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { target, 0 })
end

function M.attach(buf)
  if M._attached[buf] then return end
  M._attached[buf] = true

  vim.b[buf].neowork_chat = true
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = ""
  vim.bo[buf].modifiable = true
  vim.bo[buf].swapfile = false
  vim.bo[buf].fileencoding = "utf-8"
  vim.bo[buf].textwidth = 120
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].conceallevel = 2
      vim.wo[win].concealcursor = "nvic"
    end
  end
  pcall(require("neowork.fold").attach_window, buf)
  pcall(require("neowork.statuscol").attach_window, buf)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    buffer = buf,
    callback = function()
      pcall(require("neowork.fold").attach_window, buf)
      pcall(require("neowork.statuscol").attach_window, buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = augroup,
    buffer = buf,
    callback = function() M.detach(buf) end,
  })

  local root = M.read_frontmatter_field(buf, "root")
  if not root or root == "" then
    local filepath = vim.api.nvim_buf_get_name(buf)
    local dir = vim.fn.fnamemodify(filepath, ":h")
    if vim.fn.fnamemodify(dir, ":t") == ".neowork" then
      root = vim.fn.fnamemodify(dir, ":h")
  else
      root = vim.fn.getcwd()
    end
  end
  require("neowork.scheduler").register_root(root)
  pcall(M.apply_frontmatter_overrides, buf)
  pcall(function() require("neowork.bridge").seed_mode_from_frontmatter(buf) end)

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_call(win, function()
      vim.cmd("lcd " .. vim.fn.fnameescape(root))
    end)
    vim.wo[win].foldminlines = 0
    vim.wo[win].winbar = ""
    vim.wo[win].statusline = "%{%v:lua.require'neowork.summary'.statusline()%}"
    vim.wo[win].conceallevel = 2
    vim.wo[win].concealcursor = "nc"
    vim.wo[win].cursorline = true
    vim.wo[win].colorcolumn = ""
    vim.wo[win].winhighlight = "Normal:NeoworkWindow,NormalNC:NeoworkWindow,EndOfBuffer:NeoworkWindow,CursorLine:NeoworkCursorLine,Folded:NeoworkFolded"
  end

  M._fm_end_cache[buf] = nil

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b)
      M._fm_end_cache[b] = nil
    end,
    on_detach = function(_, b)
      M._fm_end_cache[b] = nil
      require("neowork.ast").invalidate(b)
    end,
  })

  M.compute_folds(buf)

  local hl = require("neowork.highlight")
  hl.apply(buf)
  require("neowork.summary").render_inline(buf)

  local hl_timer = vim.uv.new_timer()
  M._hl_timer[buf] = hl_timer
  local hl_fire = vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local ok, ast_mod = pcall(require, "neowork.ast")
    if ok then
      local turn = ast_mod.active_djinni_turn(buf)
      if turn then
        pcall(hl.apply, buf, turn.start_line - 1, turn.end_line)
        return
      end
    end
    pcall(hl.apply, buf)
  end)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      local t = M._hl_timer[buf]
      if not t then return end
      pcall(function() t:stop() end)
      pcall(function() t:start(80, 0, hl_fire) end)
    end,
  })

  local fm_sid = M.read_frontmatter_field(buf, "session") or ""
  if fm_sid == "" then
    pcall(M.set_frontmatter_field, buf, "session", "")
  end

  M.ensure_composer(buf)

  local bridge = require("neowork.bridge")
  local cb = function(err)
    if err then
      vim.schedule(function()
        vim.notify("neowork: session attach failed — " .. tostring(err.message or err), vim.log.levels.ERROR)
      end)
      return
    end
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        M.ensure_composer(buf)
      end
    end)
  end
  if fm_sid ~= "" then
    bridge.resume_session(buf, fm_sid, cb)
  else
    bridge.create_session(buf, cb)
  end
end

function M.get_fm_end(buf)
  if M._fm_end_cache[buf] then
    return M._fm_end_cache[buf]
  end
  local ast = require("neowork.ast")
  local fm_end = ast.frontmatter_end(buf)
  if fm_end and fm_end > 0 then
    M._fm_end_cache[buf] = fm_end
    return fm_end
  end
  return nil
end

function M.read_frontmatter_field(buf, key)
  return require("neowork.ast").read_frontmatter_field(buf, key)
end

local FRONTMATTER_OVERRIDE_KEYS = { "provider", "model" }

function M.apply_frontmatter_overrides(buf)
  local ok_cfg, config = pcall(require, "neowork.config.init")
  if not ok_cfg then return end
  local ast = require("neowork.ast")
  local fm = ast.frontmatter(buf)
  if not next(fm) then return end
  local writer = config.prepare_frontmatter(buf)
  for _, key in ipairs(FRONTMATTER_OVERRIDE_KEYS) do
    local v = fm[key]
    if v ~= nil and v ~= "" then
      pcall(function() writer[key] = v end)
    end
  end
  pcall(function() config.finalize(config.LAYERS.FRONTMATTER, nil, buf) end)
end

function M.set_frontmatter_field(buf, key, value)
  M.set_frontmatter_fields(buf, { [key] = value })
end

function M.set_frontmatter_fields(buf, fields)
  local fm_end = M.get_fm_end(buf)
  if not fm_end then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, fm_end, false)
  local pending = {}
  for k, v in pairs(fields) do pending[k] = (tostring(v)):gsub("[\r\n]+", " ") end
  local changed = false
  local summary_changed = false

  for i = 2, #lines do
    local k, v = lines[i]:match("^(%w[%w_-]*):%s*(.*)$")
    if k and pending[k] ~= nil then
      local new_val = pending[k]
      if v ~= new_val then
        lines[i] = k .. ": " .. new_val
        changed = true
        if k == "summary" then summary_changed = true end
      end
      pending[k] = nil
    end
  end

  local appended = false
  for k, v in pairs(pending) do
    lines[#lines] = k .. ": " .. v
    lines[#lines + 1] = "---"
    appended = true
    changed = true
    if k == "summary" then summary_changed = true end
  end

  if not changed then return end

  vim.api.nvim_buf_set_lines(buf, 0, fm_end, false, lines)
  M._fm_end_cache[buf] = nil
  if appended or summary_changed then
    require("neowork.summary").render_inline(buf)
  end
end

function M.ensure_composer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local ast = require("neowork.ast")
  local turns = ast.turns(buf) or {}
  local lc = vim.api.nvim_buf_line_count(buf)

  local last_you
  for i = #turns, 1, -1 do
    if turns[i].role == "You" then last_you = turns[i]; break end
  end

  if not last_you then
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, { "", "# You", "", "---" })
    return
  end

  local has_terminator = false
  for i = last_you.content_start, last_you.end_line do
    local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if line == "---" then has_terminator = true; break end
  end
  if not has_terminator then
    vim.api.nvim_buf_set_lines(buf, lc, lc, false, { "---" })
  end
end

function M.find_last_role_row(buf, role)
  local compose = M.find_compose_line(buf)
  local upper
  if compose then
    upper = compose - 2
  else
    upper = vim.api.nvim_buf_line_count(buf) - 1
  end
  local pat = "^@" .. role
  for i = upper, 0, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
    if line and line:match(pat) then return i end
  end
  return nil
end

function M.truncate_after_user_row(buf, user_row)
  local total = vim.api.nvim_buf_line_count(buf)
  local sep_after
  for i = user_row + 1, total - 1 do
    local l = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1] or ""
    if l == "---" then sep_after = i break end
  end
  if not sep_after then return end

  local compose = M.find_compose_line(buf)
  if not compose then return end
  local composer_you = compose - 1
  local sep_before_composer = composer_you - 1
  if sep_before_composer <= sep_after then return end

  local lstart = sep_after + 1
  local lend = sep_before_composer
  if lend <= lstart then return end
  vim.api.nvim_buf_set_lines(buf, lstart, lend, false, {})
end

function M.find_compose_line(buf)
  local c = scan_cache(buf)
  if c.compose ~= nil then
    return c.compose or nil
  end
  local ast = require("neowork.ast")
  local turn = ast.compose_turn(buf)
  if turn then
    c.compose = turn.start_line
    return turn.start_line
  end
  c.compose = false
  return nil
end

function M.invalidate_compose_cache(buf)
  local c = scan_cache(buf)
  c.compose = nil
end

---@param buf integer
---@param start_row integer|nil 0-based inclusive, default 0
---@param end_row integer|nil 0-based exclusive, default -1 (end)
---@return string
function M.buffer_to_string(buf, start_row, end_row)
  local lines = vim.api.nvim_buf_get_lines(buf, start_row or 0, end_row or -1, false)
  local text = table.concat(lines, "\n")
  if #lines > 0 and vim.bo[buf].eol then
    text = text .. "\n"
  end
  return text
end

function M.get_compose_text(buf)
  local compose = M.find_compose_line(buf)
  if not compose then return "" end
  local lc = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, compose, lc, false)
  local content = {}
  for _, l in ipairs(lines) do
    if l == "---" then break end
    content[#content + 1] = l
  end
  return vim.trim(table.concat(content, "\n"))
end

function M.clear_compose(buf)
  local compose = M.find_compose_line(buf)
  if not compose then return end
  local lc = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, compose, lc, false)
  local stop = lc
  for i, l in ipairs(lines) do
    if l == "---" then
      stop = compose + i - 1
      break
    end
  end
  vim.api.nvim_buf_set_lines(buf, compose, stop, false, { "" })
end

function M.clear(buf, opts)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local sid = M.read_frontmatter_field(buf, "session") or ""
  local root = M.read_frontmatter_field(buf, "root") or vim.fn.getcwd()

  local ok_bridge, bridge = pcall(require, "neowork.bridge")
  if ok_bridge then
    pcall(bridge.detach, buf, { session_id = sid })
  end

  local ok_stream, stream = pcall(require, "neowork.stream")
  if ok_stream then pcall(stream.reset, buf) end

  local ok_plan, plan = pcall(require, "neowork.plan")
  if ok_plan then pcall(plan.detach, buf) end

  local ok_hl, hl = pcall(require, "neowork.highlight")
  if ok_hl and hl.ns then
    pcall(vim.api.nvim_buf_clear_namespace, buf, hl.ns, 0, -1)
  end
  for _, name in ipairs({ "neowork_summary_inline" }) do
    local nns = vim.api.nvim_create_namespace(name)
    pcall(vim.api.nvim_buf_clear_namespace, buf, nns, 0, -1)
  end

  local fm_end = M.get_fm_end(buf)
  if fm_end then
    local lc = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, fm_end, lc, false, { "", "# You", "", "---" })
  end

  M.set_frontmatter_fields(buf, {
    session = "",
    status = const.session_status.ready,
    tokens = "0",
    cost = "0.00",
  })
  require("neowork.summary").clear(buf)
  M._fm_end_cache[buf] = nil

  if opts.purge_transcript and sid ~= "" then
    pcall(store.clear_transcript, sid, root)
    require("neowork.summary").reset_tool_count(sid)
  end

  if vim.bo[buf].modified then pcall(vim.cmd, "silent! write") end

  if ok_hl then pcall(hl.apply, buf) end
  pcall(require("neowork.summary").render_inline, buf)
  M.goto_compose(buf)

  if opts.start_session ~= false and ok_bridge then
    bridge.create_session(buf, function(err)
      if err then
        vim.schedule(function()
          vim.notify("neowork: clear — new session failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
        end)
      end
    end)
  end
end

function M.fork_at_cursor(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)

  local ast = require("neowork.ast")
  local turn_start
  for i = #lines, 1, -1 do
    local l = lines[i]
    if ast.role_of_line(l) ~= nil then
      turn_start = i
      break
    end
  end
  if not turn_start then
    vim.notify("neowork: no turn at cursor to fork from", vim.log.levels.WARN)
    return
  end

  local fm_end = M.get_fm_end(buf)
  if not fm_end then
    vim.notify("neowork: missing frontmatter", vim.log.levels.WARN)
    return
  end

  local body_end = turn_start - 1
  while body_end > fm_end do
    local l = vim.api.nvim_buf_get_lines(buf, body_end - 1, body_end, false)[1] or ""
    if l == "" or l == "---" then
      body_end = body_end - 1
    else
      break
    end
  end

  local body = {}
  if body_end > fm_end then
    body = vim.api.nvim_buf_get_lines(buf, fm_end, body_end, false)
  end

  do
    local root = M.read_frontmatter_field(buf, "root") or vim.fn.getcwd()
    local orig_path = vim.api.nvim_buf_get_name(buf)
    local orig_slug = vim.fn.fnamemodify(orig_path, ":t:r")
    local slug = orig_slug .. "-fork-" .. os.date("!%Y%m%dT%H%M%S")

    local neowork_dir = config.get_neowork_dir(root)
    store.ensure_dirs(root)
    local filepath = neowork_dir .. "/" .. slug .. ".md"

    local out = {
      "---",
      "project: " .. (M.read_frontmatter_field(buf, "project") or vim.fn.fnamemodify(root, ":t")),
      "root: " .. root,
      "session: ",
      "provider: " .. (M.read_frontmatter_field(buf, "provider") or config.get("provider")),
      "model: " .. (M.read_frontmatter_field(buf, "model") or config.get("model")),
      "status: idle",
      "created: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
      "tokens: 0",
      "cost: 0.00",
      "summary: fork of " .. orig_slug,
      "parent: " .. orig_slug,
      "---",
      "",
    }
    for _, l in ipairs(body) do
      out[#out + 1] = l
    end
    if #body == 0 or out[#out] ~= "" then out[#out + 1] = "" end
    out[#out + 1] = "---"
    out[#out + 1] = ""
    out[#out + 1] = "# You"
    out[#out + 1] = ""
    out[#out + 1] = "---"

    local fd = io.open(filepath, "w")
    if not fd then
      vim.notify("neowork: failed to write fork file", vim.log.levels.ERROR)
      return
    end
    fd:write(table.concat(out, "\n") .. "\n")
    fd:close()

    M.open(filepath)
    vim.notify("neowork: forked → " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
  end
end

local function trim_trailing_blanks(buf, stop_row)
  local row = stop_row
  while row > 0 do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    if line ~= "" then break end
    row = row - 1
  end
  return row
end

function M.insert_turn(buf, role, text)
  local compose = M.find_compose_line(buf)
  if not compose then return end
  local body_end = trim_trailing_blanks(buf, compose - 1)
  local ast = require("neowork.ast")
  local lines = { "", "", "# " .. role }
  if text and text ~= "" then
    lines[#lines + 1] = ""
    for _, l in ipairs(vim.split(text, "\n", { plain = true })) do
      lines[#lines + 1] = ast.escape_role_line(l)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ""
  lines[#lines + 1] = "---"
  lines[#lines + 1] = ""
  lines[#lines + 1] = ""
  vim.api.nvim_buf_set_lines(buf, body_end, compose - 1, false, lines)
  require("neowork.summary").render_inline(buf)
  ast.assert_invariant(buf, "document.insert_turn(" .. role .. ")")
end

function M.commit_compose(buf)
  local text = M.get_compose_text(buf)
  local ast = require("neowork.ast")
  local compose = ast.compose_turn(buf)
  local lc = vim.api.nvim_buf_line_count(buf)

  local body_end = lc
  local floor = compose and compose.start_line or 0
  while body_end > floor do
    local line = vim.api.nvim_buf_get_lines(buf, body_end - 1, body_end, false)[1] or ""
    if line ~= "" and line ~= "---" then break end
    body_end = body_end - 1
  end

  vim.api.nvim_buf_set_lines(buf, body_end, lc, false, { "", "", "---", "", "", "# You", "" })
  require("neowork.summary").render_inline(buf)
  ast.assert_invariant(buf, "document.commit_compose")
  return text
end

function M.insert_djinni_turn(buf)
  M.insert_turn(buf, "Djinni", "")
  return M.find_djinni_tail(buf)
end

function M.find_djinni_tail(buf)
  local c = scan_cache(buf)
  if c.tail ~= nil then
    return c.tail or nil
  end
  local ast = require("neowork.ast")
  local insert_row = ast.insertion_row_for_streaming(buf)
  if insert_row then
    c.tail = insert_row
    return insert_row
  end
  local compose = M.find_compose_line(buf)
  if not compose then
    c.tail = false
    return nil
  end
  local fm_end = M.get_fm_end(buf) or 0
  local closing_row
  for i = compose - 2, fm_end, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
    if line == "___" then
      closing_row = i
      break
    end
    local ast = require("neowork.ast")
    if line and (ast.role_of_line(line) == "You" or ast.role_of_line(line) == "System") then
      c.tail = false
      return nil
    end
  end
  if not closing_row then
    c.tail = false
    return nil
  end
  c.tail = closing_row
  return closing_row
end

function M.count_turns(buf)
  local ast = require("neowork.ast")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local count = 0
  for _, turn in ipairs(ast.turns(buf)) do
    if turn.role == "You" and not turn.is_compose then
      for i = turn.content_start, turn.end_line do
        if lines[i] and vim.trim(lines[i]) ~= "" then
          count = count + 1
          break
        end
      end
    end
  end
  return count
end

function M.compact(buf)
  local max_turns = config.get_max_turns()
  local current = M.count_turns(buf)
  if current <= max_turns then return end

  local fm_end = M.get_fm_end(buf) or 0
  local to_remove = current - max_turns

  for _ = 1, to_remove do
    local line_count = vim.api.nvim_buf_line_count(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, fm_end, line_count, false)
    local ast = require("neowork.ast")
    local first_you = nil
    for i, line in ipairs(lines) do
      if ast.role_of_line(line) == "You" then
        first_you = fm_end + i - 1
        break
      end
    end
    if not first_you then break end

    local block_end = nil
    local abs_lines = vim.api.nvim_buf_get_lines(buf, first_you, line_count, false)
    for i, line in ipairs(abs_lines) do
      if i > 1 and (ast.role_of_line(line) ~= nil or line == "---") then
        block_end = first_you + i - 2
        break
      end
    end
    if not block_end then
      block_end = line_count - 1
    end

    local agent_start = nil
    local post_lines = vim.api.nvim_buf_get_lines(buf, block_end, line_count, false)
    for i, line in ipairs(post_lines) do
      if ast.role_of_line(line) == "Djinni" then
        agent_start = block_end + i - 1
        break
      elseif ast.role_of_line(line) == "You" or ast.role_of_line(line) == "System" then
        break
      end
    end

    local remove_end
    if agent_start then
      local agent_post = vim.api.nvim_buf_get_lines(buf, agent_start, line_count, false)
      remove_end = nil
      for i, line in ipairs(agent_post) do
        if i > 1 and (ast.role_of_line(line) ~= nil or line == "---") then
          remove_end = agent_start + i - 2
          break
        end
      end
      if not remove_end then
        remove_end = line_count - 1
      end
    else
      remove_end = block_end
    end

    vim.api.nvim_buf_set_lines(buf, first_you - 1, remove_end, false, {})
  end
end

local role_of = util.role_of

local function collect_turns(lines, fm_end)
  local turns = {}
  for i = (fm_end or 0) + 1, #lines do
    local role = role_of(lines[i])
    if role then
      turns[#turns + 1] = { role = role, start = i }
    end
  end
  for idx, t in ipairs(turns) do
    local next_start = turns[idx + 1] and turns[idx + 1].start or (#lines + 1)
    local e = next_start - 1
    while e > t.start and (lines[e] == "" or lines[e] == nil) do
      e = e - 1
    end
    t["end"] = e
  end
  return turns
end

function M.compute_folds(buf)
  pcall(require("neowork.fold").invalidate, buf)
end

function M.detach(buf)
  M._attached[buf] = nil
  M._fm_end_cache[buf] = nil
  M._refold_pending[buf] = nil
  M._scan_cache[buf] = nil
  pcall(function() require("neowork.ast").invalidate(buf) end)
  local t = M._hl_timer[buf]
  if t then
    pcall(function() t:stop() end)
    pcall(function() t:close() end)
    M._hl_timer[buf] = nil
  end
end

function M.schedule_refold(buf)
  if M._refold_pending[buf] then return end
  M._refold_pending[buf] = true
  vim.defer_fn(function()
    M._refold_pending[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(M.compute_folds, buf)
    end
  end, 75)
end

function M.foldtext()
  local ast = require("neowork.ast")
  local foldstart = vim.v.foldstart
  local foldend = vim.v.foldend
  local line = vim.fn.getline(foldstart)
  local count = foldend - foldstart + 1
  if line == "---" then
    return "─── frontmatter ───"
  end
  local role = ast.role_of_line(line)
  if role == "You" then
    return "▸ ## You — " .. count .. " lines"
  elseif role == "Djinni" then
    return "▸ ## Djinni — " .. count .. " lines"
  elseif role == "System" then
    return "▸ ## System — " .. count .. " lines"
  elseif line:match("^>") then
    return "▸ thinking..."
  elseif line:match("^%[%*%]") then
    return "▸ " .. line:sub(5)
  elseif line:match("^### Plan") then
    return "▸ plan"
  end
  return line .. " (" .. count .. " lines)"
end

return M
