local M = {}

local KEY_PATTERN = "^(%w[%w_-]*):(.*)$"

local function parse_meta(lines)
  local meta = {}
  for _, line in ipairs(lines) do
    local key, val = line:match(KEY_PATTERN)
    if key then
      val = vim.trim(val)
      meta[key] = val ~= "" and val or nil
    end
  end
  return meta
end

function M.find_end(lines)
  if lines[1] ~= "---" then return nil end
  for i = 2, #lines do
    if lines[i] == "---" then return i end
  end
  return nil
end

function M.read_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil, nil end
  local count = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, math.min(200, count), false)
  local fm_end = M.find_end(lines)
  if not fm_end then return nil, nil end
  local body = {}
  for i = 2, fm_end - 1 do body[#body + 1] = lines[i] end
  return parse_meta(body), fm_end
end

function M.read_buffer_field(buf, key)
  local meta = M.read_buffer(buf)
  return meta and meta[key] or nil
end

function M.read_file(path)
  local fd = io.open(path, "r")
  if not fd then return nil end
  local lines = {}
  for line in fd:lines() do
    lines[#lines + 1] = line
    if #lines > 200 or (line == "---" and #lines > 1) then break end
  end
  fd:close()
  local fm_end = M.find_end(lines)
  if not fm_end then return nil end
  local body = {}
  for i = 2, fm_end - 1 do body[#body + 1] = lines[i] end
  local meta = parse_meta(body)
  return next(meta) and meta or nil
end

return M
