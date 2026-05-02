local M = {}

-- Dispatch a server-initiated request to the right handler.
-- Called from rpc._dispatch when msg.method is set and msg.id is present
-- (server request expecting a response).
function M.dispatch(rpc, msg)
  local method = msg.method
  if method == "session/request_permission" then
    M._handle_permission(rpc, msg)
  elseif method == "fs/read_text_file" then
    M._handle_read(rpc, msg)
  else
    -- Unknown method — respond with method-not-found error
    rpc:respond(msg.id, nil, { code = -32601, message = "Method not found: " .. method })
  end
end

-- session/request_permission → mailbox loclist with <CR>=allow <BS>=reject
function M._handle_permission(rpc, msg)
  local p    = msg.params or {}
  local tool = p.toolCall or {}
  vim.schedule(function()
    require("acp.mailbox").enqueue_permission({
      rpc        = rpc,
      msg_id     = msg.id,
      session_id = p.sessionId,
      tool_kind  = tool.kind or "other",
      tool_title = tool.title or tool.kind or "unknown",
      tool_input = tool.rawInput,
      options    = p.options or {
        { optionId = "allow-once",  name = "Allow once",   kind = "allow_once"  },
        { optionId = "allow-always",name = "Allow always", kind = "allow_always" },
        { optionId = "reject-once", name = "Reject",       kind = "reject_once" },
      },
    })
  end)
end

-- fs/read_text_file: serve file content, preferring unsaved buffer state.
function M._handle_read(rpc, msg)
  local p = msg.params or {}
  local path  = p.path
  local lnum  = p.line   -- 1-based, optional
  local limit = p.limit  -- line count, optional

  if not path then
    rpc:respond(msg.id, nil, { code = -32602, message = "Missing path" })
    return
  end

  -- Prefer open buffer (gives agent unsaved state)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local start = (lnum or 1) - 1
    local stop  = limit and (start + limit) or -1
    local lines = vim.api.nvim_buf_get_lines(bufnr, start, stop, false)
    rpc:respond(msg.id, { content = table.concat(lines, "\n") })
    return
  end

  -- Fall back to disk
  vim.system({ "cat", path }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        rpc:respond(msg.id, nil, { code = -32603, message = "Cannot read: " .. path })
        return
      end
      local content = res.stdout or ""
      if lnum then
        local all = vim.split(content, "\n", { plain = true })
        local slice = vim.list_slice(all, lnum, limit and (lnum + limit - 1) or #all)
        content = table.concat(slice, "\n")
      end
      rpc:respond(msg.id, { content = content })
    end)
  end)
end

return M
