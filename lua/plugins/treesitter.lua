return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter-textobjects",
  },
  config = function()
    local supported_filetypes = {
      'lua', 'python', 'javascript', 'typescript', 'jsx', 'tsx',
      'go', 'rust', 'elixir', 'heex', 'eex', 'bash', 'json',
      'html', 'css', 'markdown', 'vim', 'yaml', 'toml',
      'dart', 'swift', 'kotlin', 'java', 'astro', 'vue', 'chat'
    }

    vim.treesitter.language.register("markdown", "md")

    local group = vim.api.nvim_create_augroup('TreesitterFolds', { clear = true })

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = supported_filetypes,
      callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local buf_name = vim.api.nvim_buf_get_name(bufnr)
        if buf_name:match("%.chat$") then return end
        if vim.b[bufnr].neowork_chat then return end

        local ok = pcall(vim.treesitter.start, bufnr)
        if not ok then
          return
        end

        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then return end
          local ft = vim.bo[bufnr].filetype
          local has_ts_lang, ts_lang = pcall(vim.treesitter.language.get_lang, ft)
          if has_ts_lang and ts_lang then
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
                vim.wo[win].foldmethod = 'expr'
                vim.wo[win].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
                vim.wo[win].foldlevel = 99
                vim.wo[win].foldenable = true
                break
              end
            end
          end
        end)
      end,
    })
  end,
}
