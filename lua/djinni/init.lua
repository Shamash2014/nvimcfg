local M = {}

local defaults = {
  panel = {
    height = 15,
    position = "bottom",
  },
  chat = {
    dir = ".chat",
  },
  acp = {
    provider = "claude-code",
    command = "claude-agent-acp",
    args = {},
    idle_timeout = 300000,
  },
}

M.config = vim.tbl_deep_extend("force", {}, defaults)

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  require("djinni.integrations.projects").auto_register()

  vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
      require("djinni.integrations.projects").auto_register()
    end,
  })

  vim.api.nvim_create_user_command("Nowork", function()
    require("djinni.nowork.panel").toggle()
  end, {})

  vim.api.nvim_create_user_command("NoworkNext", function()
    require("djinni.nowork.panel").next_task()
  end, {})

  vim.api.nvim_create_user_command("NoworkPrev", function()
    require("djinni.nowork.panel").prev_task()
  end, {})

  vim.api.nvim_create_user_command("NoworkPick", function()
    require("djinni.integrations.snacks").pick_task()
  end, {})

  vim.api.nvim_create_user_command("NoworkSessions", function()
    require("djinni.integrations.snacks").pick_sessions()
  end, {})

  vim.keymap.set("n", "<leader>oac", function()
    require("djinni.code").create_with_file()
  end, { desc = "Task with file context" })

  vim.keymap.set("v", "<leader>oav", function()
    require("djinni.code").create_with_selection()
  end, { desc = "Task with selection context" })

  vim.keymap.set("n", "<leader>fp", function()
    require("djinni.nowork.panel").toggle()
  end, { desc = "Toggle Nowork panel" })

  vim.keymap.set("n", "<C-q>", function()
    require("djinni.nowork.panel").toggle()
  end, { desc = "Toggle Nowork panel" })

  vim.keymap.set("n", "]c", function()
    require("djinni.nowork.panel").next_task()
  end, { desc = "Next task" })

  vim.keymap.set("n", "[c", function()
    require("djinni.nowork.panel").prev_task()
  end, { desc = "Previous task" })

  if require("djinni.integrations.worktrunk").available() then
    local snacks = require("djinni.integrations.snacks")

    vim.api.nvim_create_user_command("WorktrunkList", function() snacks.action_worktree_list() end, {})
    vim.api.nvim_create_user_command("WorktrunkCreate", function() snacks.action_worktree_create() end, {})
    vim.api.nvim_create_user_command("WorktrunkRemove", function() snacks.action_worktree_remove() end, {})
    vim.api.nvim_create_user_command("WorktrunkMerge", function() snacks.action_worktree_merge() end, {})

    vim.api.nvim_create_user_command("Worktrunk", function()
      require("djinni.integrations.worktrunk_ui").toggle()
    end, {})

    vim.keymap.set("n", "<leader>ow", function()
      require("djinni.integrations.worktrunk_ui").toggle()
    end, { desc = "Worktrunk UI" })

    vim.keymap.set("n", "<leader>owl", function() snacks.action_worktree_list() end, { desc = "List Worktrees" })
    vim.keymap.set("n", "<leader>owc", function() snacks.action_worktree_create() end, { desc = "Create Worktree" })
    vim.keymap.set("n", "<leader>owd", function() snacks.action_worktree_remove() end, { desc = "Remove Worktree" })
    vim.keymap.set("n", "<leader>owm", function() snacks.action_worktree_merge() end, { desc = "Merge Worktree" })

    require("djinni.integrations.worktrunk").start_statusline(30000)
  end
end

return M
