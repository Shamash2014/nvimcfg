return {
  -- Pure native LSP configuration
  {
    "native-lsp",
    dir = vim.fn.stdpath("config"),
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      -- Global mappings
      vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float)
      vim.keymap.set("n", "[d", vim.diagnostic.goto_prev)
      vim.keymap.set("n", "]d", vim.diagnostic.goto_next)
      vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist)

      -- Enhanced workspace rename function
      local function workspace_rename()
        local current_word = vim.fn.expand("<cword>")
        local new_name = vim.fn.input("Rename " .. current_word .. " to: ", current_word)
        
        if new_name == "" or new_name == current_word then
          return
        end
        
        -- Get all clients that support rename
        local clients = vim.lsp.get_clients({
          bufnr = vim.api.nvim_get_current_buf(),
          method = "textDocument/rename",
        })
        
        if #clients == 0 then
          vim.notify("No LSP clients support rename", vim.log.levels.WARN)
          return
        end
        
        -- Prepare rename request
        local params = vim.lsp.util.make_position_params()
        params.newName = new_name
        
        -- Show progress
        vim.notify("Renaming " .. current_word .. " to " .. new_name .. "...", vim.log.levels.INFO)
        
        -- Send rename request to all supporting clients
        for _, client in ipairs(clients) do
          client.request("textDocument/rename", params, function(err, result)
            if err then
              vim.notify("Rename failed: " .. err.message, vim.log.levels.ERROR)
              return
            end
            
            if result then
              -- Apply workspace edits
              vim.lsp.util.apply_workspace_edit(result, client.offset_encoding)
              
              -- Count changes
              local changes = 0
              if result.changes then
                for _, file_changes in pairs(result.changes) do
                  changes = changes + #file_changes
                end
              elseif result.documentChanges then
                for _, change in ipairs(result.documentChanges) do
                  if change.edits then
                    changes = changes + #change.edits
                  end
                end
              end
              
              vim.notify(
                string.format("Renamed %s to %s (%d changes)", current_word, new_name, changes),
                vim.log.levels.INFO
              )
            else
              vim.notify("No references found for " .. current_word, vim.log.levels.WARN)
            end
          end)
        end
      end

      -- LSP attach function
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local opts = { buffer = ev.buf }
          vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
          vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
          vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
          
          -- Enhanced rename mappings
          vim.keymap.set("n", "<leader>crr", function()
            return ":IncRename " .. vim.fn.expand("<cword>")
          end, vim.tbl_extend("force", opts, { desc = "Inc Rename", expr = true }))
          vim.keymap.set("n", "<leader>crw", workspace_rename, vim.tbl_extend("force", opts, { desc = "Workspace Rename" }))
          
          vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "<leader>f", function()
            vim.lsp.buf.format { async = true }
          end, opts)
        end,
      })

      -- Start LSP clients manually
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "lua",
        callback = function()
          vim.lsp.start({
            name = "lua_ls",
            cmd = { "lua-language-server" },
            settings = {
              Lua = {
                diagnostics = {
                  globals = { "vim" },
                },
                workspace = {
                  library = vim.api.nvim_get_runtime_file("", true),
                },
                telemetry = {
                  enable = false,
                },
              },
            },
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "typescript", "javascript", "typescriptreact", "javascriptreact" },
        callback = function()
          vim.lsp.start({
            name = "ts_ls",
            cmd = { "typescript-language-server", "--stdio" },
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function()
          vim.lsp.start({
            name = "pyright",
            cmd = { "pyright-langserver", "--stdio" },
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "dart",
        callback = function()
          vim.lsp.start({
            name = "dartls",
            cmd = { "dart", "language-server", "--protocol=lsp" },
            settings = {
              dart = {
                analysisExcludedFolders = {
                  vim.fn.expand("~/.pub-cache"),
                  vim.fn.expand("~/fvm"),
                },
                updateImportsOnRename = true,
                completeFunctionCalls = true,
                showTodos = true,
                enableSnippets = true,
              },
            },
          })
        end,
      })
    end,
  },
}