local M = {}

M.ERROR_CODES = {
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32603,

  FILE_NOT_FOUND = -32001,
  FILE_READ_ERROR = -32002,
  FILE_WRITE_ERROR = -32003,
  PERMISSION_DENIED = -32004,
  TOOL_EXECUTION_ERROR = -32005,
  SESSION_ERROR = -32006,
  AUTH_ERROR = -32007,
}

function M.create_error(code, message, data)
  return {
    code = code,
    message = message,
    data = data,
  }
end

function M.format_error_response(id, error_obj)
  return {
    jsonrpc = "2.0",
    id = id,
    error = error_obj,
  }
end

function M.handle_file_read_error(file_path, error_message)
  if not vim.fn.filereadable(file_path) then
    return M.create_error(
      M.ERROR_CODES.FILE_NOT_FOUND,
      "File not found",
      { path = file_path }
    )
  end

  return M.create_error(
    M.ERROR_CODES.FILE_READ_ERROR,
    error_message or "Failed to read file",
    { path = file_path }
  )
end

function M.handle_file_write_error(file_path, error_message)
  return M.create_error(
    M.ERROR_CODES.FILE_WRITE_ERROR,
    error_message or "Failed to write file",
    { path = file_path }
  )
end

function M.handle_permission_error(action, resource)
  return M.create_error(
    M.ERROR_CODES.PERMISSION_DENIED,
    "Permission denied",
    { action = action, resource = resource }
  )
end

function M.handle_tool_error(tool_name, error_message, raw_error)
  return M.create_error(
    M.ERROR_CODES.TOOL_EXECUTION_ERROR,
    string.format("Tool '%s' failed: %s", tool_name, error_message),
    { tool = tool_name, error = raw_error }
  )
end

function M.handle_session_error(session_id, error_message)
  return M.create_error(
    M.ERROR_CODES.SESSION_ERROR,
    error_message or "Session error",
    { sessionId = session_id }
  )
end

function M.handle_auth_error(method_id, error_message)
  return M.create_error(
    M.ERROR_CODES.AUTH_ERROR,
    error_message or "Authentication failed",
    { methodId = method_id }
  )
end

function M.is_error_response(response)
  return response and response.error ~= nil
end

function M.extract_error_message(error_obj)
  if type(error_obj) == "string" then
    return error_obj
  end

  if type(error_obj) == "table" then
    if error_obj.message then
      return error_obj.message
    end
    if error_obj.error and type(error_obj.error) == "table" and error_obj.error.message then
      return error_obj.error.message
    end
  end

  return "Unknown error"
end

function M.log_error(context, error_obj, opts)
  opts = opts or {}
  local level = opts.level or vim.log.levels.ERROR

  local message = string.format(
    "[ai_repl:%s] %s",
    context,
    M.extract_error_message(error_obj)
  )

  if opts.debug and type(error_obj) == "table" then
    message = message .. "\n" .. vim.inspect(error_obj)
  end

  vim.notify(message, level)
end

function M.wrap_callback(callback, context, opts)
  opts = opts or {}

  return function(result, err)
    if err then
      if opts.on_error then
        opts.on_error(err)
      else
        M.log_error(context, err, opts)
      end

      if opts.propagate_error and callback then
        callback(nil, err)
        return
      end
    end

    if callback then
      callback(result, err)
    end
  end
end

function M.safe_json_encode(data)
  local ok, result = pcall(vim.json.encode, data)
  if not ok then
    return nil, M.create_error(
      M.ERROR_CODES.INTERNAL_ERROR,
      "Failed to encode JSON",
      { error = result }
    )
  end
  return result, nil
end

function M.safe_json_decode(json_str)
  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, M.create_error(
      M.ERROR_CODES.PARSE_ERROR,
      "Failed to parse JSON",
      { error = result }
    )
  end
  return result, nil
end

function M.create_timeout_error(method, timeout_ms)
  return M.create_error(
    M.ERROR_CODES.INTERNAL_ERROR,
    string.format("Method '%s' timed out after %dms", method, timeout_ms),
    { method = method, timeout = timeout_ms }
  )
end

function M.retry_with_backoff(fn, opts)
  opts = opts or {}
  local max_retries = opts.max_retries or 3
  local initial_delay = opts.initial_delay or 1000
  local max_delay = opts.max_delay or 10000
  local backoff_factor = opts.backoff_factor or 2

  local attempt = 0
  local delay = initial_delay

  local function try_call()
    attempt = attempt + 1

    fn(function(result, err)
      if err and attempt < max_retries then
        if opts.should_retry and not opts.should_retry(err, attempt) then
          if opts.callback then
            opts.callback(nil, err)
          end
          return
        end

        vim.defer_fn(try_call, delay)
        delay = math.min(delay * backoff_factor, max_delay)
      else
        if opts.callback then
          opts.callback(result, err)
        end
      end
    end)
  end

  try_call()
end

return M
