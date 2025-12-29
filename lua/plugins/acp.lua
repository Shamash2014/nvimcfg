return {
  dir = "/Users/shamash/temp/agent/author/nvim-acp",
  name = "nvim-acp", -- Optional, but good for display
  config = function()
    -- Put any specific configuration here if needed
    require("acp").setup({
agents = {
    claude = {
      cmd = "npx",
      args = { "-y", "@zed-industries/claude-code-acp" },
      env = {
          -- You might need to set your ANTHROPIC_API_KEY if not already in your shell
          -- ANTHROPIC_API_KEY = "sk-..."
      }
    }
    }})
  end,
  dev = true, -- Optional: marks it as a local dev plugin
}
