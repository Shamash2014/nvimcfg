local M = {}

local state_file = vim.fn.stdpath("state") .. "/nvim-profile"
local known_profiles = {
  default = true,
  focus = true,
}

local function read_state()
  local file = io.open(state_file, "r")
  if not file then
    return nil
  end

  local value = file:read("*l")
  file:close()

  if value == nil or value == "" or not known_profiles[value] then
    return nil
  end

  return value
end

local function write_state(name)
  vim.fn.mkdir(vim.fn.stdpath("state"), "p")

  local file = io.open(state_file, "w")
  if not file then
    return
  end

  file:write(name, "\n")
  file:close()
end

function M.available()
  return { "default", "focus" }
end

function M.current()
  return vim.g.nvim_profile or "default"
end

function M.resolve()
  local env_profile = vim.env.NVIM_PROFILE
  if env_profile and env_profile ~= "" and known_profiles[env_profile] then
    return env_profile
  end

  return read_state() or "default"
end

function M.set(name, persist)
  if not known_profiles[name] then
    error("Unknown Neovim profile: " .. name)
  end

  vim.g.nvim_profile = name
  if persist then
    write_state(name)
  end
end

function M.apply()
  require("config.options").apply()
  require("config.theme").apply()
end

function M.pick()
  vim.ui.select(M.available(), {
    prompt = "Select Neovim profile",
  }, function(choice)
    if not choice then
      return
    end

    M.set(choice, true)
    M.apply()
    vim.notify("Switched profile to " .. M.current(), vim.log.levels.INFO, { title = "Neovim profile" })
  end)
end

function M.setup()
  M.set(M.resolve(), false)
  M.apply()

  vim.api.nvim_create_user_command("Profile", function(opts)
    if opts.args == "" then
      vim.notify(
        "Current profile: " .. M.current() .. " | Available: " .. table.concat(M.available(), ", "),
        vim.log.levels.INFO,
        { title = "Neovim profile" }
      )
      return
    end

    M.set(opts.args, true)
    M.apply()
    vim.notify("Switched profile to " .. M.current(), vim.log.levels.INFO, { title = "Neovim profile" })
  end, {
    nargs = "?",
    complete = function()
      return M.available()
    end,
  })

  vim.api.nvim_create_user_command("ProfilePick", function()
    M.pick()
  end, {})

  vim.api.nvim_create_user_command("ProfileReload", function()
    M.apply()
  end, {})
end

return M
