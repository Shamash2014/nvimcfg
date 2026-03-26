local M = {}

local function trim(s)
  if not s then return "" end
  return s:match("^%s*(.-)%s*$")
end

local function is_test_case_header(text)
  local patterns = {
    "^TC%-",
    "^TEST%-",
    "^CASE%-",
    "^[A-Z]+%-[A-Z]*%-?%d+",
  }
  local upper = text:upper()
  for _, pattern in ipairs(patterns) do
    if upper:match(pattern) then
      return true
    end
  end
  return false
end

local function parse_test_header(line)
  local h3 = line:match("^###%s+(.+)$")
  if h3 and is_test_case_header(h3) then
    local id, name = h3:match("^([%w%-]+):%s*(.+)$")
    return { level = 3, id = id, name = name, full = h3 }
  end

  local h2 = line:match("^##%s+(.+)$")
  if h2 and not line:match("^###") and is_test_case_header(h2) then
    local id, name = h2:match("^([%w%-]+):%s*(.+)$")
    return { level = 2, id = id, name = name, full = h2 }
  end

  return nil
end

local function parse_metadata_row(line)
  local field, value = line:match("^|%s*%*%*([^*]+)%*%*%s*|%s*(.-)%s*|$")
  if field and value then
    return trim(field), trim(value)
  end
  field, value = line:match("^|%s*([^|]+)%s*|%s*(.-)%s*|$")
  if field and value and not field:match("^%-+$") then
    return trim(field), trim(value)
  end
  return nil, nil
end

local function parse_step_row(line)
  local step, action, expected = line:match("^|%s*(%d+)%s*|%s*(.-)%s*|%s*(.-)%s*|$")
  if step then
    return {
      number = tonumber(step),
      text = trim(action),
      expected = trim(expected),
    }
  end
  return nil
end

local function parse_simple_step(line)
  local num, text = line:match("^(%d+)%.%s+(.+)$")
  if num then
    return { number = tonumber(num), text = trim(text) }
  end
  return nil
end

local function parse_list_item(line)
  local text = line:match("^%s*[%-*]%s+(.+)$")
  if text then
    return trim(text)
  end
  return nil
end

local function parse_tags(line)
  local tags = {}
  local tag_str = line:match("^@tags:%s*(.+)$")
  if tag_str then
    for tag in tag_str:gmatch("[^,%s]+") do
      table.insert(tags, tag)
    end
  end
  return tags
end

local function parse_priority(line)
  return line:match("^@priority:%s*(.+)$")
end

function M.parse_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tests = {}
  local current_test = nil
  local current_section = nil
  local suite_name = nil
  local in_metadata_table = false
  local in_steps_table = false

  for i, line in ipairs(lines) do
    local h1 = line:match("^#%s+(.+)$")
    if h1 and not line:match("^##") then
      suite_name = trim(h1)
    end

    local header = parse_test_header(line)
    if header then
      if current_test then
        table.insert(tests, current_test)
      end
      current_test = {
        id = header.id or header.full,
        name = header.name or header.full,
        full_title = header.full,
        tags = {},
        priority = nil,
        type = nil,
        preconditions = {},
        steps = {},
        expected = {},
        postconditions = {},
        line_number = i,
      }
      current_section = "metadata"
      in_metadata_table = false
      in_steps_table = false
    elseif current_test then
      local is_other_header = line:match("^##[#]?%s+") and not parse_test_header(line)
      if is_other_header then
        table.insert(tests, current_test)
        current_test = nil
        current_section = nil
        in_metadata_table = false
        in_steps_table = false
        goto continue
      end

      local tags = parse_tags(line)
      if #tags > 0 then
        current_test.tags = tags
      end

      local priority = parse_priority(line)
      if priority then
        current_test.priority = trim(priority)
      end

      if line:match("^%*%*Test Steps") or line:match("^###%s*Steps") or line:match("^### Steps") then
        current_section = "steps"
        in_steps_table = false
        in_metadata_table = false
      elseif line:match("^%*%*Postconditions?") or line:match("^###%s*Postconditions?") then
        current_section = "postconditions"
        in_steps_table = false
        in_metadata_table = false
      elseif line:match("^###%s*Preconditions?") then
        current_section = "preconditions"
        in_steps_table = false
        in_metadata_table = false
      elseif line:match("^###%s*Expected") then
        current_section = "expected"
        in_steps_table = false
        in_metadata_table = false
      end

      if line:match("^|%s*Field%s*|") or line:match("^|%s*%*%*ID%*%*") then
        in_metadata_table = true
        in_steps_table = false
      elseif line:match("^|%s*Step%s*|") then
        in_steps_table = true
        in_metadata_table = false
        current_section = "steps"
      end

      if line:match("^|%-+|") then
        goto continue
      end

      if in_metadata_table then
        local field, value = parse_metadata_row(line)
        if field and value and value ~= "" then
          local f = field:lower()
          if f == "priority" then
            current_test.priority = value
          elseif f == "type" then
            current_test.type = value
          elseif f:match("precondition") then
            table.insert(current_test.preconditions, value)
          elseif f == "tags" then
            for tag in value:gmatch("[^,%s]+") do
              table.insert(current_test.tags, tag)
            end
          end
        end
      elseif in_steps_table or current_section == "steps" then
        local step = parse_step_row(line)
        if step then
          table.insert(current_test.steps, step)
          if step.expected and step.expected ~= "" then
            table.insert(current_test.expected, step.expected)
          end
        else
          step = parse_simple_step(line)
          if step then
            table.insert(current_test.steps, step)
          end
        end
      elseif current_section == "preconditions" then
        local item = parse_list_item(line)
        if item then
          table.insert(current_test.preconditions, item)
        end
      elseif current_section == "expected" then
        local item = parse_list_item(line)
        if item then
          table.insert(current_test.expected, item)
        end
      elseif current_section == "postconditions" then
        local text = line:match("^%*%*Postconditions?:%*%*%s*(.+)$")
        if text then
          table.insert(current_test.postconditions, trim(text))
        else
          local item = parse_list_item(line)
          if item then
            table.insert(current_test.postconditions, item)
          end
        end
      end
    end

    ::continue::
  end

  if current_test then
    table.insert(tests, current_test)
  end

  return {
    suite_name = suite_name or "Test Suite",
    tests = tests,
  }
end

function M.parse_file(filepath)
  local lines = vim.fn.readfile(filepath)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  local result = M.parse_buffer(bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  return result
end

return M
