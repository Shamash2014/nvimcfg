-- Filetype detection for custom file types

vim.filetype.add({
  extension = {
    chat = 'chat',  -- Use dedicated chat filetype
  },
  filename = {
    ['.chat'] = 'chat',  -- Use dedicated chat filetype
  },
  pattern = {
    ['.*%.chat'] = 'chat',  -- Use dedicated chat filetype
  },
})
