return {
  {
    src = "https://github.com/saghen/blink.cmp",
    sem_version = "1.*",
    lazy = false,
    dependencies = {
      {
        src = "https://github.com/L3MON4D3/LuaSnip",
        sem_version = "v2.*",
        build = "make install_jsregexp",
      },
    },
    config = function()
      require("blink.cmp").setup({
        keymap = {
          preset = "default",
          ["<C-j>"] = { "select_next", "fallback" },
          ["<C-k>"] = { "select_prev", "fallback" },
        },
        snippets = {
          preset = "luasnip",
        },
        completion = {
          menu = {
            border = "rounded",
          },
          documentation = {
            auto_show = true,
            auto_show_delay_ms = 200,
            window = {
              border = "rounded",
            },
          },
          list = {
            selection = {
              preselect = false,
              auto_insert = true,
            },
          },
          accept = {
            auto_brackets = {
              enabled = true,
            },
          },
        },
        sources = {
          default = { "lsp", "path", "snippets", "buffer", "acp" },
          providers = {
            acp = {
              name = "ACP",
              module = "acp.blink",
              score_offset = 100,
              trigger_characters = { "/", "@" },
              enabled = function()
                return vim.bo.filetype == "markdown"
              end,
            },
          },
        },
      })
    end,
  },
}
