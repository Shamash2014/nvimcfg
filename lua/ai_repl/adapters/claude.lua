local M = {}

function M.path_to_claude_folder(path)
  return path:gsub("/", "-")
end

function M.get_session_file(project_root, session_id)
  local folder = M.path_to_claude_folder(project_root)
  return vim.fn.expand("~/.claude/projects/" .. folder .. "/" .. session_id .. ".jsonl")
end

function M.read_session_messages(project_root, session_id)
  local file = M.get_session_file(project_root, session_id)
  if vim.fn.filereadable(file) == 0 then return nil end

  local messages = {}
  for line in io.lines(file) do
    local ok, entry = pcall(vim.json.decode, line)
    if ok and (entry.type == "user" or entry.type == "assistant") then
      local content = entry.message and entry.message.content
      if type(content) == "table" then
        local text_parts = {}
        for _, block in ipairs(content) do
          if block.type == "text" and block.text then
            table.insert(text_parts, block.text)
          end
        end
        content = table.concat(text_parts, "")
      end
      if content and content ~= "" then
        table.insert(messages, {
          role = entry.type,
          content = content
        })
      end
    end
  end
  return messages
end

return M
