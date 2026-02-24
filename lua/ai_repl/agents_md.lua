local M = {}

local DEFAULT_SEARCH_PATHS = {
  "AGENTS.md",
  ".agents.md",
  "docs/AGENTS.md",
  ".github/AGENTS.md",
}

function M.find_agents_md(cwd)
  cwd = cwd or vim.fn.getcwd()

  for _, path in ipairs(DEFAULT_SEARCH_PATHS) do
    local full_path = vim.fn.fnamemodify(cwd .. "/" .. path, ":p")
    if vim.fn.filereadable(full_path) == 1 then
      return full_path
    end
  end

  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --show-toplevel 2>/dev/null")[1]
  if git_root and git_root ~= "" then
    for _, path in ipairs(DEFAULT_SEARCH_PATHS) do
      local full_path = vim.fn.fnamemodify(git_root .. "/" .. path, ":p")
      if vim.fn.filereadable(full_path) == 1 then
        return full_path
      end
    end
  end

  return nil
end

function M.read_agents_md(file_path)
  if not file_path or vim.fn.filereadable(file_path) ~= 1 then
    return nil, "File not readable: " .. tostring(file_path)
  end

  local ok, lines = pcall(vim.fn.readfile, file_path)
  if not ok then
    return nil, "Failed to read file: " .. file_path
  end

  return table.concat(lines, "\n"), nil
end

function M.get_context_for_session(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()

  local agents_md_path = M.find_agents_md(cwd)
  if not agents_md_path then
    return nil
  end

  local content, err = M.read_agents_md(agents_md_path)
  if err then
    if opts.debug then
      vim.notify("[agents_md] " .. err, vim.log.levels.WARN)
    end
    return nil
  end

  return {
    path = agents_md_path,
    content = content,
  }
end

function M.format_as_prompt_block(agents_md_content)
  if not agents_md_content then
    return nil
  end

  return {
    type = "text",
    text = string.format(
      [[Project Context from AGENTS.md:

%s

Please follow the guidelines and context provided above when working on this project.]],
      agents_md_content
    )
  }
end

function M.inject_into_session_prompt(prompt, agents_md_content)
  if not agents_md_content then
    return prompt
  end

  local context_block = M.format_as_prompt_block(agents_md_content)
  if not context_block then
    return prompt
  end

  if type(prompt) == "string" then
    return {
      context_block,
      { type = "text", text = prompt }
    }
  elseif type(prompt) == "table" then
    local new_prompt = { context_block }
    for _, block in ipairs(prompt) do
      table.insert(new_prompt, block)
    end
    return new_prompt
  end

  return prompt
end

function M.create_system_context(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()

  local context_info = M.get_context_for_session({ cwd = cwd, debug = opts.debug })
  if not context_info then
    return nil
  end

  return {
    type = "system_context",
    source = "AGENTS.md",
    path = context_info.path,
    content = context_info.content,
  }
end

function M.should_inject(opts)
  opts = opts or {}

  if opts.disable_agents_md then
    return false
  end

  if opts.force_agents_md then
    return true
  end

  return true
end

function M.get_status(cwd)
  cwd = cwd or vim.fn.getcwd()
  local path = M.find_agents_md(cwd)

  return {
    found = path ~= nil,
    path = path,
  }
end

return M
