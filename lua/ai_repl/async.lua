local M = {}

local uv = vim.uv or vim.loop

function M.run(func, callback)
  assert(type(func) == "function", "async.run expects a function")

  local co = coroutine.create(func)

  local function step(...)
    local ok, result = coroutine.resume(co, ...)

    if not ok then
      if callback then
        callback(nil, result)
      else
        vim.notify("[async] Error: " .. tostring(result), vim.log.levels.ERROR)
      end
      return
    end

    if coroutine.status(co) == "dead" then
      if callback then
        callback(result, nil)
      end
    else
      if type(result) == "function" then
        result(step)
      else
        vim.schedule(function()
          step(result)
        end)
      end
    end
  end

  step()
end

function M.await(fn)
  return coroutine.yield(function(cb)
    fn(cb)
  end)
end

function M.schedule()
  return coroutine.yield(function(cb)
    vim.schedule(function()
      cb()
    end)
  end)
end

function M.sleep(ms)
  return coroutine.yield(function(cb)
    vim.defer_fn(cb, ms)
  end)
end

function M.timeout(ms, default_value)
  return coroutine.yield(function(cb)
    local completed = false
    local timer = uv.new_timer()

    timer:start(ms, 0, function()
      if not completed then
        completed = true
        timer:stop()
        timer:close()
        cb(default_value)
      end
    end)

    return function()
      if not completed then
        completed = true
        timer:stop()
        timer:close()
      end
    end
  end)
end

function M.wrap(fn)
  return function(...)
    local args = {...}
    return M.await(function(cb)
      fn(unpack(args), cb)
    end)
  end
end

function M.all(tasks)
  return coroutine.yield(function(cb)
    local results = {}
    local completed = 0
    local total = #tasks
    local has_error = false

    if total == 0 then
      cb({}, nil)
      return
    end

    for i, task in ipairs(tasks) do
      M.run(task, function(result, err)
        if has_error then return end

        if err then
          has_error = true
          cb(nil, err)
          return
        end

        results[i] = result
        completed = completed + 1

        if completed == total then
          cb(results, nil)
        end
      end)
    end
  end)
end

function M.race(tasks)
  return coroutine.yield(function(cb)
    local completed = false

    for _, task in ipairs(tasks) do
      M.run(task, function(result, err)
        if not completed then
          completed = true
          cb(result, err)
        end
      end)
    end
  end)
end

return M
