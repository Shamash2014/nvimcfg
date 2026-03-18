return {
  "harrisoncramer/gitlab.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
  },
  build = function()
    require("gitlab.server").build(true)
  end,
  cond = function()
    local url = vim.fn.system("git remote get-url origin 2>/dev/null")
    return url:match("gitlab") ~= nil
  end,
  event = "VeryLazy",
  keys = {
    { "<leader>gm", "", desc = "+gitlab" },
    { "<leader>gmr", function() require("gitlab").review() end, desc = "Review" },
    { "<leader>gmc", function() require("gitlab").choose_merge_request() end, desc = "Choose MR" },
    { "<leader>gmC", function() require("gitlab").create_mr() end, desc = "Create MR" },
    { "<leader>gms", function() require("gitlab").summary() end, desc = "Summary" },
    { "<leader>gmd", function() require("gitlab").toggle_discussions() end, desc = "Discussions" },
    { "<leader>gmp", function() require("gitlab").pipeline() end, desc = "Pipeline" },
    { "<leader>gmM", function() require("gitlab").merge() end, desc = "Merge" },
    { "<leader>gmo", function() require("gitlab").open_in_browser() end, desc = "Open in browser" },
  },
  config = function()
    local function do_setup()
      local token = vim.env.GITLAB_TOKEN
      local url = vim.env.GITLAB_URL
      if not token then
        local mise_env = require("core.mise").get_env()
        token = mise_env.GITLAB_TOKEN
        url = url or mise_env.GITLAB_URL
      end
      if not token then return end
      local opts = { auth_token = token }
      if url then opts.gitlab_url = url end
      require("gitlab").setup(opts)
    end

    if vim.env.GITLAB_TOKEN then
      do_setup()
    else
      vim.api.nvim_create_autocmd("User", {
        pattern = "DirenvFinished",
        once = true,
        callback = do_setup,
      })
    end
  end,
}
