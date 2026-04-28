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

  vim.api.nvim_create_user_command("NeoworkAutomation", function()
    require("djinni.automations").pick({ buf = vim.api.nvim_get_current_buf() })
  end, { desc = "Open ACP/task automation picker" })

  vim.api.nvim_create_user_command("NeoworkCodeAction", function()
    require("djinni.automations").pick({ buf = vim.api.nvim_get_current_buf() })
  end, { desc = "Open ACP/task automation picker" })

  local function open_scratch_buffer(scratch_name, content, filetype, refresh)
    local buf_name = "djinni://" .. scratch_name
    local existing = nil
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == buf_name then
        existing = b
        break
      end
    end
    local buf = existing or vim.api.nvim_create_buf(false, true)
    if not existing then
      vim.api.nvim_buf_set_name(buf, buf_name)
    end
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].filetype = filetype
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content or "", "\n"))
    vim.bo[buf].modifiable = false
    local win = vim.fn.bufwinid(buf)
    if win == -1 then
      vim.cmd("vsplit")
      vim.api.nvim_win_set_width(0, 70)
      vim.api.nvim_set_current_buf(buf)
    else
      vim.api.nvim_set_current_win(win)
    end
    vim.keymap.set("n", "q", "<C-w>c", { buffer = buf, noremap = true })
    vim.keymap.set("n", "r", function()
      local new_content = refresh and refresh() or content
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(new_content or "", "\n"))
      vim.bo[buf].modifiable = false
    end, { buffer = buf, noremap = true })
  end

  local function preview_feature(feature_name)
    local pragmas = require("djinni.pragmas")
    open_scratch_buffer(
      "feature/" .. feature_name,
      pragmas.resolve_feature(feature_name) or "",
      "xml",
      function() return pragmas.resolve_feature(feature_name) or "" end
    )
  end

  local function preview_project()
    local pragmas = require("djinni.pragmas")
    open_scratch_buffer(
      "project",
      pragmas.project_context() or "",
      "xml",
      function() return pragmas.project_context() or "" end
    )
  end

  local function preview_coverage()
    local coverage = require("djinni.pragmas.coverage")
    local function build()
      local root = vim.fn.getcwd()
      return coverage.format(coverage.report(root), root)
    end
    open_scratch_buffer("coverage", build(), "markdown", build)
  end

  vim.api.nvim_create_user_command("NeoworkFeatures", function()
    local pragmas = require("djinni.pragmas")
    local items = pragmas.list()
    if #items == 0 then
      vim.notify("No features found", vim.log.levels.WARN)
      return
    end
    local snacks_ok, Snacks = pcall(require, "snacks")
    if snacks_ok and Snacks and Snacks.picker then
      Snacks.picker({
        title = "Features",
        items = vim.tbl_map(function(item)
          return {
            id = item.name,
            text = string.format("%s — %s (%d files)", item.name, item.description:sub(1, 60), item.file_count),
          }
        end, items),
        confirm = function(picker, item)
          if item then
            picker:close()
            preview_feature(item.id)
          end
        end,
      })
    else
      vim.ui.select(vim.tbl_map(function(item) return item.name end, items), {
        prompt = "Select feature: ",
      }, function(choice)
        if choice then preview_feature(choice) end
      end)
    end
  end, { desc = "Browse and preview features" })

  vim.api.nvim_create_user_command("NeoworkFeaturePreview", function(opts)
    local name = opts.args and opts.args ~= "" and opts.args or nil
    if not name then
      vim.ui.input({ prompt = "Feature name: " }, function(input)
        if input and input ~= "" then preview_feature(input) end
      end)
    else
      preview_feature(name)
    end
  end, { desc = "Preview a feature", nargs = "?" })

  vim.api.nvim_create_user_command("NeoworkProjectContext", function()
    preview_project()
  end, { desc = "View project context" })

  vim.api.nvim_create_user_command("NeoworkCoverage", function()
    preview_coverage()
  end, { desc = "Show pragma coverage report" })

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
    vim.o.laststatus = 2
    vim.opt.statusline = require("djinni.statusline").line()
  end

  local keymaps = require("neowork.keymaps")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.b[buf].neowork_chat then
      keymaps.setup_document_keymaps(buf)
    end
  end
end

return M
