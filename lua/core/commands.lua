local M = {}

local function create(name, rhs, opts)
  vim.api.nvim_create_user_command(name, rhs, opts or {})
end

function M.setup()
  create("SessionSave", function()
    require("core.sessions").save()
  end, { desc = "Save session for cwd" })

  create("SessionLoad", function()
    require("core.sessions").load()
  end, { desc = "Load recent session" })

  create("SessionReload", function()
    require("core.sessions").reload()
  end, { desc = "Reload cwd session into a new tab" })
end

return M
