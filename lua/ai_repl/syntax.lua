local M = {}

function M.setup()
  local hl = vim.api.nvim_set_hl
  hl(0, "AIReplPrompt", { fg = "#DDDDDD", bold = true })
  hl(0, "AIReplUser", { fg = "#CCCCCC" })
  hl(0, "AIReplAssistant", { fg = "#CCCCCC" })
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
end

function M.apply_to_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].omnifunc = ""

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end

    pcall(function()
      vim.treesitter.stop(buf)
      vim.treesitter.start(buf, "markdown")
    end)

    local render_ok, render_md = pcall(require, "render-markdown")
    if render_ok then
      pcall(function()
        if render_md.attach then
          render_md.attach(buf)
        elseif render_md.enable then
          render_md.enable()
        end
      end)
    end

    local blink_ok, blink = pcall(require, "blink.cmp")
    if blink_ok and blink.attach then
      pcall(blink.attach, buf)
    end
  end)
end

return M
