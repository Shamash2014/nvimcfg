if vim.fn.executable("lua-language-server") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "lua_ls",
    cmd = { "lua-language-server" },
    root_dir = vim.fs.root(0, { ".luarc.json", ".luarc.jsonc", ".luacheckrc", ".stylua.toml", "stylua.toml", "selene.toml", "selene.yml", ".git" }),
    settings = {
      Lua = {
        runtime = {
          version = "LuaJIT",
        },
        diagnostics = {
          globals = { "vim" },
        },
        workspace = {
          library = vim.api.nvim_get_runtime_file("", true),
          checkThirdParty = false,
        },
        telemetry = {
          enable = false,
        },
      },
    },
  }))
end

local ok, lint = pcall(require, 'lint')
if ok then
  local linters = {}

  if vim.fn.executable("selene") == 1 then
    table.insert(linters, "selene")
  elseif vim.fn.executable("luacheck") == 1 then
    table.insert(linters, "luacheck")
  end

  if #linters > 0 then
    lint.linters_by_ft.lua = linters
  end
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("stylua") == 1 then
  conform.formatters_by_ft.lua = { "stylua" }
end
