local M = {}

local function nowork_dir(cwd)
  return cwd .. "/.nowork"
end

-- Create a new work file path: .nowork/<unix_ts>-<slug>.md
function M.new_file(cwd, title)
  local dir  = nowork_dir(cwd)
  vim.fn.mkdir(dir, "p")
  local ts   = os.time()
  local slug = (title or "work"):lower():gsub("[^a-z0-9]+", "-"):sub(1, 40)
  return dir .. "/" .. ts .. "-" .. slug .. ".md"
end

-- Companion worklog path for a work file.
function M.log_path(work_path)
  return work_path:gsub("%.md$", ".log.md")
end

-- Append a line to the worklog (creates file on first write).
function M.log(work_path, line)
  if not work_path then return end
  local f = io.open(M.log_path(work_path), "a")
  if f then
    f:write(os.date("[%H:%M:%S] ") .. line .. "\n")
    f:close()
  end
end

-- Return list of all .nowork/*.md files (excluding *.log.md), sorted newest-first.
function M.list(cwd)
  local dir   = nowork_dir(cwd)
  local files = vim.fn.glob(dir .. "/*.md", false, true)
  -- exclude log files
  files = vim.tbl_filter(function(f) return not f:match("%.log%.md$") end, files)
  table.sort(files, function(a, b) return a > b end)  -- newest first
  return files
end

function M.latest(cwd)
  local l = M.list(cwd); return l[1]
end

function M.load(path)
  if not path then return nil end
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close()
  return s ~= "" and s or nil
end

-- <leader>aw: prompt for title, open a scratch nofile buffer.
-- <CR> in normal mode → persist content to .nowork file and run.
function M.set(cwd)
  cwd = cwd or vim.fn.getcwd()
  vim.ui.input({ prompt = "Work title: " }, function(title)
    if not title or title == "" then return end
    local path = M.new_file(cwd, title)

    -- Scratch nofile buffer — no disk file until <CR>
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype  = "markdown"
    vim.bo[buf].buftype   = "nofile"
    vim.bo[buf].buflisted = false
    vim.api.nvim_buf_set_name(buf, "[acp-work: " .. title .. "]")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# " .. title, "", "" })

    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd("startinsert")

    -- <CR> in normal mode: persist + run + close scratch
    vim.keymap.set("n", "<CR>", function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local f = io.open(path, "w")
      if f then f:write(table.concat(lines, "\n")); f:close() end
      vim.api.nvim_win_close(0, false)
      M.run(cwd, path)
    end, { buffer = buf, desc = "Persist and run work" })

    -- Refresh workbench when scratch is closed
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once   = true,
      callback = function()
        pcall(require("acp.workbench").render)
      end,
    })
  end)
end

-- Run from a specific file path, or latest .nowork/*.md if path is nil.
-- All agent events (tool_call, text, stop) are written to the companion .log.md.
function M.run(cwd, path)
  cwd  = cwd or vim.fn.getcwd()
  path = path or M.latest(cwd)
  local text = M.load(path)
  if not text or vim.trim(text) == "" then
    vim.notify("No work item. Use <leader>aw to create one.", vim.log.levels.WARN, { title = "acp" })
    return
  end

  M.log(path, "--- session start ---")
  local prompt = "Complete the following work item:\n\n" .. text

  require("acp.session").get_or_create(cwd, function(s_err, sess)
    if s_err then
      M.log(path, "ERROR: " .. s_err)
      vim.notify("ACP: " .. s_err, vim.log.levels.ERROR, { title = "acp" })
      return
    end

    M.log(path, "session ready: " .. sess.session_id)
    vim.notify("ACP work started", vim.log.levels.INFO, { title = "acp" })
    pcall(require("acp.workbench").render)

    sess.rpc:subscribe(sess.session_id, function(notif)
      local p      = notif.params or {}
      local update = p.update or {}
      local su     = update.sessionUpdate

      -- Tool call events → activity.lua already handles signs/virt-text;
      -- we additionally write to the worklog.
      if su == "tool_call" then
        M.log(path, "tool: " .. (update.kind or "?") .. " — " .. (update.title or ""))
        vim.schedule(function()
          require("acp.activity").on_tool_call(sess.session_id, update)
        end)
      elseif su == "tool_call_update" and update.status then
        M.log(path, "  status: " .. update.status .. " (" .. (update.toolCallId or "") .. ")")
        vim.schedule(function()
          require("acp.activity").on_tool_call_update(sess.session_id, update)
        end)
      elseif su == "text" and update.text then
        -- Streaming text from agent — write chunked to worklog
        local f = io.open(M.log_path(path), "a")
        if f then f:write(update.text); f:close() end
        pcall(require("acp.workbench").on_event, path, update.text)
      end

      if p.stopReason then
        M.log(path, "--- session stop: " .. p.stopReason .. " ---")
        vim.notify("ACP work done (" .. p.stopReason .. ")", vim.log.levels.INFO, { title = "acp" })
        vim.schedule(function()
          require("acp.activity").clear(sess.session_id)
          pcall(require("acp.workbench").render)
        end)
      end
    end)

    sess.rpc:request("session/prompt", {
      sessionId = sess.session_id,
      prompt    = { { type = "text", text = prompt } },
    }, function(req_err, _)
      if req_err then
        M.log(path, "prompt error: " .. vim.inspect(req_err))
      end
    end)
  end)
end

-- Ask "what's left?" — sends goal + check instruction; result → quickfix.
function M.check_left(cwd)
  cwd = cwd or vim.fn.getcwd()
  local path = M.latest(cwd)
  local text = M.load(path)
  if not text then
    vim.notify("No work item set.", vim.log.levels.WARN, { title = "acp" }); return
  end

  local prompt = "Work item:\n\n" .. text
    .. "\n\nCheck the current state of the project and list what is still left "
    .. "to complete this work item as bullet points."

  require("acp.session").get_or_create(cwd, function(err, sess)
    if err then vim.notify(err, vim.log.levels.ERROR, { title = "acp" }); return end

    local result = ""
    sess.rpc:subscribe(sess.session_id, function(notif)
      local p      = notif.params or {}
      local update = p.update or {}
      if update.sessionUpdate == "text" and update.text then
        result = result .. update.text
      end
      if p.stopReason then
        local lines = vim.split(result, "\n", { plain = true })
        local items = {}
        for _, l in ipairs(lines) do
          if vim.trim(l) ~= "" then
            table.insert(items, { text = l, bufnr = 0, lnum = 0 })
          end
        end
        vim.fn.setqflist(items, "r", { title = "ACP: What's left?" })
        vim.cmd("copen")
      end
    end)

    sess.rpc:request("session/prompt", {
      sessionId = sess.session_id,
      prompt    = { { type = "text", text = prompt } },
    }, function() end)
  end)
end

return M
