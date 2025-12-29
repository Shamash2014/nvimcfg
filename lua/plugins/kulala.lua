return {
  "mistweaverco/kulala.nvim",
  ft = "http",
  opts = {
    default_view = "body",
    default_env = "dev",
    debug = false,
    contenttypes = {
      ["application/json"] = {
        ft = "json",
        formatter = { "jq", "." },
      },
      ["application/xml"] = {
        ft = "xml",
        formatter = { "xmllint", "--format", "-" },
      },
      ["text/html"] = {
        ft = "html",
        formatter = { "xmllint", "--format", "--html", "-" },
      },
    },
    show_icons = "on_request",
    icons = {
      inlay = {
        loading = "⏳",
        done = "✅",
        error = "❌",
      },
    },
  },
  config = function(_, opts)
    require("kulala").setup(opts)

    -- Set up keymaps for HTTP files
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "http",
      callback = function()
        local kulala = require("kulala")
        local opts = { buffer = true, silent = true }

        -- Main keybindings under <leader>ok
        vim.keymap.set("n", "<leader>okr", kulala.run, vim.tbl_extend("force", opts, { desc = "Run request" }))
        vim.keymap.set("n", "<leader>oka", kulala.run_all, vim.tbl_extend("force", opts, { desc = "Run all requests" }))
        vim.keymap.set("n", "<leader>okR", kulala.replay, vim.tbl_extend("force", opts, { desc = "Replay last request" }))
        vim.keymap.set("n", "<leader>okp", kulala.jump_prev, vim.tbl_extend("force", opts, { desc = "Jump to previous request" }))
        vim.keymap.set("n", "<leader>okn", kulala.jump_next, vim.tbl_extend("force", opts, { desc = "Jump to next request" }))

        -- View toggles
        vim.keymap.set("n", "<leader>okv", kulala.toggle_view, vim.tbl_extend("force", opts, { desc = "Toggle view (body/headers)" }))
        vim.keymap.set("n", "<leader>okb", function() kulala.set_selected_env("body") end, vim.tbl_extend("force", opts, { desc = "View body" }))
        vim.keymap.set("n", "<leader>okh", function() kulala.set_selected_env("headers") end, vim.tbl_extend("force", opts, { desc = "View headers" }))

        -- Environment management
        vim.keymap.set("n", "<leader>oke", kulala.set_selected_env, vim.tbl_extend("force", opts, { desc = "Select environment" }))

        -- Copy/inspect
        vim.keymap.set("n", "<leader>okc", kulala.copy, vim.tbl_extend("force", opts, { desc = "Copy request as curl" }))
        vim.keymap.set("n", "<leader>oki", kulala.inspect, vim.tbl_extend("force", opts, { desc = "Inspect request" }))

        -- Close response
        vim.keymap.set("n", "<leader>okq", kulala.close, vim.tbl_extend("force", opts, { desc = "Close response" }))
      end,
    })
  end,
}