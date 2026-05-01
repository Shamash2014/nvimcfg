local M = {}

local function dark_palette()
  return {
    bg = "#080808",
    bg1 = "#0f0f0f",
    bg2 = "#171717",
    bg3 = "#202020",
    dim = "#282828",
    muted = "#5f5f5f",
    mid = "#969696",
    text = "#bcbcbc",
    bright = "#d0d0d0",
    white = "#e0e0e0",
    comment = "#707070",
    subtle = "#171717",
    faded = "#707070",
    salient = "#7E9CD8",
    strong = "#e0e0e0",
    popout = "#FFA066",
    critical = "#C34043",
    err = "#C34043",
    warn = "#FFA066",
    info = "#7E9CD8",
    hint = "#7AA89F",
    add_fg = "#98BB6C",
    add_bg = "#1A2618",
    chg_fg = "#E8B468",
    chg_bg = "#2E2A1E",
    del_fg = "#D4484B",
    del_bg = "#2B1418",
    md_h1_bg = "#121212",
    md_h2_bg = "#101010",
    md_h3_bg = "#0e0e0e",
    md_h4_bg = "#0c0c0c",
    md_link = "#7E9CD8",
  }
end

local function light_palette()
  return {
    bg = "#ffffff",
    bg1 = "#fafafa",
    bg2 = "#f0f0f0",
    bg3 = "#e6e6e6",
    dim = "#d8d8d8",
    muted = "#747474",
    mid = "#4f4f4f",
    text = "#1f1f1f",
    bright = "#0f0f0f",
    white = "#000000",
    comment = "#6f6f6f",
    subtle = "#f0f0f0",
    faded = "#6f6f6f",
    salient = "#2d5f8a",
    strong = "#000000",
    popout = "#8a4a00",
    critical = "#a5222f",
    err = "#a5222f",
    warn = "#8a4a00",
    info = "#2d5f8a",
    hint = "#2f6f61",
    add_fg = "#3f6f2a",
    add_bg = "#e7f2e4",
    chg_fg = "#805000",
    chg_bg = "#f3eadb",
    del_fg = "#9a2020",
    del_bg = "#f5e2e2",
    md_h1_bg = "#f0f0f0",
    md_h2_bg = "#f4f4f4",
    md_h3_bg = "#f7f7f7",
    md_h4_bg = "#fafafa",
    md_link = "#2d5f8a",
  }
end

local function hl(group, spec)
  vim.api.nvim_set_hl(0, group, spec)
end

local function alias(group, target)
  hl(group, { link = target, default = true })
end

local setup_done = false
local group = vim.api.nvim_create_augroup("nvim2-theme", { clear = true })

function M.apply()
  local p = vim.o.background == "light" and light_palette() or dark_palette()

  vim.o.termguicolors = true

  local link = function(name, target)
    alias(name, target)
  end

  -- Editor UI
  hl("Normal", { fg = p.text, bg = p.bg })
  hl("NormalFloat", { fg = p.text, bg = p.bg1 })
  hl("FloatBorder", { fg = p.dim, bg = p.bg1 })
  hl("FloatTitle", { fg = p.strong, bg = p.bg1, bold = true })
  hl("Cursor", { fg = p.bg, bg = p.muted })
  hl("TermCursor", { fg = p.bg, bg = p.muted })
  hl("CursorLine", { bg = p.subtle })
  hl("CursorLineNr", { fg = p.strong, bold = true })
  hl("LineNr", { fg = p.faded })
  hl("SignColumn", { bg = p.bg })
  hl("ColorColumn", { bg = p.bg1 })
  hl("Visual", { bg = p.bg3 })
  hl("VisualNOS", { bg = p.bg3 })
  hl("Pmenu", { fg = p.text, bg = p.bg1 })
  hl("PmenuSel", { fg = p.strong, bg = p.bg2, bold = true })
  hl("PmenuSbar", { bg = p.bg1 })
  hl("PmenuThumb", { bg = p.muted })
  hl("StatusLine", { fg = p.mid, bg = p.bg1 })
  hl("StatusLineNC", { fg = p.muted, bg = p.bg1 })
  hl("TabLine", { fg = p.muted, bg = p.bg1 })
  hl("TabLineFill", { bg = p.bg })
  hl("TabLineSel", { fg = p.strong, bg = p.bg, bold = true })
  hl("WinSeparator", { fg = p.bg2 })
  hl("VertSplit", { fg = p.bg2 })
  hl("Folded", { fg = p.faded, bg = p.bg1, italic = true })
  hl("FoldColumn", { fg = p.faded, bg = p.bg })
  hl("NonText", { fg = p.bg2 })
  hl("SpecialKey", { fg = p.bg2 })
  hl("Whitespace", { fg = p.bg2 })
  hl("EndOfBuffer", { fg = p.bg })
  hl("Search", { fg = p.bg, bg = p.mid })
  hl("IncSearch", { fg = p.bg, bg = p.bright })
  hl("CurSearch", { fg = p.bg, bg = p.white, bold = true })
  hl("MatchParen", { fg = p.strong, bg = p.bg3, bold = true })
  hl("ModeMsg", { fg = p.strong, bold = true })
  hl("MoreMsg", { fg = p.mid })
  hl("Question", { fg = p.salient })
  hl("WarningMsg", { fg = p.popout, italic = true })
  hl("ErrorMsg", { fg = p.critical, bold = true })
  hl("Title", { fg = p.strong, bold = true })
  hl("Directory", { fg = p.strong, bold = true })
  hl("WildMenu", { fg = p.strong, bg = p.bg3 })
  hl("Conceal", { fg = p.faded })
  hl("SpellBad", { undercurl = true, sp = p.err })
  hl("SpellCap", { undercurl = true, sp = p.warn })
  hl("SpellLocal", { undercurl = true, sp = p.mid })
  hl("SpellRare", { undercurl = true, sp = p.mid })

  -- Syntax
  hl("Comment", { fg = p.faded, italic = true })
  hl("Constant", { fg = p.text })
  hl("String", { fg = p.mid })
  hl("Character", { fg = p.mid })
  hl("Number", { fg = p.text })
  hl("Boolean", { fg = p.text })
  hl("Float", { fg = p.text })
  hl("Identifier", { fg = p.text })
  hl("Function", { fg = p.strong, bold = true })
  hl("Statement", { fg = p.text })
  hl("Conditional", { fg = p.text })
  hl("Repeat", { fg = p.text })
  hl("Label", { fg = p.text })
  hl("Operator", { fg = p.muted })
  hl("Keyword", { fg = p.text })
  hl("Exception", { fg = p.text })
  hl("PreProc", { fg = p.text })
  hl("Include", { fg = p.text })
  hl("Define", { fg = p.text })
  hl("Macro", { fg = p.text })
  hl("PreCondit", { fg = p.text })
  hl("Type", { fg = p.text })
  hl("StorageClass", { fg = p.text })
  hl("Structure", { fg = p.text })
  hl("Typedef", { fg = p.text })
  hl("Special", { fg = p.text })
  hl("SpecialChar", { fg = p.mid })
  hl("Tag", { fg = p.text })
  hl("Delimiter", { fg = p.muted })
  hl("Debug", { fg = p.text })
  hl("Underlined", { fg = p.text, underline = true })
  hl("Error", { fg = p.critical })
  hl("Todo", { fg = p.strong, bg = p.bg3, bold = true })

  -- Treesitter
  link("@comment", "Comment")
  hl("@comment.documentation", { fg = p.comment, italic = true })

  hl("@string", { fg = p.mid })
  hl("@string.regex", { fg = p.mid })
  hl("@string.escape", { fg = p.muted })
  hl("@string.special", { fg = p.mid })
  hl("@character", { fg = p.mid })

  hl("@constant", { fg = p.text })
  hl("@constant.builtin", { fg = p.text })
  hl("@number", { fg = p.text })
  hl("@boolean", { fg = p.text })
  hl("@float", { fg = p.text })

  hl("@function", { fg = p.strong, bold = true })
  hl("@function.builtin", { fg = p.text })
  hl("@function.call", { fg = p.text })
  hl("@method", { fg = p.strong, bold = true })
  hl("@method.call", { fg = p.text })
  hl("@constructor", { fg = p.text })

  hl("@keyword", { fg = p.text })
  hl("@keyword.function", { fg = p.text })
  hl("@keyword.operator", { fg = p.muted })
  hl("@keyword.return", { fg = p.text })
  hl("@keyword.import", { fg = p.text })
  hl("@conditional", { fg = p.text })
  hl("@repeat", { fg = p.text })
  hl("@exception", { fg = p.text })
  hl("@label", { fg = p.text })

  hl("@variable", { fg = p.text })
  hl("@variable.builtin", { fg = p.text })
  hl("@variable.member", { fg = p.text })
  hl("@parameter", { fg = p.text })
  hl("@property", { fg = p.text })

  hl("@type", { fg = p.text })
  hl("@type.builtin", { fg = p.text })
  hl("@type.qualifier", { fg = p.text })
  hl("@type.definition", { fg = p.text })

  hl("@operator", { fg = p.muted })
  hl("@punctuation", { fg = p.muted })
  hl("@punctuation.bracket", { fg = p.muted })
  hl("@punctuation.delimiter", { fg = p.muted })
  hl("@punctuation.special", { fg = p.muted })

  hl("@tag", { fg = p.text })
  hl("@tag.attribute", { fg = p.text })
  hl("@tag.delimiter", { fg = p.muted })

  hl("@namespace", { fg = p.text })
  hl("@module", { fg = p.text })

  hl("@attribute", { fg = p.text })
  hl("@annotation", { fg = p.text })

  hl("@markup.heading", { fg = p.strong, bold = true })
  hl("@markup.heading.1", { fg = p.strong, bg = p.md_h1_bg, bold = true })
  hl("@markup.heading.2", { fg = p.strong, bg = p.md_h2_bg, bold = true })
  hl("@markup.heading.3", { fg = p.strong, bg = p.md_h3_bg })
  hl("@markup.heading.4", { fg = p.text, bg = p.md_h4_bg })
  hl("@markup.strong", { fg = p.strong, bold = true })
  hl("@markup.italic", { fg = p.text, italic = true })
  hl("@markup.link", { fg = p.md_link, underline = true })
  hl("@markup.link.url", { fg = p.mid, underline = true })
  hl("@markup.raw", { fg = p.mid, bg = p.bg1 })
  hl("@markup.list", { fg = p.muted })

  -- LSP semantic tokens
  hl("@lsp.type.namespace", { fg = p.text })
  hl("@lsp.type.type", { fg = p.text })
  hl("@lsp.type.class", { fg = p.text })
  hl("@lsp.type.enum", { fg = p.text })
  hl("@lsp.type.interface", { fg = p.text })
  hl("@lsp.type.struct", { fg = p.text })
  hl("@lsp.type.parameter", { fg = p.text })
  hl("@lsp.type.variable", { fg = p.text })
  hl("@lsp.type.property", { fg = p.text })
  hl("@lsp.type.function", { fg = p.bright, bold = true })
  hl("@lsp.type.method", { fg = p.bright, bold = true })
  hl("@lsp.type.macro", { fg = p.text })
  hl("@lsp.type.decorator", { fg = p.text })
  hl("@lsp.mod.deprecated", { strikethrough = true })

  -- Diagnostics
  hl("DiagnosticError", { fg = p.critical, bold = true })
  hl("DiagnosticWarn", { fg = p.popout })
  hl("DiagnosticInfo", { fg = p.salient, italic = true })
  hl("DiagnosticHint", { fg = p.hint, italic = true })
  hl("DiagnosticOk", { fg = p.add_fg })
  hl("DiagnosticUnderlineError", { undercurl = true, sp = p.critical })
  hl("DiagnosticUnderlineWarn", { undercurl = true, sp = p.popout })
  hl("DiagnosticUnderlineInfo", { undercurl = true, sp = p.salient })
  hl("DiagnosticUnderlineHint", { undercurl = true, sp = p.hint })
  hl("DiagnosticVirtualTextError", { fg = p.critical, bg = p.bg1, bold = true })
  hl("DiagnosticVirtualTextWarn", { fg = p.popout, bg = p.bg1 })
  hl("DiagnosticVirtualTextInfo", { fg = p.salient, bg = p.bg1, italic = true })
  hl("DiagnosticVirtualTextHint", { fg = p.hint, bg = p.bg1, italic = true })

  -- Diff
  hl("DiffAdd", { bg = p.add_bg })
  hl("DiffChange", { bg = p.chg_bg })
  hl("DiffDelete", { bg = p.del_bg })
  hl("DiffText", { bg = p.bg3 })
  hl("Added", { fg = p.add_fg })
  hl("Changed", { fg = p.chg_fg })
  hl("Removed", { fg = p.del_fg })

  -- Git signs
  hl("GitSignsAdd", { fg = p.add_fg })
  hl("GitSignsChange", { fg = p.chg_fg })
  hl("GitSignsDelete", { fg = p.del_fg })
  hl("GitSignsAddNr", { fg = p.add_fg })
  hl("GitSignsChangeNr", { fg = p.chg_fg })
  hl("GitSignsDeleteNr", { fg = p.del_fg })
  hl("GitSignsAddLn", { bg = p.add_bg })
  hl("GitSignsChangeLn", { bg = p.chg_bg })
  hl("GitSignsDeleteLn", { bg = p.del_bg })

  -- Neogit
  hl("NeogitDiffAdd", { fg = p.add_fg, bg = p.add_bg })
  hl("NeogitDiffDelete", { fg = p.del_fg, bg = p.del_bg })
  hl("NeogitDiffContext", { fg = p.text, bg = p.bg })
  hl("NeogitHunkHeader", { fg = p.strong, bg = p.bg1, bold = true })
  hl("NeogitBranch", { fg = p.strong, bold = true })
  hl("NeogitRemote", { fg = p.mid })

  -- Explorer
  hl("OilDir", { fg = p.strong, bold = true })
  hl("OilLink", { fg = p.salient, underline = true })
  hl("OilFile", { fg = p.text })
  hl("OilSize", { fg = p.muted })
  hl("OilMtime", { fg = p.muted })

  -- Blink/completion
  hl("BlinkCmpMenu", { fg = p.text, bg = p.bg1 })
  hl("BlinkCmpMenuBorder", { fg = p.dim, bg = p.bg1 })
  hl("BlinkCmpMenuSelection", { bg = p.bg2 })
  hl("BlinkCmpLabel", { fg = p.text })
  hl("BlinkCmpLabelMatch", { fg = p.strong, bold = true })
  hl("BlinkCmpKind", { fg = p.mid })
  hl("BlinkCmpDoc", { fg = p.text, bg = p.bg1 })
  hl("BlinkCmpDocBorder", { fg = p.dim, bg = p.bg1 })
  hl("BlinkCmpGhostText", { fg = p.muted, italic = true })

  -- Which-key
  hl("WhichKey", { fg = p.strong, bold = true })
  hl("WhichKeyGroup", { fg = p.strong })
  hl("WhichKeySeparator", { fg = p.muted })
  hl("WhichKeyDesc", { fg = p.text })
  hl("WhichKeyFloat", { bg = p.bg1 })

  -- Snacks
  hl("SnacksPickerMatch", { fg = p.strong, bold = true })
  hl("SnacksPickerDir", { fg = p.muted })
  hl("SnacksPickerFile", { fg = p.text })
  hl("SnacksPickerBorder", { fg = p.dim, bg = p.bg1 })
  hl("SnacksNotifierInfo", { fg = p.info })
  hl("SnacksNotifierWarn", { fg = p.warn })
  hl("SnacksNotifierError", { fg = p.err })
  hl("SnacksNotifierDebug", { fg = p.comment })
  hl("SnacksNotifierTrace", { fg = p.muted })
  hl("SnacksNotifierIconInfo", { fg = p.info })
  hl("SnacksNotifierIconWarn", { fg = p.warn })
  hl("SnacksNotifierIconError", { fg = p.err })
  hl("SnacksNotifierIconDebug", { fg = p.comment })
  hl("SnacksNotifierIconTrace", { fg = p.muted })
  hl("SnacksNotifierTitleInfo", { fg = p.info, bold = true })
  hl("SnacksNotifierTitleWarn", { fg = p.warn, bold = true })
  hl("SnacksNotifierTitleError", { fg = p.err, bold = true })
  hl("SnacksNotifierTitleDebug", { fg = p.comment, bold = true })
  hl("SnacksNotifierTitleTrace", { fg = p.muted, bold = true })
  hl("SnacksNotifierBorderInfo", { fg = p.info })
  hl("SnacksNotifierBorderWarn", { fg = p.warn })
  hl("SnacksNotifierBorderError", { fg = p.err })
  hl("SnacksNotifierBorderDebug", { fg = p.comment })
  hl("SnacksNotifierBorderTrace", { fg = p.muted })

  -- Render-markdown
  hl("RenderMarkdownH1", { fg = p.strong, bg = p.md_h1_bg, bold = true })
  hl("RenderMarkdownH1Bg", { bg = p.md_h1_bg })
  hl("RenderMarkdownH2", { fg = p.strong, bg = p.md_h2_bg, bold = true })
  hl("RenderMarkdownH2Bg", { bg = p.md_h2_bg })
  hl("RenderMarkdownH3", { fg = p.strong, bg = p.md_h3_bg })
  hl("RenderMarkdownH3Bg", { bg = p.md_h3_bg })
  hl("RenderMarkdownH4", { fg = p.text, bg = p.md_h4_bg })
  hl("RenderMarkdownH4Bg", { bg = p.md_h4_bg })
  hl("RenderMarkdownCode", { bg = p.bg1 })
  hl("RenderMarkdownCodeInline", { fg = p.mid, bg = p.bg1 })
  hl("RenderMarkdownBullet", { fg = p.strong })
  hl("RenderMarkdownDash", { fg = p.dim })
  hl("RenderMarkdownLink", { fg = p.md_link, underline = true })
  hl("RenderMarkdownQuote", { fg = p.comment, italic = true })

  if not setup_done then
    setup_done = true
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = group,
      callback = M.apply,
    })
  end
end

return M
