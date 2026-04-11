local M = {}

local defaults = {
  panel = {
    width = 40,
  },
  chat = {
    dir = ".chat",
  },
  acp = {
    provider = "claude-code",
    command = "claude-agent-acp",
    args = {},
    idle_timeout = 300000,
    providers = {},
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

  vim.api.nvim_create_user_command("NoworkTask", function()
    require("djinni.nowork.task").toggle()
  end, {})

  vim.api.nvim_create_user_command("NoworkPick", function()
    require("djinni.integrations.snacks").pick_task()
  end, {})

  vim.api.nvim_create_user_command("NoworkSessions", function()
    require("djinni.integrations.snacks").pick_sessions()
  end, {})


  vim.api.nvim_create_user_command("NoworkConsole", function()
    require("djinni.nowork.panel").toggle()
  end, {})

  vim.api.nvim_create_user_command("NoworkSplit", function()
    local chat = require("djinni.nowork.chat")
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local wb = vim.api.nvim_win_get_buf(win)
      if vim.bo[wb].filetype == "nowork-chat" then
        vim.cmd("vsplit")
        vim.api.nvim_set_current_buf(wb)
        return
      end
    end
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "nowork-chat" then
        vim.cmd("vsplit")
        vim.api.nvim_set_current_buf(b)
        return
      end
    end
    local root = require("core.utils").get_project_root() or vim.fn.getcwd()
    chat.create(root, { split = true })
  end, {})

  vim.keymap.set("n", "gac", function()
    require("djinni.code").create_with_file()
  end, { desc = "Task with file context" })

  vim.keymap.set("v", "gav", function()
    require("djinni.code").create_with_selection()
  end, { desc = "Task with selection context" })

  vim.keymap.set("v", "gas", function()
    require("djinni.code").send_selection_to_chat()
  end, { desc = "Send selection to chat" })

  vim.keymap.set("n", "<C-q>", function()
    require("djinni.nowork.panel").toggle()
  end, { desc = "Toggle Nowork panel" })


  vim.keymap.set("n", "]c", function()
    require("djinni.nowork.panel").next_task()
  end, { desc = "Next task" })

  vim.keymap.set("n", "[c", function()
    require("djinni.nowork.panel").prev_task()
  end, { desc = "Previous task" })

  vim.keymap.set("n", "<C-6>", function()
    require("djinni.nowork.panel").switch_last_session()
  end, { desc = "Switch last session" })

  if require("djinni.integrations.worktrunk").available() then
    local snacks = require("djinni.integrations.snacks")

    vim.api.nvim_create_user_command("WorktrunkList", function() snacks.action_worktree_list() end, {})
    vim.api.nvim_create_user_command("WorktrunkCreate", function() snacks.action_worktree_create() end, {})
    vim.api.nvim_create_user_command("WorktrunkRemove", function() snacks.action_worktree_remove() end, {})
    vim.api.nvim_create_user_command("WorktrunkMerge", function() snacks.action_worktree_merge() end, {})

    require("djinni.integrations.worktrunk").start_statusline(30000)
  end

  local chat = require("djinni.nowork.chat")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "nowork-chat" then
      chat.attach(buf)
      chat._ensure_session(buf)
    end
  end
end

return M
