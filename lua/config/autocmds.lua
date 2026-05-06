local group = vim.api.nvim_create_augroup("nvim2", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 120 })
  end,
})

vim.api.nvim_create_autocmd({ "TermOpen", "BufWinEnter" }, {
  group = group,
  callback = function()
    if vim.bo.buftype == "terminal" then
      vim.wo.scrolloff = 1000
      vim.wo.sidescrolloff = 0
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = {
    "bash",
    "dart",
    "elixir",
    "go",
    "yaml",
    "json",
    "javascript",
    "lua",
    "markdown",
    "markdown_inline",
    "typescript",
    "tsx",
    "vim",
    "vimdoc",
  },
  callback = function()
    vim.bo.indentexpr = "v:lua.vim.treesitter.indentexpr()"
  end,
})

-- LSP progress display via nvim_echo (cleaner than floating windows)
vim.api.nvim_create_autocmd("LspProgress", {
  callback = function(ev)
    local value = ev.data.params.value
    vim.api.nvim_echo({ { value.message or "done" } }, false, {
      id = "lsp." .. ev.data.client_id,
      kind = "progress",
      source = "vim.lsp",
      title = value.title,
      status = value.kind ~= "end" and "running" or "success",
      percent = value.percentage,
    })
  end,
})

-- LSP keymaps (only active when LSP is attached)
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("nvim2-lsp-keymaps", { clear = true }),
  callback = function(ev)
    local bufnr = ev.buf
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    local opts = { buffer = bufnr, noremap = true, silent = true }

    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "gs", vim.lsp.buf.signature_help, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)

    if client and client.supports_method("textDocument/formatting") then
      vim.keymap.set("n", "<leader>cf", function()
        vim.lsp.buf.format({ bufnr = bufnr, async = true })
      end, opts)
    end
  end,
})

return M
