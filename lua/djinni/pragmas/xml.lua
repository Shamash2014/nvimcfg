local M = {}

local function escape(text)
  if not text then
    return ""
  end
  return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

function M.tag(name, attrs, body)
  local attr_str = ""
  if attrs then
    for k, v in pairs(attrs) do
      attr_str = attr_str .. ' ' .. k .. '="' .. escape(tostring(v)) .. '"'
    end
  end
  if body then
    return "<" .. name .. attr_str .. ">" .. escape(body) .. "</" .. name .. ">"
  else
    return "<" .. name .. attr_str .. " />"
  end
end

function M.section(name, body)
  if not body or body == "" then
    return ""
  end
  return "<" .. name .. ">\n  " .. body:gsub("\n", "\n  ") .. "\n</" .. name .. ">"
end

return M
