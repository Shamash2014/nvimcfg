local function dark_palette()
  return {
    bg      = "#080808",
    bg1     = "#0f0f0f",
    bg2     = "#171717",
    bg3     = "#202020",
    dim     = "#282828",
    muted   = "#505050",
    mid     = "#888888",
    text    = "#bcbcbc",
    bright  = "#d0d0d0",
    white   = "#e0e0e0",
    comment = "#606060",
    err     = "#FF6673",
    warn    = "#E8B468",
    info    = "#8CACD8",
    hint    = "#7AAE9E",
    add_fg  = "#87A77C",
    add_bg  = "#1A2618",
    chg_fg  = "#E8B468",
    chg_bg  = "#2E2A1E",
    del_fg  = "#D4484B",
    del_bg  = "#2B1418",
    md_h1_bg = "#121212",
    md_h2_bg = "#101010",
    md_h3_bg = "#0e0e0e",
    md_h4_bg = "#0c0c0c",
    md_link  = "#7E9CD8",
    none    = "NONE",
  }
end

local function light_palette()
  return {
    bg      = "#eee8d5",
    bg1     = "#e5dfcb",
    bg2     = "#dbd5c1",
    bg3     = "#d0cab6",
    dim     = "#bfb9a5",
    muted   = "#887a64",
    mid     = "#605848",
    text    = "#352f28",
    bright  = "#1e1a14",
    white   = "#0e0c08",
    comment = "#a09888",
    err     = "#b82020",
    warn    = "#9a6010",
    info    = "#35608a",
    hint    = "#407058",
    add_fg  = "#3a5828",
    add_bg  = "#dde8d4",
    chg_fg  = "#805510",
    chg_bg  = "#ece0c8",
    del_fg  = "#902828",
    del_bg  = "#eed8d8",
    md_h1_bg = "#e5dfd6",
    md_h2_bg = "#e8e2da",
    md_h3_bg = "#ece7e0",
    md_h4_bg = "#efebe5",
    md_link  = "#35608a",
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
  hl("Cursor",       { fg = p.bg, bg = p.muted })
  hl("TermCursor",   { fg = p.bg, bg = p.muted })
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

  -- Syntax (Alabaster: only strings, comments, errors get distinction)
  hl("Comment",      { fg = p.comment, italic = true })
  hl("Constant",     { fg = p.text })
  hl("String",       { fg = p.mid })
  hl("Character",    { fg = p.mid })
  hl("Number",       { fg = p.text })
  hl("Boolean",      { fg = p.text })
  hl("Float",        { fg = p.text })
  hl("Identifier",   { fg = p.text })
  hl("Function",     { fg = p.bright, bold = true })
  hl("Statement",    { fg = p.text })
  hl("Conditional",  { fg = p.text })
  hl("Repeat",       { fg = p.text })
  hl("Label",        { fg = p.text })
  hl("Operator",     { fg = p.muted })
  hl("Keyword",      { fg = p.text })
  hl("Exception",    { fg = p.text })
  hl("PreProc",      { fg = p.text })
  hl("Include",      { fg = p.text })
  hl("Define",       { fg = p.text })
  hl("Macro",        { fg = p.text })
  hl("PreCondit",    { fg = p.text })
  hl("Type",         { fg = p.text })
  hl("StorageClass", { fg = p.text })
  hl("Structure",    { fg = p.text })
  hl("Typedef",      { fg = p.text })
  hl("Special",      { fg = p.text })
  hl("SpecialChar",  { fg = p.mid })
  hl("Tag",          { fg = p.text })
  hl("Delimiter",    { fg = p.muted })
  hl("Debug",        { fg = p.text })
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

  hl("@constant",         { fg = p.text })
  hl("@constant.builtin", { fg = p.text })
  hl("@number",           { fg = p.text })
  hl("@boolean",          { fg = p.text })
  hl("@float",            { fg = p.text })

  hl("@function",         { fg = p.bright, bold = true })
  hl("@function.builtin", { fg = p.text })
  hl("@function.call",    { fg = p.text })
  hl("@method",           { fg = p.bright, bold = true })
  hl("@method.call",      { fg = p.text })
  hl("@constructor",      { fg = p.text })

  hl("@keyword",           { fg = p.text })
  hl("@keyword.function",  { fg = p.text })
  hl("@keyword.operator",  { fg = p.muted })
  hl("@keyword.return",    { fg = p.text })
  hl("@keyword.import",    { fg = p.text })
  hl("@conditional",       { fg = p.text })
  hl("@repeat",            { fg = p.text })
  hl("@exception",         { fg = p.text })
  hl("@label",             { fg = p.text })

  hl("@variable",         { fg = p.text })
  hl("@variable.builtin", { fg = p.text })
  hl("@variable.member",  { fg = p.text })
  hl("@parameter",        { fg = p.text })
  hl("@property",         { fg = p.text })

  hl("@type",            { fg = p.text })
  hl("@type.builtin",    { fg = p.text })
  hl("@type.qualifier",  { fg = p.text })
  hl("@type.definition", { fg = p.text })

  hl("@operator",              { fg = p.muted })
  hl("@punctuation",           { fg = p.muted })
  hl("@punctuation.bracket",   { fg = p.muted })
  hl("@punctuation.delimiter", { fg = p.muted })
  hl("@punctuation.special",   { fg = p.muted })

  hl("@tag",           { fg = p.text })
  hl("@tag.attribute", { fg = p.text })
  hl("@tag.delimiter", { fg = p.muted })

  hl("@namespace", { fg = p.text })
  hl("@module",    { fg = p.text })

  hl("@attribute",  { fg = p.text })
  hl("@annotation", { fg = p.text })

  hl("@markup.heading",   { fg = p.bright, bold = true })
  hl("@markup.heading.1", { fg = p.white, bg = p.md_h1_bg, bold = true })
  hl("@markup.heading.2", { fg = p.bright, bg = p.md_h2_bg, bold = true })
  hl("@markup.heading.3", { fg = p.bright, bg = p.md_h3_bg })
  hl("@markup.heading.4", { fg = p.text, bg = p.md_h4_bg })
  hl("@markup.strong",    { fg = p.bright, bold = true })
  hl("@markup.italic",    { fg = p.text, italic = true })
  hl("@markup.link",      { fg = p.md_link, underline = true })
  hl("@markup.link.url",  { fg = p.mid, underline = true })
  hl("@markup.raw",       { fg = p.mid, bg = p.bg1 })
  hl("@markup.list",      { fg = p.muted })

  -- LSP semantic tokens
  hl("@lsp.type.namespace",  { fg = p.text })
  hl("@lsp.type.type",       { fg = p.text })
  hl("@lsp.type.class",      { fg = p.text })
  hl("@lsp.type.enum",       { fg = p.text })
  hl("@lsp.type.interface",  { fg = p.text })
  hl("@lsp.type.struct",     { fg = p.text })
  hl("@lsp.type.parameter",  { fg = p.text })
  hl("@lsp.type.variable",   { fg = p.text })
  hl("@lsp.type.property",   { fg = p.text })
  hl("@lsp.type.function",   { fg = p.bright, bold = true })
  hl("@lsp.type.method",     { fg = p.bright, bold = true })
  hl("@lsp.type.macro",      { fg = p.text })
  hl("@lsp.type.decorator",  { fg = p.text })
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
  hl("BlinkCmpGhostText",     { fg = p.muted, italic = true })

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

  -- Djinni / Neowork
  hl("DjinniYou",    { fg = p.white, bold = true })
  hl("DjinniAI",     { fg = p.bright, bold = true })
  hl("DjinniSystem", { fg = p.muted, bold = true })
  hl("DjinniPanel",       { fg = p.text, bg = p.bg1 })
  hl("DjinniPanelBorder", { fg = p.dim, bg = p.bg1 })
  hl("DjinniPanelTitle",  { fg = p.white, bg = p.bg1, bold = true })
  hl("DjinniSessionName", { fg = p.bright, bold = true })
end

return {
  dir = ".",
  name = "mono-palette",
  lazy = false,
  priority = 1000,
  config = function()
    vim.o.background = "light"
    apply()
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = apply,
    })
  end,
}
