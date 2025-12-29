return {
  -- Inline diagnostics display
  {
    "dgagn/diagflow.nvim",
    event = "LspAttach",
    opts = {
      enable = true,
      max_width = 60,
      max_height = 10,
      severity_colors = {
        error = "DiagnosticFloatingError",
        warning = "DiagnosticFloatingWarn",
        info = "DiagnosticFloatingInfo",
        hint = "DiagnosticFloatingHint",
      },
      format = function(diagnostic)
        return diagnostic.message
      end,
      gap_size = 1,
      scope = "cursor",
      padding_top = 0,
      padding_right = 0,
      text_align = "left",
      placement = "top",
      inline_padding_left = 0,
      update_event = { "DiagnosticChanged", "BufEnter" },
      toggle_event = { },
      show_sign = false,
      render_event = { "DiagnosticChanged", "CursorMoved" },
      border_chars = {
        top_left = "┌",
        top_right = "┐",
        bottom_left = "└",
        bottom_right = "┘",
        horizontal = "─",
        vertical = "│"
      },
      show_borders = true,
    },
  },

  -- Direnv integration (async)
  {
    "actionshrimp/direnv.nvim",
    event = { "BufEnter", "DirChanged" },
    opts = {
      async = true,
      type = "dir",
    },
  },

  -- EditorConfig support
  {
    "editorconfig/editorconfig-vim",
    event = "BufReadPre",
  },

  -- Git conflict resolution
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    event = "BufReadPost",
    config = function()
      require("git-conflict").setup({
        default_mappings = {
          ours = "co",
          theirs = "ct",
          none = "c0",
          both = "cb",
          next = "]x",
          prev = "[x",
        },
        default_commands = true,
        disable_diagnostics = false,
        list_opener = "copen",
        highlights = {
          incoming = "DiffAdd",
          current = "DiffText",
        },
      })
    end,
  },

  -- Color highlighting with treesitter integration
  {
    "brenoprata10/nvim-highlight-colors",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("nvim-highlight-colors").setup({
        render = "virtual", -- 'background', 'foreground' or 'virtual'
        virtual_symbol = "■",
        virtual_symbol_position = "inline",
        enable_hex = true,
        enable_short_hex = true,
        enable_rgb = true,
        enable_hsl = true,
        enable_var_usage = true,
        enable_named_colors = true,
        enable_tailwind = false, -- Disable tailwind to avoid conflicts
        -- Removed custom_colors as they were causing issues
        -- The plugin will still detect standard hex colors in Flutter like 0xFF6200EE
        exclude_filetypes = {},
        exclude_buftypes = {},
      })
    end,
  },
}