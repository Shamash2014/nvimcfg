local plugins = {
  -- Modern completion engine with AI support
  {
    "saghen/blink.cmp",
    event = "InsertEnter", -- Load only when entering insert mode
    dependencies = {
      "rafamadriz/friendly-snippets",
      "saghen/blink.compat",
      -- AI completion sources
      {
        "zbirenbaum/copilot.lua",
        event = "InsertEnter",
        cmd = "Copilot",
        config = function()
          require("copilot").setup({
            suggestion = { enabled = false },
            panel = { enabled = false },
          })
        end,
      },
      {
        "giuxtaposition/blink-cmp-copilot",
      },
      {
        "supermaven-inc/supermaven-nvim",
        event = "InsertEnter",
        cmd = {
          "SupermavenUseFree",
          "SupermavenUsePro", 
          "SupermavenLogout",
          "SupermavenRestart",
          "SupermavenStatus"
        },
        opts = {
          disable_inline_completion = true,
          disable_keymaps = true,
        },
      },
      {
        "tzachar/cmp-tabnine",
        build = "./install.sh",
      },
    },
    version = "*",
    opts = {
      keymap = {
        preset = "default",
        ["<C-k>"] = { "select_prev", "fallback" },
        ["<C-j>"] = { "select_next", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
      },
      completion = {
        ghost_text = { enabled = true },
        menu = {
          draw = {
            components = {
              kind_icon = {
                ellipsis = false,
                text = function(ctx)
                  return ctx.kind_icon .. ctx.icon_gap
                end,
              }
            }
          }
        }
      },
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = "mono"
      },
      sources = {
        default = { "lsp", "path", "snippets", "buffer", "copilot", "supermaven", "cmp_tabnine" },
        providers = {
          copilot = {
            name = "copilot",
            module = "blink-cmp-copilot",
          },
          supermaven = {
            name = "supermaven",
            module = "blink.compat.source",
          },
          cmp_tabnine = {
            name = "cmp_tabnine",
            module = "blink.compat.source",
          },
        },
      },
    },
    opts_extend = { "sources.default" }
  },

  -- Key binding helper with Helix-style popup
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix", -- Use helix preset for similar look
      delay = 500, -- Delay before showing which-key
      expand = 1, -- expand groups when <= n mappings
      notify = false,
      triggers = {
        { "<auto>", mode = "nixsotc" },
        { "<leader>", mode = { "n", "v" } },
      },
      spec = {
        -- Define groups with Helix-style naming
        { "<leader>f", group = "file", mode = { "n", "v" } },
        { "<leader>b", group = "buffer", mode = { "n", "v" } },
        { "<leader>c", group = "code", mode = { "n", "v" } },
        { "<leader>g", group = "git", mode = { "n", "v" } },
        { "<leader>s", group = "search", mode = { "n", "v" } },
        { "<leader>w", group = "window", mode = { "n", "v" } },
        { "<leader>t", group = "toggle", mode = { "n", "v" } },
        { "<leader>o", group = "open", mode = { "n", "v" } },
        { "<leader>d", group = "debug", mode = { "n", "v" } },
        { "<leader>m", group = "mcp", mode = { "n", "v" } },
        { "<leader>a", group = "ai", mode = { "n", "v" } },
        { "<leader>i", group = "import", mode = { "n", "v" } },
        { "<leader>oj", group = "jupyter", mode = { "n", "v" } },
        { "<leader>fw", group = "workspace", mode = { "n", "v" } },
        { "g", group = "goto", mode = { "n", "v" } },
        { "z", group = "fold", mode = { "n", "v" } },
        { "]", group = "next", mode = { "n", "v" } },
        { "[", group = "prev", mode = { "n", "v" } },
        { "<c-w>", group = "window", mode = "n" },
      },
      win = {
        -- Helix-style window configuration
        border = "single",
        padding = { 1, 2 }, -- extra window padding [top/bottom, left/right]
        wo = {
          winblend = 0, -- value between 0-100 for transparency
        },
      },
      layout = {
        width = { min = 20 }, -- min and max width of columns
        spacing = 3, -- spacing between columns
        align = "left", -- align columns left, center or right
      },
      keys = {
        scroll_down = "<c-d>", -- binding to scroll down inside the popup
        scroll_up = "<c-u>", -- binding to scroll up inside the popup
      },
      sort = { "local", "order", "group", "alphanum", "mod" },
      expand = 0, -- expand groups when <= n mappings
      -- Custom icons to match Helix style
      icons = {
        breadcrumb = "»", -- symbol used in the command line area that shows your active key combo
        separator = "➜", -- symbol used between a key and it's label
        group = "+", -- symbol prepended to a group
        ellipsis = "…",
        -- Custom mappings for common keys
        rules = false,
        colors = true,
        keys = {
          Up = " ",
          Down = " ",
          Left = " ",
          Right = " ",
          C = "󰘴 ",
          M = "󰘵 ",
          D = "󰘳 ",
          S = "󰘶 ",
          CR = "󰌑 ",
          Esc = "󱊷 ",
          ScrollWheelDown = "󱕐 ",
          ScrollWheelUp = "󱕑 ",
          NL = "󰌑 ",
          BS = "⌫",
          Space = "󱁐 ",
          Tab = "󰌒 ",
          F1 = "󱊫",
          F2 = "󱊬",
          F3 = "󱊭",
          F4 = "󱊮",
          F5 = "󱊯",
          F6 = "󱊰",
          F7 = "󱊱",
          F8 = "󱊲",
          F9 = "󱊳",
          F10 = "󱊴",
          F11 = "󱊵",
          F12 = "󱊶",
        },
      },
    },
    config = function(_, opts)
      local wk = require("which-key")
      wk.setup(opts)
      
      -- Add custom Helix-style theme colors
      vim.api.nvim_set_hl(0, "WhichKey", { fg = "#ffffff", bold = true })
      vim.api.nvim_set_hl(0, "WhichKeyGroup", { fg = "#bb9af7" })
      vim.api.nvim_set_hl(0, "WhichKeyDesc", { fg = "#666666" })
      vim.api.nvim_set_hl(0, "WhichKeySeperator", { fg = "#444444" })
      vim.api.nvim_set_hl(0, "WhichKeyFloat", { bg = "#111111" })
      vim.api.nvim_set_hl(0, "WhichKeyBorder", { fg = "#333333" })
    end,
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Local Keymaps",
      },
      {
        "<c-h>",
        function()
          require("which-key").show({ keys = "<c-w>", loop = true })
        end,
        desc = "Window Hydra Mode (which-key)",
      },
    },
  },

  -- Syntax highlighting with comprehensive text objects
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" }, -- Load only when reading/creating files
    build = ":TSUpdate",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
      "nvim-treesitter/nvim-treesitter-context",
    },
    config = function()
      local configs = require("nvim-treesitter.configs")
      configs.setup({
        ensure_installed = {
          "c", "lua", "vim", "vimdoc", "query", "javascript", "typescript",
          "html", "css", "scss", "python", "bash", "json", "yaml", "markdown",
          "r", "julia", "latex", "astro", "go", "gomod", "gowork", "gosum",
          "dockerfile", "toml", "xml", "rust", "elixir", "dart"
        },
        sync_install = false,
        highlight = { enable = true },
        indent = { enable = true },
        
        -- Enhanced text objects (Helix/Doom Emacs style)
        textobjects = {
          select = {
            enable = true,
            lookahead = true, -- Automatically jump forward to textobj, similar to targets.vim
            keymaps = {
              -- Functions
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["aC"] = "@class.outer",
              ["iC"] = "@class.inner",
              ["ac"] = "@call.outer",
              ["ic"] = "@call.inner",
              
              -- Loops and conditionals
              ["al"] = "@loop.outer",
              ["il"] = "@loop.inner",
              ["aa"] = "@conditional.outer",
              ["ia"] = "@conditional.inner",
              
              -- Blocks and statements
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",
              ["as"] = "@statement.outer",
              ["is"] = "@statement.inner",
              
              -- Parameters and arguments
              ["ap"] = "@parameter.outer",
              ["ip"] = "@parameter.inner",
              
              -- Comments
              ["ag"] = "@comment.outer",
              ["ig"] = "@comment.inner",
              
              -- Assignments
              ["a="] = "@assignment.outer",
              ["i="] = "@assignment.inner",
              ["l="] = "@assignment.lhs",
              ["r="] = "@assignment.rhs",
              
              -- Return statements
              ["ar"] = "@return.outer",
              ["ir"] = "@return.inner",
              
              -- Numbers
              ["an"] = "@number.inner",
              ["in"] = "@number.inner",
              
              -- Regex
              ["a/"] = "@regex.outer",
              ["i/"] = "@regex.inner",
              
              -- Strings and characters
              ["a'"] = "@string.outer",
              ["i'"] = "@string.inner",
              ["a\""] = "@string.outer",
              ["i\""] = "@string.inner",
              
              -- Type definitions and annotations
              ["at"] = "@type.outer",
              ["it"] = "@type.inner",
              
              -- Imports/includes
              ["ai"] = "@import.outer",
              ["ii"] = "@import.inner",
              
              -- Attributes (decorators, annotations)
              ["aA"] = "@attribute.outer",
              ["iA"] = "@attribute.inner",
              
              -- Scope (for languages that have explicit scope)
              ["aS"] = "@scope.outer",
              ["iS"] = "@scope.inner",
              
              -- Frame (for stack-based languages)
              ["aF"] = "@frame.outer",
              ["iF"] = "@frame.inner",
            },
            selection_modes = {
              ['@parameter.outer'] = 'v', -- charwise
              ['@function.outer'] = 'V', -- linewise
              ['@class.outer'] = '<c-v>', -- blockwise
            },
            include_surrounding_whitespace = false,
          },
          
          -- Smart movement between text objects
          move = {
            enable = true,
            set_jumps = true, -- whether to set jumps in the jumplist
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]a"] = "@parameter.inner",
              ["]o"] = "@loop.outer",
              ["]s"] = "@statement.outer",
              ["]z"] = "@fold",
              ["]g"] = "@comment.outer",
              ["]t"] = "@type.outer",
              ["]i"] = "@import.outer",
              ["]A"] = "@attribute.outer",
              ["]b"] = "@block.outer",
              ["]r"] = "@return.outer",
              ["]l"] = "@call.outer",
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
              ["]A"] = "@parameter.inner",
              ["]O"] = "@loop.outer",
              ["]S"] = "@statement.outer",
              ["]Z"] = "@fold",
              ["]G"] = "@comment.outer",
              ["]T"] = "@type.outer",
              ["]I"] = "@import.outer",
              ["]A"] = "@attribute.outer",
              ["]B"] = "@block.outer",
              ["]R"] = "@return.outer",
              ["]L"] = "@call.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[a"] = "@parameter.inner",
              ["[o"] = "@loop.outer",
              ["[s"] = "@statement.outer",
              ["[z"] = "@fold",
              ["[g"] = "@comment.outer",
              ["[t"] = "@type.outer",
              ["[i"] = "@import.outer",
              ["[A"] = "@attribute.outer",
              ["[b"] = "@block.outer",
              ["[r"] = "@return.outer",
              ["[l"] = "@call.outer",
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
              ["[A"] = "@parameter.inner",
              ["[O"] = "@loop.outer",
              ["[S"] = "@statement.outer",
              ["[Z"] = "@fold",
              ["[G"] = "@comment.outer",
              ["[T"] = "@type.outer",
              ["[I"] = "@import.outer",
              ["[A"] = "@attribute.outer",
              ["[B"] = "@block.outer",
              ["[R"] = "@return.outer",
              ["[L"] = "@call.outer",
            },
          },
          
          -- Swap text objects (useful for refactoring)
          swap = {
            enable = true,
            swap_next = {
              ["<leader>xp"] = "@parameter.inner",
              ["<leader>xf"] = "@function.outer",
              ["<leader>xa"] = "@attribute.outer",
            },
            swap_previous = {
              ["<leader>xP"] = "@parameter.inner",
              ["<leader>xF"] = "@function.outer",
              ["<leader>xA"] = "@attribute.outer",
            },
          },
          
          -- LSP interop for precise text objects
          lsp_interop = {
            enable = true,
            border = 'single',
            floating_preview_opts = {},
            peek_definition_code = {
              ["<leader>df"] = "@function.outer",
              ["<leader>dF"] = "@class.outer",
            },
          },
        },
        
        -- Show context of current function/class (like breadcrumbs)
        context = {
          enable = true,
          max_lines = 3,
          min_window_height = 0,
          line_numbers = true,
          multiline_threshold = 1,
          trim_scope = 'outer',
          mode = 'cursor',
          separator = nil,
          zindex = 20,
          on_attach = function()
            return vim.bo.filetype ~= 'help'
          end,
        },
      })
      
      -- Enhanced which-key integration for text objects
      local wk = require("which-key")
      wk.add({
        mode = { "o", "x" },
        { "a", group = "around" },
        { "i", group = "inside" },
        { "af", desc = "around function" },
        { "if", desc = "inside function" },
        { "aC", desc = "around class" },
        { "iC", desc = "inside class" },
        { "ac", desc = "around call" },
        { "ic", desc = "inside call" },
        { "al", desc = "around loop" },
        { "il", desc = "inside loop" },
        { "aa", desc = "around conditional" },
        { "ia", desc = "inside conditional" },
        { "ab", desc = "around block" },
        { "ib", desc = "inside block" },
        { "ap", desc = "around parameter" },
        { "ip", desc = "inside parameter" },
        { "ag", desc = "around comment" },
        { "ig", desc = "inside comment" },
        { "a=", desc = "around assignment" },
        { "i=", desc = "inside assignment" },
        { "ar", desc = "around return" },
        { "ir", desc = "inside return" },
        { "at", desc = "around type" },
        { "it", desc = "inside type" },
        { "ai", desc = "around import" },
        { "ii", desc = "inside import" },
        { "aA", desc = "around attribute" },
        { "iA", desc = "inside attribute" },
      })
      
      -- Movement descriptions
      wk.add({
        { "]", group = "next" },
        { "[", group = "previous" },
        { "]f", desc = "next function start" },
        { "]F", desc = "next function end" },
        { "[f", desc = "prev function start" },
        { "[F", desc = "prev function end" },
        { "]c", desc = "next class start" },
        { "]C", desc = "next class end" },
        { "[c", desc = "prev class start" },
        { "[C", desc = "prev class end" },
        { "]b", desc = "next block start" },
        { "]B", desc = "next block end" },
        { "[b", desc = "prev block start" },
        { "[B", desc = "prev block end" },
        { "]g", desc = "next comment" },
        { "[g", desc = "prev comment" },
        { "]l", desc = "next call" },
        { "[l", desc = "prev call" },
        { "]s", desc = "next statement" },
        { "[s", desc = "prev statement" },
        { "]r", desc = "next return" },
        { "[r", desc = "prev return" },
        { "]t", desc = "next type" },
        { "[t", desc = "prev type" },
        { "]i", desc = "next import" },
        { "[i", desc = "prev import" },
      })
      
      -- Exchange/swap descriptions
      wk.add({
        { "<leader>x", group = "exchange" },
        { "<leader>xp", desc = "swap next parameter" },
        { "<leader>xP", desc = "swap prev parameter" },
        { "<leader>xf", desc = "swap next function" },
        { "<leader>xF", desc = "swap prev function" },
        { "<leader>xa", desc = "swap next attribute" },
        { "<leader>xA", desc = "swap prev attribute" },
      })
      
      -- Custom text object commands
      vim.api.nvim_create_user_command("TSTextobjects", function()
        print("Available text objects:")
        print("Functions: af/if (around/inside function)")
        print("Classes: aC/iC (around/inside class)")
        print("Calls: ac/ic (around/inside call)")
        print("Loops: al/il (around/inside loop)")
        print("Conditionals: aa/ia (around/inside conditional)")
        print("Blocks: ab/ib (around/inside block)")
        print("Parameters: ap/ip (around/inside parameter)")
        print("Comments: ag/ig (around/inside comment)")
        print("Assignments: a=/i= (around/inside assignment)")
        print("Returns: ar/ir (around/inside return)")
        print("Types: at/it (around/inside type)")
        print("Imports: ai/ii (around/inside import)")
        print("Attributes: aA/iA (around/inside attribute)")
        print("")
        print("Movement: ]f/[f (next/prev function), ]c/[c (class), etc.")
        print("Swap: <leader>xp (parameters), <leader>xf (functions)")
      end, { desc = "Show available treesitter text objects" })
    end
  },

  -- File explorer (replaces netrw)
  {
    "stevearc/oil.nvim",
    cmd = "Oil",
    init = function()
      -- Only set up directory handling when actually needed
      if vim.fn.isdirectory(vim.fn.expand("%")) == 1 then
        require("oil")
      end
    end,
    keys = {
      { "-", "<CMD>Oil<CR>", desc = "Open parent directory" }
    },
    opts = {
      default_file_explorer = true,
      view_options = {
        show_hidden = false,
      },
    },
    dependencies = { "echasnovski/mini.icons" },
  },

  -- Git interface (Magit-like for Neovim)
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    cmd = { "Neogit" },
    config = function()
      -- Git operation helper that uses current file's git repository
      local function safe_git_operation(operation, options)
        local git_root = nil
        
        -- Get current file's directory first
        local current_file = vim.fn.expand('%:p')
        local file_dir = current_file and current_file ~= '' and vim.fn.fnamemodify(current_file, ':h') or vim.fn.getcwd()
        
        -- Try to find git root from current file's location
        local cmd = string.format("cd %s && git rev-parse --show-toplevel 2>/dev/null", vim.fn.shellescape(file_dir))
        git_root = vim.fn.system(cmd):gsub("\n", "")
        
        if vim.v.shell_error == 0 and git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
          -- We found the git root for current file, change to it
          local current_cwd = vim.fn.getcwd()
          if git_root ~= current_cwd then
            vim.cmd("cd " .. vim.fn.fnameescape(git_root))
          end
        end
        
        -- Open Neogit regardless of whether we found git root or not
        if operation then
          require("neogit").open({ operation }, options or {})
        else
          require("neogit").open(options or { kind = "vsplit" })
        end
      end
      
      -- Store globally for use in keymaps
      _G.NeogitSafeGitOp = safe_git_operation
    end,
    keys = {
      { 
        "<leader>gg", 
        function() 
          _G.NeogitSafeGitOp(nil, { kind = "vsplit" })
        end, 
        desc = "Neogit" 
      },
      { 
        "<leader>gc", 
        function()
          _G.NeogitSafeGitOp("commit")
        end, 
        desc = "Git commit" 
      },
      { 
        "<leader>gp", 
        function()
          _G.NeogitSafeGitOp("push")
        end, 
        desc = "Git push" 
      },
      { 
        "<leader>gl", 
        function()
          _G.NeogitSafeGitOp("pull")
        end, 
        desc = "Git pull" 
      },
    },
    opts = {
      integrations = {
        diffview = true,
      },
    },
  },

  -- Modern Git Blame with virtual lines (Zed-style)
  {
    "f-person/git-blame.nvim",
    event = "VeryLazy", -- Load even later for better startup
    opts = {
      enabled = false, -- Start disabled, toggle when needed
      message_template = "  <author>, <date> - <summary>",
      date_format = "%Y-%m-%d",
      virtual_text_column = nil,
      highlight_group = "GitBlame",
      delay = 200, -- Faster delay like Zed
      message_when_not_committed = "  Not committed yet",
      ignore_whitespace = true, -- Better performance
      use_blame_commit_file_urls = false,
      max_file_size = 100000, -- Don't blame huge files
    },
    config = function(_, opts)
      -- Custom highlight to match theme (subtle)
      vim.api.nvim_set_hl(0, "GitBlame", { fg = "#555555", italic = true })
      
      require("gitblame").setup(opts)
      
      -- Auto-disable for large files (Zed-like behavior)
      vim.api.nvim_create_autocmd("BufReadPost", {
        group = vim.api.nvim_create_augroup("GitBlamePerf", { clear = true }),
        callback = function()
          local file_size = vim.fn.getfsize(vim.fn.expand("%"))
          if file_size > 100000 then -- 100KB limit
            vim.cmd("GitBlameDisable")
          end
        end,
      })
    end,
    keys = {
      { "<leader>gb", "<cmd>GitBlameToggle<cr>", desc = "Toggle git blame" },
      { "<leader>gB", "<cmd>GitBlameOpenCommitURL<cr>", desc = "Open commit URL" },
      { "<leader>gc", "<cmd>GitBlameCopySHA<cr>", desc = "Copy SHA" },
      { "<leader>gC", "<cmd>GitBlameCopyCommitURL<cr>", desc = "Copy commit URL" },
    },
  },

  -- Git signs for hunks and basic git info
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add          = { text = '┃' },
        change       = { text = '┃' },
        delete       = { text = '_' },
        topdelete    = { text = '‾' },
        changedelete = { text = '~' },
        untracked    = { text = '┆' },
      },
      signs_staged = {
        add          = { text = '┃' },
        change       = { text = '┃' },
        delete       = { text = '_' },
        topdelete    = { text = '‾' },
        changedelete = { text = '~' },
        untracked    = { text = '┆' },
      },
      signs_staged_enable = true,
      signcolumn = true,
      current_line_blame = false, -- We use blame.nvim for this
      attach_to_untracked = false,
      update_debounce = 100,
      max_file_length = 40000,
      preview_config = {
        border = 'single',
        style = 'minimal',
        relative = 'cursor',
        row = 0,
        col = 1
      },
    },
    keys = {
      { "]h", function() require("gitsigns").next_hunk() end, desc = "Next git hunk" },
      { "[h", function() require("gitsigns").prev_hunk() end, desc = "Previous git hunk" },
      { "<leader>ghs", function() require("gitsigns").stage_hunk() end, desc = "Stage hunk" },
      { "<leader>ghr", function() require("gitsigns").reset_hunk() end, desc = "Reset hunk" },
      { "<leader>ghS", function() require("gitsigns").stage_buffer() end, desc = "Stage buffer" },
      { "<leader>ghu", function() require("gitsigns").undo_stage_hunk() end, desc = "Undo stage hunk" },
      { "<leader>ghR", function() require("gitsigns").reset_buffer() end, desc = "Reset buffer" },
      { "<leader>ghp", function() require("gitsigns").preview_hunk() end, desc = "Preview hunk" },
      { "<leader>ghd", function() require("gitsigns").diffthis() end, desc = "Diff this" },
      { "<leader>gtd", function() require("gitsigns").toggle_deleted() end, desc = "Toggle deleted" },
      -- Visual mode hunk operations
      { "<leader>ghs", function() require("gitsigns").stage_hunk({vim.fn.line("."), vim.fn.line("v")}) end, mode = "v", desc = "Stage hunk" },
      { "<leader>ghr", function() require("gitsigns").reset_hunk({vim.fn.line("."), vim.fn.line("v")}) end, mode = "v", desc = "Reset hunk" },
      -- Text objects
      { "ih", ":<C-U>Gitsigns select_hunk<CR>", mode = {"o", "x"}, desc = "Select git hunk" },
    },
  },

  -- Git conflict resolution
  {
    "akinsho/git-conflict.nvim",
    event = "BufReadPost", -- only load when reading files
    opts = {
      default_mappings = true,
      default_commands = true,
      disable_diagnostics = false,
      list_opener = 'copen',
      highlights = {
        incoming = 'DiffAdd',
        current = 'DiffText',
      }
    },
  },

  -- Git diff viewer with inline diffing
  {
    "sindrets/diffview.nvim",
    cmd = { 
      "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", 
      "DiffviewFileHistory", "DiffviewRefresh"
    },
    config = function()
      require("diffview").setup({
        enhanced_diff_hl = true,
        view = {
          default = { 
            layout = "diff2_horizontal",
            winbar_info = true,
          },
          file_history = { 
            layout = "diff2_horizontal",
            winbar_info = true,
          },
          merge_tool = { 
            layout = "diff3_horizontal",
            winbar_info = true,
          },
        },
        file_panel = {
          listing_style = "tree",
          tree_options = {
            flatten_dirs = true,
            folder_statuses = "only_folded",
          },
          win_config = {
            position = "left",
            width = 35,
          },
        },
        file_history_panel = {
          log_options = {
            git = {
              single_file = {
                diff_merges = "combined",
              },
              multi_file = {
                diff_merges = "first-parent",
              },
            },
          },
        },
        commit_log_panel = {
          win_config = {
            win_opts = {},
          },
        },
        default_args = {
          DiffviewOpen = {},
          DiffviewFileHistory = {},
        },
        hooks = {},
        keymaps = {
          disable_defaults = false,
          view = {
            -- Inline diff toggles
            ["<leader>di"] = function()
              vim.cmd("set diffopt+=iwhite")
              vim.cmd("diffupdate")
              vim.notify("Inline diff: ignore whitespace enabled", vim.log.levels.INFO)
            end,
            ["<leader>dI"] = function()
              vim.cmd("set diffopt-=iwhite")
              vim.cmd("diffupdate")
              vim.notify("Inline diff: ignore whitespace disabled", vim.log.levels.INFO)
            end,
            ["<leader>dw"] = function()
              if vim.wo.wrap then
                vim.wo.wrap = false
                vim.notify("Inline diff: word wrap disabled", vim.log.levels.INFO)
              else
                vim.wo.wrap = true
                vim.notify("Inline diff: word wrap enabled", vim.log.levels.INFO)
              end
            end,
          },
          file_panel = {},
          file_history_panel = {},
          option_panel = {},
        },
      })
    end,
    keys = {
      -- Basic diff operations
      { "<leader>gdd", "<cmd>DiffviewOpen<cr>", desc = "Open diff view" },
      { "<leader>gdc", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
      { "<leader>gdf", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>gdh", "<cmd>DiffviewFileHistory<cr>", desc = "Project history" },
      { "<leader>gdr", "<cmd>DiffviewRefresh<cr>", desc = "Refresh diff view" },
      
      -- Inline diff toggle command
      {
        "<leader>gdi",
        function()
          -- Toggle inline diff for current file against HEAD in bottom split
          if vim.wo.diff then
            -- Turn off diff mode and close any diff windows
            vim.cmd("diffoff!")
            local wins = vim.api.nvim_list_wins()
            for _, win in ipairs(wins) do
              local buf = vim.api.nvim_win_get_buf(win)
              local buf_name = vim.api.nvim_buf_get_name(buf)
              if buf_name:match("%(HEAD%)") or buf_name:match("%(staged%)") then
                vim.api.nvim_win_close(win, true)
              end
            end
          else
            -- Show native diff for current file against HEAD in bottom split
            local file = vim.fn.expand("%:p")
            local filename = vim.fn.expand("%:t")
            if file ~= "" then
              -- Get HEAD version of file
              local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
              if vim.v.shell_error == 0 then
                local relative_path = vim.fn.fnamemodify(file, ":~:.")
                local head_content = vim.fn.system("git show HEAD:" .. vim.fn.shellescape(relative_path) .. " 2>/dev/null")
                
                if vim.v.shell_error == 0 then
                  -- Create bottom split
                  vim.cmd("botright split")
                  vim.cmd("resize 15")
                  
                  -- Create temporary buffer with HEAD content
                  local bufnr = vim.api.nvim_create_buf(false, true)
                  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(head_content, "\n"))
                  vim.api.nvim_buf_set_name(bufnr, filename .. " (HEAD)")
                  vim.api.nvim_win_set_buf(0, bufnr)
                  
                  -- Set filetype to match original
                  local ft = vim.bo[vim.fn.bufnr(file)].filetype
                  vim.bo[bufnr].filetype = ft
                  vim.bo[bufnr].readonly = true
                  
                  -- Enable diff mode
                  vim.cmd("diffthis")
                  vim.cmd("wincmd k")
                  vim.cmd("diffthis")
                else
                  vim.notify("Could not get HEAD version of file", vim.log.levels.WARN)
                end
              else
                vim.notify("Not in a git repository", vim.log.levels.WARN)
              end
            else
              vim.notify("No file to diff", vim.log.levels.WARN)
            end
          end
        end,
        desc = "Toggle inline diff vs HEAD"
      },
    },
  },

  -- Collection of small QoL plugins
  {
    "folke/snacks.nvim",
    priority = 1000, -- high priority for core functionality
    event = "UIEnter", -- Load when UI is ready
    opts = {
      bigfile = { enabled = true },
      pickers = { 
        enabled = true,
        sources = {
          grep = {
            cmd = "rg",
            args = {
              "--color=never",
              "--no-heading",
              "--with-filename",
              "--line-number",
              "--column",
              "--smart-case",
              "--hidden",
              "--follow",
              "--glob=!.git/*",
              "--glob=!node_modules/*",
              "--glob=!target/*",
              "--glob=!dist/*",
              "--glob=!build/*",
            },
          },
        },
      },
      dashboard = { enabled = false },
      indent = { enabled = true },
      input = { enabled = true },
      notifier = { enabled = false },
      quickfile = { enabled = true },
      scroll = { enabled = true },
      statuscolumn = { enabled = true },
      words = { enabled = true },
      zen = { enabled = true },
    },
    init = function()
      -- Use snacks for LSP hover
      vim.lsp.handlers["textDocument/hover"] = function(_, result, ctx, config)
        config = config or {}
        config.border = "single"
        config.max_width = 80
        config.max_height = 20
        if result and result.contents then
          local markdown_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
          if vim.tbl_isempty(markdown_lines) then
            return
          end
          return require("snacks").docs.show(markdown_lines, {
            ft = "markdown",
            border = "single",
            title = "LSP Hover",
          })
        end
      end
    end,
    keys = {
      -- File operations
      { "<leader>ff", function() Snacks.picker.files({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Find files" },
      { "<leader>fr", function() Snacks.picker.recent({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Recent files" },
      { "<leader>bb", function() Snacks.picker.buffers({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Switch buffers" },
      { "<leader>bm", function() Snacks.picker.marks({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Buffer marks" },
      
      -- Search operations
      { "<leader>sg", function() Snacks.picker.grep({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Live grep" },
      { "<leader>s*", function() Snacks.picker.grep_word({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Grep word under cursor" },
      { "<leader>sa", function() 
          vim.ui.input({ prompt = "AST-grep pattern: " }, function(pattern)
            if pattern and pattern ~= "" then
              -- Check if ast-grep is available
              if vim.fn.executable("ast-grep") == 0 then
                vim.notify("ast-grep not found. Please install it first.", vim.log.levels.ERROR)
                return
              end
              
              Snacks.picker.pick({
                items = function()
                  -- Build the ast-grep command with proper format
                  local cmd = string.format("ast-grep run --pattern '%s' .", pattern)
                  local result = vim.fn.system(cmd .. " 2>/dev/null")
                  
                  if vim.v.shell_error ~= 0 then
                    vim.notify("AST-grep search failed. Pattern: " .. pattern, vim.log.levels.WARN)
                    return {}
                  end
                  
                  local items = {}
                  for line in result:gmatch("[^\r\n]+") do
                    -- ast-grep output format: filename:line:column:matched_text
                    local file, lnum, col, text = line:match("^([^:]+):(%d+):(%d+):(.*)")
                    if file and lnum and text then
                      table.insert(items, {
                        file = file,
                        line = tonumber(lnum),
                        col = tonumber(col) or 1,
                        text = text:gsub("^%s+", ""),
                        display = string.format("%s:%s: %s", file, lnum, text:gsub("^%s+", "")),
                      })
                    end
                  end
                  
                  if #items == 0 then
                    vim.notify("No matches found for pattern: " .. pattern, vim.log.levels.INFO)
                  end
                  
                  return items
                end,
                format = function(item)
                  return item.display
                end,
                confirm = function(item)
                  vim.cmd("edit " .. vim.fn.fnameescape(item.file))
                  vim.api.nvim_win_set_cursor(0, { item.line, item.col - 1 })
                end,
                layout = { preset = "vscode", preview = "main" },
                title = "AST-grep: " .. pattern,
              })
            end
          end)
        end, desc = "AST-grep search" },
      { "<leader><leader>", function() Snacks.picker.smart({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Smart picker" },
      
      -- Code operations  
      { "<leader>cd", function() Snacks.picker.diagnostics({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Diagnostics" },
      { "<leader>cs", function() Snacks.picker.lsp_symbols({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Document symbols" },
      { "<leader>cw", function() Snacks.picker.lsp_workspace_symbols({ layout = { preset = "vscode", preview = "main" } }) end, desc = "Workspace symbols" },
      { "<leader>ct", function() Snacks.terminal.toggle() end, desc = "Terminal" },
      
      -- Toggle operations
      { "<leader>td", function() Snacks.dim() end, desc = "Toggle dim" },
      { "<leader>tz", function() Snacks.zen() end, desc = "Toggle Zen Mode" },
    },
  },

  -- Minimal statusline with LSP and lint info
  {
    "nvim-lualine/lualine.nvim",
    event = "UIEnter",
    dependencies = { "echasnovski/mini.icons" },
    opts = {
      options = {
        theme = {
          normal = {
            a = { bg = "#444444", fg = "#ffffff", gui = "bold" },
            b = { bg = "#333333", fg = "#ffffff" },
            c = { bg = "#222222", fg = "#aaaaaa" },
          },
          insert = {
            a = { bg = "#bb9af7", fg = "#000000", gui = "bold" },
            b = { bg = "#333333", fg = "#ffffff" },
            c = { bg = "#222222", fg = "#aaaaaa" },
          },
          visual = {
            a = { bg = "#bb9af7", fg = "#000000", gui = "bold" },
            b = { bg = "#333333", fg = "#ffffff" },
            c = { bg = "#222222", fg = "#aaaaaa" },
          },
          command = {
            a = { bg = "#bb9af7", fg = "#000000", gui = "bold" },
            b = { bg = "#333333", fg = "#ffffff" },
            c = { bg = "#222222", fg = "#aaaaaa" },
          },
        },
        component_separators = "",
        section_separators = "",
        globalstatus = true,
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = {
          "branch",
          {
            "diff",
            colored = false,
            symbols = { added = "+", modified = "~", removed = "-" },
          },
        },
        lualine_c = {
          {
            "filename",
            path = 1,
            color = { fg = "#ffffff" },
          },
          {
            "diagnostics",
            sources = { "nvim_lsp" },
            sections = { "error", "warn", "info", "hint" },
            symbols = { error = "E:", warn = "W:", info = "I:", hint = "H:" },
            colored = false,
            update_in_insert = false,
            always_visible = false,
          },
        },
        lualine_x = {
          {
            function()
              -- Safely get LSP clients
              local ok, clients = pcall(vim.lsp.get_clients, { bufnr = 0 })
              if not ok or not clients then
                return ""
              end
              
              local client_names = {}
              for _, client in pairs(clients) do
                if client.name then
                  table.insert(client_names, client.name)
                end
              end
              
              if #client_names > 0 then
                return "LSP:" .. table.concat(client_names, ",")
              end
              return ""
            end,
            color = { fg = "#666666" },
            cond = function()
              -- Only show if LSP is available and attached
              local ok, clients = pcall(vim.lsp.get_clients, { bufnr = 0 })
              return ok and clients and #clients > 0
            end,
          },
          {
            function()
              -- Safely check for nvim-lint
              local ok, lint = pcall(require, "lint")
              if not ok then
                return ""
              end
              
              local linters = lint.linters_by_ft[vim.bo.filetype] or {}
              if #linters > 0 then
                return "Lint:" .. table.concat(linters, ",")
              end
              return ""
            end,
            color = { fg = "#666666" },
            cond = function()
              -- Only show if nvim-lint is available
              return pcall(require, "lint")
            end,
          },
        },
        lualine_y = { "filetype" },
        lualine_z = { "location" },
      },
      inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { "filename" },
        lualine_x = { "location" },
        lualine_y = {},
        lualine_z = {},
      },
    },
  },

  -- Leap motion (Doom Emacs style)
  {
    "ggandor/leap.nvim",
    keys = { "s", "S", { "s", mode = { "x", "o" } }, { "S", mode = { "x", "o" } } },
    dependencies = {
      {
        "ggandor/flit.nvim",
        keys = { "f", "F", "t", "T" },
        opts = {},
      }
    },
    config = function()
      local leap = require('leap')
      leap.opts.equivalence_classes = { ' \t\r\n', '([{', ')]}', '\'"`' }
      
      -- Set keymaps
      vim.keymap.set('n', 's', '<Plug>(leap)')
      vim.keymap.set('n', 'S', '<Plug>(leap-from-window)')
      vim.keymap.set({ 'x', 'o' }, 's', '<Plug>(leap-forward)')
      vim.keymap.set({ 'x', 'o' }, 'S', '<Plug>(leap-backward)')
      vim.keymap.set({ 'n', 'x', 'o' }, 'ga', function()
        require('leap.treesitter').select()
      end)
      vim.keymap.set({ 'n', 'o' }, 'gs', function()
        require('leap.remote').action()
      end)
    end
  },

  -- Text object surround
  {
    "kylechui/nvim-surround",
    version = "*",
    keys = {
      { "ys", mode = "n" },
      { "ds", mode = "n" },
      { "cs", mode = "n" },
      { "S", mode = "x" },
    },
    opts = {},
  },

  -- Enhanced word motions
  {
    "chrisgrieser/nvim-spider",
    keys = {
      { "w", function() require('spider').motion('w') end, mode = { "n", "o", "x" }, desc = "Spider w" },
      { "e", function() require('spider').motion('e') end, mode = { "n", "o", "x" }, desc = "Spider e" },
      { "b", function() require('spider').motion('b') end, mode = { "n", "o", "x" }, desc = "Spider b" },
    },
  },

  -- Enhanced matchit (better % matching)
  {
    "andymass/vim-matchup",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      -- Performance optimizations
      vim.g.matchup_matchparen_enabled = 0 -- Disable real-time paren highlighting
      vim.g.matchup_matchparen_deferred = 1 -- Defer highlighting for performance
      vim.g.matchup_matchparen_hi_surround_always = 0
      vim.g.matchup_matchparen_hi_background = 0
      vim.g.matchup_motion_override_Npercent = 0 -- Don't override N%
      vim.g.matchup_delim_stopline = 1500 -- Limit search range for performance
      vim.g.matchup_delim_noskips = 2 -- Skip comments and strings sometimes
      
      -- Enable text objects and motions
      vim.g.matchup_motion_enabled = 1
      vim.g.matchup_text_obj_enabled = 1
      
      -- Custom matchit patterns for better language support
      vim.b.match_words = vim.b.match_words or ""
      
      -- Add language-specific patterns
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("MatchupConfig", { clear = true }),
        callback = function()
          local ft = vim.bo.filetype
          if ft == "lua" then
            vim.b.match_words = "\\<function\\>:\\<end\\>,\\<if\\>:\\<elseif\\>:\\<else\\>:\\<end\\>,\\<for\\>:\\<end\\>,\\<while\\>:\\<end\\>,\\<repeat\\>:\\<until\\>"
          elseif ft == "javascript" or ft == "typescript" then
            vim.b.match_words = "\\<if\\>:\\<else\\>,\\<try\\>:\\<catch\\>:\\<finally\\>,\\<switch\\>:\\<case\\>:\\<default\\>"
          elseif ft == "python" then
            vim.b.match_words = "\\<if\\>:\\<elif\\>:\\<else\\>,\\<try\\>:\\<except\\>:\\<finally\\>,\\<for\\>:\\<else\\>,\\<while\\>:\\<else\\>,\\<with\\>:"
          end
        end,
      })
    end,
    keys = {
      { "%", "<plug>(matchup-%)", mode = { "n", "x" }, desc = "Matchup %" },
      { "g%", "<plug>(matchup-g%)", mode = { "n", "x" }, desc = "Matchup g%" },
      { "[%", "<plug>(matchup-[%)", mode = { "n", "x" }, desc = "Prev outer open" },
      { "]%", "<plug>(matchup-]%)", mode = { "n", "x" }, desc = "Next outer close" },
      { "z%", "<plug>(matchup-z%)", mode = { "n", "x" }, desc = "Inside match" },
      -- Text objects
      { "i%", "<plug>(matchup-i%)", mode = { "x", "o" }, desc = "Inside match" },
      { "a%", "<plug>(matchup-a%)", mode = { "x", "o" }, desc = "Around match" },
    },
  },

  -- Unimpaired commands (Helix style)
  {
    "echasnovski/mini.bracketed",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("mini.bracketed").setup({
        buffer     = { suffix = 'b', options = {} },
        comment    = { suffix = 'c', options = {} },
        conflict   = { suffix = 'x', options = {} },
        diagnostic = { suffix = 'd', options = {} },
        file       = { suffix = 'f', options = {} },
        indent     = { suffix = 'i', options = {} },
        jump       = { suffix = 'j', options = {} },
        location   = { suffix = 'l', options = {} },
        oldfile    = { suffix = 'o', options = {} },
        quickfix   = { suffix = 'q', options = {} },
        treesitter = { suffix = 't', options = {} },
        undo       = { suffix = 'u', options = {} },
        window     = { suffix = 'w', options = {} },
        yank       = { suffix = 'y', options = {} },
      })
      
      -- Additional Helix-style navigation and manipulation
      local map = vim.keymap.set
      
      -- Line manipulation (Helix style)
      map("n", "]<Space>", "o<Esc>", { desc = "Add empty line below" })
      map("n", "[<Space>", "O<Esc>", { desc = "Add empty line above" })
      map("n", "]e", ":.m+1<CR>==", { desc = "Move line down" })
      map("n", "[e", ":.m-2<CR>==", { desc = "Move line up" })
      map("v", "]e", ":m'>+1<CR>gv=gv", { desc = "Move selection down" })
      map("v", "[e", ":m'<-2<CR>gv=gv", { desc = "Move selection up" })
      
      -- Duplicate lines/selections (Helix style)
      map("n", "]d", "yyP", { desc = "Duplicate line above" })
      map("n", "[d", "yyp", { desc = "Duplicate line below" })
      map("v", "]d", "y'>p", { desc = "Duplicate selection below" })
      map("v", "[d", "y'<P", { desc = "Duplicate selection above" })
      
      -- Text manipulation
      map("n", "]<", "<<", { desc = "Decrease indent" })
      map("n", "]>", ">>", { desc = "Increase indent" })
      map("v", "]<", "<gv", { desc = "Decrease indent" })
      map("v", "]>", ">gv", { desc = "Increase indent" })
      
      -- Case manipulation
      map("n", "]u", "viwU<Esc>", { desc = "Uppercase word" })
      map("n", "[u", "viwu<Esc>", { desc = "Lowercase word" })
      map("v", "]u", "U", { desc = "Uppercase selection" })
      map("v", "[u", "u", { desc = "Lowercase selection" })
      
      -- Toggle case
      map("n", "]~", "viw~<Esc>", { desc = "Toggle case word" })
      map("v", "]~", "~", { desc = "Toggle case selection" })
      
      -- Spell checking navigation
      map("n", "]s", "]s", { desc = "Next misspelled word" })
      map("n", "[s", "[s", { desc = "Previous misspelled word" })
      map("n", "]S", "]S", { desc = "Next bad word (rare)" })
      map("n", "[S", "[S", { desc = "Previous bad word (rare)" })
      
      -- Tab navigation
      map("n", "]t", ":tabnext<CR>", { desc = "Next tab" })
      map("n", "[t", ":tabprevious<CR>", { desc = "Previous tab" })
      map("n", "]T", ":tablast<CR>", { desc = "Last tab" })
      map("n", "[T", ":tabfirst<CR>", { desc = "First tab" })
      
      -- Window navigation
      map("n", "]w", "<C-w>w", { desc = "Next window" })
      map("n", "[w", "<C-w>W", { desc = "Previous window" })
      
      -- Search result navigation with center
      map("n", "]n", "nzzzv", { desc = "Next search result" })
      map("n", "[n", "Nzzzv", { desc = "Previous search result" })
      
      -- Fold navigation
      map("n", "]z", "zj", { desc = "Next fold start" })
      map("n", "[z", "zk", { desc = "Previous fold start" })
      map("n", "]Z", "zj", { desc = "Next fold end" })
      map("n", "[Z", "zk", { desc = "Previous fold end" })
      
      -- Git hunk navigation (if gitsigns is available)
      local ok, gitsigns = pcall(require, "gitsigns")
      if ok then
        map("n", "]h", function()
          if vim.wo.diff then return "]c" end
          vim.schedule(function() gitsigns.next_hunk() end)
          return "<Ignore>"
        end, { expr = true, desc = "Next git hunk" })
        
        map("n", "[h", function()
          if vim.wo.diff then return "[c" end
          vim.schedule(function() gitsigns.prev_hunk() end)
          return "<Ignore>"
        end, { expr = true, desc = "Previous git hunk" })
      end
      
      -- Change list navigation
      map("n", "]g", "g;", { desc = "Next change" })
      map("n", "[g", "g,", { desc = "Previous change" })
      
      -- Diff navigation (built-in)
      map("n", "]c", "]c", { desc = "Next diff" })
      map("n", "[c", "[c", { desc = "Previous diff" })
      
      -- Argument list navigation
      map("n", "]a", ":next<CR>", { desc = "Next argument" })
      map("n", "[a", ":previous<CR>", { desc = "Previous argument" })
      map("n", "]A", ":last<CR>", { desc = "Last argument" })
      map("n", "[A", ":first<CR>", { desc = "First argument" })
      
      -- URL/file under cursor
      map("n", "]p", function()
        local cfile = vim.fn.expand("<cfile>")
        if cfile:match("^https?://") then
          vim.fn.system("open " .. cfile)
        else
          vim.cmd("edit " .. cfile)
        end
      end, { desc = "Open file/URL under cursor" })
      
      -- Bracket/parentheses navigation (enhanced)
      map("n", "](", ")zz", { desc = "Next unmatched (" })
      map("n", "[)", "(zz", { desc = "Previous unmatched )" })
      map("n", "]{", "}zz", { desc = "Next unmatched {" })
      map("n", "[}", "{zz", { desc = "Previous unmatched }" })
      map("n", "]]", "]]zz", { desc = "Next section" })
      map("n", "[[", "[[zz", { desc = "Previous section" })
      
      -- Toggle options (Helix style)
      local function toggle_option(option, name)
        return function()
          vim.opt_local[option] = not vim.opt_local[option]:get()
          local state = vim.opt_local[option]:get() and "enabled" or "disabled"
          vim.notify(name .. " " .. state, vim.log.levels.INFO)
        end
      end
      
      map("n", "]oc", toggle_option("cursorline", "Cursor line"), { desc = "Toggle cursor line" })
      map("n", "[oc", toggle_option("cursorline", "Cursor line"), { desc = "Toggle cursor line" })
      map("n", "]on", toggle_option("number", "Line numbers"), { desc = "Toggle line numbers" })
      map("n", "[on", toggle_option("number", "Line numbers"), { desc = "Toggle line numbers" })
      map("n", "]or", toggle_option("relativenumber", "Relative numbers"), { desc = "Toggle relative numbers" })
      map("n", "[or", toggle_option("relativenumber", "Relative numbers"), { desc = "Toggle relative numbers" })
      map("n", "]ow", toggle_option("wrap", "Line wrap"), { desc = "Toggle line wrap" })
      map("n", "[ow", toggle_option("wrap", "Line wrap"), { desc = "Toggle line wrap" })
      map("n", "]oh", function()
        if vim.opt.hlsearch:get() then
          vim.cmd("nohlsearch")
          vim.notify("Search highlight disabled", vim.log.levels.INFO)
        else
          vim.opt.hlsearch = true
          vim.notify("Search highlight enabled", vim.log.levels.INFO)
        end
      end, { desc = "Toggle search highlight" })
      map("n", "[oh", function()
        if vim.opt.hlsearch:get() then
          vim.cmd("nohlsearch")
          vim.notify("Search highlight disabled", vim.log.levels.INFO)
        else
          vim.opt.hlsearch = true
          vim.notify("Search highlight enabled", vim.log.levels.INFO)
        end
      end, { desc = "Toggle search highlight" })
      
      -- Toggle spell checking
      map("n", "]os", toggle_option("spell", "Spell checking"), { desc = "Toggle spell checking" })
      map("n", "[os", toggle_option("spell", "Spell checking"), { desc = "Toggle spell checking" })
      
      -- Toggle list chars
      map("n", "]ol", toggle_option("list", "List chars"), { desc = "Toggle list chars" })
      map("n", "[ol", toggle_option("list", "List chars"), { desc = "Toggle list chars" })
      
      -- Paste mode toggle
      map("n", "]op", function()
        vim.opt.paste = not vim.opt.paste:get()
        local state = vim.opt.paste:get() and "enabled" or "disabled"
        vim.notify("Paste mode " .. state, vim.log.levels.INFO)
      end, { desc = "Toggle paste mode" })
      
      -- Colorcolumn toggle
      map("n", "]ox", function()
        if vim.opt.colorcolumn:get()[1] then
          vim.opt.colorcolumn = ""
          vim.notify("Color column disabled", vim.log.levels.INFO)
        else
          vim.opt.colorcolumn = "80"
          vim.notify("Color column enabled", vim.log.levels.INFO)
        end
      end, { desc = "Toggle color column" })
      
      -- Background toggle
      map("n", "]ob", function()
        vim.opt.background = vim.opt.background:get() == "dark" and "light" or "dark"
        vim.notify("Background: " .. vim.opt.background:get(), vim.log.levels.INFO)
      end, { desc = "Toggle background" })
      
      -- Whitespace and line ending navigation
      map("n", "]w", "/\\s\\+$<CR>", { desc = "Next trailing whitespace" })
      map("n", "[w", "?\\s\\+$<CR>", { desc = "Previous trailing whitespace" })
      
      -- URL navigation in text
      map("n", "]u", "/https\\?://<CR>", { desc = "Next URL" })
      map("n", "[u", "?https\\?://<CR>", { desc = "Previous URL" })
      
      -- Enhanced which-key integration
      local wk = require("which-key")
      wk.add({
        { "]", group = "next" },
        { "[", group = "previous" },
        { "]<Space>", desc = "add empty line below" },
        { "[<Space>", desc = "add empty line above" },
        { "]e", desc = "move line/selection down" },
        { "[e", desc = "move line/selection up" },
        { "]d", desc = "duplicate line/selection" },
        { "[d", desc = "duplicate line/selection" },
        { "]>", desc = "increase indent" },
        { "]<", desc = "decrease indent" },
        { "]u", desc = "uppercase word/selection" },
        { "[u", desc = "lowercase word/selection" },
        { "]~", desc = "toggle case" },
        { "]s", desc = "next misspelled word" },
        { "[s", desc = "prev misspelled word" },
        { "]t", desc = "next tab" },
        { "[t", desc = "prev tab" },
        { "]n", desc = "next search result" },
        { "[n", desc = "prev search result" },
        { "]h", desc = "next git hunk" },
        { "[h", desc = "prev git hunk" },
        { "]g", desc = "next change" },
        { "[g", desc = "prev change" },
        { "]c", desc = "next diff" },
        { "[c", desc = "prev diff" },
        { "]a", desc = "next argument" },
        { "[a", desc = "prev argument" },
        { "]w", desc = "next trailing whitespace" },
        { "[w", desc = "prev trailing whitespace" },
        { "]u", desc = "next URL" },
        { "[u", desc = "prev URL" },
        { "]o", group = "toggle options" },
        { "[o", group = "toggle options" },
        { "]oc", desc = "toggle cursor line" },
        { "]on", desc = "toggle line numbers" },
        { "]or", desc = "toggle relative numbers" },
        { "]ow", desc = "toggle line wrap" },
        { "]oh", desc = "toggle search highlight" },
        { "]os", desc = "toggle spell checking" },
        { "]ol", desc = "toggle list chars" },
        { "]op", desc = "toggle paste mode" },
        { "]ox", desc = "toggle color column" },
        { "]ob", desc = "toggle background" },
      })
    end,
  },

  -- Direnv integration
  {
    "direnv/direnv.vim",
    event = { "BufReadPre", "BufNewFile" },
  },

  -- Minimal theme with colorbuddy (custom)
  {
    "tjdevries/colorbuddy.nvim",
    priority = 1000,
    lazy = false,
    config = function()
      local colorbuddy = require("colorbuddy")
      local Color = colorbuddy.Color
      local colors = colorbuddy.colors
      local Group = colorbuddy.Group
      local styles = colorbuddy.styles

      -- Clear existing colors
      colorbuddy.colorscheme("default")

      -- Define your minimal color palette
      Color.new("bg", "#111111")        -- Dark background
      Color.new("fg", "#ffffff")        -- White text
      Color.new("gray", "#666666")      -- Comments
      Color.new("light_gray", "#888888") -- UI elements
      Color.new("dark_gray", "#444444")  -- Subtle UI
      Color.new("selection", "#222222")  -- Visual selection
      Color.new("error", "#ff5555")      -- Errors only
      Color.new("accent", "#bb9af7")     -- Minimal accent

      -- Base groups
      Group.new("Normal", colors.fg, colors.bg)
      Group.new("NormalNC", colors.fg, colors.bg)
      Group.new("Comment", colors.gray, nil, styles.italic)

      -- ALL syntax highlighting white (your preference)
      local white_groups = {
        "String", "Keyword", "Function", "Type", "Identifier", "Operator", 
        "Special", "Constant", "Statement", "Conditional", "Repeat", "Label",
        "Structure", "StorageClass", "Typedef", "PreProc", "Include", "Define", "Macro"
      }
      for _, group in ipairs(white_groups) do
        Group.new(group, colors.fg)
      end

      -- UI elements
      Group.new("LineNr", colors.dark_gray)
      Group.new("CursorLineNr", colors.light_gray)
      Group.new("Visual", nil, colors.selection)
      Group.new("Search", colors.bg, colors.gray)
      Group.new("IncSearch", colors.bg, colors.gray)
      Group.new("CursorLine", nil, colors.selection)
      Group.new("ColorColumn", nil, colors.selection)

      -- Only errors get color
      Group.new("Error", colors.error, nil, styles.bold)
      Group.new("ErrorMsg", colors.error, nil, styles.bold)
      Group.new("DiagnosticError", colors.error)
      Group.new("DiagnosticWarn", colors.fg)
      Group.new("DiagnosticInfo", colors.fg)
      Group.new("DiagnosticHint", colors.gray)

      -- UI components
      Group.new("StatusLine", colors.fg, colors.dark_gray)
      Group.new("StatusLineNC", colors.gray, colors.dark_gray)
      Group.new("Pmenu", colors.fg, colors.selection)
      Group.new("PmenuSel", colors.bg, colors.accent)
      Group.new("FloatBorder", colors.gray)
      Group.new("NormalFloat", colors.fg, colors.bg)

      -- TreeSitter (all white)
      local ts_groups = {
        "@keyword", "@function", "@type", "@variable", "@property", "@parameter",
        "@method", "@field", "@namespace", "@tag", "@attribute", "@string",
        "@number", "@boolean", "@operator", "@punctuation", "@keyword.import",
        "@keyword.include", "@preproc", "@include", "@define"
      }
      for _, group in ipairs(ts_groups) do
        Group.new(group, colors.fg)
      end
      Group.new("@comment", colors.gray, nil, styles.italic)

      -- LSP semantic tokens (all white)
      local lsp_groups = {
        "@lsp.type.class", "@lsp.type.function", "@lsp.type.method", "@lsp.type.variable",
        "@lsp.type.parameter", "@lsp.type.property", "@lsp.type.keyword", 
        "@lsp.type.string", "@lsp.type.number"
      }
      for _, group in ipairs(lsp_groups) do
        Group.new(group, colors.fg)
      end

      -- Plugin highlights
      Group.new("WhichKey", colors.fg, nil, styles.bold)
      Group.new("WhichKeyGroup", colors.accent)
      Group.new("WhichKeyDesc", colors.gray)
      Group.new("GitSignsAdd", colors.fg)
      Group.new("GitSignsChange", colors.fg)
      Group.new("GitSignsDelete", colors.fg)
      Group.new("Folded", colors.gray, colors.selection)
      Group.new("FoldColumn", colors.dark_gray)

      -- Oil file manager highlights (purple instead of yellow)
      Group.new("OilDir", colors.accent)                -- Directories in purple
      Group.new("OilDirIcon", colors.accent)            -- Directory icons in purple
      Group.new("OilLink", colors.accent)               -- Symlinks in purple
      Group.new("OilLinkTarget", colors.fg)             -- Link targets in white
      Group.new("OilCopy", colors.accent)               -- Copy operations in purple
      Group.new("OilMove", colors.accent)               -- Move operations in purple
      Group.new("OilChange", colors.accent)             -- Changed files in purple
      Group.new("OilCreate", colors.accent)             -- New files in purple
      Group.new("OilDelete", colors.error)              -- Deleted files in red
      Group.new("OilPermissionRead", colors.fg)         -- Read permissions in white
      Group.new("OilPermissionWrite", colors.accent)    -- Write permissions in purple
      Group.new("OilPermissionExecute", colors.accent)  -- Execute permissions in purple
      Group.new("OilTypeText", colors.fg)               -- Text files in white
      Group.new("OilTypeBinary", colors.gray)           -- Binary files in gray
      Group.new("OilSocket", colors.accent)             -- Sockets in purple
      Group.new("OilFifo", colors.accent)               -- Named pipes in purple
      Group.new("OilBlockDevice", colors.accent)        -- Block devices in purple
      Group.new("OilCharDevice", colors.accent)         -- Character devices in purple

      -- Clean borders and separators
      Group.new("VertSplit", colors.dark_gray)
      Group.new("WinSeparator", colors.dark_gray)
      Group.new("SignColumn", nil, colors.bg)
      Group.new("EndOfBuffer", colors.dark_gray)

      -- Terminal colors (minimal)
      vim.g.terminal_color_0 = "#111111"
      vim.g.terminal_color_8 = "#666666"
      vim.g.terminal_color_7 = "#ffffff"
      vim.g.terminal_color_15 = "#ffffff"
      -- All other colors use white/gray for minimal appearance
      for i = 1, 6 do
        vim.g["terminal_color_" .. i] = "#ffffff"
        vim.g["terminal_color_" .. (i + 8)] = "#666666"
      end
    end,
  },
}

-- Load editor plugins and return combined table
local editor_plugins = require("editor")
vim.list_extend(plugins, editor_plugins)

return plugins