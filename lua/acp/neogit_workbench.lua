local M = {}

local Buffer = require("neogit.lib.buffer")
local Ui = require("neogit.lib.ui")

local _buffer = nil
local _buffer_win = nil
local _diff_win = nil
local _diff_buf = nil
local _render_timer = nil
local _uv = vim.uv or vim.loop
local _registered_autocmd = false
local unpack = table.unpack or unpack

local function set_winbar(win, title, tokens, model)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local token_str = (tokens and ("  " .. tokens)) or ""
  local model_str = (model and ("  " .. model)) or ""
  vim.wo[win].winbar = "%#AcpWinbarText#  " .. title .. token_str .. model_str .. "  %*"
end

local function ensure_diff_pane(workbench_win)
  if _diff_win and vim.api.nvim_win_is_valid(_diff_win) then
    if not _diff_buf or not vim.api.nvim_buf_is_valid(_diff_buf) then
      _diff_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[_diff_buf].buftype  = "nofile"
      vim.bo[_diff_buf].swapfile = false
      vim.api.nvim_win_set_buf(_diff_win, _diff_buf)
    end
    return _diff_win, _diff_buf
  end
  local origin = workbench_win or vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  end
  vim.cmd("rightbelow vsplit")
  _diff_win = vim.api.nvim_get_current_win()
  _diff_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_diff_buf].buftype  = "nofile"
  vim.bo[_diff_buf].swapfile = false
  vim.api.nvim_win_set_buf(_diff_win, _diff_buf)
  set_winbar(_diff_win, "diff", nil, nil)
  return _diff_win, _diff_buf
end

local function focus_diff(workbench_win)
  local win, _ = ensure_diff_pane(workbench_win)
  vim.api.nvim_set_current_win(win)
end

local function debounced_refresh()
  if _render_timer then
    _render_timer:stop()
    if not _render_timer:is_closing() then _render_timer:close() end
  end
  _render_timer = _uv.new_timer()
  local timer = _render_timer
  timer:start(80, 0, vim.schedule_wrap(function()
    if _render_timer == timer then _render_timer = nil end
    if not timer:is_closing() then timer:close() end
    M.refresh()
  end))
end

local function get_cwd()
  return vim.fn.getcwd()
end

local function render_header(cwd)
  local workbench = require("acp.workbench")
  local mailbox = require("acp.mailbox")

  local branch = workbench._cached_branch and workbench._cached_branch(cwd) or ""
  if not branch or branch == "" then
    branch = vim.fn.system("git -C " .. cwd .. " branch --show-current 2>/dev/null"):gsub("%s+$", "")
  end

  local pending_count = mailbox.pending_count()
  local header_text = "Head: " .. branch
  if pending_count and pending_count > 0 then
    header_text = header_text .. "  ! " .. pending_count .. " pending"
  end

  return Ui.text(header_text)
end

local function get_thread_items(cwd)
  local workbench = require("acp.workbench")
  local items = workbench.list(cwd)
  local result = {}
  for _, path in ipairs(items) do
    local name = vim.fn.fnamemodify(path, ":t")
    table.insert(result, {
      _type = "thread",
      _path = path,
      display = name,
    })
  end
  return result
end

local function get_context_items(cwd)
  return {}
end

local function get_pipeline_items(cwd)
  local pipeline = require("acp.pipeline")
  local runs = pipeline.list_runs(cwd, 5) or {}
  local result = {}
  for _, run in ipairs(runs) do
    table.insert(result, {
      _type = "pipeline",
      _run = run,
      display = (run.displayTitle or "?"):sub(1, 55) .. " [" .. tostring(run.databaseId or "") .. "]",
    })
  end
  return result
end

local function get_diff_items(cwd)
  local diff = require("acp.diff")
  local files = diff.list_files(cwd) or {}
  local result = {}
  for _, f in ipairs(files) do
    local status_word = ({ A = "A", M = "M", D = "D" })[f.status] or "M"
    table.insert(result, {
      _type = "diff",
      _path = f.path,
      display = status_word .. "  " .. f.path,
    })
  end
  return result
end

local function get_comment_items(cwd)
  local diff = require("acp.diff")
  local threads = diff.get_threads(cwd)
  local result = {}

  for _, entry in ipairs(threads) do
    if entry.file and entry.row and not entry.file:match("%.nowork/") and entry.row >= 0 then
      table.insert(result, {
        _type = "comment",
        _file = entry.file,
        _row = entry.row,
        _thread = entry.thread,
        display = entry.file .. ":" .. entry.row,
      })
    end
  end

  return result
end

local function create_section(title, items)
  if not items or #items == 0 then return nil end

  local rows = {}
  for _, item in ipairs(items) do
    table.insert(rows, Ui.row({
      Ui.text("  " .. item.display),
    }, {
      interactive = true,
      context = item,
    }))
  end

  local section_id = title:lower():gsub("%s+", "_")
  return Ui.col.tag("Section")({
    Ui.row({
      Ui.text(title, { highlight = "NeogitSectionHeader" }),
      Ui.text(" ("),
      Ui.text(tostring(#items), { highlight = "NeogitSectionHeaderCount" }),
      Ui.text(")"),
    }),
    Ui.col(rows),
  }, {
    foldable = true,
    folded   = false,
    section  = section_id,
  })
end

local function handle_thread_cr(item)
  M.show_thread(item._path, -1)
end

local function handle_diff_cr(item, workbench_win)
  local win, buf = ensure_diff_pane(workbench_win)
  require("acp.diff").show_file(item._path, win, buf, function(file, tokens, model)
    set_winbar(win, file, tokens, model)
    set_winbar(_buffer_win, "ACP workbench", tokens, model)
  end)
end

local function handle_pipeline_cr(item, workbench_win)
  local win, buf = ensure_diff_pane(workbench_win)
  require("acp.pipeline").open(get_cwd(), win, buf, function() end)
end

local function handle_comment_cr(item, workbench_win)
  local diff = require("acp.diff")
  local win, buf = ensure_diff_pane(workbench_win)
  diff.show_file(item._file, win, buf, function(file, tokens, model)
    set_winbar(win, file, tokens, model)
    set_winbar(_buffer_win, "ACP workbench", tokens, model)
  end)
  pcall(vim.api.nvim_win_set_cursor, win, { item._row + 1, 0 })
  diff.open_thread_view(item._row, win)
end

local function mappings()
  return {
    n = {
      ["<CR>"] = function(buf)
        local context = buf.ui:get_cursor_context()
        if not context or not context.options.context then return end

        local workbench_win = vim.api.nvim_get_current_win()
        local item = context.options.context
        if item._type == "thread" then
          handle_thread_cr(item)
        elseif item._type == "diff" then
          handle_diff_cr(item, workbench_win)
        elseif item._type == "pipeline" then
          handle_pipeline_cr(item, workbench_win)
        elseif item._type == "comment" then
          handle_comment_cr(item, workbench_win)
        end
      end,

      ["<BS>"] = function()
        require("acp.git").open_neogit({ kind = "replace" })
      end,

      ["n"] = function()
        require("acp.workbench").set(get_cwd())
      end,

      ["P"] = function()
        require("acp.workbench").pick_project()
      end,

      ["dd"] = function(buf)
        local context = buf.ui:get_cursor_context()
        if not context or not context.options.context then return end

        local item = context.options.context
        if item._type == "thread" then
          require("acp.diff").delete_thread(item._path, -1)
          pcall(os.remove, item._path)
          debounced_refresh()
        elseif item._type == "comment" then
          require("acp.diff").delete_thread(item._file, item._row)
          debounced_refresh()
        end
      end,

      ["R"] = function()
        require("acp.workbench")._branch_cache = {}
        require("acp.workbench")._wt_cache = {}
        require("acp.diff").invalidate_files(get_cwd())
        M.refresh()
      end,

      ["<tab>"] = function() vim.cmd("normal! za") end,
      ["za"]    = function() vim.cmd("normal! za") end,

      ["q"] = function(buf)
        buf:close()
      end,

      ["?"] = function()
        require("acp.workbench").show_help()
      end,
    },
  }
end

function M.render(buf)
  local cwd = get_cwd()

  local sections = {}

  table.insert(sections, Ui.col({ Ui.row({ render_header(cwd) }) }))
  table.insert(sections, Ui.col({ Ui.row({ Ui.text("") }) }))

  local thread_items = get_thread_items(cwd)
  local thread_section = create_section("Threads", thread_items)
  if thread_section then table.insert(sections, thread_section) end

  local context_items = get_context_items(cwd)
  local context_section = create_section("Context", context_items)
  if context_section then table.insert(sections, context_section) end

  local diff_items = get_diff_items(cwd)
  local diff_section = create_section("Changed files", diff_items)
  if diff_section then table.insert(sections, diff_section) end

  local pipeline_items = get_pipeline_items(cwd)
  local pipeline_section = create_section("Pipelines", pipeline_items)
  if pipeline_section then table.insert(sections, pipeline_section) end

  local comment_items = get_comment_items(cwd)
  local comment_section = create_section("Comments", comment_items)
  if comment_section then table.insert(sections, comment_section) end

  return sections
end

function M.open(opts)
  local cwd = get_cwd()

  if _buffer and _buffer:is_visible() then
    _buffer:focus()
    return
  end

  pcall(vim.cmd, "packadd neogit")

  local kind = opts and opts.kind or "tab"

  _buffer = Buffer.create({
    name = "NeogitACPWorkbench",
    filetype = "NeogitACPWorkbench",
    kind = kind,
    status_column = "",
    context_highlight = false,
    active_item_highlight = true,
    mappings = mappings(),
    render = function(buf) return M.render(buf) end,
  })

  _buffer_win = vim.api.nvim_get_current_win()
  set_winbar(_buffer_win, "ACP workbench", nil, nil)

  local workbench_win = _buffer_win
  require("acp.diff").with_files(cwd, function(files)
    if #files > 0 then
      local win, buf = ensure_diff_pane(workbench_win)
      require("acp.diff").show_file(files[1].path, win, buf, function(file, tokens, model)
        set_winbar(win, file, tokens, model)
        set_winbar(_buffer_win, "ACP workbench", tokens, model)
      end)
      if vim.api.nvim_win_is_valid(workbench_win) then
        vim.api.nvim_set_current_win(workbench_win)
      end
    end
  end)

  if not _registered_autocmd then
    _registered_autocmd = true
    vim.api.nvim_create_autocmd("User", {
      pattern = "NeogitStatusRefreshed",
      callback = function()
        debounced_refresh()
      end,
    })
  end
end

function M.refresh()
  if _buffer and _buffer:is_visible() then
    _buffer.ui:render(unpack(M.render(_buffer)))
  end
end

function M.show_thread(file, row)
  row = row or -1
  local cwd  = vim.fn.getcwd()
  local diff = require("acp.diff")

  local needle = string.format("acp-thread-%s-%s", file, row)

  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):find(needle, 1, true) then
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == b then
          vim.api.nvim_set_current_win(w); return
        end
      end
      vim.cmd("botright vsplit"); vim.api.nvim_set_current_buf(b); return
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, needle)
  vim.bo[buf].buftype  = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"

  diff.render_thread_view(buf, cwd, file, row)

  vim.cmd("botright vsplit")
  vim.api.nvim_set_current_buf(buf)

  local key  = diff.thread_session_key(cwd, file, row)
  local sess = require("acp.session").get(key)
  if sess then diff.subscribe_to_thread(sess, cwd, file, row) end

  local function km(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, noremap = true })
  end
  km("<CR>",    function() diff.reply_at(row, file) end)
  km("R",       function() diff.restart_thread(row, file) end)
  km("m",       function() require("acp.workbench").pick_mode(key) end)
  km("<S-Tab>", function() require("acp.workbench").pick_mode(key) end)
  km("M",       function() require("acp").pick_model(cwd) end)
  km("i",       function() M.refresh() end)
  km("<C-c>",   function()
    local sess = require("acp.session").get(key)
    if not sess or not sess.session_id then
      vim.notify("No active turn", vim.log.levels.WARN, { title = "acp" }); return
    end
    require("acp.mailbox").cancel_for_session(sess.session_id)
    sess.rpc:notify("session/cancel", { sessionId = sess.session_id })
    diff.append_thread_msg(cwd, file, row, { role = "system", type = "info", text = "--- canceled ---" })
    vim.notify("ACP turn canceled", vim.log.levels.INFO, { title = "acp" })
  end)
  km("q",       function() pcall(vim.api.nvim_win_close, 0, true) end)
end

function M._stop_all_timers()
  if _render_timer then
    pcall(function()
      _render_timer:stop()
      if not _render_timer:is_closing() then _render_timer:close() end
    end)
    _render_timer = nil
  end
end

return M
