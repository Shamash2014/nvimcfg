return {
  {
    "mg979/vim-visual-multi",
    event = "VeryLazy",
    init = function()
      -- Disable default mappings to avoid conflicts
      vim.g.VM_default_mappings = 0
      vim.g.VM_maps = {
        ["Find Under"] = "",
        ["Find Subword Under"] = "",
      }

      -- Custom highlighting to match theme
      vim.g.VM_Cursor_hl = "MultiCursor"
      vim.g.VM_Extend_hl = "MultiCursorExtend"
      vim.g.VM_Mono_hl = "MultiCursorMono"
      vim.g.VM_Insert_hl = "MultiCursorInsert"
    end,
    config = function()
      -- Set custom highlight groups
      vim.api.nvim_set_hl(0, "MultiCursor", { fg = "#ffffff", bg = "#bb9af7", bold = true })
      vim.api.nvim_set_hl(0, "MultiCursorExtend", { fg = "#ffffff", bg = "#666666" })
      vim.api.nvim_set_hl(0, "MultiCursorMono", { fg = "#bb9af7", bg = "#222222" })
      vim.api.nvim_set_hl(0, "MultiCursorInsert", { fg = "#000000", bg = "#bb9af7" })
    end,
    keys = {
      -- Doom Emacs gz prefix keybindings and alternative quick access
      { "gzm", "<Plug>(VM-Find-Under)", mode = { "n", "v" }, desc = "Find word under cursor" },
      { "gzM", "<Plug>(VM-Find-Subword-Under)", mode = { "n", "v" }, desc = "Find subword under cursor" },
      { "gzn", "<Plug>(VM-Add-Cursor-Down)", mode = { "n", "v" }, desc = "Add cursor down" },
      { "gzp", "<Plug>(VM-Add-Cursor-Up)", mode = { "n", "v" }, desc = "Add cursor up" },
      { "gzs", "<Plug>(VM-Start-Regex-Search)", mode = { "n", "v" }, desc = "Start regex search" },
      { "gzA", "<Plug>(VM-Select-All)", mode = { "n", "v" }, desc = "Select all" },
      { "gzr", "<Plug>(VM-Reselect-Last)", mode = { "n", "v" }, desc = "Reselect last" },
      { "gzq", "<Plug>(VM-Toggle-Mappings)", mode = { "n", "v" }, desc = "Toggle mappings" },
      
      -- Alternative quick access (common patterns)
      { "<C-n>", "<Plug>(VM-Find-Under)", mode = { "n", "v" }, desc = "Multi-cursor find under" },
      { "<C-S-n>", "<Plug>(VM-Find-Subword-Under)", mode = { "n", "v" }, desc = "Multi-cursor find subword" },
    },
  },
}