-- Expert LSP Configuration (restored)
local expert_cmd = vim.fn.expand("~/.tools/expert/expert")
if vim.fn.executable(expert_cmd) == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "expert",
    cmd = { expert_cmd },
    root_dir = vim.fs.root(0, { "mix.exs", ".git" }),
    filetypes = { "elixir", "eelixir", "heex", "surface" },
    settings = {
      expert = {
        dialyzerEnabled = true,
        mixEnv = "prod",
        signatures = true,
        hover = true,
        symbols = true,
        completion = {
          enable = true,
          autoImport = true,
        },
      },
    },
  }))
else
  vim.notify("Expert LSP not found at " .. expert_cmd .. ". Install expert for full LSP support.", vim.log.levels.WARN)
end

-- Linting with credo
local ok, lint = pcall(require, 'lint')
if ok then
  local linters = {}

  if vim.fn.executable("credo") == 1 then
    table.insert(linters, "credo")
  end

  if #linters > 0 then
    lint.linters_by_ft.elixir = linters
  end
end

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'ElixirRunTests',
  function()
    vim.cmd('terminal mix test')
  end, { desc = 'Run Elixir tests' })

vim.api.nvim_buf_create_user_command(0, 'ElixirCompile',
  function()
    vim.cmd('terminal mix compile')
  end, { desc = 'Compile Elixir project' })

vim.api.nvim_buf_create_user_command(0, 'ElixirDeps',
  function()
    vim.cmd('terminal mix deps.get')
  end, { desc = 'Get Elixir dependencies' })

vim.api.nvim_buf_create_user_command(0, 'ElixirIEx',
  function()
    vim.cmd('terminal iex -S mix')
  end, { desc = 'Start IEx with project' })

vim.api.nvim_buf_create_user_command(0, 'ElixirFormat',
  function()
    vim.cmd('terminal mix format')
  end, { desc = 'Format Elixir code' })

local project_root = vim.fs.root(0, {"mix.exs"})
if project_root then
  local phoenix_file = project_root .. "/lib/**/*_web.ex"
  if vim.fn.glob(phoenix_file) ~= "" then
    vim.api.nvim_buf_create_user_command(0, 'PhoenixServer',
      function()
        vim.cmd('terminal mix phx.server')
      end, { desc = 'Start Phoenix server' })

    vim.api.nvim_buf_create_user_command(0, 'PhoenixRoutes',
      function()
        vim.cmd('terminal mix phx.routes')
      end, { desc = 'Show Phoenix routes' })

    vim.api.nvim_buf_create_user_command(0, 'PhoenixMigrate',
      function()
        vim.cmd('terminal mix ecto.migrate')
      end, { desc = 'Run database migrations' })

    vim.api.nvim_buf_create_user_command(0, 'PhoenixReset',
      function()
        vim.cmd('terminal mix ecto.reset')
      end, { desc = 'Reset database' })
  end
end
-- Formatting with conform
local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("mix") == 1 then
  conform.formatters_by_ft.elixir = { "mix" }
end

