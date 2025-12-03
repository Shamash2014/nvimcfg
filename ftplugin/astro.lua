if vim.fn.executable("astro-ls") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "astro",
    cmd = { "astro-ls", "--stdio" },
    root_dir = vim.fs.root(0, { "astro.config.mjs", "astro.config.js", "astro.config.ts", "package.json", ".git" }),
    init_options = {
      typescript = {
        tsdk = vim.fs.normalize(vim.fs.root(0, { "node_modules" }) .. "/node_modules/typescript/lib")
      }
    },
    handlers = {
      ["textDocument/publishDiagnostics"] = vim.lsp.with(
        vim.lsp.diagnostic.on_publish_diagnostics,
        { virtual_text = false }
      ),
    },
  }))
end

-- TypeScript support is handled by astro-ls itself

-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'AstroBuild',
  function()
    vim.cmd('terminal npm run build')
  end, { desc = 'Build Astro project' })

vim.api.nvim_buf_create_user_command(0, 'AstroDev',
  function()
    vim.cmd('terminal npm run dev')
  end, { desc = 'Start Astro dev server' })

vim.api.nvim_buf_create_user_command(0, 'AstroPreview',
  function()
    vim.cmd('terminal npm run preview')
  end, { desc = 'Preview Astro build' })

vim.api.nvim_buf_create_user_command(0, 'AstroCheck',
  function()
    vim.cmd('terminal npx astro check')
  end, { desc = 'Check Astro project' })

-- Linting with ESLint if available
local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("eslint") == 1 then
  lint.linters_by_ft.astro = { "eslint" }
end

-- Formatting with Prettier if available
local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.astro = { "prettier" }
end