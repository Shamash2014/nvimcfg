local M = {}

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function strip_quotes(s)
  s = trim(s)
  return s:match('^"(.*)"$') or s:match("^'(.*)'$") or s
end

local function split_heading(rest)
  local dash_idx = rest:find(" — ") or rest:find(" %- ")
  if dash_idx then
    local id = trim(rest:sub(1, dash_idx - 1))
    local desc = trim(rest:sub(dash_idx + (rest:sub(dash_idx, dash_idx + 4) == " — " and 5 or 3)))
    return strip_quotes(id), strip_quotes(desc)
  end
  local id = rest:match("^(%S+)")
  local desc = trim(rest:sub((id or ""):len() + 1))
  return strip_quotes(id or ""), strip_quotes(desc)
end

function M.parse_tasks(text)
  local interior = text:match("<Tasks>%s*\n(.-)\n?%s*</Tasks>") or text

  local tasks = {}
  local current = nil
  local section = nil

  for line in (interior .. "\n"):gmatch("([^\n]*)\n") do
    local trimmed = trim(line)

    if trimmed:match("^##%s+[^#]") then
      local rest = trimmed:match("^##%s+(.+)$")
      local id, desc = split_heading(rest)
      current = { id = id, desc = desc, deps = {}, subtasks = {}, acceptance = {}, context = {}, implementation = {} }
      tasks[#tasks + 1] = current
      section = nil
    elseif current and trimmed:match("^###%s+") then
      local label = trim(trimmed:match("^###%s+(.+)$") or ""):lower()
      if label == "deps" or label == "dependencies" then
        section = "deps"
      elseif label == "subtasks" then
        section = "subtasks"
      elseif label == "acceptance" then
        section = "acceptance"
      elseif label == "context" then
        section = "context"
      elseif label == "implementation" then
        section = "implementation"
      elseif label == "skills" then
        section = "skills"
      else
        section = nil
      end
    elseif current and section then
      if section == "deps" then
        local dep = trimmed:match("^[%-%*]%s+(.+)$")
        if dep then
          dep = strip_quotes(trim(dep))
          if dep ~= "" then current.deps[#current.deps + 1] = dep end
        end
      elseif section == "skills" then
        local skill = trimmed:match("^[%-%*]%s+(.+)$")
        if skill then
          skill = strip_quotes(trim(skill))
          if skill ~= "" then
            current.skills = current.skills or {}
            current.skills[#current.skills + 1] = skill
          end
        end
      elseif section == "subtasks" then
        local done_mark, st_text = trimmed:match("^[%-%*]%s+%[([ xX])%]%s*(.*)$")
        if st_text then
          current.subtasks[#current.subtasks + 1] = {
            text = strip_quotes(trim(st_text)),
            done = done_mark == "x" or done_mark == "X",
          }
        else
          local plain = trimmed:match("^[%-%*]%s+(.+)$")
          if plain then
            current.subtasks[#current.subtasks + 1] = {
              text = strip_quotes(trim(plain)),
              done = false,
            }
          end
        end
      elseif section == "acceptance" then
        local req = trimmed:match("^[%-%*]%s+[Rr]equired:%s*(.+)$")
        local opt = trimmed:match("^[%-%*]%s+[Oo]ptional:%s*(.+)$")
        if req then
          current.acceptance[#current.acceptance + 1] = { required = true, text = strip_quotes(trim(req)) }
        elseif opt then
          current.acceptance[#current.acceptance + 1] = { required = false, text = strip_quotes(trim(opt)) }
        else
          local plain = trimmed:match("^[%-%*]%s+(.+)$")
          if plain then
            current.acceptance[#current.acceptance + 1] = { required = false, text = strip_quotes(trim(plain)) }
          end
        end
      elseif section == "context" then
        local line_text = trimmed:match("^[%-%*]%s+(.+)$")
        if line_text then
          current.context[#current.context + 1] = strip_quotes(trim(line_text))
        end
      elseif section == "implementation" then
        local line_text = trimmed:match("^[%-%*]%s+(.+)$")
        if line_text then
          current.implementation[#current.implementation + 1] = strip_quotes(trim(line_text))
        end
      end
    end
  end

  local id_set = {}
  for _, t in ipairs(tasks) do
    if not t.id or t.id == "" then
      return nil, "task: missing id"
    end
    if not t.desc or t.desc == "" then
      return nil, "task " .. t.id .. ": missing desc"
    end
    if #t.acceptance == 0 then
      return nil, "task " .. t.id .. ": missing acceptance"
    end
    if id_set[t.id] then
      return nil, "task " .. t.id .. ": duplicate id"
    end
    id_set[t.id] = true
  end

  for _, t in ipairs(tasks) do
    for _, dep in ipairs(t.deps) do
      if not id_set[dep] then
        return nil, "task " .. t.id .. ": unknown dep " .. dep
      end
    end
  end

  return tasks, nil
end

function M.has_cycle(tasks)
  local adj = {}
  for _, t in ipairs(tasks) do
    adj[t.id] = t.deps or {}
  end

  for _, t in ipairs(tasks) do
    local visited = {}
    local on_stack = {}
    local stack = { t.id }
    on_stack[t.id] = true

    while #stack > 0 do
      local current = stack[#stack]
      local neighbors = adj[current] or {}
      local pushed = false

      if not visited[current] then
        for _, neighbor in ipairs(neighbors) do
          if on_stack[neighbor] then
            return true
          end
          if not visited[neighbor] then
            on_stack[neighbor] = true
            stack[#stack + 1] = neighbor
            pushed = true
            break
          end
        end
        if not pushed then
          visited[current] = true
          on_stack[current] = nil
          stack[#stack] = nil
        end
      else
        on_stack[current] = nil
        stack[#stack] = nil
      end
    end
  end

  return false
end

function M.topo_sort(tasks)
  local indeg = {}
  local id_to_task = {}

  for _, t in ipairs(tasks) do
    indeg[t.id] = #t.deps
    id_to_task[t.id] = t
  end

  local dependents = {}
  for _, t in ipairs(tasks) do
    for _, dep in ipairs(t.deps) do
      if not dependents[dep] then dependents[dep] = {} end
      dependents[dep][#dependents[dep] + 1] = t.id
    end
  end

  local queue = {}
  for _, t in ipairs(tasks) do
    if indeg[t.id] == 0 then
      queue[#queue + 1] = t.id
    end
  end

  local result = {}
  local head = 1

  while head <= #queue do
    local id = queue[head]
    head = head + 1
    result[#result + 1] = id

    for _, dependent_id in ipairs(dependents[id] or {}) do
      indeg[dependent_id] = indeg[dependent_id] - 1
      if indeg[dependent_id] == 0 then
        queue[#queue + 1] = dependent_id
      end
    end
  end

  if #result < #tasks then
    return nil, "cycle detected"
  end

  return result, nil
end

return M
