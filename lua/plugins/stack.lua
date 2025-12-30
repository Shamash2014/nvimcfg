return {
  {
    dir = vim.fn.stdpath("config") .. "/lua/core/stack",
    name = "stack",
    lazy = false,
    dependencies = { "nvimtools/hydra.nvim" },
    config = function()
      local stack = require("core.stack")
      stack.setup()

      local Hydra = require("hydra")
      local git = require("core.stack.git")
      local config = require("core.stack.config")

      local function hint()
        local current = git.current_branch() or "(detached)"
        local parent = git.get_parent(current)
        local children = git.get_children(current)
        local trunk = config.get_trunk() or "main"

        local status = current
        if parent then
          status = status .. " ← " .. parent
        end
        if #children > 0 then
          status = status .. " → " .. table.concat(children, ", ")
        end

        local lines = {
          " " .. status,
          " trunk: " .. trunk,
          "",
          " _u_ up    _d_ down   _t_ top    _b_ bottom",
          " _C_ commit _m_ amend _e_ edit   _q_ squash",
          " _c_ create _l_ list  _L_ log",
          " _s_ sync   _r_ restack _p_ push _S_ submit",
          " _a_ adopt  _o_ orphan  _D_ delete",
        }
        return table.concat(lines, "\n")
      end

      vim.api.nvim_set_hl(0, "HydraHint", { fg = "#C0C0C0", bg = "#1A1A1A" })
      vim.api.nvim_set_hl(0, "HydraBorder", { fg = "#555555", bg = "#1A1A1A" })
      vim.api.nvim_set_hl(0, "HydraTitle", { fg = "#DDDDDD", bg = "#1A1A1A", bold = true })
      vim.api.nvim_set_hl(0, "HydraRed", { fg = "#FFFFFF", bold = true })
      vim.api.nvim_set_hl(0, "HydraBlue", { fg = "#FFFFFF", bold = true })
      vim.api.nvim_set_hl(0, "HydraAmaranth", { fg = "#FFFFFF", bold = true })
      vim.api.nvim_set_hl(0, "HydraTeal", { fg = "#FFFFFF", bold = true })
      vim.api.nvim_set_hl(0, "HydraPink", { fg = "#FFFFFF", bold = true })

      Hydra({
        name = "Stack",
        hint = hint(),
        config = {
          invoke_on_body = true,
          hint = {
            type = "window",
            position = "bottom-right",
            float_opts = {
              border = "single",
            },
            hide_on_load = false,
          },
        },
        mode = "n",
        body = "<leader>gk",
        heads = {
          { "u", function() stack.up() end, { desc = "up" } },
          { "d", function() stack.down() end, { desc = "down" } },
          { "t", function() stack.top() end, { desc = "top" } },
          { "b", function() stack.bottom() end, { desc = "bottom" } },
          { "C", function() stack.commit() end, { desc = "commit" } },
          { "m", function() stack.modify() end, { desc = "modify" } },
          { "e", function() stack.edit() end, { exit = true, desc = "edit" } },
          { "q", function() stack.squash() end, { exit = true, desc = "squash" } },
          { "c", function() stack.create() end, { exit = true, desc = "create" } },
          { "l", function() stack.list() end, { desc = "list" } },
          { "L", function() stack.log() end, { exit = true, desc = "log" } },
          { "s", function() stack.sync() end, { exit = true, desc = "sync" } },
          { "r", function() stack.restack() end, { exit = true, desc = "restack" } },
          { "p", function() stack.push() end, { exit = true, desc = "push" } },
          { "S", function() stack.submit() end, { exit = true, desc = "submit" } },
          { "a", function() stack.adopt() end, { exit = true, desc = "adopt" } },
          { "o", function() stack.orphan() end, { desc = "orphan" } },
          { "D", function() stack.delete() end, { exit = true, desc = "delete" } },
          { "<Esc>", function() end, { exit = true, nowait = true, desc = "close" } },
        },
      })
    end,
    keys = {
      { "<leader>gk", desc = "Stack popup (Hydra)" },
      { "[k", function() require("core.stack").up() end, desc = "Stack up (parent)" },
      { "]k", function() require("core.stack").down() end, desc = "Stack down (child)" },
    },
  },
  { "nvimtools/hydra.nvim", lazy = true },
}
