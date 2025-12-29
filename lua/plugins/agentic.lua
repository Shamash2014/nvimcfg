return {
  "carlos-algms/agentic.nvim",
  lazy = false,
  event = "VeryLazy",
  opts = {
    provider = "claude-acp",
  },
  config = function()
    -- Manual keybindings with leader 'a' prefix
    vim.keymap.set({ "n", "v", "i" }, "<leader>aa", function()
      require("agentic").toggle()
    end, { desc = "Toggle Agentic Chat" })

    vim.keymap.set({ "n", "v", "i" }, "<leader>ac", function()
      require("agentic").open()
    end, { desc = "Open Agentic Chat" })

    vim.keymap.set({ "n", "v" }, "<leader>ap", function()
      require("agentic").add_selection_or_file_to_context()
    end, { desc = "Add file or selection to Agentic Context" })

    vim.keymap.set({ "n", "v", "i" }, "<leader>an", function()
      require("agentic").new_session()
    end, { desc = "New Agentic Session" })

    vim.keymap.set("v", "<leader>af", function()
      require("agentic").add_selection()
    end, { desc = "Add selection to Agentic Context" })

    vim.keymap.set("n", "<leader>aF", function()
      require("agentic").add_file()
    end, { desc = "Add file to Agentic Context" })

    vim.keymap.set({ "n", "v", "i" }, "<leader>aq", function()
      require("agentic").close()
    end, { desc = "Close Agentic Chat" })
  end
}