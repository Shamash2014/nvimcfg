local zpack_path = vim.fs.joinpath(vim.fn.stdpath("data"), "site/pack/core/opt/zpack.nvim")

if vim.uv.fs_stat(zpack_path) then
  pcall(vim.cmd.packadd, "zpack.nvim")
else
  vim.pack.add({
    {
      src = "https://github.com/zuqini/zpack.nvim",
      name = "zpack.nvim",
    },
  }, {
    confirm = false,
    load = true,
  })
end

require("zpack").setup({
  spec = {
    { import = "plugins" },
  },
})
