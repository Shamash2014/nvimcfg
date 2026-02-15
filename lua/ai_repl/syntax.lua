local M = {}

function M.setup()
  local hl = vim.api.nvim_set_hl
  hl(0, "AIReplPrompt", { fg = "#DDDDDD", bold = true })
  hl(0, "AIReplUser", { fg = "#B0D0B0" })
  hl(0, "AIReplDjinni", { fg = "#D0B0F0" })
  hl(0, "AIReplHeader", { fg = "#DDDDDD", bold = true })
  hl(0, "AIReplTool", { fg = "#AAAAAA" })
  hl(0, "AIReplToolPending", { fg = "#999999" })
  hl(0, "AIReplToolDone", { fg = "#CCCCCC" })
  hl(0, "AIReplToolFail", { fg = "#FF4444" })
  hl(0, "AIReplPlan", { fg = "#AAAAAA" })
  hl(0, "AIReplPlanActive", { fg = "#CCCCCC" })
  hl(0, "AIReplPlanComplete", { fg = "#808080" })
  hl(0, "AIReplQuestion", { fg = "#CCCCCC", bold = true })
  hl(0, "AIReplPermission", { fg = "#DDDDDD", bold = true })
  hl(0, "AIReplKey", { fg = "#DDDDDD", bold = true })
  hl(0, "AIReplLabel", { fg = "#AAAAAA" })
  hl(0, "AIReplInfo", { fg = "#AAAAAA" })
  hl(0, "AIReplError", { fg = "#FF4444" })
  hl(0, "AIReplSeparator", { fg = "#808080" })
  -- Diff-specific highlights
  hl(0, "AIReplDiffHeader", { fg = "#888888", bg = "#2a2a2a", bold = true })
  hl(0, "AIReplDiffHunk", { fg = "#AAAAAA", bg = "#252525" })
  hl(0, "AIReplDiffAdd", { bg = "#1a2f1a", fg = "#A0C0A0" })
  hl(0, "AIReplDiffDelete", { bg = "#2f1a1a", fg = "#C0A0A0" })
  hl(0, "AIReplDiffChange", { bg = "#2f2f1a", fg = "#C0C0A0" })
  hl(0, "AIReplDiffAddWord", { bg = "#2a4a2a", fg = "#B0D0B0", bold = true })
  hl(0, "AIReplDiffDeleteWord", { bg = "#4a2a2a", fg = "#D0B0B0", bold = true })
  hl(0, "AIReplDiffContext", { fg = "#888888" })
  hl(0, "AIReplDiffStats", { fg = "#AAAAAA", bold = true })
  -- Chat buffer decorations - enhanced
  hl(0, "ChatRoleYou", { bg = "#1a3a1a", bold = true, fg = "#B0D0B0", italic = true })
  hl(0, "ChatRoleDjinni", { bg = "#2a1a3a", bold = true, fg = "#D0B0F0", italic = false })
  hl(0, "ChatRoleSystem", { bg = "#2f2f1a", bold = true, fg = "#C0C0A0" })
  hl(0, "ChatRuler", { fg = "#444444" })
  hl(0, "ChatRulerYou", { fg = "#3a7a3a", bg = "#0a2a0a" })
  hl(0, "ChatRulerDjinni", { fg = "#5a3a7a", bg = "#1a0a2a" })
  hl(0, "ChatBorder", { fg = "#666666" })
  hl(0, "ChatSpinner", { fg = "#888888", italic = true })
  hl(0, "ChatTokenInfo", { fg = "#666666", italic = true })
  hl(0, "ChatUserMarker", { fg = "#90EE90", bold = true, bg = "#1a3a1a" })
  hl(0, "ChatDjinniMarker", { fg = "#DDA0DD", bold = true, bg = "#2a1a3a" })

  -- Enhanced markdown-specific highlights for chat buffers
  -- Code blocks
  hl(0, "RenderMarkdownCode", { bg = "#1a1a2e", fg = "#a9b1d6" })
  hl(0, "RenderMarkdownCodeInline", { bg = "#2a2a3e", fg = "#a9b1d6", italic = true })

  -- Headings with gradient backgrounds
  hl(0, "RenderMarkdownH1", { fg = "#ff9e64", bold = true })
  hl(0, "RenderMarkdownH1Bg", { bg = "#2a1a1a" })
  hl(0, "RenderMarkdownH2", { fg = "#e0af68", bold = true })
  hl(0, "RenderMarkdownH2Bg", { bg = "#2a2a1a" })
  hl(0, "RenderMarkdownH3", { fg = "#9ece6a", bold = true })
  hl(0, "RenderMarkdownH3Bg", { bg = "#1a2a1a" })
  hl(0, "RenderMarkdownH4", { fg = "#7dcfff", bold = true })
  hl(0, "RenderMarkdownH4Bg", { bg = "#1a1a2a" })
  hl(0, "RenderMarkdownH5", { fg = "#bb9af7", bold = true })
  hl(0, "RenderMarkdownH5Bg", { bg = "#1a1a2a" })
  hl(0, "RenderMarkdownH6", { fg = "#f7768e", bold = true })
  hl(0, "RenderMarkdownH6Bg", { bg = "#1a1a2a" })

  -- Lists and bullets
  hl(0, "RenderMarkdownBullet", { fg = "#7dcfff", bold = true })
  hl(0, "RenderMarkdownChecked", { fg = "#9ece6a", bold = true })
  hl(0, "RenderMarkdownUnchecked", { fg = "#565f89", bold = true })
  hl(0, "RenderMarkdownTodo", { fg = "#e0af68", bold = true })

  -- Tables
  hl(0, "RenderMarkdownTableHead", { fg = "#7dcfff", bold = true, bg = "#1a1a2e" })
  hl(0, "RenderMarkdownTableRow", { fg = "#c0caf5", bg = "#16161e" })
  hl(0, "RenderMarkdownTableFill", { fg = "#414868", bg = "#1a1b26" })

  -- Blockquotes and callouts
  hl(0, "RenderMarkdownQuote", { fg = "#9aa5ce", italic = true })
  hl(0, "RenderMarkdownInfo", { fg = "#7dcfff", bg = "#1a1a2e" })
  hl(0, "RenderMarkdownSuccess", { fg = "#9ece6a", bg = "#1a2a1a" })
  hl(0, "RenderMarkdownWarn", { fg = "#e0af68", bg = "#2a2a1a" })
  hl(0, "RenderMarkdownError", { fg = "#f7768e", bg = "#2a1a1a" })
  hl(0, "RenderMarkdownHint", { fg = "#bb9af7", bg = "#2a1a2a" })

  -- Links
  hl(0, "RenderMarkdownLink", { fg = "#7aa2f7", underline = true })

  -- Inline highlights
  hl(0, "RenderMarkdownInlineHighlight", { bg = "#2a2a3e", fg = "#ff9e64" })

  -- Custom highlights for AI response markers
  hl(0, "ChatThinking", { fg = "#565f89", italic = true })
  hl(0, "ChatInlineCode", { bg = "#2a2a3e", fg = "#a9b1d6" })
  hl(0, "ChatCodeBlock", { bg = "#1a1a2e", fg = "#a9b1d6" })
  hl(0, "ChatHeading", { fg = "#ff9e64", bold = true })
  hl(0, "ChatList", { fg = "#7dcfff", bold = true })
  hl(0, "ChatBlockquote", { fg = "#9aa5ce", italic = true })
  hl(0, "ChatBold", { fg = "#c0caf5", bold = true })
  hl(0, "ChatItalic", { fg = "#c0caf5", italic = true })
  hl(0, "ChatLink", { fg = "#7aa2f7", underline = true })
end

function M.apply_to_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].omnifunc = ""

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end

    -- Enable Treesitter for markdown and markdown_inline
    pcall(function()
      vim.treesitter.stop(buf)
      vim.treesitter.start(buf, "markdown")
      vim.treesitter.start(buf, "markdown_inline")
    end)

    -- Attach render-markdown with enhanced configuration
    local render_ok, render_md = pcall(require, "render-markdown")
    if render_ok then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(function()
            -- Try the attach method first (newer versions)
            if render_md.attach then
              render_md.attach(buf, { enabled = true })
              vim.notify("[ai_repl] render-markdown attached to buffer", vim.log.levels.DEBUG)
            -- Try enable method (older versions)
            elseif render_md.enable then
              render_md.enable()
              vim.notify("[ai_repl] render-markdown enabled", vim.log.levels.DEBUG)
            else
              vim.notify("[ai_repl] render-markdown loaded but no attach method found", vim.log.levels.DEBUG)
            end
          end)
        end
      end)
    else
      vim.notify("[ai_repl] render-markdown not available", vim.log.levels.WARN)
    end

    -- Attach blink.cmp if available
    local blink_ok, blink = pcall(require, "blink.cmp")
    if blink_ok and blink.attach then
      pcall(blink.attach, buf)
    end

    -- Apply enhanced markdown syntax
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        -- Enable enhanced markdown features
        vim.cmd([[
          syntax cluster markdown add=ChatThinking,ChatInlineCode,ChatCodeBlock,ChatHeading,ChatList,ChatBlockquote,ChatBold,ChatItalic,ChatLink
          syntax match ChatMarkdownCode /\_[^`]\+/ containedin=ALL
        ]])
      end
    end)
  end)
end

return M
