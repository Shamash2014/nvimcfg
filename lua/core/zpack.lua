local M = {}

local function zpack_path()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "site/pack/core/opt/zpack.nvim")
end

local function bootstrap()
  if vim.uv.fs_stat(zpack_path()) then
    vim.cmd.packadd("zpack.nvim")
    return
  end

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

function M.setup()
  bootstrap()

  local ok, zpack = pcall(require, "zpack")
  if not ok then
    error("failed to load zpack.nvim: " .. zpack)
  end

  zpack.setup({
    defaults = {
      confirm = false,
    },
    spec = {
      { import = "plugins" },
    },
  })
end

return M
