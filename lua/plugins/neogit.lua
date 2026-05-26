return {
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      local ok, neogit = pcall(require, "neogit")
      if not ok then
        return
      end

      neogit.setup({
        kind = "split",
        disable_hint = true,
        graph_style = "unicode",
        diff_viewer = "codediff",
        commit_editor = {
          kind = "split",
        },
        commit_select_view = {
          kind = "split",
        },
        popup = {
          kind = "split",
        },
        integrations = {
          codediff = true,
        },
        mappings = {
          status = {
            ["w"] = function()
              require("core.wt").pick({ neogit = true })
            end,
            ["Ww"] = function()
              require("core.wt").pick({ neogit = true })
            end,
            ["Wc"] = function()
              local branch = vim.fn.input("wt create branch: ")
              if branch ~= "" then
                require("core.wt").create(branch, { neogit = true })
              end
            end,
            ["Wx"] = function()
              require("core.wt").remove()
            end,
            ["Wm"] = function()
              require("core.wt").merge()
            end,
          },
        },
      })

    end,
  },
  {
    "akinsho/git-conflict.nvim",
    lazy = false,
    config = function()
      local ok, git_conflict = pcall(require, "git-conflict")
      if ok then
        git_conflict.setup()
      end
    end,
  },
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    config = function()
      local ok, codediff = pcall(require, "codediff")
      if ok then
        codediff.setup({})
      end
    end,
  },
}
