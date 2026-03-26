return {
  "actionshrimp/direnv.nvim",
  event = { "BufEnter", "DirChanged" },
  opts = {
    async = true,
    type = "dir",
  },
}
