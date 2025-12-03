local ok, lint = pcall(require, 'lint')
if ok then
  local linters = {}

  -- Use Vale if available (now installed)
  if vim.fn.executable("vale") == 1 then
    table.insert(linters, "vale")
  end

  -- Use markdownlint if available
  if vim.fn.executable("markdownlint") == 1 then
    table.insert(linters, "markdownlint")
  end

  if #linters > 0 then
    lint.linters_by_ft.markdown = linters
  end
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.markdown = { "prettier" }
end

-- Markdown rendering toggle available via command palette only (no keybinding)

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'MarkdownToggleRender',
  'RenderMarkdown toggle', { desc = 'Toggle Markdown Rendering' })

vim.api.nvim_buf_create_user_command(0, 'MarkdownPreview',
  '!open -a "Marked 2" %', { desc = 'Preview in Marked 2' })

vim.api.nvim_buf_create_user_command(0, 'MarkdownWordCount',
  function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local text = table.concat(lines, ' ')
    local words = 0
    for _ in text:gmatch('%S+') do words = words + 1 end
    vim.notify('Word count: ' .. words, vim.log.levels.INFO)
  end, { desc = 'Count Words in Document' })

vim.api.nvim_buf_create_user_command(0, 'MarkdownTOC',
  function()
    vim.cmd('normal! gg')
    vim.cmd('global/^#\\+/put =submatch(0)')
    vim.notify('TOC generated at top of file', vim.log.levels.INFO)
  end, { desc = 'Generate Table of Contents' })
