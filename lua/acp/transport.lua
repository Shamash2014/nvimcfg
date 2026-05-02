local uv = vim.uv or vim.loop
local M = {}

-- Spawns an ACP server process. Returns a handle or nil+err.
-- on_line(line: string) called per complete JSON line from stdout.
-- on_exit(code: integer) called when process exits.
function M.spawn(cmd, on_line, on_exit)
  local stdin  = uv.new_pipe(false)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  if not stdin or not stdout or not stderr then
    return nil, "failed to create pipes"
  end

  local handle = { stdin = stdin, stdout = stdout, stderr = stderr, buf = "" }

  local proc, err = uv.spawn(cmd[1], {
    args  = vim.list_slice(cmd, 2),
    stdio = { stdin, stdout, stderr },
    env   = vim.tbl_map(function(k) return k .. "=" .. vim.env[k] end,
              vim.tbl_keys(vim.fn.environ())),
  }, function(code)
    vim.schedule(function() on_exit(code) end)
  end)

  if not proc then
    return nil, err
  end

  handle.proc = proc

  stdout:read_start(function(err2, chunk)
    if err2 or not chunk then return end
    handle.buf = handle.buf .. chunk
    local tail = handle.buf
    for line in tail:gmatch("([^\n]*)\n") do
      if line ~= "" then
        vim.schedule(function() on_line(line) end)
      end
    end
    handle.buf = tail:match("[^\n]*$") or ""
  end)

  stderr:read_start(function(_, _) end)  -- drain stderr silently

  return handle, nil
end

function M.write(handle, data)
  if handle.stdin and not handle.stdin:is_closing() then
    handle.stdin:write(data .. "\n")
    return true
  end
  return false
end

function M.close(handle)
  if handle.stdin and not handle.stdin:is_closing() then
    handle.stdin:shutdown(function()
      handle.stdin:close()
    end)
  end
  if handle.proc and not handle.proc:is_closing() then
    handle.proc:close()
  end
end

return M
