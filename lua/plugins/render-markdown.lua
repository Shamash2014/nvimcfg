return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-treesitter/nvim-treesitter-textobjects",
  },
  ft = { "markdown", "md", "chat" },
  config = function()
    require("render-markdown").setup({
      -- Heading configuration
      heading = {
        enabled = true,
        sign = true,
        icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
        width = 'full',
        left_pad = 2,
        right_pad = 2,
        min_width = 0,
        border = true,
        border_prefix = false,
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
      -- Code block configuration - enhanced for AI responses
      code = {
        enabled = true,
        sign = true,
        style = 'full',
        position = 'left',
        language_pad = 2,
        disable_background = { 'diff' },
        width = 'full',
        left_pad = 2,
        right_pad = 2,
        min_width = 80,
        border = 'thick',
        highlight = 'RenderMarkdownCode',
        highlight_inline = 'RenderMarkdownCodeInline',
      },
      -- List bullets - better visual hierarchy
      bullet = {
        enabled = true,
        icons = { '●', '○', '◆', '◇' },
        left_pad = 2,
        right_pad = 2,
        highlight = 'RenderMarkdownBullet',
      },
      -- Checkboxes - better task management
      checkbox = {
        enabled = true,
        unchecked = {
          icon = 'ↀ',
          highlight = 'RenderMarkdownUnchecked',
        },
        checked = {
          icon = '✓',
          highlight = 'RenderMarkdownChecked',
        },
        custom = {
          todo = { raw = '[-]', rendered = '⟳', highlight = 'RenderMarkdownTodo' },
          important = { raw = '[!]', rendered = '⚠', highlight = 'DiagnosticWarn' },
          in_progress = { raw = '[~]', rendered = '⟳', highlight = 'DiagnosticInfo' },
          cancelled = { raw = '[x]', rendered = '✗', highlight = 'DiagnosticError' },
        },
      },
      -- Tables - better formatting
      pipe_table = {
        enabled = true,
        preset = 'heavy',
        style = 'full',
        cell = 'padded',
        border = {
          '┌', '┬', '┐',
          '├', '┼', '┤',
          '└', '┴', '┘',
          '│', '─',
        },
        head = 'RenderMarkdownTableHead',
        row = 'RenderMarkdownTableRow',
        filler = 'RenderMarkdownTableFill',
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
      link = {
        enabled = true,
        image = '󰥭 ',
        email = '󰀓 ',
        hyperlink = '󰌷 ',
        highlight = 'RenderMarkdownLink',
        custom = {
          youtube = { pattern = 'youtube%.com', icon = '󰗃 ', highlight = 'RenderMarkdownLink' },
          github = { pattern = 'github%.com', icon = '󰊤 ', highlight = 'RenderMarkdownLink' },
        },
      },
      -- Quotes - better blockquote rendering
      quote = {
        enabled = true,
        icon = '┃',
        repeat_linebreak = false,
        highlight = 'RenderMarkdownQuote',
      },
      -- Inline highlights
      inline_highlight = {
        enabled = true,
        icon = '󰠱 ',
        highlight = 'RenderMarkdownInlineHighlight',
      },
      -- Indent blankline integration
      indent = {
        enabled = true,
        per_level = 2,
      },
      -- Winbar integration
      winbar = {
        enabled = false,
      },
      -- Enable all file types including .chat files
      file_types = { 'markdown', 'chat' },
      -- Disable for large files
      max_file_size = 10.0,
      -- Anti-conceal settings
      anti_conceal = {
        enabled = true,
        above = 2,
        below = 2,
      },
      -- Enable in all modes
      render_modes = { 'n', 'c', 't' },
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