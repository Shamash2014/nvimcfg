return {
  "pwntester/octo.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  cond = function()
    local url = vim.fn.system("git remote get-url origin 2>/dev/null")
    return url:match("github") ~= nil
  end,
  event = "VeryLazy",
  keys = {
    { "<leader>gmn", "", desc = "+github" },
    { "<leader>gmnr", "<cmd>Octo pr list<cr>", desc = "List PRs" },
    { "<leader>gmnc", "<cmd>Octo pr checkout<cr>", desc = "Checkout PR" },
    { "<leader>gmnC", "<cmd>Octo pr create<cr>", desc = "Create PR" },
    { "<leader>gmns", "<cmd>Octo pr view<cr>", desc = "View PR" },
    { "<leader>gmnd", "<cmd>Octo review start<cr>", desc = "Start Review" },
    { "<leader>gmnD", "<cmd>Octo review submit<cr>", desc = "Submit Review" },
    { "<leader>gmnm", "<cmd>Octo pr merge<cr>", desc = "Merge PR" },
    { "<leader>gmno", "<cmd>Octo pr browser<cr>", desc = "Open in browser" },
    { "<leader>gmni", "<cmd>Octo issue list<cr>", desc = "List Issues" },
    { "<leader>gmnI", "<cmd>Octo issue create<cr>", desc = "Create Issue" },
    { "<leader>gmnp", "<cmd>Octo pr checks<cr>", desc = "PR Checks" },
  },
  config = function()
    local function do_setup()
      local token = vim.env.GITHUB_TOKEN
      if not token then
        local mise_env = require("core.mise").get_env()
        token = mise_env.GITHUB_TOKEN
      end
      if not token then return end
      require("octo").setup()
    end

    if vim.env.GITHUB_TOKEN then
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
