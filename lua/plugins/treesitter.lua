return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter-textobjects",
    "nvim-treesitter/nvim-treesitter-context",
  },
  config = function()
    local supported_filetypes = {
      'lua', 'python', 'javascript', 'typescript', 'jsx', 'tsx',
      'go', 'rust', 'elixir', 'heex', 'eex', 'bash', 'json',
      'html', 'css', 'markdown', 'markdown_inline', 'vim', 'yaml', 'toml',
      'dart', 'swift', 'kotlin', 'java', 'astro', 'vue', 'chat'
    }

    local function patch_query_get()
      local query = vim.treesitter.query
      if type(query) ~= "table" then return end
      local orig = query.get
      if type(orig) ~= "function" then return end
      query.get = function(lang, query_name)
        local ok, result = pcall(orig, lang, query_name)
        if ok then return result end
      end
    end
    patch_query_get()

    require("nvim-treesitter").setup()

    -- Ensure parsers are installed (async, non-blocking)
    local ensure_installed = {
      "lua", "vim", "vimdoc", "query", "markdown", "markdown_inline",
      "json", "yaml", "toml", "bash", "python", "javascript",
      "typescript", "tsx", "css", "html", "regex", "diff",
    }
    vim.schedule(function()
      local installed = require("nvim-treesitter.config").get_installed()
      local missing = vim.tbl_filter(function(lang)
        return not vim.list_contains(installed, lang)
      end, ensure_installed)
      if #missing > 0 then
        vim.cmd("TSInstall " .. table.concat(missing, " "))
      end
    end)

    -- Treesitter context
    require("treesitter-context").setup({
      enable = true,
      max_lines = 3,
      min_window_height = 0,
      line_timeout = 200,
      trim_scope = "outer",
      patterns = {
        default = {
          "class", "function", "method",
          "for", "while", "if", "switch", "case",
        },
        markdown = {
          "section", "atx_heading", "list_item",
        },
      },
      exact_patterns = {},
      zindex = 20,
      mode = "cursor",
    })

    vim.treesitter.language.register("markdown", "md")
    vim.treesitter.language.register("markdown_inline", "md")

    local group = vim.api.nvim_create_augroup('TreesitterFolds', { clear = true })

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = supported_filetypes,
      callback = function()
        local buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
        if buf_name:match("%.chat$") then
          return
        end

        local ok = pcall(vim.treesitter.start)
        if not ok then
          return
        end

        vim.schedule(function()
          local has_ts_lang, ts_lang = pcall(vim.treesitter.language.get_lang, vim.bo.filetype)
          if has_ts_lang and ts_lang then
            local bufnr = vim.api.nvim_get_current_buf()
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_get_buf(win) == bufnr then
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
