-- Lua LSP now configured centrally in lua/lsp.lua

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'LuaRun',
  function()
    if vim.fn.executable("lua") == 0 then
      vim.notify("Lua executable not found", vim.log.levels.ERROR)
      return
    end
    local file = vim.fn.expand('%')
    vim.cmd('terminal lua ' .. file)
  end, { desc = 'Run current Lua file' })

vim.api.nvim_buf_create_user_command(0, 'LuaCheck',
  function()
    if vim.fn.executable("luacheck") == 1 then
      vim.cmd('terminal luacheck %')
    elseif vim.fn.executable("selene") == 1 then
      vim.cmd('terminal selene %')
    else
      vim.notify("No Lua linter found (luacheck or selene)", vim.log.levels.WARN)
    end
  end, { desc = 'Check Lua file' })

vim.api.nvim_buf_create_user_command(0, 'LuaFormat',
  function()
    if vim.fn.executable("stylua") == 1 then
      vim.cmd('terminal stylua %')
    else
      vim.notify("StyLua formatter not found", vim.log.levels.WARN)
    end
  end, { desc = 'Format Lua file' })

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
