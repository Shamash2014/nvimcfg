local uv = vim.uv or vim.loop
local M = {}

local LOG_FILE = vim.fn.stdpath("cache") .. "/acp.log"
local function debug_log(prefix, data)
  local f = io.open(LOG_FILE, "a")
  if f then
    f:write(string.format("[%s] %s %s\n", os.date("%H:%M:%S"), prefix, data))
    f:close()
  end
end

-- Spawns an ACP server process using jobstart with PTY.
function M.spawn(cmd, on_line, on_exit, cwd)
  local handle = { buf = "" }

  local job_id = vim.fn.jobstart(cmd, {
    pty = false,
    cwd = cwd,
    env = {
      IS_AI_TERMINAL = "1",
      NODE_NO_WARNINGS = "1",
    },
    on_stdout = function(_, data)
      if not data then return end
      local chunk = table.concat(data, "\n")
      handle.buf = handle.buf .. chunk

      while true do
        local nl = handle.buf:find("[\n\r]")
        if not nl then break end
        
        local line = handle.buf:sub(1, nl - 1)
        handle.buf = handle.buf:sub(nl + 1)

        if line ~= "" then
          local clean = line:gsub("\x1b%[[0-9;]*[a-zA-Z]", "")
                            :gsub("\x1b%]0;[^\x07]*\x07", "")
          if clean:match("%S") then
            if clean:match("^{") then
              debug_log("IN: ", clean)
              vim.schedule(function() on_line(clean) end)
            elseif #clean < 500 then
              debug_log("RAW:", clean)
            end
          end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function() on_exit(code) end)
    end,
  })

  if job_id <= 0 then
    return nil, "failed to start job: " .. job_id
  end

  handle.job_id = job_id
  return handle, nil
end

function M.write(handle, data)
  if handle.job_id then
    debug_log("OUT:", data)
    vim.fn.chansend(handle.job_id, data .. "\n")
    return true
  end
  return false
end

function M.close(handle)
  if handle.job_id then
    vim.fn.jobstop(handle.job_id)
  end
end

return M
