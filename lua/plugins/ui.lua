return {
  {
    "stevearc/oil.nvim",
    cmd = { "Oil" },
    config = function()
      local ok, oil = pcall(require, "oil")
      if not ok then
        return
      end

      oil.setup({
        default_file_explorer = false,
        view_options = {
          show_hidden = true,
        },
        keymaps = {
          ["!"] = {
            desc = "Spawn nvim in folder under cursor",
            callback = function()
              local entry = oil.get_cursor_entry()
              local dir = oil.get_current_dir()
              if entry and entry.type == "directory" and dir then
                dir = dir .. entry.name
              end
              if not dir or dir == "" then
                vim.notify("oil: no folder under cursor", vim.log.levels.WARN)
                return
              end
              require("core.task_picker").nvim_in(dir)
            end,
          },
        },
      })
    end,
  },
  {
    "nvim-mini/mini.cursorword",
    lazy = false,
    config = function()
      local ok, cursorword = pcall(require, "mini.cursorword")
      if ok then
        cursorword.setup({})
      end
    end,
  },
  {
    "kevinhwang91/nvim-bqf",
    lazy = false,
    ft = "qf",
    config = function()
      local ok, bqf = pcall(require, "bqf")
      if ok then
        bqf.setup({
          auto_enable = true,
          auto_resize_height = true,
        })
      end
    end,
  },
  {
    "stevearc/quicker.nvim",
    lazy = false,
    config = function()
      local ok, quicker = pcall(require, "quicker")
      if not ok then
        return
      end

      quicker.setup({
        opts = {
          buflisted = false,
          number = false,
          relativenumber = false,
          signcolumn = "auto",
          winfixheight = true,
          wrap = false,
        },
        edit = {
          enabled = true,
          autosave = "unmodified",
        },
        keys = {
          {
            ">",
            function()
              require("quicker").expand({ before = 2, after = 2, add_to_existing = true })
            end,
            desc = "Expand quickfix context",
          },
          {
            "<",
            function()
              require("quicker").collapse()
            end,
            desc = "Collapse quickfix context",
          },
        },
      })
    end,
  },
}
