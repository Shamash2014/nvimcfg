local M = {}

local chat_state = require("ai_repl.chat_state")

function M.lock_buffer(buf)
  local state = chat_state.get_buffer_state(buf)
  if not state.locked then
    state.locked = true
    vim.bo[buf].modifiable = false
  end
end

function M.unlock_buffer(buf)
  local state = chat_state.get_buffer_state(buf)
  if state.locked then
    state.locked = false
    vim.bo[buf].modifiable = true
  end
end

function M.modify_while_locked(buf, fn)
  local was_locked = chat_state.get_buffer_state(buf).locked

  if was_locked then
    vim.bo[buf].modifiable = true
  end

  local ok, err = pcall(fn)

  if was_locked then
    vim.bo[buf].modifiable = false
  end

  if not ok then
    error(err)
  end
end

function M.inject_tool_placeholder(buf, tool_id, tool_name, tool_input)
  M.modify_while_locked(buf, function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line_count = #lines

    if line_count > 0 and lines[line_count] ~= "" then
      vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { "" })
      line_count = line_count + 1
    end

    local placeholder_lines = {
      "",
      string.format("**Tool Use:** `%s` (`%s`)", tool_id, tool_name),
      "```json",
      vim.json.encode(tool_input or {}),
      "```",
      "",
    }

    vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, placeholder_lines)
  end)
end

function M.inject_tool_result(buf, tool_id, result, is_error)
  M.modify_while_locked(buf, function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local tool_line = nil
    for i, line in ipairs(lines) do
      if line:match("^%*%*Tool Use:%*%*.*`" .. vim.pesc(tool_id) .. "`") then
        tool_line = i
        break
      end
    end

    if not tool_line then
      return
    end

    local insert_at = tool_line
    while insert_at <= #lines do
      if lines[insert_at]:match("^```$") then
        insert_at = insert_at + 1
        break
      end
      insert_at = insert_at + 1
    end

    local result_text = type(result) == "string" and result or vim.inspect(result)

    local result_lines = {
      "",
      is_error and "**Tool Result:** (error)" or "**Tool Result:**",
      "```",
      result_text,
      "```",
      "",
    }

    vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, result_lines)
  end)
end

return M
