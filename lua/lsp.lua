vim.diagnostic.config({
  virtual_text = false,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    border = "single",
    source = "always",
    header = "",
    prefix = "",
  },
})

local signs = { Error = "✘", Warn = "▲", Hint = "⚑", Info = "»" }
for type, icon in pairs(signs) do
  local hl = "DiagnosticSign" .. type
  vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

local on_attach = function(client, bufnr)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, noremap = true, silent = true })
  end

  map("n", "gd", vim.lsp.buf.definition, "Go to Definition")
  map("n", "gD", vim.lsp.buf.declaration, "Go to Declaration")
  map("n", "gi", vim.lsp.buf.implementation, "Go to Implementation")
  map("n", "gr", vim.lsp.buf.references, "Go to References")
  map("n", "gt", vim.lsp.buf.type_definition, "Go to Type Definition")
  map("n", "K", vim.lsp.buf.hover, "Hover Documentation")
  map("n", "<C-k>", vim.lsp.buf.signature_help, "Signature Help")
  map("i", "<C-k>", vim.lsp.buf.signature_help, "Signature Help")

  map("n", "<leader>ca", vim.lsp.buf.code_action, "Code Action")
  map("v", "<leader>ca", vim.lsp.buf.code_action, "Code Action")
  map("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
  map("n", "<leader>cd", vim.diagnostic.open_float, "Show Diagnostic")
  map("n", "[d", vim.diagnostic.goto_prev, "Previous Diagnostic")
  map("n", "]d", vim.diagnostic.goto_next, "Next Diagnostic")

  if client.server_capabilities.documentHighlightProvider then
    local group = vim.api.nvim_create_augroup("LSPDocumentHighlight_" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = group,
      buffer = bufnr,
      callback = vim.lsp.buf.document_highlight,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = group,
      buffer = bufnr,
      callback = vim.lsp.buf.clear_references,
    })
  end

  if client.server_capabilities.inlayHintProvider then
    map("n", "<leader>ch", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
    end, "Toggle Inlay Hints")
  end
end

local capabilities = vim.lsp.protocol.make_client_capabilities()

_G.lsp_config = {
  on_attach = on_attach,
  capabilities = capabilities,
  flags = {
    debounce_text_changes = 150,
  },
}

vim.api.nvim_create_user_command("LspRestart", function()
  vim.lsp.stop_client(vim.lsp.get_active_clients())
  vim.cmd("edit")
end, { desc = "Restart LSP servers" })

vim.api.nvim_create_user_command("LspLog", function()
  vim.cmd("edit " .. vim.lsp.get_log_path())
end, { desc = "Open LSP log" })

-- Debug autocmd to notify when LSP attaches
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then
      vim.notify(string.format("LSP '%s' attached to buffer", client.name), vim.log.levels.INFO)
    end
  end
})
