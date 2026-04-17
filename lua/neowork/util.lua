local M = {}

local const = require("neowork.const")

function M.slug(name)
  return (name:gsub("%s+", "-"):gsub("[^%w%-_]", ""):lower())
end

function M.is_role_line(line)
  return line:sub(1, #const.role.user) == const.role.user
    or line:sub(1, #const.role.agent) == const.role.agent
    or line:sub(1, #const.role.system) == const.role.system
end

function M.role_of(line)
  if not line then return nil end
  if line:sub(1, #const.role.user) == const.role.user then return "You" end
  if line:sub(1, #const.role.agent) == const.role.agent then return "Djinni" end
  if line:sub(1, #const.role.system) == const.role.system then return "System" end
  return nil
end

function M.lazy(modname)
  local cached
  return function()
    if cached then return cached end
    local ok, mod = pcall(require, modname)
    if ok then cached = mod end
    return cached
  end
end

function M.jump_to_marker(buf, dir)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local from, to, step
  if dir == 1 then
    from, to, step = cursor + 1, #lines, 1
  else
    from, to, step = cursor - 1, 1, -1
  end
  for i = from, to, step do
    if M.is_role_line(lines[i]) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return
    end
  end
end

function M.new_session(root, name)
  if not name or name == "" then return nil end
  local slug = M.slug(name)
  local filepath = require("neowork.store").write_session_file(root, slug, {
    project = vim.fn.fnamemodify(root, ":t"),
    root = root,
  })
  return filepath
end

return M
