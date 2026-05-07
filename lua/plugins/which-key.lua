local function session_desc()
  local ok, acp = pcall(require, "acp")
  if not ok or type(acp.current_session_name) ~= "function" then
    return "ACP sessions"
  end
  local name = acp.current_session_name()
  if not name or name == "" then
    return "Projects / worktrees"
  end
  return "Session: " .. name
end

return {
  {
    src = "https://github.com/folke/which-key.nvim",
    lazy = false,
    opts = {
      spec = {
        { "<leader>aw", desc = "New thread" },
        { "<leader>pp", desc = session_desc },
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer local keymaps",
      },
    },
  },
}
