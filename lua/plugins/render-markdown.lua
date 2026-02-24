return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-treesitter/nvim-treesitter-textobjects",
  },
  ft = { "markdown", "md" },
  config = function()
    require("render-markdown").setup({
      -- DISABLE render-markdown for chat buffers for performance
      -- Chat buffers have their own decoration system
      exclude = { 'chat' },
      -- AGGRESSIVE performance optimizations for chat buffers
      debounce = 1000,  -- Very slow debounce (1s) for large chat buffers
      max_file_size = 0.5,  -- Disable for files > 500KB (was 10MB)
      max_overlap_width = 50,
      render_modes = { 'n' },  -- ONLY render in normal mode, skip insert/command mode
      -- Lazy rendering - only render visible area
      lazy = {
        enabled = true,  -- Enable lazy rendering
      },
      -- Minimal heading configuration for performance
      heading = {
        enabled = true,
        sign = false,  -- DISABLE signs for performance
        icons = { '# ', '## ', '### ', '#### ', '##### ', '###### ' },  -- Simple text icons
        width = 'full',
        left_pad = 0,  -- Reduce padding
        right_pad = 0,
        border = false,  -- DISABLE borders for performance
        backgrounds = {
          'RenderMarkdownH1Bg',
          'RenderMarkdownH2Bg',
          'RenderMarkdownH3Bg',
          'RenderMarkdownH4Bg',
          'RenderMarkdownH5Bg',
          'RenderMarkdownH6Bg',
        },
        foregrounds = {
          'RenderMarkdownH1',
          'RenderMarkdownH2',
          'RenderMarkdownH3',
          'RenderMarkdownH4',
          'RenderMarkdownH5',
          'RenderMarkdownH6',
        },
      },
      -- Minimal code block configuration
      code = {
        enabled = true,
        sign = false,  -- DISABLE signs for performance
        style = 'language',  -- Minimal style
        position = 'left',
        language_pad = 0,  -- No padding
        disable_background = {},  -- Show background for all
        width = 'full',
        left_pad = 0,
        right_pad = 0,
        border = 'none',  -- DISABLE borders for performance
        highlight = 'RenderMarkdownCode',
        highlight_inline = 'RenderMarkdownCodeInline',
      },
      -- Minimal list bullets
      bullet = {
        enabled = true,
        icons = { '-', '-', '*', '*' },  -- Simple ASCII
        left_pad = 0,  -- No padding
        right_pad = 0,
        highlight = 'RenderMarkdownBullet',
      },
      -- Disable checkboxes for performance
      checkbox = {
        enabled = false,  -- DISABLE checkboxes entirely
      },
      -- Disable tables for performance (very expensive)
      pipe_table = {
        enabled = false,  -- DISABLE tables
      },
      -- Callouts / Blockquotes - enhanced
      callout = {
        note = { raw = '[!NOTE]', rendered = '󰋽 Note', highlight = 'RenderMarkdownInfo' },
        tip = { raw = '[!TIP]', rendered = '💡 Tip', highlight = 'RenderMarkdownSuccess' },
        important = { raw = '[!IMPORTANT]', rendered = '▶ Important', highlight = 'RenderMarkdownHint' },
        warning = { raw = '[!WARNING]', rendered = '⚠ Warning', highlight = 'RenderMarkdownWarn' },
        caution = { raw = '[!CAUTION]', rendered = '󰳧 Caution', highlight = 'RenderMarkdownError' },
        question = { raw = '[!QUESTION]', rendered = '❓ Question', highlight = 'DiagnosticQuestion' },
        example = { raw = '[!EXAMPLE]', rendered = '󰱸 Example', highlight = 'DiagnosticOk' },
        quote = { raw = '[!QUOTE]', rendered = '󰆪 Quote', highlight = 'Comment' },
      },
      -- Links - enhanced with better visuals
      -- Minimal links
      link = {
        enabled = true,
        image = '',  -- No icon for performance
        email = '',
        hyperlink = '',  -- No icon for performance
        highlight = 'RenderMarkdownLink',
        custom = {
          -- Disable custom link patterns for performance
        },
      },
      -- Minimal quotes
      quote = {
        enabled = true,
        icon = '',  -- No icon for performance
        repeat_linebreak = false,
        highlight = 'RenderMarkdownQuote',
      },
      -- Disable inline highlights for performance
      inline_highlight = {
        enabled = false,  -- DISABLE for performance
      },
      -- Disable indent blankline for performance
      indent = {
        enabled = false,  -- DISABLE for performance
      },
      -- Winbar integration
      winbar = {
        enabled = false,
      },
      -- Enable for markdown files (including .chat)
      file_types = { 'markdown' },
      -- Keybindings
      mappings = {
        enable = false,
      },
      -- Custom overlays for chat-specific elements
      custom_handlers = {
        sigil = {
          enabled = false,
        },
      },
    })
  end,
}