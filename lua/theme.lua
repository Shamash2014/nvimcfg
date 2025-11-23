-- Custom Monochrome Theme for Neovim
local M = {}

-- Define color palette - Pure Monochrome
local colors = {
  bg = '#100F0F',
  bg_alt = '#1a1a1a',
  fg = '#FFFFFF',
  fg_alt = '#FFFCF0',
  selection = '#333333',
  border = '#404040',
  comment = '#878585',
  docstring = '#878585',
  red = '#D14D41',
  green = '#FFFCF0',
  yellow = '#FFFCF0',
  blue = '#FFFCF0',
  magenta = '#FFFCF0',
  cyan = '#FFFCF0',
  orange = '#FFFCF0',
  warning = '#BC522D',

  -- Status line colors
  statusline_bg = '#1a1a1a',
  statusline_fg = '#FFFCF0',

  -- Git colors
  git_add = '#FFFCF0',
  git_change = '#FFFCF0',
  git_delete = '#D14D41',

  -- Diagnostic colors
  error = '#D14D41',
  warning = '#BC522D',
  info = '#FFFCF0',
  hint = '#FFFCF0',
}

-- Highlight groups
M.groups = {
  -- Editor basics
  Normal = { fg = colors.fg, bg = colors.bg },
  NormalNC = { fg = colors.fg_alt, bg = colors.bg },
  NormalFloat = { fg = colors.fg, bg = colors.bg_alt },
  FloatBorder = { fg = colors.border, bg = colors.bg_alt },

  -- Cursor
  Cursor = { fg = colors.bg, bg = colors.fg },
  CursorLine = { bg = colors.bg_alt },
  CursorLineNr = { fg = colors.fg, bg = colors.bg_alt },

  -- Line numbers
  LineNr = { fg = colors.comment },
  SignColumn = { bg = colors.bg },

  -- Selection
  Visual = { bg = colors.selection },
  VisualNOS = { bg = colors.selection },

  -- Search
  IncSearch = { fg = colors.bg, bg = colors.yellow },
  Search = { fg = colors.bg, bg = colors.yellow },

  -- Folding
  FoldColumn = { fg = colors.comment, bg = colors.bg },
  Folded = { fg = colors.comment, bg = colors.bg_alt },

  -- Diff
  DiffAdd = { bg = '#1a3a1a' },
  DiffChange = { bg = '#3a3a1a' },
  DiffDelete = { bg = '#3a1a1a' },
  DiffText = { bg = '#2a2a1a' },

  -- Messages
  ErrorMsg = { fg = colors.error },
  WarningMsg = { fg = colors.warning },
  ModeMsg = { fg = colors.fg },
  MoreMsg = { fg = colors.blue },

  -- Status line
  StatusLine = { fg = colors.statusline_fg, bg = colors.statusline_bg },
  StatusLineNC = { fg = colors.comment, bg = colors.statusline_bg },

  -- Tab line
  TabLine = { fg = colors.comment, bg = colors.bg_alt },
  TabLineFill = { fg = colors.bg, bg = colors.bg_alt },
  TabLineSel = { fg = colors.fg, bg = colors.selection },

  -- Completion menu
  Pmenu = { fg = colors.fg, bg = colors.bg_alt },
  PmenuSel = { fg = colors.bg, bg = colors.selection },
  PmenuSbar = { bg = colors.selection },
  PmenuThumb = { bg = colors.border },

  -- Wild menu
  WildMenu = { fg = colors.bg, bg = colors.selection },

  -- Splits
  VertSplit = { fg = colors.border },

  -- Title
  Title = { fg = colors.fg, bold = true },

  -- Whitespace
  NonText = { fg = colors.comment },
  SpecialKey = { fg = colors.comment },
  Whitespace = { fg = colors.comment },

  -- Syntax highlighting - Pure Monochrome with emphasis on contrast
  Comment = { fg = colors.comment, italic = true },
  DocString = { fg = colors.docstring, italic = true },
  Constant = { fg = colors.fg, bold = true },
  String = { fg = colors.fg },
  Character = { fg = colors.fg },
  Number = { fg = colors.fg, bold = true },
  Boolean = { fg = colors.fg, bold = true },
  Float = { fg = colors.fg, bold = true },

  Identifier = { fg = colors.fg },
  Function = { fg = colors.fg, bold = true },

  Statement = { fg = colors.fg, bold = true },
  Conditional = { fg = colors.fg, bold = true },
  Repeat = { fg = colors.fg, bold = true },
  Label = { fg = colors.fg, bold = true },
  Operator = { fg = colors.fg },
  Keyword = { fg = colors.fg, bold = true },
  Exception = { fg = colors.fg, bold = true },

  PreProc = { fg = colors.fg_alt, bold = true },
  Include = { fg = colors.fg_alt, bold = true },
  Define = { fg = colors.fg_alt, bold = true },
  Macro = { fg = colors.fg_alt, bold = true },
  PreCondit = { fg = colors.fg_alt, bold = true },

  Type = { fg = colors.fg, italic = true },
  StorageClass = { fg = colors.fg, italic = true },
  Structure = { fg = colors.fg, italic = true },
  Typedef = { fg = colors.fg, italic = true },

  Special = { fg = colors.fg_alt },
  SpecialChar = { fg = colors.fg_alt },
  Tag = { fg = colors.fg_alt },
  Delimiter = { fg = colors.fg },
  SpecialComment = { fg = colors.comment, italic = true },
  Debug = { fg = colors.fg, underline = true },

  Underlined = { underline = true },
  Bold = { bold = true },
  Italic = { italic = true },

  -- LSP
  LspReferenceText = { bg = colors.bg_alt },
  LspReferenceRead = { bg = colors.bg_alt },
  LspReferenceWrite = { bg = colors.bg_alt },
  LspSignatureActiveParameter = { bg = colors.bg_alt },

  -- Diagnostics - Monochrome with red for errors
  DiagnosticError = { fg = colors.red, bg = '#1a0000', bold = true },
  DiagnosticWarn = { fg = colors.fg, bg = '#1a1a00', bold = true },
  DiagnosticInfo = { fg = colors.fg, bg = '#001a1a', bold = true },
  DiagnosticHint = { fg = colors.fg, bg = '#0a0a0a', bold = true },
  DiagnosticUnderlineError = { underline = true, sp = colors.red },
  DiagnosticUnderlineWarn = { underline = true, sp = colors.fg },
  DiagnosticUnderlineInfo = { underline = true, sp = colors.fg },
  DiagnosticUnderlineHint = { underline = true, sp = colors.fg },

  -- Git signs - Pure monochrome with different intensities
  GitSignsAdd = { fg = colors.fg_alt, bold = true },
  GitSignsChange = { fg = colors.fg, bold = true },
  GitSignsDelete = { fg = colors.fg, bold = true, reverse = true },

  -- Oil file explorer
  OilDir = { fg = colors.fg, bold = true },
  OilFile = { fg = colors.fg },
  OilSocket = { fg = colors.fg_alt },
  OilLink = { fg = colors.fg_alt, underline = true },
  OilCopy = { fg = colors.fg_alt },
  OilMove = { fg = colors.fg_alt },
  OilCreate = { fg = colors.fg_alt },
  OilDelete = { fg = colors.red },
  OilChange = { fg = colors.fg_alt },
  OilPending = { fg = colors.fg_alt },
  OilHidden = { fg = colors.fg_alt },
  OilTrash = { fg = colors.red },
  OilRestore = { fg = colors.red },

  -- Snacks picker
  SnacksPicker = { fg = colors.fg, bg = colors.bg },
  SnacksPickerBorder = { fg = colors.border, bg = colors.bg },
  SnacksPickerTitle = { fg = colors.fg, bg = colors.bg_alt, bold = true },
  SnacksPickerInput = { fg = colors.fg, bg = colors.bg_alt },
  SnacksInputBorder = { fg = colors.border },
  SnacksPickerList = { fg = colors.fg, bg = colors.bg },
  SnacksPickerSelected = { fg = colors.bg, bg = colors.selection, bold = true },
  SnacksPickerCursor = { fg = colors.bg, bg = colors.selection },
  SnacksPickerMatch = { fg = colors.fg, bold = true },
  SnacksPickerDir = { fg = colors.fg_alt },
  SnacksPickerFile = { fg = colors.fg },
  SnacksPickerIcon = { fg = colors.fg_alt },
  SnacksPickerPreview = { fg = colors.fg, bg = colors.bg },
  SnacksPickerPreviewBorder = { fg = colors.border, bg = colors.bg },
  SnacksPickerPreviewTitle = { fg = colors.fg, bg = colors.bg_alt, bold = true },

  -- Which-key
  WhichKeyFloat = { fg = colors.fg, bg = colors.bg_alt },
  WhichKeyBorder = { fg = colors.border, bg = colors.bg_alt },
  WhichKeyGroup = { fg = colors.fg_alt, bold = true },
  WhichKeyDesc = { fg = colors.fg },
  WhichKeySeparator = { fg = colors.comment },

  -- Treesitter context
  TreesitterContext = { bg = colors.bg_alt },
  TreesitterContextLineNumber = { fg = colors.comment, bg = colors.bg_alt },

  -- Snacks input
  SnacksInput = { fg = colors.fg, bg = colors.bg_alt },
  SnacksInputIcon = { fg = colors.fg_alt },
  SnacksInputTitle = { fg = colors.fg, bold = true },

  -- Flash
  FlashLabel = { fg = colors.bg, bg = colors.fg, bold = true },
  FlashCurrent = { fg = colors.bg, bg = colors.fg_alt, bold = true },
  FlashMatch = { fg = colors.fg, bg = colors.selection },

  -- Git
  NeogitNormal = { fg = colors.fg, bg = colors.bg_alt },
  NeogitBorder = { fg = colors.border, bg = colors.bg_alt },
  NeogitSectionHeader = { fg = colors.fg, bold = true },
  NeogitCommitViewHeader = { fg = colors.fg_alt, bg = colors.bg_alt },
  NeogitDiffAdd = { fg = colors.fg_alt, bg = '#001a00' },
  NeogitDiffDelete = { fg = colors.red, bg = '#1a0000' },

  -- Indent guides
  IndentBlanklineChar = { fg = colors.bg_alt },
  IndentBlanklineContextChar = { fg = colors.border },

  -- Completion
  PmenuThumb = { bg = colors.border },

  -- Terminal colors
  SnacksTerminal = { fg = colors.fg_alt, bg = colors.bg },
  SnacksTerminalNormal = { fg = colors.fg_alt, bg = colors.bg },
  SnacksTerminalBorder = { fg = colors.border, bg = colors.bg },
  TerminalNormal = { fg = colors.fg_alt, bg = colors.bg },
  TerminalBorder = { fg = colors.border, bg = colors.bg },
}

-- Terminal colors (16 colors: 0-7 normal, 8-15 bright)
M.term_colors = {
  colors.bg,       -- 0: black
  colors.red,      -- 1: red
  colors.comment,  -- 2: green (muted)
  colors.warning,  -- 3: yellow (warning orange)
  colors.fg_alt,   -- 4: blue (off-white)
  colors.fg,       -- 5: magenta (white)
  colors.comment,  -- 6: cyan (muted)
  colors.fg_alt,   -- 7: white (off-white)
  colors.comment,  -- 8: bright black (gray)
  colors.red,      -- 9: bright red
  colors.fg_alt,   -- 10: bright green (off-white)
  colors.fg,       -- 11: bright yellow (white)
  colors.fg,       -- 12: bright blue (white)
  colors.fg,       -- 13: bright magenta (white)
  colors.fg_alt,   -- 14: bright cyan (off-white)
  colors.fg        -- 15: bright white
}

-- Setup function
function M.setup()
  -- Apply highlight groups
  for name, hl in pairs(M.groups) do
    vim.api.nvim_set_hl(0, name, hl)
  end

  -- Set terminal colors
  for i, color in ipairs(M.term_colors) do
    vim.g["terminal_color_" .. (i - 1)] = color
  end

  -- Set background
  vim.opt.background = 'dark'

  -- Set color scheme name
  vim.g.colors_name = 'custom-monochrome'

  -- Apply terminal colors to new terminal buffers
  vim.api.nvim_create_autocmd({"TermOpen", "BufEnter"}, {
    pattern = "term://*",
    callback = function()
      -- Set terminal-specific colors
      for i, color in ipairs(M.term_colors) do
        vim.cmd(string.format("let b:terminal_color_%d = '%s'", i - 1, color))
      end
      -- Ensure proper background for terminal
      vim.cmd("setlocal winhighlight=Normal:SnacksTerminalNormal,NormalFloat:SnacksTerminalNormal")
    end,
  })

  -- Apply colors to snacks_terminal filetype
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "snacks_terminal",
    callback = function()
      vim.cmd("setlocal winhighlight=Normal:SnacksTerminalNormal,NormalFloat:SnacksTerminalNormal,FloatBorder:SnacksTerminalBorder")
    end,
  })
end

return M