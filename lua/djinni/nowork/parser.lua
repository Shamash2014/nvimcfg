local M = {}

local function get_html_parser(text)
  pcall(vim.treesitter.language.add, "html")
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, "html")
  if not ok or not parser then return nil end
  return parser
end

local function get_node_text(node, src)
  if not node then return "" end
  return vim.treesitter.get_node_text(node, src) or ""
end

local function tag_name(start_tag, src)
  for sub in start_tag:iter_children() do
    if sub:type() == "tag_name" then
      return get_node_text(sub, src)
    end
  end
end

local function element_name(element, src)
  for child in element:iter_children() do
    if child:type() == "start_tag" then
      return tag_name(child, src)
    end
  end
end

local function element_body(element, src)
  local start_tag, end_tag
  for child in element:iter_children() do
    if child:type() == "start_tag" then
      start_tag = child
    elseif child:type() == "end_tag" then
      end_tag = child
    end
  end
  if not start_tag or not end_tag then return "" end
  local _, _, s_byte = start_tag:end_()
  local _, _, e_byte = end_tag:start()
  if s_byte >= e_byte then return "" end
  local body = src:sub(s_byte + 1, e_byte)
  body = body:gsub("^%s*\n", "")
  body = body:gsub("\n?%s*$", "")
  return body
end

local function strip_quotes(value)
  value = value:gsub('^"', ""):gsub('"$', "")
  value = value:gsub("^'", ""):gsub("'$", "")
  return value
end

local function element_attr(element, src, attr_name)
  for child in element:iter_children() do
    if child:type() == "start_tag" then
      for sub in child:iter_children() do
        if sub:type() == "attribute" then
          local name_node, value_node
          for a in sub:iter_children() do
            if a:type() == "attribute_name" then
              name_node = a
            elseif a:type() == "quoted_attribute_value" or a:type() == "attribute_value" then
              value_node = a
            end
          end
          if name_node and value_node and get_node_text(name_node, src) == attr_name then
            return strip_quotes(get_node_text(value_node, src))
          end
        end
      end
    end
  end
end

local function find_elements(text, tag)
  local parser = get_html_parser(text)
  if not parser then return nil end
  local tree = (parser:parse() or {})[1]
  if not tree then return {} end
  local results = {}
  local function walk(node)
    if node:type() == "element" then
      local name = element_name(node, text)
      if name and name:lower() == tag:lower() then
        table.insert(results, node)
      end
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(tree:root())
  return results
end

function M.extract_locations_block(text)
  local nodes = find_elements(text, "Locations")
  if not nodes or #nodes == 0 then return nil end
  return element_body(nodes[1], text)
end

function M.extract_review_blocks(text)
  local out = {}
  local nodes = find_elements(text, "Review")
  if not nodes then return out end
  for _, node in ipairs(nodes) do
    table.insert(out, {
      title = element_attr(node, text, "title"),
      body = element_body(node, text),
    })
  end
  return out
end

local LOG_ALLOWED_TAGS = {
  review = "Review",
  tasks = "Tasks",
  observation = "Observation",
  observations = "Observations",
  summary = "Summary",
  options = "Options",
  feedback = "Feedback",
  next = "Next",
}

local SECTION_LIST_FOR_QF = { "Summary", "Observation", "Observations", "Next", "Tasks", "Review" }

local LOG_MARKER_PATTERNS = {
  "^PLAN_COMPLETE$",
  "^TASK_COMPLETE:[%w_.%-]+$",
  "^TASK_BLOCKED:[%w_.%-]+$",
  "^EVAL_PASS:[%w_.%-]+$",
  "^EVAL_FAIL:[%w_.%-]+$",
  "^QUESTION:%s*.+$",
}

local SECTION_TAGS = { "Summary", "Review", "Observation", "Tasks" }

function M.extract_sections(text)
  local out = {}
  if not text or text == "" then return out end
  for _, tag in ipairs(SECTION_TAGS) do
    local nodes = find_elements(text, tag)
    if nodes and nodes[1] then
      out[tag:lower()] = element_body(nodes[1], text)
    end
  end
  return out
end

local function find_allowed_elements(text)
  local parser = get_html_parser(text)
  if not parser then return {} end
  local tree = (parser:parse() or {})[1]
  if not tree then return {} end
  local results = {}
  local function walk(node)
    if node:type() == "element" then
      local name = element_name(node, text)
      if name then
        local canonical = LOG_ALLOWED_TAGS[name:lower()]
        if canonical then
          results[#results + 1] = { node = node, tag = canonical }
        end
      end
    end
    for child in node:iter_children() do walk(child) end
  end
  walk(tree:root())
  return results
end

function M.extract_log_slices(text)
  if not text or text == "" then return {} end

  local items = {}
  local block_ranges = {}

  for _, entry in ipairs(find_allowed_elements(text)) do
    local node = entry.node
    local _, _, sbyte = node:start()
    local _, _, ebyte = node:end_()
    sbyte = sbyte or 0
    ebyte = ebyte or sbyte
    block_ranges[#block_ranges + 1] = { sbyte, ebyte }
    items[#items + 1] = {
      sbyte = sbyte,
      slice = {
        kind = "block",
        tag = entry.tag,
        title = element_attr(node, text, "title"),
        body = element_body(node, text),
      },
    }
  end

  local byte = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    for _, pat in ipairs(LOG_MARKER_PATTERNS) do
      if trimmed:match(pat) then
        local inside = false
        for _, r in ipairs(block_ranges) do
          if byte >= r[1] and byte < r[2] then inside = true; break end
        end
        if not inside then
          items[#items + 1] = { sbyte = byte, slice = { kind = "marker", tag = trimmed } }
        end
        break
      end
    end
    byte = byte + #line + 1
  end

  table.sort(items, function(a, b) return a.sbyte < b.sbyte end)
  local out = {}
  for _, it in ipairs(items) do out[#out + 1] = it.slice end
  return out
end

local function split_record(line)
  local filepath, lnum_str, after = line:match("^(.-):(%d+):(.*)$")
  if not filepath or filepath == "" or not lnum_str then return nil end
  local lnum = tonumber(lnum_str)

  local col
  local col_str, rest = after:match("^(%d+)(.*)$")
  if col_str then
    col = tonumber(col_str)
    after = rest
  end

  local text
  if after == "" then
    text = ""
  elseif after:sub(1, 1) == "," then
    local parts = after:sub(2)
    local _, notes = parts:match("^([^,]*),(.*)$")
    text = notes or parts
  elseif after:sub(1, 1) == ":" then
    text = after:sub(2)
  else
    text = after
  end
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")

  return require("djinni.nowork.qfix").build_item({
    filename = filepath,
    lnum = lnum,
    col = col or 1,
    text = text,
  })
end

function M.parse_line(line)
  return split_record(line)
end

local function parse_body(body)
  local items = {}
  for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
    if vim.trim(line) ~= "" then
      local it = split_record(line)
      if it then table.insert(items, it) end
    end
  end
  return items
end

function M.parse(text)
  local block = M.extract_locations_block(text)
  if block == nil then
    return parse_body(text)
  end
  return parse_body(block)
end

local function one_line_preview(body, max)
  max = max or 100
  if not body then return "" end
  local first
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local t = vim.trim(line)
    if t ~= "" then first = t; break end
  end
  first = first or ""
  if #first > max then first = first:sub(1, max - 1) .. "…" end
  return first
end

function M.parse_with_sections(text, ref)
  local out = {}
  if not text or text == "" then
    if ref and ref.filename then
      out[#out + 1] = {
        filename = ref.filename, lnum = 1, col = 1,
        text = "[worklog] " .. vim.fn.fnamemodify(ref.filename, ":t"),
      }
    end
    return out
  end
  local filename = ref and ref.filename
  local section_ranges = {}

  for _, tag in ipairs(SECTION_LIST_FOR_QF) do
    local nodes = find_elements(text, tag)
    if nodes then
      for _, node in ipairs(nodes) do
        local row = select(1, node:start()) or 0
        local _, _, sbyte = node:start()
        local _, _, ebyte = node:end_()
        section_ranges[#section_ranges + 1] = { sbyte or 0, ebyte or 0 }
        local title = element_attr(node, text, "title")
        local body = element_body(node, text)
        local label = title and title ~= "" and ("[" .. tag .. ": " .. title .. "]") or ("[" .. tag .. "]")
        local file_items = parse_body(body)
        if #file_items > 0 then
          for _, fi in ipairs(file_items) do
            local note = fi.text or ""
            fi.text = note ~= "" and (label .. " " .. note) or label
            out[#out + 1] = fi
          end
        elseif filename then
          local preview = one_line_preview(body, 100)
          out[#out + 1] = {
            filename = filename,
            lnum = row + 1,
            col = 1,
            text = preview ~= "" and (label .. " " .. preview) or label,
          }
        end
      end
    end
  end

  local loc_block = M.extract_locations_block(text)
  if loc_block then
    for _, it in ipairs(parse_body(loc_block)) do out[#out + 1] = it end
  else
    local byte = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      local inside = false
      for _, r in ipairs(section_ranges) do
        if byte >= r[1] and byte < r[2] then inside = true; break end
      end
      if not inside then
        local it = split_record(line)
        if it then out[#out + 1] = it end
      end
      byte = byte + #line + 1
    end
  end

  if #out == 0 and filename then
    out[#out + 1] = {
      filename = filename, lnum = 1, col = 1,
      text = "[worklog] " .. vim.fn.fnamemodify(filename, ":t"),
    }
  end
  return out
end

return M
