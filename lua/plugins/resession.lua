return {
  "stevearc/resession.nvim",
  lazy = false,
  opts = {
    dir = "session",
    autosave = {
      enabled = true,
      interval = 60,
      notify = false,
    },
    buf_filter = function(bufnr)
      local buftype = vim.bo[bufnr].buftype
      if buftype == 'help' then
        return false
      end
      if buftype ~= '' and buftype ~= 'acwrite' then
        return false
      end
      return vim.bo[bufnr].buflisted
    end,
    extensions = {
      quickfix = {},
    },
  },
  config = function(_, opts)
    local resession = require('resession')
    resession.setup(opts)

    -- Generate session name from folder
    local function get_session_name()
      local root = require('core.utils').get_project_root()
      if root then
        local folder_name = vim.fn.fnamemodify(root, ':t')
        return string.lower(folder_name)
      else
        return "default"
      end
    end

    -- Auto-save folder-based session on exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        local session_name = get_session_name()
        resession.save(session_name, { notify = false })
      end,
    })

    -- Auto-load folder session on startup if no files were specified
    vim.api.nvim_create_autocmd("VimEnter", {
      callback = function()
        if vim.fn.argc(-1) == 0 then
          local session_name = get_session_name()
          pcall(function()
            resession.load(session_name, { silence_errors = true })
          end)
        end
      end,
    })

    -- Keymaps
    vim.keymap.set("n", "<leader>ps", function()
      local session_name = get_session_name()
      resession.save(session_name)
      vim.notify("Session saved: " .. session_name, vim.log.levels.INFO)
    end, { desc = "Save session" })

    vim.keymap.set("n", "<leader>pl", function()
      local sessions = resession.list()
      if #sessions == 0 then
        vim.notify("No sessions found", vim.log.levels.WARN)
        return
      end

      -- Use Snacks picker directly
      local items = {}
      for _, session in ipairs(sessions) do
        table.insert(items, {
          text = session,
          value = session,
        })
      end

      require("snacks").picker({
        title = "Load Session",
        items = items,
        format = function(item)
          return { { item.text } }
        end,
        layout = { preset = "vscode" },
        confirm = function(picker, item)
          if item and item.value then
            resession.load(item.value, { silence_errors = false })
            vim.notify("Session loaded: " .. item.value, vim.log.levels.INFO)
          end
        end,
      })
    end, { desc = "Load session" })
  end,
}