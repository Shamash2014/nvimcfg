return {
  dir = vim.fn.stdpath("config"),
  name = "djinni",
  dependencies = {
    "folke/snacks.nvim",
    "folke/which-key.nvim",
    "MeanderingProgrammer/render-markdown.nvim",
  },
  ft = { "nowork-chat" },
  keys = {
    { "<leader>fo", function()
      local panel = require("djinni.nowork.panel")
      panel._scan_tasks()
      local groups = panel._get_grouped_tasks()
      local has_tasks = false
      for _, g in ipairs(groups) do
        if #g.tasks > 0 then has_tasks = true; break end
      end
      if not has_tasks then
        vim.notify("No tasks", vim.log.levels.INFO)
        return
      end
      local items = {}
      for _, group in ipairs(groups) do
        for _, task in ipairs(group.tasks) do
          local fname = vim.fn.fnamemodify(task.file_path, ":t"):gsub("%.md$", "")
          table.insert(items, {
            text = group.name .. "/" .. fname,
            project = group.name,
            task = fname,
            file = task.file_path,
          })
        end
      end
      Snacks.picker({
        title = "Nowork Tasks",
        items = items,
        layout = { preset = "vscode", preview = false },
        format = function(item, _)
          return {
            { item.project, "Comment" },
            { " / ", "Comment" },
            { item.task, "Normal" },
          }
        end,
        confirm = function(picker, item)
          picker:close()
          if not item then return end
          require("djinni.nowork.chat").open(item.file)
        end,
      })
    end, desc = "Nowork tasks" },
    { "<leader>fp", function() require("djinni.nowork.panel").toggle() end, desc = "Nowork panel" },
    { "<leader>ft", function() require("djinni.nowork.panel").toggle() end, desc = "Nowork panel" },
  },
  config = function()
    require("djinni").setup()
  end,
}
