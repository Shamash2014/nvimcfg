local M = {}

M.PLAN_COMPLETE = "PLAN_COMPLETE"
M.EVAL_PASS = "EVAL_PASS"
M.EVAL_FAIL = "EVAL_FAIL"
M.TESTS_PASSED = "TESTS_PASSED"
M.TASK_COMPLETE = "TASK_COMPLETE"
M.TASK_BLOCKED = "TASK_BLOCKED"
M.QUESTION = "QUESTION"
M.REQUIREMENT_NOT_MET = "REQUIREMENT_NOT_MET"
M.VALIDATION_PASSED = "VALIDATION_PASSED"
M.VALIDATION_FAILED = "VALIDATION_FAILED"

function M.detect(text)
  local lines = vim.split(text, "\n", { plain = true })
  for i = #lines, 1, -1 do
    local line = vim.trim(lines[i])
    if line == "PLAN_COMPLETE" then
      return "PLAN_COMPLETE", nil
    elseif line == "TESTS_PASSED" then
      return "TESTS_PASSED", nil
    else
      local name, payload = line:match("^(TASK_COMPLETE):(.+)$")
      if name then return name, payload end
      name, payload = line:match("^(TASK_BLOCKED):(.+)$")
      if name then return name, payload end
      name, payload = line:match("^(EVAL_PASS):(.+)$")
      if name then return name, payload end
      name, payload = line:match("^(EVAL_FAIL):(.+)$")
      if name then return name, payload end
      name, payload = line:match("^(QUESTION):(.+)$")
      if name then return name, payload end
      name, payload = line:match("^(VALIDATION_PASSED):?(.+)$")
      if not name and line == "VALIDATION_PASSED" then name = "VALIDATION_PASSED" end
      if name then return name, payload end
      name, payload = line:match("^(VALIDATION_FAILED):?(.+)$")
      if not name and line == "VALIDATION_FAILED" then name = "VALIDATION_FAILED" end
      if name then return name, payload end
      name, payload = line:match("^(REQUIREMENT_NOT_MET):(.+)$")
      if name then return name, payload end
    end
  end
  return nil, nil
end

function M.extract_options(text)
  local block = text:match("<Options>%s*\n?(.-)\n?</Options>")
  if not block then return {} end
  local opts = {}
  for line in (block .. "\n"):gmatch("([^\n]*)\n") do
    local v = vim.trim(line)
    if v ~= "" then
      v = v:gsub("^[%-%*]%s*", ""):gsub("^%d+[%.%)]%s*", ""):gsub("^%[.-%]%s*", "")
      opts[#opts + 1] = v
    end
  end
  return opts
end

function M.extract_ask_user(text)
  local body = text:match("<AskUser>%s*\n?(.-)\n?%s*</AskUser>")
  if not body then return nil, {} end
  local options = {}

  local tasks_block = body:match("<Tasks>%s*\n?(.-)\n?%s*</Tasks>")
  if tasks_block then
    for line in (tasks_block .. "\n"):gmatch("([^\n]*)\n") do
      local rest = line:match("^##%s+(.+)$")
      if rest then
        rest = vim.trim(rest)
        local id, desc
        local dash = rest:find(" — ", 1, true) or rest:find(" %- ")
        if dash then
          id = vim.trim(rest:sub(1, dash - 1))
          desc = vim.trim(rest:sub(dash + (rest:sub(dash, dash + 4) == " — " and 5 or 3)))
        else
          id = rest:match("^(%S+)") or rest
          desc = vim.trim(rest:sub(#id + 1))
        end
        if id and id ~= "" then
          options[#options + 1] = desc ~= "" and ("[" .. id .. "] " .. desc) or id
        end
      end
    end
  end

  local stripped = body:gsub("<Tasks>.-</Tasks>", "")
  local question_lines = {}
  local in_options = false
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%s*<Options>") then
      in_options = true
    elseif line:match("^%s*</Options>") then
      in_options = false
    elseif in_options then
      local v = vim.trim(line)
      if v ~= "" then
        v = v:gsub("^%-%s*", ""):gsub("^%d+[%.%)]%s*", "")
        options[#options + 1] = v
      end
    else
      question_lines[#question_lines + 1] = line
    end
  end
  local question = vim.trim(table.concat(question_lines, "\n"))
  if question == "" then return nil, options end
  return question, options
end

return M
