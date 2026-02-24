return {
  dir = vim.fn.stdpath("config") .. "/lua/tramp",
  name = "tramp.nvim",
  event = "VeryLazy",
  config = function()
    require("tramp").setup({
      ssh_config = vim.fn.expand("~/.ssh/config"),
      cache_dir = vim.fn.stdpath("cache") .. "/tramp",
      connection_timeout = 10,
      default_user = nil,
    })
  end,
  keys = {
    { "<leader>re", function() require("tramp").edit_remote() end, desc = "Edit Remote File" },
    { "<leader>rf", function() require("tramp").find_remote() end, desc = "Find Remote Files" },
    { "<leader>rx", function() require("tramp").explore_remote() end, desc = "Explore Remote Directory" },
    { "<leader>rg", function()
        vim.ui.input({ prompt = "Grep pattern: " }, function(pattern)
          if pattern then
            require("tramp").grep_remote(pattern)
          end
        end)
      end, desc = "Grep Remote Files" },
    { "<leader>rc", function() require("tramp").connect() end, desc = "Connect to Remote Host" },
    { "<leader>rd", function() require("tramp").disconnect() end, desc = "Disconnect Remote Host" },
    { "<leader>ri", function() require("tramp").info() end, desc = "Remote Connection Info" },
  },
}
