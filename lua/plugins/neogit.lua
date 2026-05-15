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
      })

      local map = vim.keymap.set
      map("n", "<leader>gw", function()
        require("core.wt").pick({ neogit = true })
      end, { desc = "wt: pick worktree -> Neogit" })
      map("n", "<leader>gW", function()
        local branch = vim.fn.input("wt create branch: ")
        if branch ~= "" then
          require("core.wt").create(branch, { neogit = true })
        end
      end, { desc = "wt: create worktree -> Neogit" })
      map("n", "<leader>gx", function()
        require("core.wt").remove()
      end, { desc = "wt: remove current worktree" })
      map("n", "<leader>gm", function()
        require("core.wt").merge()
      end, { desc = "wt: merge current branch" })
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
    "sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
      "DiffviewRefresh",
      "DiffviewFileHistory",
    },
    config = function()
      local ok, diffview = pcall(require, "diffview")
      if ok then
        diffview.setup({})
      end
    end,
  },
}
