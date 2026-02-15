-- Filetype detection for custom file types

vim.filetype.add({
  extension = {
    chat = 'markdown',  -- Keep markdown for rendering
  },
  filename = {
    ['.chat'] = 'markdown',  -- Keep markdown for rendering
  },
  pattern = {
    ['.*%.chat'] = 'markdown',  -- Keep markdown for rendering
  },
})
