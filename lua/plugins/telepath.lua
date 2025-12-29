return {
  "rasulomaroff/telepath.nvim",
  dependencies = "ggandor/leap.nvim",
  config = function()
    require('telepath').use_default_mappings()
  end,
}