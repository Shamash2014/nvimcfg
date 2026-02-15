-- Syntax highlighting for .chat buffers
-- Enhances markdown with chat-specific features

local M = {}

function M.setup()
  -- Define enhanced highlight groups for chat-specific syntax
  vim.cmd([[
    " Role markers (@You:, @Djinni:, @User:, etc.)
    syntax match ChatRoleMarker /^@\w\+:/
    syntax match ChatRoleName contained /\w\+/
    syntax match ChatRole /^@\(\(You\)\|\(Djinni\)\|\(Assistant\)\|\(User\)\|\(System\)\):/ contains=ChatRoleName

    " Tool use markers - enhanced with better highlighting
    syntax match ChatToolUse /^\*\*Tool Use:\*\*/ contained
    syntax match ChatToolResult /^\*\*Tool Result:\*\*/ contained

    " Thinking tags - better visual distinction
    syntax match ChatThinkingTag /^<thinking>/ contained
    syntax match ChatThinkingEnd /^<\/thinking>/ contained
    syntax region ChatThinking start=/^<thinking>/ end=/^<\/thinking>/ keepend contains=ChatThinkingTag,ChatThinkingEnd

    " Attachments
    syntax match ChatAttachment /^@\w\+\.\w\+/

    " Annotations - enhanced
    syntax match ChatAnnotation /^@Annotation:/
    syntax match ChatAnnotationNote contained /-\s*\*\*`[^`]*`\*\*\s*—/
    syntax region ChatAnnotationLine start=/^-\s*\*\*`/ end=/$/ oneline contains=ChatAnnotationNote

    " Code blocks in tool results - better language support
    syntax region ChatToolCode matchgroup=ChatToolCodeDelim start=/^\%(==\s*\)\@<!```lua/ end=/^```/ contains=@lua
    syntax region ChatToolCode matchgroup=ChatToolCodeDelim start=/^\%(==\s*\)\@<!```json/ end=/^```/ contains=@json
    syntax region ChatToolCode matchgroup=ChatToolCodeDelim start=/^\%(==\s*\)\@<!```python/ end=/^```/ contains=@python
    syntax region ChatToolCode matchgroup=ChatToolCodeDelim start=/^\%(==\s*\)\@<!```bash/ end=/^```/ contains=@bash
    syntax region ChatToolCode matchgroup=ChatToolCodeDelim start=/^\%(==\s*\)\@<!```/ end=/^```/

    " Session status headers - better styling
    syntax match ChatHeader /^===.*===$/
    syntax match ChatSection /^---*$/

    " Markdown inline code - enhanced detection
    syntax region ChatInlineCode start=/`/ end=/`/ oneline keepend

    " Markdown code blocks - enhanced
    syntax region ChatCodeBlock start=/^\z(`\{3,}\)\S*/ end=/^\z1\ze\s*$/ keepend

    " Markdown headings - better integration
    syntax match ChatHeading /^#\+.*$/ contains=@Spell

    " Markdown lists - enhanced
    syntax match ChatList /^\s*[-*+]\s\+/
    syntax match ChatList /^\s*\d\+\.\s\+/

    " Markdown blockquotes - enhanced
    syntax match ChatBlockquote /^>\s*.*/ contains=@Spell

    " Markdown bold and italic
    syntax match ChatBold /\*\*[^*]*\*\*/ contained
    syntax match ChatItalic /\*[^*]*\*/ contained
    syntax match ChatBoldItalic /\*\*\*[^*]*\*\*\*/ contained

    " Markdown links - enhanced
    syntax match ChatLink /\[[^\]]*\](\([^)]*\))/ contained
    syntax match ChatLink /\[[^\]]*\](\[[^\]]*\])/ contained

    " Link to existing markdown syntax
    syntax cluster chatSyntax add=ChatRoleMarker,ChatRole,ChatToolUse,ChatToolResult,ChatThinking,ChatAttachment,ChatAnnotation,ChatHeader,ChatSection,ChatInlineCode,ChatCodeBlock,ChatHeading,ChatList,ChatBlockquote,ChatBold,ChatItalic,ChatBoldItalic,ChatLink

    " Enhanced highlights with better color schemes
    highlight default link ChatRoleMarker Special
    highlight default link ChatRoleName Identifier
    highlight default link ChatRole Special
    highlight default link ChatToolUse Function
    highlight default link ChatToolResult String
    highlight default link ChatThinking Comment
    highlight default link ChatAnnotation Todo
    highlight default link ChatAttachment Directory
    highlight default link ChatToolCodeDelim Delimiter
    highlight default link ChatHeader Comment
    highlight default link ChatSection NonText
    highlight default link ChatInlineCode Special
    highlight default link ChatCodeBlock String
    highlight default link ChatHeading Title
    highlight default link ChatList Operator
    highlight default link ChatBlockquote Comment
    highlight default link ChatBold Special
    highlight default link ChatItalic Underlined
    highlight default link ChatBoldItalic SpecialBold
    highlight default link ChatLink Underlined
  ]])

  -- Setup optimized syntax for chat buffers
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function(ev)
      local buf = ev.buf
      local buf_name = vim.api.nvim_buf_get_name(buf)

      -- Check if this is a .chat buffer
      if buf_name:match("%.chat$") then
        -- Set up custom folding for chat buffers
        vim.bo[buf].foldmethod = "expr"
        vim.bo[buf].foldexpr = "v:lua.require'ai_repl.chat_decorations'.foldexpr(v:lnum)"
        vim.bo[buf].foldtext = "v:lua.require'ai_repl.chat_decorations'.foldtext()"

        -- For chat buffers: use ONLY render-markdown, disable treesitter for speed
        -- Treesitter markdown parsing is too slow for real-time chat
        return
      end

      -- For regular markdown files, enable treesitter
      pcall(function()
        vim.treesitter.start(buf, "markdown")
        vim.treesitter.start(buf, "markdown_inline")
      end)
    end,
  })
end

return M
