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
end

return M
