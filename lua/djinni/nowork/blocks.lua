local M = {}

local SEPARATOR_CHAR = "~"

local function is_separator(line)
  return line:match("^%-%-%-$")
end

local function is_input_separator(line)
  return line:match("^" .. SEPARATOR_CHAR .. "+$")
end

local function is_block_header(line)
  local t = line:match("^@(%w+)%s*$")
  if t then
    t = t:lower()
    if t == "you" or t == "djinni" or t == "system" then
      return t
    end
  end
  return nil
end

local function extract_refs(content)
  local refs = {}
  for line in content:gmatch("[^\n]+") do
    local ref = line:match("^(@%./.+)") or line:match("^(@{.+})")
    if ref then
      refs[#refs + 1] = ref
    end
    local file_path = line:match("%[#file%]%((.-)%)")
    if file_path then
      refs[#refs + 1] = "@./" .. file_path
    end
  end
  return refs
end

function M.parse(lines)
  local blocks = {}
  local i = 1
  local n = #lines

  if n == 0 then
    return blocks
  end

  if is_separator(lines[1] or "") then
    local fm_start = 1
    local fm_end = nil
    for j = 2, n do
      if is_separator(lines[j]) then
        fm_end = j
        break
      end
    end
    if fm_end then
      local content_lines = {}
      for j = fm_start + 1, fm_end - 1 do
        content_lines[#content_lines + 1] = lines[j]
      end
      blocks[#blocks + 1] = {
        type = "frontmatter",
        content = table.concat(content_lines, "\n"),
        start_line = fm_start,
        end_line = fm_end,
      }
      i = fm_end + 1
    end
  end

  local current_block = nil

  local function flush()
    if not current_block then
      return
    end
    local content = table.concat(current_block._lines, "\n")
    content = content:gsub("^%s+", ""):gsub("%s+$", "")
    current_block.content = content
    if current_block.type == "you" then
      current_block.refs = extract_refs(content)
    end
    current_block._lines = nil
    blocks[#blocks + 1] = current_block
    current_block = nil
  end

  while i <= n do
    local line = lines[i]

    if is_input_separator(line) then
      flush()
      blocks[#blocks + 1] = {
        type = "input_zone",
        start_line = i,
        end_line = n,
      }
      break
    elseif is_separator(line) then
      flush()
      blocks[#blocks + 1] = {
        type = "separator",
        start_line = i,
        end_line = i,
      }
      i = i + 1
    else
      local header = is_block_header(line)
      if header and not current_block then
        current_block = {
          type = header,
          start_line = i,
          end_line = i,
          _lines = {},
        }
        i = i + 1
      elseif header and current_block then
        flush()
        current_block = {
          type = header,
          start_line = i,
          end_line = i,
          _lines = {},
        }
        i = i + 1
      else
        if current_block then
          current_block._lines[#current_block._lines + 1] = line
          current_block.end_line = i
        end
        i = i + 1
      end
    end
  end

  flush()
  return blocks
end

function M.serialize(blocks)
  local lines = {}
  local function add(l)
    lines[#lines + 1] = l
  end

  for _, block in ipairs(blocks) do
    if block.type == "frontmatter" then
      add("---")
      for line in block.content:gmatch("[^\n]+") do
        add(line)
      end
      add("---")
    elseif block.type == "separator" then
      add("---")
    elseif block.type == "you" then
      add("@You")
      if block.content and block.content ~= "" then
        for line in block.content:gmatch("[^\n]*") do
          add(line)
        end
      end
    elseif block.type == "djinni" then
      add("@Djinni")
      if block.content and block.content ~= "" then
        for line in block.content:gmatch("[^\n]*") do
          add(line)
        end
      end
    elseif block.type == "system" then
      add("@System")
      if block.content and block.content ~= "" then
        for line in block.content:gmatch("[^\n]*") do
          add(line)
        end
      end
    elseif block.type == "input_zone" then
      add(string.rep(SEPARATOR_CHAR, 45))
      add("")
    end
  end

  return lines
end

function M.find_block_at(blocks, line_nr)
  for _, block in ipairs(blocks) do
    if line_nr >= block.start_line and line_nr <= block.end_line then
      return block
    end
  end
  return nil
end

function M.get_frontmatter(blocks)
  for _, block in ipairs(blocks) do
    if block.type == "frontmatter" then
      local result = {}
      for line in block.content:gmatch("[^\n]+") do
        local key, value = line:match("^([%w_]+):%s*(.*)")
        if key then
          value = value:gsub("^%s+", ""):gsub("%s+$", "")
          if value == "" then
            result[key] = nil
          else
            result[key] = value
          end
        end
      end
      return result
    end
  end
  return {}
end

return M
