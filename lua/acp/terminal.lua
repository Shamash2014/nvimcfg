local M = {}

local _terminals = {}
local _id_seq    = 0

function M.create(params, on_done)
  _id_seq = _id_seq + 1
  local tid   = "term_" .. _id_seq
  local entry = { output = "", exit_code = nil, waiters = {}, job_id = nil }
  _terminals[tid] = entry

  local limit = params.outputByteLimit
  local function append(chunks)
    for _, c in ipairs(chunks) do
      if c ~= "" then
        entry.output = entry.output .. c
        if limit and #entry.output > limit then
          entry.output = entry.output:sub(-limit)
        end
      end
    end
  end

  local cmd = { params.command }
  for _, a in ipairs(params.args or {}) do table.insert(cmd, a) end

  local job_id = vim.fn.jobstart(cmd, {
    cwd       = params.cwd,
    env       = params.env,
    pty       = true,
    on_stdout = function(_, data) append(data) end,
    on_stderr = function(_, data) append(data) end,
    on_exit   = function(_, code)
      entry.exit_code = code
      local waiters = entry.waiters
      entry.waiters  = {}
      for _, w in ipairs(waiters) do
        vim.schedule(function() w(code) end)
      end
    end,
  })

  if job_id <= 0 then
    _terminals[tid] = nil
    on_done(nil, { code = -32603, message = "Failed to start process" })
    return
  end

  entry.job_id = job_id
  on_done({ terminalId = tid }, nil)
end

function M.wait_for_exit(tid, rpc, msg_id)
  local entry = _terminals[tid]
  if not entry then
    rpc:respond(msg_id, nil, { code = -32602, message = "Unknown terminalId: " .. tostring(tid) })
    return
  end
  if entry.exit_code ~= nil then
    rpc:respond(msg_id, { exitCode = entry.exit_code })
    return
  end
  table.insert(entry.waiters, function(code)
    rpc:respond(msg_id, { exitCode = code })
  end)
end

function M.get_output(tid)
  local entry = _terminals[tid]
  return entry and entry.output or nil
end

function M.kill(tid)
  local entry = _terminals[tid]
  if entry and entry.job_id then vim.fn.jobstop(entry.job_id) end
end

function M.release(tid)
  local entry = _terminals[tid]
  if not entry then return end
  if entry.job_id and entry.exit_code == nil then vim.fn.jobstop(entry.job_id) end
  _terminals[tid] = nil
end

return M
