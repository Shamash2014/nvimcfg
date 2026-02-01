return {
  "rasulomaroff/telepath.nvim",
  dependencies = {
    "https://codeberg.org/andyg/leap.nvim",
  },
  config = function()
    require('telepath').use_default_mappings()
  end,
}