return {
  "stevearc/quicker.nvim",
  event = "FileType qf",
  keys = {
    { "<leader>fq", function() require("quicker").toggle() end, desc = "Toggle quickfix (quicker)" },
    {
      "<leader>ah",
      function()
        local count = vim.fn.getqflist({ nr = "$" }).nr
        if count == 0 then
          vim.notify("No quickfix history", vim.log.levels.WARN)
          return
        end
        local current = vim.fn.getqflist({ nr = 0 }).nr
        local entries = {}
        for i = 1, count do
          local info = vim.fn.getqflist({ nr = i, title = 0, size = 0 })
          local mark = (i == current) and "●" or " "
          local title = (info.title and info.title ~= "") and info.title or "(no title)"
          entries[#entries + 1] = {
            nr = i,
            label = string.format("%s %d  [%d]  %s", mark, i, info.size or 0, title),
          }
        end
        local labels = {}
        for _, e in ipairs(entries) do labels[#labels + 1] = e.label end
        Snacks.picker.select(labels, { prompt = "Quickfix history" }, function(_, idx)
          if not idx then return end
          local target = entries[idx].nr
          local delta = target - current
          if delta < 0 then
            pcall(vim.cmd, ("silent colder %d"):format(-delta))
          elseif delta > 0 then
            pcall(vim.cmd, ("silent cnewer %d"):format(delta))
          end
          require("quicker").open({ focus = true })
        end)
      end,
      desc = "qf: history picker",
    },
  },
  opts = {},
  init = function()
    vim.api.nvim_create_autocmd("QuickFixCmdPost", {
      pattern = { "grep", "grepadd", "vimgrep", "vimgrepadd", "cexpr", "cgetexpr", "caddexpr", "cbuffer", "cgetbuffer", "caddbuffer", "cfile", "cgetfile", "caddfile", "make" },
      callback = function()
        if #vim.fn.getqflist() > 0 then
          require("quicker").open({ focus = false })
        end
      end,
    })

    pcall(vim.cmd, "packadd cfilter")

    local function filter_cmd_for_current_win()
      local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
      return (info and info.loclist == 1) and "Lfilter" or "Cfilter"
    end

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "qf",
      callback = function(args)
        local buf = args.buf

        vim.keymap.set("n", "<C-j>", "j", { buffer = buf, desc = "qf: next item" })
        vim.keymap.set("n", "<C-k>", "k", { buffer = buf, desc = "qf: prev item" })

        vim.keymap.set("n", "f", function()
          vim.ui.input({ prompt = "Filter (keep): " }, function(pat)
            if pat and pat ~= "" then
              pcall(vim.cmd, filter_cmd_for_current_win() .. " /" .. pat .. "/")
            end
          end)
        end, { buffer = buf, desc = "qf: filter (keep matches)" })

        vim.keymap.set("n", "F", function()
          vim.ui.input({ prompt = "Filter (drop): " }, function(pat)
            if pat and pat ~= "" then
              pcall(vim.cmd, filter_cmd_for_current_win() .. "! /" .. pat .. "/")
            end
          end)
        end, { buffer = buf, desc = "qf: filter (drop matches)" })

        vim.keymap.set("n", "<localleader>qq", function()
          local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
          if info and info.loclist == 1 then
            vim.fn.setloclist(0, {}, "r", { items = {}, title = "" })
            vim.notify("loclist cleared", vim.log.levels.INFO)
          else
            vim.fn.setqflist({}, "r", { items = {}, title = "" })
            vim.notify("quickfix cleared", vim.log.levels.INFO)
          end
        end, { buffer = buf, desc = "qf: clear list" })
      end,
    })
  end,
}
