vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("core.options").setup()
if vim.env.NVIM3_TESTING ~= "1" then
  local ok, err = xpcall(function()
    require("core.zpack").setup()
  end, debug.traceback)
  if not ok then
    vim.schedule(function()
      vim.notify(err, vim.log.levels.ERROR, { title = "nvim.3 zpack" })
    end)
  end
end
require("config.theme").apply()
require("core.project").setup()
require("core.env").setup()
require("core.lsp").setup()
require("core.keymaps").setup()
require("core.commands").setup()
require("core.sessions").setup()
require("core.statusline").setup()
require("core.agent_term").setup()
require("core.skills").setup()
require("core.exit").setup()
