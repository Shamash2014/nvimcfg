local M = {}

local MAX_RETRIES = 10

M._queues = {}
M._scheduled = {}
M._draining = {}

local function is_textlock(err)
  return type(err) == "string" and err:find("E565") ~= nil
end

local function drain(buf)
  M._scheduled[buf] = false
  if M._draining[buf] then return end
  local q = M._queues[buf]
  if not q or #q == 0 then return end

  M._draining[buf] = true
  while #q > 0 do
    if not vim.api.nvim_buf_is_valid(buf) then
      M._queues[buf] = nil
      M._draining[buf] = false
      return
    end
    local entry = q[1]
    local ok, err = pcall(entry.fn)
    if ok then
      table.remove(q, 1)
    elseif is_textlock(err) and entry.retries < MAX_RETRIES then
      entry.retries = entry.retries + 1
      M._draining[buf] = false
      if not M._scheduled[buf] then
        M._scheduled[buf] = true
        vim.schedule(function() drain(buf) end)
      end
      return
    else
      table.remove(q, 1)
    end
  end
  M._draining[buf] = false
end

function M.enqueue(buf, fn)
  M._queues[buf] = M._queues[buf] or {}
  table.insert(M._queues[buf], { fn = fn, retries = 0 })
  if M._draining[buf] then return end
  drain(buf)
end

function M.flush(buf)
  if not M._queues[buf] then return end
  drain(buf)
end

function M.detach(buf)
  M._queues[buf] = nil
  M._scheduled[buf] = nil
  M._draining[buf] = nil
end

return M
