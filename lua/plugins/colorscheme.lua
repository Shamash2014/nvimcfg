local function dark_palette()
  return {
    bg      = "#0d0c0c",
    bg1     = "#141414",
    bg2     = "#1c1c1c",
    bg3     = "#252525",
    dim     = "#2d2d2d",
    muted   = "#3d3d3d",
    mid     = "#5e5e5e",
    text    = "#DCD7BA",
    bright  = "#F0F0F0",
    white   = "#FFFFFF",
    comment = "#505050",
    err     = "#FF5D62",
    warn    = "#DCA561",
    info    = "#7E9CD8",
    hint    = "#6A9589",
    add_fg  = "#76946A",
    add_bg  = "#2B3328",
    chg_fg  = "#DCA561",
    chg_bg  = "#49443C",
    del_fg  = "#C34043",
    del_bg  = "#43242B",
    md_h1_bg = "#1a1a1a",
    md_h2_bg = "#181818",
    md_h3_bg = "#161616",
    md_h4_bg = "#141414",
    md_link  = "#7E9CD8",
    none    = "NONE",
  }
end

local function light_palette()
  return {
    bg      = "#FFFFFF",
    bg1     = "#F7F4ED",
    bg2     = "#EDEAD8",
    bg3     = "#E4E0CE",
    dim     = "#D5D1C0",
    muted   = "#B5B1A4",
    mid     = "#8A8680",
    text    = "#545464",
    bright  = "#3C3C54",
    white   = "#1F1F28",
    comment = "#A09D94",
    err     = "#E82424",
    warn    = "#DCA561",
    info    = "#7E9CD8",
    hint    = "#6A9589",
    add_fg  = "#5E7955",
    add_bg  = "#E0EDDA",
    chg_fg  = "#B8860B",
    chg_bg  = "#F0E8D0",
    del_fg  = "#B33040",
    del_bg  = "#F5DDE0",
    md_h1_bg = "#EDE8D8",
    md_h2_bg = "#F0ECE0",
    md_h3_bg = "#F3F0E8",
    md_h4_bg = "#F5F3ED",
    md_link  = "#7E9CD8",
    none    = "NONE",
  }
end

local function apply()
  local p = vim.o.background == "light" and light_palette() or dark_palette()

  local hl = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- Editor UI
  hl("Normal",       { fg = p.text, bg = p.bg })
  hl("NormalFloat",  { fg = p.text, bg = p.bg1 })
  hl("FloatBorder",  { fg = p.dim, bg = p.bg1 })
  hl("FloatTitle",   { fg = p.bright, bg = p.bg1, bold = true })
  hl("CursorLine",   { bg = p.bg1 })
  hl("CursorLineNr", { fg = p.white, bold = true })
  hl("LineNr",       { fg = p.muted })
  hl("SignColumn",   { bg = p.bg })
  hl("ColorColumn",  { bg = p.bg1 })
  hl("Visual",       { bg = p.bg3 })
  hl("VisualNOS",    { bg = p.bg3 })
  hl("Pmenu",        { fg = p.text, bg = p.bg1 })
  hl("PmenuSel",     { fg = p.white, bg = p.bg2, bold = true })
  hl("PmenuSbar",    { bg = p.bg1 })
  hl("PmenuThumb",   { bg = p.muted })
  hl("StatusLine",   { fg = p.mid, bg = p.bg1 })
  hl("StatusLineNC", { fg = p.muted, bg = p.bg1 })
  hl("TabLine",      { fg = p.muted, bg = p.bg1 })
  hl("TabLineFill",  { bg = p.bg })
  hl("TabLineSel",   { fg = p.white, bg = p.bg, bold = true })
  hl("WinSeparator", { fg = p.bg2 })
  hl("VertSplit",    { fg = p.bg2 })
  hl("Folded",       { fg = p.mid, bg = p.bg1, italic = true })
  hl("FoldColumn",   { fg = p.muted, bg = p.bg })
  hl("NonText",      { fg = p.bg2 })
  hl("SpecialKey",   { fg = p.bg2 })
  hl("Whitespace",   { fg = p.bg2 })
  hl("EndOfBuffer",  { fg = p.bg })
  hl("Search",       { fg = p.bg, bg = p.mid })
  hl("IncSearch",    { fg = p.bg, bg = p.bright })
  hl("CurSearch",    { fg = p.bg, bg = p.white, bold = true })
  hl("MatchParen",   { fg = p.white, bg = p.bg3, bold = true })
  hl("ModeMsg",      { fg = p.bright, bold = true })
  hl("MoreMsg",      { fg = p.mid })
  hl("Question",     { fg = p.mid })
  hl("WarningMsg",   { fg = p.warn, italic = true })
  hl("ErrorMsg",     { fg = p.err, bold = true })
  hl("Title",        { fg = p.white, bold = true })
  hl("Directory",    { fg = p.bright, bold = true })
  hl("WildMenu",     { fg = p.white, bg = p.bg3 })
  hl("Conceal",      { fg = p.muted })
  hl("SpellBad",     { undercurl = true, sp = p.err })
  hl("SpellCap",     { undercurl = true, sp = p.warn })
  hl("SpellLocal",   { undercurl = true, sp = p.mid })
  hl("SpellRare",    { undercurl = true, sp = p.mid })

  -- Syntax (monochrome)
  hl("Comment",      { fg = p.comment, italic = true })
  hl("Constant",     { fg = p.bright })
  hl("String",       { fg = p.mid })
  hl("Character",    { fg = p.mid })
  hl("Number",       { fg = p.bright })
  hl("Boolean",      { fg = p.bright })
  hl("Float",        { fg = p.bright })
  hl("Identifier",   { fg = p.text })
  hl("Function",     { fg = p.white, bold = true })
  hl("Statement",    { fg = p.white, bold = true })
  hl("Conditional",  { fg = p.white, bold = true })
  hl("Repeat",       { fg = p.white, bold = true })
  hl("Label",        { fg = p.bright })
  hl("Operator",     { fg = p.muted })
  hl("Keyword",      { fg = p.white, bold = true })
  hl("Exception",    { fg = p.bright })
  hl("PreProc",      { fg = p.bright })
  hl("Include",      { fg = p.bright })
  hl("Define",       { fg = p.bright })
  hl("Macro",        { fg = p.bright })
  hl("PreCondit",    { fg = p.bright })
  hl("Type",         { fg = p.bright })
  hl("StorageClass", { fg = p.bright })
  hl("Structure",    { fg = p.bright })
  hl("Typedef",      { fg = p.bright })
  hl("Special",      { fg = p.mid })
  hl("SpecialChar",  { fg = p.mid })
  hl("Tag",          { fg = p.bright })
  hl("Delimiter",    { fg = p.muted })
  hl("Debug",        { fg = p.mid })
  hl("Underlined",   { fg = p.text, underline = true })
  hl("Error",        { fg = p.err })
  hl("Todo",         { fg = p.white, bg = p.bg3, bold = true })

  -- Treesitter
  hl("@comment",                { link = "Comment" })
  hl("@comment.documentation",  { fg = p.comment, italic = true })

  hl("@string",         { fg = p.mid })
  hl("@string.regex",   { fg = p.mid })
  hl("@string.escape",  { fg = p.muted })
  hl("@string.special", { fg = p.mid })
  hl("@character",      { fg = p.mid })

  hl("@constant",         { fg = p.bright })
  hl("@constant.builtin", { fg = p.bright })
  hl("@number",           { fg = p.bright })
  hl("@boolean",          { fg = p.bright })
  hl("@float",            { fg = p.bright })

  hl("@function",         { fg = p.white, bold = true })
  hl("@function.builtin", { fg = p.bright })
  hl("@function.call",    { fg = p.bright })
  hl("@method",           { fg = p.white, bold = true })
  hl("@method.call",      { fg = p.bright })
  hl("@constructor",      { fg = p.bright })

  hl("@keyword",           { fg = p.white, bold = true })
  hl("@keyword.function",  { fg = p.white, bold = true })
  hl("@keyword.operator",  { fg = p.bright })
  hl("@keyword.return",    { fg = p.white, bold = true })
  hl("@keyword.import",    { fg = p.bright })
  hl("@conditional",       { fg = p.white, bold = true })
  hl("@repeat",            { fg = p.white, bold = true })
  hl("@exception",         { fg = p.bright })
  hl("@label",             { fg = p.mid })

  hl("@variable",         { fg = p.text })
  hl("@variable.builtin", { fg = p.bright })
  hl("@variable.member",  { fg = p.text })
  hl("@parameter",        { fg = p.text })
  hl("@property",         { fg = p.text })

  hl("@type",            { fg = p.bright })
  hl("@type.builtin",    { fg = p.bright })
  hl("@type.qualifier",  { fg = p.bright })
  hl("@type.definition", { fg = p.bright })

  hl("@operator",              { fg = p.muted })
  hl("@punctuation",           { fg = p.muted })
  hl("@punctuation.bracket",   { fg = p.muted })
  hl("@punctuation.delimiter", { fg = p.muted })
  hl("@punctuation.special",   { fg = p.muted })

  hl("@tag",           { fg = p.bright })
  hl("@tag.attribute", { fg = p.text })
  hl("@tag.delimiter", { fg = p.muted })

  hl("@namespace", { fg = p.mid })
  hl("@module",    { fg = p.mid })

  hl("@attribute",  { fg = p.mid })
  hl("@annotation", { fg = p.mid })

  hl("@markup.heading",   { fg = p.white, bold = true })
  hl("@markup.heading.1", { fg = p.white, bg = p.md_h1_bg, bold = true })
  hl("@markup.heading.2", { fg = p.bright, bg = p.md_h2_bg, bold = true })
  hl("@markup.heading.3", { fg = p.bright, bg = p.md_h3_bg })
  hl("@markup.heading.4", { fg = p.text, bg = p.md_h4_bg })
  hl("@markup.strong",    { fg = p.white, bold = true })
  hl("@markup.italic",    { fg = p.bright, italic = true })
  hl("@markup.link",      { fg = p.md_link, underline = true })
  hl("@markup.link.url",  { fg = p.mid, underline = true })
  hl("@markup.raw",       { fg = p.mid, bg = p.bg1 })
  hl("@markup.list",      { fg = p.bright })

  -- LSP semantic tokens
  hl("@lsp.type.namespace",  { fg = p.mid })
  hl("@lsp.type.type",       { fg = p.bright })
  hl("@lsp.type.class",      { fg = p.bright })
  hl("@lsp.type.enum",       { fg = p.bright })
  hl("@lsp.type.interface",  { fg = p.bright })
  hl("@lsp.type.struct",     { fg = p.bright })
  hl("@lsp.type.parameter",  { fg = p.text })
  hl("@lsp.type.variable",   { fg = p.text })
  hl("@lsp.type.property",   { fg = p.text })
  hl("@lsp.type.function",   { fg = p.white, bold = true })
  hl("@lsp.type.method",     { fg = p.white, bold = true })
  hl("@lsp.type.macro",      { fg = p.bright })
  hl("@lsp.type.decorator",  { fg = p.mid })
  hl("@lsp.mod.deprecated",  { strikethrough = true })

  -- Diagnostics
  hl("DiagnosticError",          { fg = p.err, bold = true })
  hl("DiagnosticWarn",           { fg = p.warn })
  hl("DiagnosticInfo",           { fg = p.info, italic = true })
  hl("DiagnosticHint",           { fg = p.hint, italic = true })
  hl("DiagnosticOk",             { fg = p.add_fg })
  hl("DiagnosticUnderlineError", { undercurl = true, sp = p.err })
  hl("DiagnosticUnderlineWarn",  { undercurl = true, sp = p.warn })
  hl("DiagnosticUnderlineInfo",  { undercurl = true, sp = p.info })
  hl("DiagnosticUnderlineHint",  { undercurl = true, sp = p.hint })
  hl("DiagnosticVirtualTextError", { fg = p.err, bg = p.bg1, bold = true })
  hl("DiagnosticVirtualTextWarn",  { fg = p.warn, bg = p.bg1 })
  hl("DiagnosticVirtualTextInfo",  { fg = p.info, bg = p.bg1, italic = true })
  hl("DiagnosticVirtualTextHint",  { fg = p.hint, bg = p.bg1, italic = true })

  -- Diff (red/green with visible backgrounds)
  hl("DiffAdd",    { bg = p.add_bg })
  hl("DiffChange", { bg = p.chg_bg })
  hl("DiffDelete", { bg = p.del_bg })
  hl("DiffText",   { bg = p.bg3 })
  hl("Added",      { fg = p.add_fg })
  hl("Changed",    { fg = p.chg_fg })
  hl("Removed",    { fg = p.del_fg })

  -- Git signs
  hl("GitSignsAdd",          { fg = p.add_fg })
  hl("GitSignsChange",       { fg = p.chg_fg })
  hl("GitSignsDelete",       { fg = p.del_fg })
  hl("GitSignsAddNr",        { fg = p.add_fg })
  hl("GitSignsChangeNr",     { fg = p.chg_fg })
  hl("GitSignsDeleteNr",     { fg = p.del_fg })
  hl("GitSignsAddLn",        { bg = p.add_bg })
  hl("GitSignsChangeLn",     { bg = p.chg_bg })
  hl("GitSignsDeleteLn",     { bg = p.del_bg })

  -- Neogit
  hl("NeogitDiffAdd",        { fg = p.add_fg, bg = p.add_bg })
  hl("NeogitDiffDelete",     { fg = p.del_fg, bg = p.del_bg })
  hl("NeogitDiffContext",     { fg = p.text, bg = p.bg })
  hl("NeogitHunkHeader",     { fg = p.bright, bg = p.bg1, bold = true })
  hl("NeogitBranch",         { fg = p.bright, bold = true })
  hl("NeogitRemote",         { fg = p.mid })

  -- Oil
  hl("OilDir",      { fg = p.bright, bold = true })
  hl("OilLink",     { fg = p.mid, underline = true })
  hl("OilFile",     { fg = p.text })
  hl("OilSize",     { fg = p.muted })
  hl("OilMtime",    { fg = p.muted })

  -- Blink/completion
  hl("BlinkCmpMenu",           { fg = p.text, bg = p.bg1 })
  hl("BlinkCmpMenuBorder",     { fg = p.dim, bg = p.bg1 })
  hl("BlinkCmpMenuSelection",  { bg = p.bg2 })
  hl("BlinkCmpLabel",          { fg = p.text })
  hl("BlinkCmpLabelMatch",     { fg = p.white, bold = true })
  hl("BlinkCmpKind",           { fg = p.mid })
  hl("BlinkCmpDoc",            { fg = p.text, bg = p.bg1 })
  hl("BlinkCmpDocBorder",      { fg = p.dim, bg = p.bg1 })

  -- Which-key
  hl("WhichKey",          { fg = p.white, bold = true })
  hl("WhichKeyGroup",     { fg = p.bright })
  hl("WhichKeySeparator", { fg = p.muted })
  hl("WhichKeyDesc",      { fg = p.text })
  hl("WhichKeyFloat",     { bg = p.bg1 })

  -- Snacks
  hl("SnacksPickerMatch",      { fg = p.white, bold = true })
  hl("SnacksPickerDir",        { fg = p.muted })
  hl("SnacksPickerFile",       { fg = p.text })
  hl("SnacksPickerBorder",     { fg = p.dim, bg = p.bg1 })
  hl("SnacksNotifierInfo",         { fg = p.info })
  hl("SnacksNotifierWarn",         { fg = p.warn })
  hl("SnacksNotifierError",        { fg = p.err })
  hl("SnacksNotifierDebug",        { fg = p.comment })
  hl("SnacksNotifierTrace",        { fg = p.muted })
  hl("SnacksNotifierIconInfo",     { fg = p.info })
  hl("SnacksNotifierIconWarn",     { fg = p.warn })
  hl("SnacksNotifierIconError",    { fg = p.err })
  hl("SnacksNotifierIconDebug",    { fg = p.comment })
  hl("SnacksNotifierIconTrace",    { fg = p.muted })
  hl("SnacksNotifierTitleInfo",    { fg = p.info, bold = true })
  hl("SnacksNotifierTitleWarn",    { fg = p.warn, bold = true })
  hl("SnacksNotifierTitleError",   { fg = p.err, bold = true })
  hl("SnacksNotifierTitleDebug",   { fg = p.comment, bold = true })
  hl("SnacksNotifierTitleTrace",   { fg = p.muted, bold = true })
  hl("SnacksNotifierBorderInfo",   { fg = p.info })
  hl("SnacksNotifierBorderWarn",   { fg = p.warn })
  hl("SnacksNotifierBorderError",  { fg = p.err })
  hl("SnacksNotifierBorderDebug",  { fg = p.comment })
  hl("SnacksNotifierBorderTrace",  { fg = p.muted })

  -- Render-markdown
  hl("RenderMarkdownH1",         { fg = p.white, bg = p.md_h1_bg, bold = true })
  hl("RenderMarkdownH1Bg",       { bg = p.md_h1_bg })
  hl("RenderMarkdownH2",         { fg = p.bright, bg = p.md_h2_bg, bold = true })
  hl("RenderMarkdownH2Bg",       { bg = p.md_h2_bg })
  hl("RenderMarkdownH3",         { fg = p.bright, bg = p.md_h3_bg })
  hl("RenderMarkdownH3Bg",       { bg = p.md_h3_bg })
  hl("RenderMarkdownH4",         { fg = p.text, bg = p.md_h4_bg })
  hl("RenderMarkdownH4Bg",       { bg = p.md_h4_bg })
  hl("RenderMarkdownCode",       { bg = p.bg1 })
  hl("RenderMarkdownCodeInline", { fg = p.mid, bg = p.bg1 })
  hl("RenderMarkdownBullet",     { fg = p.bright })
  hl("RenderMarkdownDash",       { fg = p.dim })
  hl("RenderMarkdownLink",       { fg = p.md_link, underline = true })
  hl("RenderMarkdownQuote",      { fg = p.comment, italic = true })

  -- Djinni
  hl("DjinniYou",    { fg = p.bright, bold = true })
  hl("DjinniAI",     { fg = p.white, bold = true })
  hl("DjinniSystem", { fg = p.mid, bold = true })
end

return {
  dir = ".",
  name = "mono-palette",
  lazy = false,
  priority = 1000,
  config = function()
    vim.o.background = "dark"
    apply()
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = apply,
    })
  end,
}
