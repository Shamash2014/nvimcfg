return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  init = function()
    -- Enable treesitter highlighting for common filetypes
    vim.api.nvim_create_autocmd('FileType', {
      pattern = {
        'lua', 'python', 'javascript', 'typescript', 'jsx', 'tsx',
        'go', 'rust', 'elixir', 'heex', 'eex', 'bash', 'json',
        'html', 'css', 'markdown', 'vim', 'yaml', 'toml'
      },
      callback = function()
        pcall(vim.treesitter.start)
      end,
    })

    -- Enable treesitter folding
    vim.api.nvim_create_autocmd('FileType', {
      pattern = {
        'lua', 'python', 'javascript', 'typescript', 'jsx', 'tsx',
        'go', 'rust', 'elixir'
      },
      callback = function()
        vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
        vim.wo[0][0].foldmethod = 'expr'
        vim.wo[0][0].foldenable = false -- Start with folds open
      end,
    })

    -- Parsers will be auto-installed when opening files
  end,
}