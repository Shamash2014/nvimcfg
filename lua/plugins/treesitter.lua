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

    require("nvim-treesitter.configs").setup({
      ensure_installed = {
        "lua",
        "vim",
        "vimdoc",
        "query",
        "markdown",
        "markdown_inline",
        "json",
        "yaml",
        "toml",
        "bash",
        "python",
        "javascript",
        "typescript",
        "tsx",
        "css",
        "html",
        "regex",
        "diff",
      },
      sync_install = false,
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = { "markdown" },
        disable = function(lang, buf)
          -- Disable for very large files
          local max_file_size = 1024 * 1024 -- 1MB
          local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
          if ok and stats and stats.size > max_file_size then
            return true
          end

          -- Disable treesitter for .chat buffers for performance
          -- They use render-markdown instead
          local buf_name = vim.api.nvim_buf_get_name(buf)
          if buf_name:match("%.chat$") then
            return true
          end

          return false
        end,
      },
      indent = {
        enable = true,
        disable = { "markdown" },
      },
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = "<CR>",
          node_incremental = "<CR>",
          scope_incremental = "<TAB>",
          node_decremental = "<S-TAB>",
        },
      },
      textobjects = {
        select = {
          enable = true,
          lookahead = true,
          keymaps = {
            ["af"] = "@function.outer",
            ["if"] = "@function.inner",
            ["ac"] = "@class.outer",
            ["ic"] = "@class.inner",
            ["ab"] = "@block.outer",
            ["ib"] = "@block.inner",
            ["al"] = "@call.outer",
            ["il"] = "@call.inner",
            ["aa"] = "@parameter.outer",
            ["ia"] = "@parameter.inner",
          },
        },
        swap = {
          enable = true,
          swap_next = {
            ["<leader>a"] = "@parameter.inner",
          },
          swap_previous = {
            ["<leader>A"] = "@parameter.inner",
          },
        },
        move = {
          enable = true,
          set_jumps = true,
          goto_next_start = {
            ["]f"] = "@function.outer",
            ["]c"] = "@class.outer",
            ["]b"] = "@block.outer",
            ["]a"] = "@parameter.outer",
          },
          goto_next_end = {
            ["]F"] = "@function.outer",
            ["]C"] = "@class.outer",
            ["]B"] = "@block.outer",
            ["]A"] = "@parameter.outer",
          },
          goto_previous_start = {
            ["[f"] = "@function.outer",
            ["[c"] = "@class.outer",
            ["[b"] = "@block.outer",
            ["[a"] = "@parameter.outer",
          },
          goto_previous_end = {
            ["[F"] = "@function.outer",
            ["[C"] = "@class.outer",
            ["[B"] = "@block.outer",
            ["[A"] = "@parameter.outer",
          },
        },
      },
    })

    -- Monkey-patch Treesitter to handle query errors gracefully
    local ts_query = vim.treesitter.query
    if type(ts_query) == "table" and type(ts_query.get) == "function" then
      local original_get = ts_query.get
      ts_query.get = function(lang, type_name)
        local ok, query = pcall(original_get, lang, type_name)
        if not ok then
          -- Log the error but don't crash
          vim.notify_once("Treesitter query error for " .. lang .. "/" .. type_name .. ": " .. tostring(query), vim.log.levels.WARN)
          return nil
        end
        return query
      end
    end

    -- Treesitter context for showing current context in winbar
    require("treesitter-context").setup({
      enable = true,
      max_lines = 3,
      min_window_height = 0,
      line_timeout = 200,
      trim_scope = "outer",
      patterns = {
        default = {
          "class",
          "function",
          "method",
          "for",
          "while",
          "if",
          "switch",
          "case",
        },
        markdown = {
          "section",
          "atx_heading",
          "list_item",
        },
      },
      exact_patterns = {},
      zindex = 20,
      mode = "cursor",
    })

    -- Enable markdown injection for better syntax highlighting
    vim.treesitter.language.register("markdown", "md")
    vim.treesitter.language.register("markdown_inline", "md")
    -- Chat files use markdown but skip treesitter for performance
    -- vim.treesitter.language.register("markdown", "chat")
    -- vim.treesitter.language.register("markdown_inline", "chat")

    local group = vim.api.nvim_create_augroup('TreesitterFolds', { clear = true })

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = supported_filetypes,
      callback = function()
        -- Safely start Treesitter with error handling
        local ok, err = pcall(vim.treesitter.start)
        if not ok then
          vim.notify("Treesitter start error: " .. tostring(err), vim.log.levels.DEBUG)
          -- Don't set up folding if Treesitter failed
          return
        end

        vim.schedule(function()
          -- Only set up folding if Treesitter is actually working and buffer is in a window
          local has_ts_lang, ts_lang = pcall(vim.treesitter.language.get_lang, vim.bo.filetype)
          if has_ts_lang and ts_lang then
            -- Check if the current buffer is displayed in any window
            local bufnr = vim.api.nvim_get_current_buf()
            local has_window = false
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_get_buf(win) == bufnr then
                has_window = true
                break
              end
            end
            
            -- Only set window-local options if buffer is displayed in a window
            if has_window then
              vim.wo.foldmethod = 'expr'
              vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
              vim.wo.foldlevel = 99
              vim.wo.foldenable = true
            end
          end
        end)
      end,
    })
  end,
}