local M = {}
local xml = require("djinni.pragmas.xml")

local function read_first_nonblank(filepath, n)
  local f = io.open(filepath, "r")
  if not f then return "" end
  local lines = {}
  while #lines < n do
    local line = f:read()
    if not line then break end
    if line:match("%S") then table.insert(lines, line) end
  end
  f:close()
  return table.concat(lines, "\n")
end

local function get_signatures(filepath, opts)
  opts = opts or {}

  local ok, parser = pcall(vim.treesitter.get_parser, filepath)
  if not ok or not parser then
    return read_first_nonblank(filepath, 5)
  end

  local tree = parser:parse()
  local root = tree[1]:root()
  local snippets = {}

  local function traverse(node, depth)
    if depth > 2 then return end
    local type = node:type()
    if type == "function_declaration" or type == "function" or type == "method_definition" or
       type == "class_definition" or type == "interface_declaration" or type == "type_alias_declaration" then
      local text = vim.treesitter.get_node_text(node, filepath)
      if text and text ~= "" then
        local first_line = text:match("[^\n]+")
        if first_line then
          table.insert(snippets, first_line)
        end
      end
    end
    for child in node:iter_children() do
      traverse(child, depth + 1)
    end
  end

  traverse(root, 0)
  if #snippets == 0 then
    return read_first_nonblank(filepath, 5)
  end
  return table.concat(snippets, "\n")
end

function M.resolve(scan_result, names, opts)
  opts = opts or {}
  local xml_parts = {}

  for _, name in ipairs(names or {}) do
    local feature = scan_result.features[name]
    if feature then
      local files_xml = {}
      local seen = {}
      for _, filepath in ipairs(feature.files) do
        if not seen[filepath] then
          seen[filepath] = true
          local sig = get_signatures(filepath, opts)
          if sig and sig ~= "" then
            table.insert(files_xml, xml.tag("file", { path = filepath }, sig))
          else
            table.insert(files_xml, xml.tag("file", { path = filepath }))
          end
        end
      end
      table.insert(xml_parts, xml.section("feature", xml.tag("name", {}, name) .. "\n  " .. table.concat(files_xml, "\n  ")))
    end
  end

  if #xml_parts > 0 then
    return xml.section("features", table.concat(xml_parts, "\n  "))
  end
  return ""
end

function M.index(scan_result)
  local names = {}
  for name in pairs(scan_result.features) do
    table.insert(names, name)
  end
  table.sort(names)
  if #names > 0 then
    return xml.tag("feature_index", {}, table.concat(names, ", "))
  end
  return ""
end

return M
