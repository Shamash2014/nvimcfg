local M = {}

local defaults = {
  acp = {
    provider = "claude-code",
    command = "claude-agent-acp",
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

  vim.api.nvim_create_user_command("NeoworkTask", function()
    require("djinni.code").create_task()
  end, { desc = "Create a new neowork task" })

  vim.api.nvim_create_user_command("NeoworkPick", function()
    require("djinni.integrations.snacks").pick_task()
  end, { desc = "Browse neowork tasks" })

  vim.api.nvim_create_user_command("NeoworkSessions", function()
    require("djinni.integrations.snacks").pick_sessions()
  end, { desc = "Browse neowork sessions" })

  vim.api.nvim_create_user_command("NeoworkConsole", function()
    require("djinni.code").create_task()
  end, { desc = "Create a new neowork task" })

  vim.api.nvim_create_user_command("NeoworkSplit", function()
    local document = require("neowork.document")
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local wb = vim.api.nvim_win_get_buf(win)
      if vim.b[wb].neowork_chat then
        vim.cmd("vsplit")
        vim.api.nvim_set_current_buf(wb)
        return
      end
    end
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.b[b].neowork_chat then
        vim.cmd("vsplit")
        vim.api.nvim_set_current_buf(b)
        return
      end
    end
    local filepath = require("neowork.util").new_session(
      require("core.utils").get_project_root() or vim.fn.getcwd(),
      "session " .. os.date("!%Y%m%dT%H%M%S")
    )
    if filepath then document.open(filepath, { split = "vsplit" }) end
  end, { desc = "Open neowork in a vertical split" })


  vim.keymap.set("n", "<C-q>", function()
    require("djinni.code").create_task()
  end, { desc = "New neowork task" })


  vim.keymap.set("n", "]c", function()
    require("djinni.integrations.snacks").pick_task()
  end, { desc = "Browse neowork tasks" })

  vim.keymap.set("n", "[c", function()
    require("djinni.integrations.snacks").pick_sessions()
  end, { desc = "Browse neowork sessions" })

  vim.keymap.set("n", "<C-6>", function()
    require("djinni.integrations.snacks").pick_sessions()
  end, { desc = "Switch last session" })

  if require("djinni.integrations.worktrunk").available() then
    local snacks = require("djinni.integrations.snacks")

    vim.api.nvim_create_user_command("WorktrunkList", function() snacks.action_worktree_list() end, {})
    vim.api.nvim_create_user_command("WorktrunkCreate", function() snacks.action_worktree_create() end, {})
    vim.api.nvim_create_user_command("WorktrunkRemove", function() snacks.action_worktree_remove() end, {})
    vim.api.nvim_create_user_command("WorktrunkMerge", function() snacks.action_worktree_merge() end, {})

    vim.api.nvim_create_user_command("WorktrunkInit", function(cmd)
      require("djinni.integrations.worktrunk").init({ force = cmd.bang }, function(ok, path, msg)
        vim.schedule(function()
          if ok then
            vim.notify("[wt] " .. msg, vim.log.levels.INFO)
            if path then vim.cmd("split " .. vim.fn.fnameescape(path)) end
          else
            vim.notify("[wt] init failed: " .. (msg or "unknown"), vim.log.levels.ERROR)
          end
        end)
      end)
    end, { bang = true, desc = "Initialize .config/wt.toml for this repo" })

    require("djinni.integrations.worktrunk").start_statusline(30000)
  end

  local keymaps = require("neowork.keymaps")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.b[buf].neowork_chat then
      keymaps.setup_document_keymaps(buf)
    end
  end
end

return M
