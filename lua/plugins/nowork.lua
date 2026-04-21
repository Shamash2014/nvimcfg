return {
  dir = vim.fn.stdpath("config"),
  name = "nowork",
  dependencies = {
    "folke/snacks.nvim",
  },
  cmd = {
    "Nowork",
    "NoworkSay",
    "NoworkCancel",
    "NoworkDone",
    "NoworkPicker",
    "NoworkChatToQfix",
    "NoworkToggleAutoApply",
    "NoworkQfixFromLog",
    "NoworkShadow",
    "NoworkMailbox",
  },
  keys = {
    { "<leader>as", function() require("djinni.nowork").launch("explore") end, desc = "nowork: explore" },
    { "<leader>aw", function() require("djinni.nowork").launch("routine") end, desc = "nowork: routine" },
    { "<leader>aa", function() require("djinni.nowork").launch("autorun") end, desc = "nowork: autorun" },
    { "<leader>ao", function()
      require("djinni.nowork.overview").open({ all_projects = true, label = "projects", project_visit_split = "vsplit" })
    end, desc = "nowork: projects (all)" },
    { "<leader>al", function()
      require("djinni.nowork.picker").pick({ include_history = true, include_archive = true })
    end, desc = "nowork: logs (active + recent + archive)" },
    { "<leader>ap", function()
      require("djinni.nowork.mailbox").open()
    end, desc = "nowork: permissions mailbox" },
    { "<leader>av", mode = "x", function()
      local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
      if l1 > l2 then l1, l2 = l2, l1 end
      vim.cmd("normal! \27")
      local bufname = vim.fn.expand("%:.")
      local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
      local ft = vim.bo.filetype or ""
      local snippet = table.concat({
        "From `" .. bufname .. ":" .. l1 .. "-" .. l2 .. "`:",
        "",
        "```" .. ft,
        table.concat(lines, "\n"),
        "```",
        "",
      }, "\n")
      require("djinni.nowork.capture").route(snippet)
    end, desc = "nowork: capture selection → routine droid" },
    { "<leader>ac", mode = "n", function()
      local picker = require("djinni.nowork.picker")
      local alt_buf = vim.fn.bufnr("#")
      if picker.count({ mode_filter = { "routine", "autorun" } }) == 0 then
        require("djinni.nowork.compose").open(nil, {
          alt_buf = alt_buf,
          title = " compose → new routine droid ",
          on_submit = function(text) require("djinni.nowork").routine(text, {}) end,
        })
        return
      end
      picker.pick({
        mode_filter = { "routine", "autorun" },
        on_droid = function(d)
          require("djinni.nowork.compose").open(d, { alt_buf = alt_buf })
        end,
      })
    end, desc = "nowork: compose to droid (or launch)" },
    { "<leader>yq", mode = "n", function()
      local info = vim.fn.getqflist({ items = 0 })
      if #(info.items or {}) == 0 then
        vim.notify("nowork: quickfix list is empty", vim.log.levels.WARN)
        return
      end
      local picker = require("djinni.nowork.picker")
      if picker.count({ mode_filter = { "routine", "autorun" } }) == 0 then
        vim.notify("nowork: no routine/autorun droids — start one with <leader>aw or <leader>aa", vim.log.levels.WARN)
        return
      end
      local share = require("djinni.nowork.qfix_share")
      local marks = require("djinni.nowork.qf_marks")
      local use_marks = marks.has_marks()
      picker.pick({ mode_filter = { "routine", "autorun" }, on_droid = function(d)
        if use_marks then share.share_marked(d) else share.share_full(d) end
      end })
    end, desc = "nowork: share qflist to droid" },
    { "<leader>yq", mode = "x", function()
      if vim.bo.filetype ~= "qf" then
        vim.notify("nowork: yq visual only works in quickfix window", vim.log.levels.WARN)
        return
      end
      local l1 = vim.fn.line("v")
      local l2 = vim.fn.line(".")
      if l1 > l2 then l1, l2 = l2, l1 end
      vim.cmd("normal! \27")
      local info = vim.fn.getqflist({ items = 0 })
      if #(info.items or {}) == 0 then
        vim.notify("nowork: quickfix list is empty", vim.log.levels.WARN)
        return
      end
      local picker = require("djinni.nowork.picker")
      if picker.count({ mode_filter = { "routine", "autorun" } }) == 0 then
        vim.notify("nowork: no routine/autorun droids — start one with <leader>aw or <leader>aa", vim.log.levels.WARN)
        return
      end
      picker.pick({
        mode_filter = { "routine", "autorun" },
        on_droid = function(d) require("djinni.nowork.qfix_share").share_range(d, l1, l2) end,
      })
    end, desc = "nowork: share qf range to droid" },
    { "<leader>yQ", mode = "n", function()
      local picker = require("djinni.nowork.picker")
      if picker.count() == 0 then
        vim.notify("nowork: no active droids", vim.log.levels.WARN)
        return
      end
      picker.pick({ on_droid = function(d)
        local bag = d.state and d.state.touched
        if bag and bag.items and #bag.items > 0 then
          require("djinni.nowork.qfix_share").flush_touched(d)
        else
          require("djinni.nowork.qfix_share").pull_from_droid(d)
        end
      end })
    end, desc = "nowork: pull from droid (touched→qflist or log parse)" },
  },
  config = function()
    require("djinni.nowork").setup()
  end,
}
