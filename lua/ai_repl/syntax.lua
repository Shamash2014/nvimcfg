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
end

function M.apply_to_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  pcall(function()
    vim.treesitter.start(buf, "markdown")
  end)
  local render_ok, render_md = pcall(require, "render-markdown")
  if render_ok and render_md.enable then
    pcall(function()
      render_md.enable()
    end)
  end
end

return M
