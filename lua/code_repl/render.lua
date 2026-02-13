local M = {}

-- Namespace for virtual text
local ns = vim.api.nvim_create_namespace("code_repl")

-- Store results per buffer
local results = {}

function M.init()
  -- Set up highlight groups
  vim.api.nvim_set_hl(0, "CodeReplResult", {
    default = true,
    fg = "#00ff00",
  })
  
  vim.api.nvim_set_hl(0, "CodeReplError", {
    default = true,
    fg = "#ff0000",
  })
  
  vim.api.nvim_set_hl(0, "CodeReplArrow", {
    default = true,
    fg = "#888888",
  })
end

function M.show_result(buf, result)
  buf = buf or 0
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Get current line
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  
  -- Truncate if needed
  local max_len = 100
  local truncated = result
  if #result > max_len then
    truncated = result:sub(1, max_len - 3) .. "..."
  end
  
  -- Display as virtual text
  vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
    virt_text = { { "⮕ " .. truncated, "CodeReplResult" } },
    virt_text_pos = "eol",
    virt_text_win_col = 0,
    hl_mode = "combine",
  })
  
  -- Store for clearing
  results[buf] = results[buf] or {}
  table.insert(results[buf], { line = line, ns = ns })
end

function M.show_error(buf, error)
  buf = buf or 0
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  
  -- Truncate error
  local max_len = 100
  local truncated = error
  if #error > max_len then
    truncated = error:sub(1, max_len - 3) .. "..."
  end
  
  vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
    virt_text = { { "[✗] " .. truncated, "CodeReplError" } },
    virt_text_pos = "eol",
    virt_text_win_col = 0,
    hl_mode = "combine",
  })
  
  results[buf] = results[buf] or {}
  table.insert(results[buf], { line = line, ns = ns })
end

function M.clear_result(buf)
  buf = buf or 0
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Clear all virtual text for this buffer
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  results[buf] = nil
end

function M.clear_all()
  for buf, _ in pairs(results) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end
  results = {}
end

return M
