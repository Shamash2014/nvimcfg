return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "folke/snacks.nvim",
    },
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
    keys = {
      { "<leader>ai", "<cmd>CodeCompanionActions<cr>",     desc = "AI Actions",    mode = { "n", "v" } },
      { "<leader>ac", "<cmd>CodeCompanionChat<cr>",        desc = "AI Chat" },
      { "<leader>at", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle AI Chat" },
      { "<leader>aa", "<cmd>CodeCompanion<cr>",            desc = "AI Inline" },
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          http = {
            lmstudio = function()
              return require("codecompanion.adapters").extend("openai", {
                url = "http://localhost:1234/v1/chat/completions",
                env = {
                  api_key = "lm-studio",
                },
                schema = {
                  model = {
                    default = "qwen3-coder-30b-a3b-instruct-mlx",
                  },
                },
              })
            end,
          },
          acp = {
            claude_code = function()
              return require("codecompanion.adapters").extend("claude_code", {
                env = {
                  CLAUDE_CODE_OAUTH_TOKEN = os.getenv("CLAUDE_OAUTH"),
                },
              })
            end,
          },
        },
        strategies = {
          chat = {
            adapter = "lmstudio",
            slash_commands = {
              ["file"] = {
                callback = "strategies.chat.slash_commands.file",
                description = "Select a file",
                opts = {
                  provider = "snacks",
                  contains_code = true,
                },
              },
              ["buffer"] = {
                callback = "strategies.chat.slash_commands.buffer",
                description = "Select a buffer",
                opts = {
                  provider = "snacks",
                  contains_code = true,
                },
              },
            },
          },
          inline = {
            adapter = "lmstudio",
          },
          agent = {
            adapter = "claude_code",
          },
        },
        display = {
          action_palette = {
            provider = "default",
          },
          chat = {
            provider = "default",
            intro_message = "Welcome to CodeCompanion ✨! Press ? for options",
            separator = "─",
            show_context = true,
            show_header_separator = false,
            show_settings = false,
            show_token_count = true,
            show_tools_processing = true,
            start_in_insert_mode = false,
          },
        },
        opts = {
          log_level = "ERROR",
          send_code = true,
        },
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "codecompanion",
        callback = function(ev)
          vim.keymap.set("n", "]c", "}", { buffer = ev.buf, desc = "Next Chat" })
          vim.keymap.set("n", "[c", "{", { buffer = ev.buf, desc = "Prev Chat" })
        end,
      })
    end,
  },
  
  {
    "supermaven-inc/supermaven-nvim",
    event = "InsertEnter",
    opts = {
      keymaps = {
        accept_suggestion = "<M-l>",
        clear_suggestion = "<C-]>",
        accept_word = "<M-w>",
      },
      ignore_filetypes = {
        codecompanion = true,
        TelescopePrompt = true,
      },
      color = {
        suggestion_color = "#808080",
        cterm = 244,
      },
      log_level = "warn",
      disable_inline_completion = false,
      disable_keymaps = false,
    },
  },
}