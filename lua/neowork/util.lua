local M = {}

local ui = require("djinni.integrations.snacks_ui")
local const = require("neowork.const")

local function pick_provider(provider_name, callback)
  if provider_name and provider_name ~= "" then
    callback(provider_name)
    return
  end

  local Provider = require("djinni.acp.provider")
  local names = Provider.list()
  if #names <= 1 then
    callback(names[1] or nil)
    return
  end

  ui.select(names, { prompt = "Provider:" }, function(choice)
    callback(choice)
  end)
end

function M.slug(name)
  return (name:gsub("%s+", "-"):gsub("[^%w%-_]", ""):lower())
end

function M.unique_slug(root, base)
  local dir = root .. "/.neowork"
  local candidate = base
  local i = 1
  while vim.fn.filereadable(dir .. "/" .. candidate .. ".md") == 1 do
    candidate = base .. "-" .. string.format("%02d", i)
    i = i + 1
  end
  return candidate
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

function M.new_session(root, name, opts)
  opts = opts or {}
  if not name or name == "" then return nil end
  local slug = M.unique_slug(root, M.slug(name))
  local filepath = require("neowork.store").write_session_file(root, slug, {
    project = vim.fn.fnamemodify(root, ":t"),
    root = root,
    provider = opts.provider,
  })
  return filepath
end

function M.new_session_interactive(root, opts, callback)
  opts = opts or {}
  local function create(name)
    if not name or name == "" then
      if callback then callback(nil) end
      return
    end
    pick_provider(opts.provider, function(provider)
      if not provider then
        if callback then callback(nil) end
        return
      end
      local filepath = M.new_session(root, name, { provider = provider })
      if callback then callback(filepath, provider, name) end
    end)
  end

  local name = vim.trim(opts.name or "")
  if name ~= "" then
    create(name)
    return
  end

  vim.ui.input({ prompt = opts.prompt or "Session name: " }, function(input)
    create(vim.trim(input or ""))
  end)
end

return M
