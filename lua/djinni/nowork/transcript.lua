local blocks = require("djinni.nowork.blocks")

local M = {}

local role_labels = {
  system = "System",
  you = "You",
  djinni = "Djinni",
}

local function trim(text)
  return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function useful_line(block)
  for line in (block.content or ""):gmatch("[^\n]+") do
    local text = trim(line)
    if text ~= "" and not text:match("^%[%*%]%s+") then
      return text
    end
  end
  return nil
end

local function shorten(text)
  if #text <= 100 then return text end
  return text:sub(1, 97) .. "..."
end

function M.entries(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return {} end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = blocks.parse(lines)
  local items = {}

  for _, block in ipairs(parsed) do
    local label = role_labels[block.type]
    if label then
      local title = useful_line(block) or label
      items[#items + 1] = {
        bufnr = buf,
        lnum = block.start_line,
        col = 1,
        text = label .. ": " .. shorten(title),
      }
    end
  end

  return items
end

function M.open(buf, opts)
  opts = opts or {}
  buf = buf or vim.api.nvim_get_current_buf()
  local items = M.entries(buf)
  local title = "Nowork Transcript"

  if opts.quickfix then
    vim.fn.setqflist({}, "r", { title = title, items = items })
    vim.cmd("copen")
  else
    vim.fn.setloclist(0, {}, "r", { title = title, items = items })
    vim.cmd("lopen")
  end

  if #items == 0 then
    vim.notify("[djinni] No transcript entries", vim.log.levels.INFO)
  end
end

return M
