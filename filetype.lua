-- Filetype detection for custom file types

vim.filetype.add({
  extension = {
    chat = 'markdown',
  },
  filename = {
    ['.chat'] = 'markdown',
  },
  pattern = {
    ['.*%.chat'] = 'markdown',
  },
})
