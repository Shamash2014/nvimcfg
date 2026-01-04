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

    -- Enable treesitter folding for all supported filetypes
    vim.api.nvim_create_autocmd('FileType', {
      pattern = {
        'lua', 'python', 'javascript', 'typescript', 'jsx', 'tsx',
        'go', 'rust', 'elixir', 'heex', 'eex', 'json', 'html', 'css',
        'yaml', 'toml', 'dart', 'swift', 'kotlin', 'java', 'astro', 'vue'
      },
      callback = function()
        vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
        vim.wo.foldmethod = 'expr'
        vim.wo.foldlevel = 99
        vim.wo.foldenable = true
      end,
    })

    -- Parsers will be auto-installed when opening files
  end,
}