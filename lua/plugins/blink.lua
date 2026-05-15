return {
  {
    "Saghen/blink.cmp",
    sem_version = "1.*",
    lazy = false,
    config = function()
      local ok, blink = pcall(require, "blink.cmp")
      if not ok then return end

      blink.setup({
        keymap = { preset = "default" },
        appearance = { nerd_font_variant = "mono" },
        completion = {
          accept = { auto_brackets = { enabled = false } },
          menu = { border = "rounded" },
          documentation = { auto_show = true, auto_show_delay_ms = 200 },
          ghost_text = { enabled = false },
        },
        sources = {
          default = { "lsp", "path", "snippets", "buffer" },
        },
      })
    end,
  },
}
