return {
  "NeogitOrg/neogit",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
  },
  cmd = "Neogit",
  keys = {
    { "<leader>gg", "<cmd>Neogit<cr>", desc = "Neogit" },
    { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Git Commit" },
    { "<leader>gl", "<cmd>Neogit log<cr>", desc = "Git Log" },
  },
  config = function(_, opts)
    require("neogit").setup(opts)
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "NeogitStatus",
      callback = function(ev)
        vim.keymap.set("n", "k", function()
          require("core.stack").popup()
        end, { buffer = ev.buf, desc = "Stack popup" })
      end,
    })
  end,
  opts = {
    -- Emacs-like keybindings
    mappings = {
      popup = {
        ["p"] = "PushPopup",
        ["P"] = "PullPopup",
        ["Z"] = "StashPopup",
        ["b"] = "BranchPopup",
        ["B"] = "BisectPopup",
        ["r"] = "RebasePopup",
        ["f"] = "FetchPopup",
        ["m"] = "MergePopup",
        ["M"] = "RemotePopup",
        ["X"] = "ResetPopup",
        ["A"] = "CherryPickPopup",
        ["v"] = "RevertPopup",
        ["w"] = "WorktreePopup",
      },
      status = {
        ["q"] = "Close",
        ["1"] = "Depth1",
        ["2"] = "Depth2",
        ["3"] = "Depth3",
        ["4"] = "Depth4",
        ["<tab>"] = "Toggle",
        ["x"] = "Discard",
        ["s"] = "Stage",
        ["S"] = "StageUnstaged",
        ["<c-s>"] = "StageAll",
        ["u"] = "Unstage",
        ["U"] = "UnstageStaged",
        ["$"] = "CommandHistory",
        ["Y"] = "YankSelected",
        ["<c-r>"] = "RefreshBuffer",
        ["<enter>"] = "GoToFile",
        ["<c-v>"] = "VSplitOpen",
        ["<c-x>"] = "SplitOpen",
        ["<c-t>"] = "TabOpen",
        ["{"] = "GoToPreviousHunkHeader",
        ["}"] = "GoToNextHunkHeader",
      },
    },
    -- Performance optimizations
    disable_hint = true,
    disable_context_highlighting = true,
    disable_signs = false,
    -- Use Snacks picker instead of telescope
    use_default_keymaps = true,
    remember_settings = false,
    use_per_project_settings = true,
    ignored_settings = {
      "NeogitPushPopup--force-with-lease",
      "NeogitPushPopup--force",
      "NeogitPullPopup--rebase",
      "NeogitCommitPopup--allow-empty",
      "NeogitRevertPopup--no-edit",
    },
    -- Git performance
    git = {
      timeout = 5000,
    },
    -- UI optimizations
    auto_refresh = true,
    kind = "split",
    signs = {
      hunk = { "", "" },
      item = { ">", "v" },
      section = { ">", "v" },
    },
    integrations = {
      telescope = false,
      diffview = true,
    },
    sections = {
      sequencer = {
        folded = false,
        hidden = false,
      },
      untracked = {
        folded = false,
        hidden = false,
      },
      unstaged = {
        folded = false,
        hidden = false,
      },
      staged = {
        folded = false,
        hidden = false,
      },
      stashes = {
        folded = true,
        hidden = false,
      },
      unpulled_upstream = {
        folded = true,
        hidden = false,
      },
      unmerged_upstream = {
        folded = false,
        hidden = false,
      },
      unpulled_pushRemote = {
        folded = true,
        hidden = false,
      },
      unmerged_pushRemote = {
        folded = false,
        hidden = false,
      },
      recent = {
        folded = true,
        hidden = false,
      },
      rebase = {
        folded = true,
        hidden = false,
      },
    },
  },
}