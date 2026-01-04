return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  config = function()
    local supported_filetypes = {
      'lua', 'python', 'javascript', 'typescript', 'jsx', 'tsx',
      'go', 'rust', 'elixir', 'heex', 'eex', 'bash', 'json',
      'html', 'css', 'markdown', 'vim', 'yaml', 'toml',
      'dart', 'swift', 'kotlin', 'java', 'astro', 'vue'
    }

    local group = vim.api.nvim_create_augroup('TreesitterFolds', { clear = true })

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = supported_filetypes,
      callback = function()
        pcall(vim.treesitter.start)
        vim.schedule(function()
          vim.wo.foldmethod = 'expr'
          vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
          vim.wo.foldlevel = 99
          vim.wo.foldenable = true
        end)
      end,
    })
  end,
}