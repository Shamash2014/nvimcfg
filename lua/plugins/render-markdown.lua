return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  ft = { "markdown", "md" },
  config = function()
    require("render-markdown").setup({
      -- Heading configuration
      heading = {
        enabled = true,
        sign = false,
        icons = {},
        width = 'full',
        left_pad = 0,
        right_pad = 0,
        min_width = 0,
        border = false,
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
      -- Code block configuration
      code = {
        enabled = true,
        sign = false,
        style = 'full',
        position = 'left',
        language_pad = 0,
        disable_background = { 'diff' },
        width = 'full',
        left_pad = 0,
        right_pad = 0,
        min_width = 0,
        border = 'thin',
        highlight = 'RenderMarkdownCode',
        highlight_inline = 'RenderMarkdownCodeInline',
      },
      -- List bullets
      bullet = {
        enabled = true,
        icons = { '•', '◦', '▪', '▫' },
        left_pad = 0,
        right_pad = 0,
      },
      -- Checkboxes
      checkbox = {
        enabled = true,
        unchecked = {
          icon = '[ ]',
          highlight = 'RenderMarkdownUnchecked',
        },
        checked = {
          icon = '[x]',
          highlight = 'RenderMarkdownChecked',
        },
        custom = {
          todo = { raw = '[-]', rendered = '[-]', highlight = 'RenderMarkdownTodo' },
          important = { raw = '[!]', rendered = '[!]', highlight = 'DiagnosticWarn' },
        },
      },
      -- Tables
      pipe_table = {
        enabled = true,
        preset = 'heavy',
        style = 'full',
        cell = 'padded',
      },
      -- Callouts / Blockquotes
      callout = {
        note = { raw = '[!NOTE]', rendered = 'Note', highlight = 'RenderMarkdownInfo' },
        tip = { raw = '[!TIP]', rendered = 'Tip', highlight = 'RenderMarkdownSuccess' },
        important = { raw = '[!IMPORTANT]', rendered = 'Important', highlight = 'RenderMarkdownHint' },
        warning = { raw = '[!WARNING]', rendered = 'Warning', highlight = 'RenderMarkdownWarn' },
        caution = { raw = '[!CAUTION]', rendered = 'Caution', highlight = 'RenderMarkdownError' },
      },
      -- Links
      link = {
        enabled = true,
        image = '',
        email = '',
        hyperlink = '',
        highlight = 'RenderMarkdownLink',
        custom = {},
      },
      -- Enable all file types
      file_types = { 'markdown' },
      -- Disable for large files
      max_file_size = 10.0,
      -- Anti-conceal settings
      anti_conceal = {
        enabled = true,
        above = 0,
        below = 0,
      },
      -- Enable in all modes
      render_modes = { 'n', 'c', 't' },
      -- Keybindings
      mappings = {
        enable = false,
      },
    })
  end,
}