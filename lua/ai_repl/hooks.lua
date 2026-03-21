local M = {}

local hook_config = {}

function M.setup(config)
  hook_config = config or {}
end

local function substitute_vars(cmd, vars)
  for key, val in pairs(vars or {}) do
    cmd = cmd:gsub("{" .. key .. "}", vim.fn.shellescape(tostring(val)))
  end
  return cmd
end

local function run_hook(command, vars)
  local expanded = substitute_vars(command, vars)
  vim.fn.jobstart(expanded, {
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("[hooks] Command exited " .. code .. ": " .. expanded, vim.log.levels.WARN)
        end)
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line and line ~= "" then
          vim.schedule(function()
            vim.notify("[hooks] " .. line, vim.log.levels.DEBUG)
          end)
        end
      end
    end,
  })
end

local function dispatch(event_name, vars, tool_name)
  local hooks = hook_config[event_name]
  if not hooks then return end

  for _, hook in ipairs(hooks) do
    local match = true
    if hook.match_tool and tool_name then
      match = tool_name:lower():find(hook.match_tool:lower(), 1, true) ~= nil
    end
    if match and hook.command then
      run_hook(hook.command, vars)
    end
  end
end

function M.pre_tool_use(tool_name, tool_input)
  local file = tool_input and (tool_input.file_path or tool_input.path) or ""
  dispatch("PreToolUse", {
    tool = tool_name,
    file = file,
  }, tool_name)
end

function M.post_tool_use(tool_name, tool_input)
  local file = tool_input and (tool_input.file_path or tool_input.path) or ""
  dispatch("PostToolUse", {
    tool = tool_name,
    file = file,
  }, tool_name)
end

function M.on_complete(summary, session_id)
  dispatch("OnComplete", {
    summary = summary or "",
    session_id = session_id or "",
  })
end

function M.on_error(error_msg, session_id)
  dispatch("OnError", {
    error = error_msg or "",
    session_id = session_id or "",
  })
end

return M
