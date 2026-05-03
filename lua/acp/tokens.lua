local M = {}

local ASCII_TOKENS_PER_CHAR = 0.25
local NON_ASCII_TOKENS_PER_CHAR = 1.3
local MAX_CHARS_FOR_FULL_HEURISTIC = 100000
local DEFAULT_CHARS_PER_TOKEN = 4

local function estimate_tokens(text)
  if type(text) ~= "string" then
    return 0
  end

  local len = #text
  if len > MAX_CHARS_FOR_FULL_HEURISTIC then
    return len / DEFAULT_CHARS_PER_TOKEN
  end

  local tokens = 0
  for i = 1, len do
    if text:byte(i) <= 127 then
      tokens = tokens + ASCII_TOKENS_PER_CHAR
    else
      tokens = tokens + NON_ASCII_TOKENS_PER_CHAR
    end
  end
  return tokens
end

function M.estimate_text(text)
  return estimate_tokens(text)
end

function M.estimate(messages)
  local total = 0
  for _, msg in ipairs(messages) do
    if type(msg.content) == "string" then
      total = total + estimate_tokens(msg.content)
    elseif type(msg.text) == "string" then
      total = total + estimate_tokens(msg.text)
    end

    if msg.tool_calls and #msg.tool_calls > 0 then
      total = total + estimate_tokens(vim.json.encode(msg.tool_calls))
    end

    if msg.role == "tool" and msg.tool_call_id then
      total = total + estimate_tokens(msg.tool_call_id)
    end
  end
  return math.floor(total)
end

function M.format(n, limit)
  limit = limit or 200000
  local k = math.floor(n / 1000)
  local limit_k = math.floor(limit / 1000)
  if k >= 1 then
    return "~" .. k .. "k/" .. limit_k .. "k"
  else
    return "~" .. math.floor(n) .. "/" .. limit_k .. "k"
  end
end

return M
